//! Peer discovery over mDNS.
//!
//! The advertisement is anonymous: a random ID that rotates, a port, and no
//! name. Names are only exchanged after the encrypted handshake.

use anyhow::{Context, Result};
use mdns_sd::{Receiver, ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use tokio::sync::mpsc;

pub const SERVICE_TYPE: &str = "_kinly._tcp.local.";
const TXT_ID: &str = "id";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveredPeer {
    pub address: String,
    pub port: u16,
}

pub struct Discovery {
    daemon: ServiceDaemon,
    port: u16,
    fullname: String,
    id: String,
}

impl Discovery {
    /// Starts advertising on `port` with a fresh anonymous ID.
    pub fn start(port: u16, id: &str) -> Result<Self> {
        let daemon = ServiceDaemon::new().context("starting the mDNS daemon")?;
        let fullname = register(&daemon, port, id)?;
        Ok(Self {
            daemon,
            port,
            fullname,
            id: id.to_string(),
        })
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    /// Replaces the advertised anonymous ID. Called periodically so a passive
    /// observer cannot track a device by its discovery beacon.
    pub fn rotate(&mut self, id: &str) -> Result<()> {
        let _ = self.daemon.unregister(&self.fullname);
        self.fullname = register(&self.daemon, self.port, id)?;
        self.id = id.to_string();
        Ok(())
    }

    /// Browses for peers. Resolved peers are forwarded to the returned channel
    /// by a background thread owned by the mDNS daemon.
    pub fn browse(&self) -> Result<mpsc::UnboundedReceiver<DiscoveredPeer>> {
        let events: Receiver<ServiceEvent> = self.daemon.browse(SERVICE_TYPE)?;
        let own_fullname = self.fullname.clone();
        let (tx, rx) = mpsc::unbounded_channel();
        std::thread::Builder::new()
            .name("kinly-mdns".into())
            .spawn(move || {
                while let Ok(event) = events.recv() {
                    if let ServiceEvent::ServiceResolved(info) = event {
                        if info.fullname == own_fullname {
                            continue;
                        }
                        let Some(address) = info
                            .addresses
                            .iter()
                            .find(|address| address.is_ipv4())
                            .map(|address| address.to_ip_addr().to_string())
                        else {
                            continue;
                        };
                        let peer = DiscoveredPeer {
                            address,
                            port: info.port,
                        };
                        if tx.send(peer).is_err() {
                            break;
                        }
                    }
                }
            })
            .context("starting the mDNS thread")?;
        Ok(rx)
    }

    pub fn shutdown(&self) {
        let _ = self.daemon.unregister(&self.fullname);
        let _ = self.daemon.shutdown();
    }
}

fn register(daemon: &ServiceDaemon, port: u16, id: &str) -> Result<String> {
    let instance = format!("kinly-{id}");
    let host = format!("{instance}.local.");
    let ip = local_ip_address::local_ip()
        .map(|ip| ip.to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string());
    let mut properties = HashMap::new();
    properties.insert(TXT_ID.to_string(), id.to_string());
    let info = ServiceInfo::new(
        SERVICE_TYPE,
        &instance,
        &host,
        ip.as_str(),
        port,
        properties,
    )
    .with_context(|| format!("advertising {instance} on port {port}"))?;
    let fullname = info.get_fullname().to_string();
    daemon.register(info)?;
    Ok(fullname)
}

/// Generates a random anonymous discovery ID.
pub fn random_discovery_id() -> String {
    format!("{:016x}", rand::random::<u64>())
}
