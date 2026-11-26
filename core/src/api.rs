//! Flutter bridge (flutter_rust_bridge).
//!
//! The app starts one node and polls [`KinlyNode::poll_events`] for UI events.
//! All calls block on a shared Tokio runtime; the generated Dart bindings run
//! them off the UI isolate.

use crate::node::{self, Config, Event, NodeHandle};
use crate::storage::{MessageRow, Person, Storage};
use anyhow::Result;
use flutter_rust_bridge::frb;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::broadcast;

fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| Runtime::new().expect("starting the Tokio runtime"))
}

/// Options for the first run / start.
#[derive(Debug, Clone)]
pub struct StartOptions {
    pub name: String,
    pub data_dir: String,
    /// 0 picks a free port.
    pub listen_port: u16,
    pub enable_mdns: bool,
}

/// A known person, as shown in the chat list.
#[derive(Debug, Clone)]
pub struct PersonInfo {
    pub device_id: String,
    pub name: String,
    pub avatar: Option<String>,
    /// Our visibility toggle for this person (true = we are visible to them).
    pub visible: bool,
    /// True when this person hid themselves from us.
    pub hidden_by_peer: bool,
    pub online: bool,
    pub last_seen: u64,
}

/// One stored message.
#[derive(Debug, Clone)]
pub struct MessageInfo {
    pub id: String,
    pub peer: String,
    pub direction: String,
    pub body: String,
    pub state: String,
    pub created_at: u64,
}

/// One event for the UI, flattened so Dart can switch on `kind`.
#[derive(Debug, Clone)]
pub struct BridgeEvent {
    pub kind: String,
    pub device_id: String,
    pub name: String,
    pub message_id: String,
    pub body: String,
    pub state: String,
    pub transfer_id: String,
    pub path: String,
    pub error: String,
    pub size: u64,
    pub offset: u64,
    pub received: u64,
    pub total: u64,
    pub visible: bool,
    pub typing: bool,
}

impl BridgeEvent {
    fn new(kind: &str) -> Self {
        Self {
            kind: kind.to_string(),
            device_id: String::new(),
            name: String::new(),
            message_id: String::new(),
            body: String::new(),
            state: String::new(),
            transfer_id: String::new(),
            path: String::new(),
            error: String::new(),
            size: 0,
            offset: 0,
            received: 0,
            total: 0,
            visible: true,
            typing: false,
        }
    }
}

/// Opaque node handle. Create it with [`start_node`].
pub struct KinlyNode {
    handle: NodeHandle,
    events: std::sync::Mutex<broadcast::Receiver<Event>>,
}

impl KinlyNode {
    #[frb(sync)]
    pub fn name(&self) -> String {
        self.handle.name()
    }

    #[frb(sync)]
    pub fn avatar(&self) -> Option<String> {
        self.handle.avatar()
    }

    /// Renames this device and/or replaces the profile photo. An empty `name`
    /// or `avatar_base64` keeps the current value; `remove_avatar` clears the
    /// photo.
    pub fn set_profile(
        &self,
        name: String,
        avatar_base64: String,
        remove_avatar: bool,
    ) -> Result<()> {
        let name = if name.trim().is_empty() {
            None
        } else {
            Some(name)
        };
        let avatar = if remove_avatar {
            Some(None)
        } else if avatar_base64.is_empty() {
            None
        } else {
            Some(Some(avatar_base64))
        };
        runtime().block_on(self.handle.set_profile(name, avatar))
    }

    #[frb(sync)]
    pub fn device_id(&self) -> String {
        self.handle.device_id.clone()
    }

    #[frb(sync)]
    pub fn port(&self) -> u16 {
        self.handle.port
    }

    /// Drains every event received since the last poll.
    #[frb(sync)]
    pub fn poll_events(&self) -> Vec<BridgeEvent> {
        let Ok(mut events) = self.events.lock() else {
            return Vec::new();
        };
        let mut out = Vec::new();
        loop {
            match events.try_recv() {
                Ok(event) => out.push(map_event(event)),
                Err(broadcast::error::TryRecvError::Empty) => break,
                Err(broadcast::error::TryRecvError::Lagged(_)) => continue,
                Err(broadcast::error::TryRecvError::Closed) => break,
            }
        }
        out
    }

    pub fn people(&self) -> Result<Vec<PersonInfo>> {
        let online = runtime().block_on(self.handle.online_peers())?;
        let people = runtime().block_on(self.handle.people())?;
        Ok(people
            .into_iter()
            .map(|person| map_person(person, &online))
            .collect())
    }

    pub fn online_peers(&self) -> Result<Vec<String>> {
        runtime().block_on(self.handle.online_peers())
    }

    pub fn unread_count(&self, device_id: &str) -> Result<u32> {
        runtime().block_on(self.handle.unread_count(device_id))
    }

    pub fn history(&self, device_id: &str, limit: u32) -> Result<Vec<MessageInfo>> {
        let messages = runtime().block_on(self.handle.history(device_id, limit as usize))?;
        Ok(messages.into_iter().map(map_message).collect())
    }

    pub fn send_message(&self, device_id: &str, body: &str) -> Result<String> {
        let id = runtime().block_on(self.handle.send_message(device_id, body))?;
        Ok(id.to_string())
    }

    pub fn send_file(&self, device_id: &str, path: &str) -> Result<String> {
        let id = runtime().block_on(self.handle.send_file(device_id, PathBuf::from(path)))?;
        Ok(id.to_string())
    }

    pub fn set_visibility(&self, device_id: &str, visible: bool) -> Result<()> {
        runtime().block_on(self.handle.set_visibility(device_id, visible))
    }

    pub fn set_typing(&self, device_id: &str, typing: bool) -> Result<()> {
        runtime().block_on(self.handle.set_typing(device_id, typing))
    }

    pub fn mark_read(&self, device_id: &str) -> Result<()> {
        runtime().block_on(self.handle.mark_read(device_id))
    }

    pub fn cancel_file(&self, transfer_id: &str) -> Result<()> {
        let id = transfer_id
            .parse()
            .map_err(|error| anyhow::anyhow!("invalid transfer id: {error}"))?;
        runtime().block_on(self.handle.cancel_file(id))
    }

    /// Sends a WebRTC call signal (offer, answer, ICE candidate or hangup)
    /// through the encrypted channel.
    #[frb(sync)]
    pub fn send_call_signal(&self, peer: &str, call_id: &str, payload: &str) -> Result<()> {
        let call_id = call_id
            .parse::<uuid::Uuid>()
            .map_err(|_| anyhow::anyhow!("invalid call id: {call_id}"))?;
        runtime().block_on(self.handle.send_call_signal(peer, call_id, payload.to_string()))
    }

    pub fn connect_to(&self, address: &str) -> Result<()> {
        runtime().block_on(self.handle.connect_to(address))
    }

    /// The 60-digit code shared with `device_id`, for out-of-band verification.
    #[frb(sync)]
    pub fn safety_code(&self, device_id: String) -> Result<String> {
        crate::safety::safety_code(&self.handle.device_id, &device_id)
    }

    /// A short fingerprint of this device's identity key.
    #[frb(sync)]
    pub fn fingerprint(&self) -> Result<String> {
        crate::safety::fingerprint(&self.handle.device_id)
    }

    /// Sends a queued or failed outgoing message again.
    pub fn retry_message(&self, message_id: &str) -> Result<()> {
        let id = message_id
            .parse()
            .map_err(|error| anyhow::anyhow!("invalid message id: {error}"))?;
        runtime().block_on(self.handle.retry_message(id))
    }

    /// Stops the node and releases the port. Called when the app quits.
    pub fn shutdown(&self) {
        runtime().block_on(self.handle.shutdown());
        // Let the socket close before the process goes away.
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// Reads the name saved by a previous run, or null on a fresh device.
/// Used by the app to decide between the welcome screen and the chat list.
pub fn load_name(data_dir: String) -> Result<Option<String>> {
    let storage = Storage::open(std::path::Path::new(&data_dir))?;
    storage.get_setting("name")
}

/// Erases the identity, the database and downloaded files of this device.
/// Call it after [`KinlyNode::shutdown`] so no file is still open.
pub fn wipe_data(data_dir: String) -> Result<()> {
    let path = PathBuf::from(&data_dir);
    if path.as_os_str().is_empty() || path.parent().is_none() {
        anyhow::bail!("refusing to wipe an unsafe path");
    }
    if path.exists() {
        std::fs::remove_dir_all(&path)?;
    }
    Ok(())
}

/// Starts the node. The data directory holds the identity and the database.
pub fn start_node(options: StartOptions) -> Result<KinlyNode> {
    let mut config = Config::new(options.name, PathBuf::from(options.data_dir));
    config.listen_port = options.listen_port;
    config.enable_mdns = options.enable_mdns;
    let handle = runtime().block_on(node::start(config))?;
    let events = handle.subscribe();
    Ok(KinlyNode {
        handle,
        events: std::sync::Mutex::new(events),
    })
}

fn map_person(person: Person, online: &[String]) -> PersonInfo {
    PersonInfo {
        device_id: person.device_id.clone(),
        name: person.name,
        avatar: person.avatar,
        visible: !person.hidden,
        hidden_by_peer: person.hidden_by_peer,
        online: online.contains(&person.device_id),
        last_seen: person.last_seen.unwrap_or(0),
    }
}

fn map_message(message: MessageRow) -> MessageInfo {
    MessageInfo {
        id: message.id.to_string(),
        peer: message.peer,
        direction: message.direction,
        body: message.body,
        state: message.state,
        created_at: message.created_at,
    }
}

fn map_event(event: Event) -> BridgeEvent {
    match event {
        Event::PeerUp { device_id, name } => {
            let mut out = BridgeEvent::new("peer_up");
            out.device_id = device_id;
            out.name = name;
            out
        }
        Event::PeerDown { device_id } => {
            let mut out = BridgeEvent::new("peer_down");
            out.device_id = device_id;
            out
        }
        Event::ProfileChanged { name, avatar } => {
            let mut out = BridgeEvent::new("profile_changed");
            out.name = name;
            out.body = avatar.unwrap_or_default();
            out
        }
        Event::PeerVisibility { device_id, visible } => {
            let mut out = BridgeEvent::new("visibility");
            out.device_id = device_id;
            out.visible = visible;
            out
        }
        Event::Message { device_id, message } => {
            let mut out = BridgeEvent::new("message");
            out.device_id = device_id;
            out.message_id = message.id.to_string();
            out.body = message.body;
            out.state = message.state;
            out.offset = message.created_at;
            out
        }
        Event::MessageState { message_id, state } => {
            let mut out = BridgeEvent::new("message_state");
            out.message_id = message_id.to_string();
            out.state = state;
            out
        }
        Event::Typing { device_id, typing } => {
            let mut out = BridgeEvent::new("typing");
            out.device_id = device_id;
            out.typing = typing;
            out
        }
        Event::FileOffer {
            transfer_id,
            device_id,
            name,
            size,
            offset,
        } => {
            let mut out = BridgeEvent::new("file_offer");
            out.transfer_id = transfer_id.to_string();
            out.device_id = device_id;
            out.name = name;
            out.size = size;
            out.offset = offset;
            out
        }
        Event::FileProgress {
            transfer_id,
            received,
            total,
        } => {
            let mut out = BridgeEvent::new("file_progress");
            out.transfer_id = transfer_id.to_string();
            out.received = received;
            out.total = total;
            out
        }
        Event::FileComplete { transfer_id, path } => {
            let mut out = BridgeEvent::new("file_complete");
            out.transfer_id = transfer_id.to_string();
            out.path = path;
            out
        }
        Event::FileFailed { transfer_id, error } => {
            let mut out = BridgeEvent::new("file_failed");
            out.transfer_id = transfer_id.to_string();
            out.error = error;
            out
        }
        Event::FileSent { transfer_id } => {
            let mut out = BridgeEvent::new("file_sent");
            out.transfer_id = transfer_id.to_string();
            out
        }
        Event::CallSignal {
            device_id,
            call_id,
            payload,
        } => {
            let mut out = BridgeEvent::new("call_signal");
            out.device_id = device_id;
            out.transfer_id = call_id.to_string();
            out.body = payload;
            out
        }
        Event::NameConflict { device_id, name } => {
            let mut out = BridgeEvent::new("name_conflict");
            out.device_id = device_id;
            out.name = name;
            out
        }
        Event::Error { message } => {
            let mut out = BridgeEvent::new("error");
            out.error = message;
            out
        }
    }
}
