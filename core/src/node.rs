//! Node orchestration: listener, outbound connections, sessions, message
//! queue, visibility, file transfers and events.
//!
//! All state lives in one actor task. Session tasks do the network I/O and
//! forward decrypted frames to the actor; the actor answers commands and emits
//! events for the UI / CLI.

use crate::crypto::{self, Handshake, SharedTransport};
use crate::discovery::{self, Discovery};
use crate::files::{hash_file, IncomingFile};
use crate::identity::{self, Identity};
use crate::protocol::{
    AckState, CallSignal, FileOffer, Frame, Hello, Payload, PresenceState, FILE_CHUNK_SIZE,
    PROTOCOL_VERSION,
};
use crate::storage::{MessageRow, Person, Storage, TransferRow};
use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tracing::{debug, warn};
use uuid::Uuid;

const OUT_QUEUE: usize = 64;
const SESSION_QUEUE: usize = 256;
const DIAL_INTERVAL: Duration = Duration::from_secs(10);
const DISCOVERY_ROTATE_TICKS: u32 = 120; // 120 * 5s = 10 minutes
const PROGRESS_INTERVAL: Duration = Duration::from_millis(200);

/// Configuration for a node.
#[derive(Debug, Clone)]
pub struct Config {
    pub name: String,
    pub data_dir: PathBuf,
    pub listen_port: u16,
    /// Manual peers as `host:port` (useful for tests and for networks where
    /// mDNS is blocked).
    pub peers: Vec<String>,
    pub enable_mdns: bool,
    /// How often manual peers are dialed. Shortened in tests.
    pub dial_interval: Duration,
}

impl Config {
    pub fn new(name: impl Into<String>, data_dir: impl Into<PathBuf>) -> Self {
        Self {
            name: name.into(),
            data_dir: data_dir.into(),
            listen_port: 0,
            peers: Vec::new(),
            enable_mdns: true,
            dial_interval: DIAL_INTERVAL,
        }
    }
}

/// Events emitted by the node for the UI / CLI.
#[derive(Debug, Clone)]
pub enum Event {
    PeerUp {
        device_id: String,
        name: String,
    },
    PeerDown {
        device_id: String,
    },
    /// Visibility changed: our own hide toggle, or the peer hiding from us.
    PeerVisibility {
        device_id: String,
        visible: bool,
    },
    Message {
        device_id: String,
        message: MessageRow,
    },
    MessageState {
        message_id: Uuid,
        state: String,
    },
    Typing {
        device_id: String,
        typing: bool,
    },
    FileOffer {
        transfer_id: Uuid,
        device_id: String,
        name: String,
        size: u64,
        offset: u64,
    },
    FileProgress {
        transfer_id: Uuid,
        received: u64,
        total: u64,
    },
    FileComplete {
        transfer_id: Uuid,
        path: String,
    },
    FileFailed {
        transfer_id: Uuid,
        error: String,
    },
    FileSent {
        transfer_id: Uuid,
    },
    CallSignal {
        device_id: String,
        call_id: Uuid,
        payload: String,
    },
    NameConflict {
        device_id: String,
        name: String,
    },
    Error {
        message: String,
    },
}

/// Handle used by the app to send commands and subscribe to events.
pub struct NodeHandle {
    pub device_id: String,
    pub name: String,
    pub port: u16,
    cmd_tx: mpsc::Sender<Command>,
    events: broadcast::Sender<Event>,
}

impl NodeHandle {
    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.events.subscribe()
    }

    /// Queues a message; it is delivered immediately if the peer is online,
    /// otherwise when the peer comes back.
    pub async fn send_message(&self, peer: &str, body: &str) -> Result<Uuid> {
        let (reply, response) = oneshot::channel();
        self.cmd_tx
            .send(Command::SendMessage {
                peer: peer.to_string(),
                body: body.to_string(),
                reply,
            })
            .await
            .context("node is not running")?;
        response.await.context("node stopped")?
    }

    /// Sends a file. Returns the transfer ID immediately; progress is reported
    /// through events.
    pub async fn send_file(&self, peer: &str, path: impl Into<PathBuf>) -> Result<Uuid> {
        let (reply, response) = oneshot::channel();
        self.cmd_tx
            .send(Command::SendFile {
                peer: peer.to_string(),
                path: path.into(),
                reply,
            })
            .await
            .context("node is not running")?;
        response.await.context("node stopped")?
    }

    /// Turns the visibility toggle for `peer` on or off.
    pub async fn set_visibility(&self, peer: &str, visible: bool) -> Result<()> {
        let (reply, response) = oneshot::channel();
        self.cmd_tx
            .send(Command::SetVisibility {
                peer: peer.to_string(),
                visible,
                reply,
            })
            .await
            .context("node is not running")?;
        response.await.context("node stopped")?
    }

    pub async fn set_typing(&self, peer: &str, typing: bool) -> Result<()> {
        self.cmd_tx
            .send(Command::SetTyping {
                peer: peer.to_string(),
                typing,
            })
            .await
            .context("node is not running")
    }

    pub async fn cancel_file(&self, transfer_id: Uuid) -> Result<()> {
        self.cmd_tx
            .send(Command::CancelFile { transfer_id })
            .await
            .context("node is not running")
    }

    pub async fn mark_read(&self, peer: &str) -> Result<()> {
        self.cmd_tx
            .send(Command::MarkRead {
                peer: peer.to_string(),
            })
            .await
            .context("node is not running")
    }

    /// Lists every person the node knows about.
    pub async fn people(&self) -> Result<Vec<Person>> {
        let (reply, response) = oneshot::channel();
        self.cmd_tx
            .send(Command::ListPeople { reply })
            .await
            .context("node is not running")?;
        response.await.context("node stopped")?
    }

    /// Returns the latest messages exchanged with `peer`.
    pub async fn history(&self, peer: &str, limit: usize) -> Result<Vec<MessageRow>> {
        let (reply, response) = oneshot::channel();
        self.cmd_tx
            .send(Command::History {
                peer: peer.to_string(),
                limit,
                reply,
            })
            .await
            .context("node is not running")?;
        response.await.context("node stopped")?
    }

    pub async fn send_call_signal(&self, peer: &str, call_id: Uuid, payload: String) -> Result<()> {
        self.cmd_tx
            .send(Command::SendCallSignal {
                peer: peer.to_string(),
                call_id,
                payload,
            })
            .await
            .context("node is not running")
    }

    /// Dials a manual peer address (`host:port`).
    pub async fn connect_to(&self, address: impl Into<String>) -> Result<()> {
        self.cmd_tx
            .send(Command::ConnectTo {
                address: address.into(),
            })
            .await
            .context("node is not running")
    }

    /// Stops the node, closes every session and releases the listening port.
    pub async fn shutdown(&self) {
        let (reply, response) = oneshot::channel();
        if self.cmd_tx.send(Command::Shutdown { reply }).await.is_ok() {
            let _ = tokio::time::timeout(Duration::from_secs(3), response).await;
        }
    }
}

#[derive(Debug)]
enum Command {
    SendMessage {
        peer: String,
        body: String,
        reply: oneshot::Sender<Result<Uuid>>,
    },
    SendFile {
        peer: String,
        path: PathBuf,
        reply: oneshot::Sender<Result<Uuid>>,
    },
    OfferReady {
        transfer_id: Uuid,
        peer: String,
        path: PathBuf,
        hash: String,
        size: u64,
    },
    SetVisibility {
        peer: String,
        visible: bool,
        reply: oneshot::Sender<Result<()>>,
    },
    SetTyping {
        peer: String,
        typing: bool,
    },
    CancelFile {
        transfer_id: Uuid,
    },
    MarkRead {
        peer: String,
    },
    SendCallSignal {
        peer: String,
        call_id: Uuid,
        payload: String,
    },
    ConnectTo {
        address: String,
    },
    ListPeople {
        reply: oneshot::Sender<Result<Vec<Person>>>,
    },
    History {
        peer: String,
        limit: usize,
        reply: oneshot::Sender<Result<Vec<MessageRow>>>,
    },
    Shutdown {
        reply: oneshot::Sender<()>,
    },
}

#[derive(Debug)]
enum SessionEvent {
    Up {
        connection_id: Uuid,
        device_id: String,
        name: String,
        initiator: bool,
        out_tx: mpsc::Sender<Frame>,
        shutdown: watch::Sender<bool>,
    },
    Down {
        connection_id: Uuid,
        device_id: String,
    },
    Frame {
        device_id: String,
        frame: Frame,
    },
    HiddenByPeer {
        device_id: String,
    },
    HiddenPeer {
        device_id: String,
    },
    NameConflict {
        device_id: String,
        name: String,
    },
    Error {
        device_id: Option<String>,
        message: String,
    },
}

#[derive(Clone)]
struct SessionContext {
    identity: Arc<Identity>,
    noise_private: Arc<Vec<u8>>,
    storage: Arc<Storage>,
    device_id: String,
    name: String,
}

struct ConnectedPeer {
    connection_id: Uuid,
    out_tx: mpsc::Sender<Frame>,
    shutdown: watch::Sender<bool>,
}

struct NodeState {
    identity: Arc<Identity>,
    noise_private: Arc<Vec<u8>>,
    storage: Arc<Storage>,
    name: String,
    device_id: String,
    events: broadcast::Sender<Event>,
    self_tx: mpsc::Sender<Command>,
    session_tx: mpsc::Sender<SessionEvent>,
    peers: HashMap<String, ConnectedPeer>,
    pending_accepts: HashMap<Uuid, oneshot::Sender<u64>>,
    incoming: HashMap<Uuid, IncomingFile>,
    progress_at: HashMap<Uuid, Instant>,
    downloads_dir: PathBuf,
    dialed_at: HashMap<String, Instant>,
    dial_interval: Duration,
    listener_stop: watch::Sender<bool>,
    listener_task: Option<tokio::task::JoinHandle<()>>,
}

/// Starts a node. The listener is already bound when this returns.
pub async fn start(config: Config) -> Result<NodeHandle> {
    let name = identity::validate_name(&config.name)?;
    std::fs::create_dir_all(&config.data_dir)?;

    let identity = Arc::new(Identity::load_or_create(&config.data_dir)?);
    let noise_key = crypto::load_or_create_static_key(&config.data_dir)?;
    let storage = Arc::new(Storage::open(&config.data_dir)?);

    if let Some(existing) = storage.person_by_name(&name)? {
        if existing.device_id != identity.device_id() {
            bail!("name already taken: {name}");
        }
    }
    storage.set_setting("name", &name)?;

    let downloads_dir = config.data_dir.join("downloads");
    std::fs::create_dir_all(&downloads_dir)?;

    let listener = TcpListener::bind(("0.0.0.0", config.listen_port))
        .await
        .with_context(|| format!("binding port {}", config.listen_port))?;
    let port = listener.local_addr()?.port();

    let (events, _) = broadcast::channel(1024);
    let (cmd_tx, cmd_rx) = mpsc::channel(128);
    let (session_tx, session_rx) = mpsc::channel(SESSION_QUEUE);

    let device_id = identity.device_id();
    let session_context = SessionContext {
        identity: identity.clone(),
        noise_private: Arc::new(noise_key.private.clone()),
        storage: storage.clone(),
        device_id: device_id.clone(),
        name: name.clone(),
    };

    let (listener_stop, mut listener_stop_rx) = watch::channel(false);
    let accept_context = session_context;
    let accept_tx = session_tx.clone();

    let listener_task = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = listener_stop_rx.changed() => {
                    if changed.is_err() || *listener_stop_rx.borrow() {
                        break;
                    }
                }
                result = listener.accept() => {
                    match result {
                        Ok((stream, _addr)) => {
                            let context = accept_context.clone();
                            let tx = accept_tx.clone();
                            tokio::spawn(async move {
                                if let Err(error) = run_session(stream, false, context, tx).await {
                                    debug!("inbound session ended: {error:#}");
                                }
                            });
                        }
                        Err(error) => {
                            warn!("listener stopped: {error}");
                            break;
                        }
                    }
                }
            }
        }
    });

    let state = NodeState {
        identity: identity.clone(),
        noise_private: Arc::new(noise_key.private.clone()),
        storage: storage.clone(),
        name: name.clone(),
        device_id: device_id.clone(),
        events: events.clone(),
        self_tx: cmd_tx.clone(),
        session_tx: session_tx.clone(),
        peers: HashMap::new(),
        pending_accepts: HashMap::new(),
        incoming: HashMap::new(),
        progress_at: HashMap::new(),
        downloads_dir,
        dialed_at: HashMap::new(),
        dial_interval: config.dial_interval,
        listener_stop: listener_stop.clone(),
        listener_task: Some(listener_task),
    };

    let peers = config.peers.clone();
    let enable_mdns = config.enable_mdns;
    tokio::spawn(async move {
        run_node(state, cmd_rx, session_rx, port, peers, enable_mdns).await;
    });

    Ok(NodeHandle {
        device_id,
        name,
        port,
        cmd_tx,
        events,
    })
}

async fn run_node(
    mut state: NodeState,
    mut cmd_rx: mpsc::Receiver<Command>,
    mut session_rx: mpsc::Receiver<SessionEvent>,
    port: u16,
    manual_peers: Vec<String>,
    enable_mdns: bool,
) {
    let mut discovery = None;
    if enable_mdns {
        match Discovery::start(port, &discovery::random_discovery_id()) {
            Ok(started) => {
                match started.browse() {
                    Ok(mut peers) => {
                        let tx = state.self_tx.clone();
                        tokio::spawn(async move {
                            while let Some(peer) = peers.recv().await {
                                let address = format!("{}:{}", peer.address, peer.port);
                                if tx.send(Command::ConnectTo { address }).await.is_err() {
                                    break;
                                }
                            }
                        });
                    }
                    Err(error) => {
                        warn!("mDNS browse failed: {error:#}");
                        emit(
                            &state.events,
                            Event::Error {
                                message: format!("discovery unavailable: {error}"),
                            },
                        );
                    }
                }
                discovery = Some(started);
            }
            Err(error) => {
                warn!("mDNS advertisement failed: {error:#}");
                emit(
                    &state.events,
                    Event::Error {
                        message: format!("discovery unavailable: {error}"),
                    },
                );
            }
        }
    }

    let mut ticker = tokio::time::interval(Duration::from_secs(5));
    let mut ticks: u32 = 0;
    let mut shutdown_reply = None;
    loop {
        tokio::select! {
            command = cmd_rx.recv() => {
                let Some(command) = command else { break };
                match command {
                    Command::Shutdown { reply } => {
                        shutdown_reply = Some(reply);
                        break;
                    }
                    other => handle_command(&mut state, other).await,
                }
            }
            event = session_rx.recv() => {
                let Some(event) = event else { break };
                handle_session_event(&mut state, event).await;
            }
            _ = ticker.tick() => {
                ticks += 1;
                for peer in &manual_peers {
                    maybe_dial(&mut state, peer).await;
                }
                if let Some(discovery) = discovery.as_mut() {
                    if ticks.is_multiple_of(DISCOVERY_ROTATE_TICKS) {
                        let id = discovery::random_discovery_id();
                        if let Err(error) = discovery.rotate(&id) {
                            warn!("rotating the discovery ID failed: {error:#}");
                        }
                    }
                }
            }
        }
    }

    let _ = state.listener_stop.send(true);
    if let Some(discovery) = discovery {
        discovery.shutdown();
    }
    for (_, peer) in state.peers.drain() {
        let _ = peer.shutdown.send(true);
    }
    if let Some(task) = state.listener_task.take() {
        let _ = task.await;
    }
    if let Some(reply) = shutdown_reply {
        let _ = reply.send(());
    }
}

async fn handle_command(state: &mut NodeState, command: Command) {
    match command {
        Command::SendMessage { peer, body, reply } => {
            let result = send_message(state, &peer, &body).await;
            let _ = reply.send(result);
        }
        Command::SendFile { peer, path, reply } => {
            let result = prepare_file(state, &peer, path).await;
            let _ = reply.send(result);
        }
        Command::OfferReady {
            transfer_id,
            peer,
            path,
            hash,
            size,
        } => {
            if let Err(error) = offer_file(state, transfer_id, &peer, path, hash, size).await {
                emit(
                    &state.events,
                    Event::FileFailed {
                        transfer_id,
                        error: error.to_string(),
                    },
                );
            }
        }
        Command::SetVisibility {
            peer,
            visible,
            reply,
        } => {
            let result = set_visibility(state, &peer, visible).await;
            let _ = reply.send(result);
        }
        Command::SetTyping { peer, typing } => {
            let _ = send_frame(state, &peer, Frame::Control(Payload::Typing { typing })).await;
        }
        Command::CancelFile { transfer_id } => {
            if let Some(incoming) = state.incoming.remove(&transfer_id) {
                drop(incoming);
                let _ = state
                    .storage
                    .update_transfer_progress(transfer_id, 0, "cancelled");
            }
            if let Some(peer) = state
                .storage
                .transfer(transfer_id)
                .ok()
                .flatten()
                .map(|transfer| transfer.peer)
            {
                let _ = send_frame(
                    state,
                    &peer,
                    Frame::Control(Payload::FileCancel {
                        transfer_id,
                        reason: "cancelled".into(),
                    }),
                )
                .await;
            }
            let _ = tokio::fs::remove_file(state.downloads_dir.join(format!("{transfer_id}.part")))
                .await;
        }
        Command::MarkRead { peer } => {
            if let Ok(messages) = state.storage.messages(&peer, 100) {
                for message in messages.into_iter().filter(|m| m.direction == "in") {
                    let _ = send_frame(
                        state,
                        &peer,
                        Frame::Control(Payload::Ack {
                            message_id: message.id,
                            state: AckState::Read,
                        }),
                    )
                    .await;
                }
            }
        }
        Command::SendCallSignal {
            peer,
            call_id,
            payload,
        } => {
            let _ = send_frame(
                state,
                &peer,
                Frame::Control(Payload::CallSignal(CallSignal { call_id, payload })),
            )
            .await;
        }
        Command::ConnectTo { address } => {
            maybe_dial(state, &address).await;
        }
        Command::ListPeople { reply } => {
            let _ = reply.send(state.storage.people());
        }
        Command::History { peer, limit, reply } => {
            let _ = reply.send(state.storage.messages(&peer, limit));
        }
        Command::Shutdown { .. } => {}
    }
}

async fn handle_session_event(state: &mut NodeState, event: SessionEvent) {
    match event {
        SessionEvent::Up {
            connection_id,
            device_id,
            name,
            initiator,
            out_tx,
            shutdown,
        } => {
            // Keep the session initiated by the device with the smaller ID so
            // simultaneous connections resolve to one session on both sides.
            let keep_new = if initiator {
                state.device_id < device_id
            } else {
                device_id < state.device_id
            };
            if state.peers.contains_key(&device_id) {
                if keep_new {
                    if let Some(existing) = state.peers.remove(&device_id) {
                        let _ = existing.shutdown.send(true);
                    }
                } else {
                    let _ = shutdown.send(true);
                    return;
                }
            }
            state.peers.insert(
                device_id.clone(),
                ConnectedPeer {
                    connection_id,
                    out_tx: out_tx.clone(),
                    shutdown,
                },
            );
            let _ = state.storage.touch_last_seen(&device_id);
            emit(
                &state.events,
                Event::PeerUp {
                    device_id: device_id.clone(),
                    name,
                },
            );

            // Deliver messages that were queued while the peer was offline.
            if let Ok(pending) = state.storage.pending_messages(&device_id) {
                for message in pending {
                    let frame = Frame::Control(Payload::Msg {
                        id: message.id,
                        body: message.body,
                        sent_at: message.created_at,
                    });
                    if out_tx.send(frame).await.is_ok() {
                        let _ = state.storage.update_message_state(message.id, "sent");
                        emit(
                            &state.events,
                            Event::MessageState {
                                message_id: message.id,
                                state: "sent".into(),
                            },
                        );
                    } else {
                        break;
                    }
                }
            }

            resume_transfers(state, &device_id).await;
        }
        SessionEvent::Down {
            connection_id,
            device_id,
        } => {
            let matches = state
                .peers
                .get(&device_id)
                .map(|peer| peer.connection_id == connection_id)
                .unwrap_or(false);
            if matches {
                state.peers.remove(&device_id);
                emit(&state.events, Event::PeerDown { device_id });
            }
        }
        SessionEvent::Frame { device_id, frame } => {
            handle_frame(state, &device_id, frame).await;
        }
        SessionEvent::HiddenByPeer { device_id } => {
            let _ = state.storage.set_hidden_by_peer(&device_id, true);
            emit(
                &state.events,
                Event::PeerVisibility {
                    device_id,
                    visible: false,
                },
            );
        }
        SessionEvent::HiddenPeer { device_id } => {
            emit(
                &state.events,
                Event::PeerVisibility {
                    device_id,
                    visible: false,
                },
            );
        }
        SessionEvent::NameConflict { device_id, name } => {
            emit(&state.events, Event::NameConflict { device_id, name });
        }
        SessionEvent::Error { device_id, message } => {
            let _ = device_id;
            emit(&state.events, Event::Error { message });
        }
    }
}

async fn handle_frame(state: &mut NodeState, peer: &str, frame: Frame) {
    match frame {
        Frame::Control(payload) => match payload {
            Payload::Msg { id, body, sent_at } => {
                let message = MessageRow {
                    id,
                    peer: peer.to_string(),
                    direction: "in".into(),
                    body,
                    state: "delivered".into(),
                    created_at: sent_at,
                };
                if state.storage.insert_message(&message).is_ok() {
                    emit(
                        &state.events,
                        Event::Message {
                            device_id: peer.to_string(),
                            message,
                        },
                    );
                    let _ = send_frame(
                        state,
                        peer,
                        Frame::Control(Payload::Ack {
                            message_id: id,
                            state: AckState::Delivered,
                        }),
                    )
                    .await;
                }
            }
            Payload::Ack {
                message_id,
                state: ack_state,
            } => {
                let state_name = match ack_state {
                    AckState::Delivered => "delivered",
                    AckState::Read => "read",
                    AckState::Failed => "failed",
                    AckState::NameTaken => "name_taken",
                };
                let _ = state.storage.update_message_state(message_id, state_name);
                if !matches!(ack_state, AckState::NameTaken) {
                    emit(
                        &state.events,
                        Event::MessageState {
                            message_id,
                            state: state_name.into(),
                        },
                    );
                }
            }
            Payload::Typing { typing } => {
                emit(
                    &state.events,
                    Event::Typing {
                        device_id: peer.to_string(),
                        typing,
                    },
                );
            }
            Payload::FileOffer(offer) => {
                if let Err(error) = accept_file_offer(state, peer, offer).await {
                    emit(
                        &state.events,
                        Event::Error {
                            message: format!("file offer failed: {error}"),
                        },
                    );
                }
            }
            Payload::FileAccept {
                transfer_id,
                offset,
            } => {
                if let Some(sender) = state.pending_accepts.remove(&transfer_id) {
                    let _ = sender.send(offset);
                }
                let _ = state
                    .storage
                    .update_transfer_progress(transfer_id, offset, "sending");
            }
            Payload::FileCancel {
                transfer_id,
                reason,
            } => {
                state.incoming.remove(&transfer_id);
                state.progress_at.remove(&transfer_id);
                let _ = state
                    .storage
                    .update_transfer_progress(transfer_id, 0, "cancelled");
                emit(
                    &state.events,
                    Event::FileFailed {
                        transfer_id,
                        error: reason,
                    },
                );
            }
            Payload::CallSignal(signal) => {
                emit(
                    &state.events,
                    Event::CallSignal {
                        device_id: peer.to_string(),
                        call_id: signal.call_id,
                        payload: signal.payload,
                    },
                );
            }
            Payload::Visibility { visible } => {
                let _ = state.storage.set_hidden_by_peer(peer, !visible);
                emit(
                    &state.events,
                    Event::PeerVisibility {
                        device_id: peer.to_string(),
                        visible,
                    },
                );
            }
            Payload::Presence { state: presence } => {
                if presence == PresenceState::Online {
                    let _ = state.storage.touch_last_seen(peer);
                }
            }
            Payload::Hello(_) => {}
        },
        Frame::Chunk {
            transfer_id,
            offset,
            last,
            data,
        } => {
            let Some(incoming) = state.incoming.get_mut(&transfer_id) else {
                return;
            };
            if let Err(error) = incoming.write_chunk(offset, &data).await {
                state.incoming.remove(&transfer_id);
                emit(
                    &state.events,
                    Event::FileFailed {
                        transfer_id,
                        error: error.to_string(),
                    },
                );
                return;
            }
            let received = incoming.written();
            let total = incoming.size();

            let should_emit = last
                || state
                    .progress_at
                    .get(&transfer_id)
                    .map(|at| at.elapsed() >= PROGRESS_INTERVAL)
                    .unwrap_or(true);
            if should_emit {
                state.progress_at.insert(transfer_id, Instant::now());
                emit(
                    &state.events,
                    Event::FileProgress {
                        transfer_id,
                        received,
                        total,
                    },
                );
            }

            if last {
                if let Some(incoming) = state.incoming.remove(&transfer_id) {
                    state.progress_at.remove(&transfer_id);
                    match incoming.finish().await {
                        Ok(path) => {
                            let _ = state.storage.update_transfer_progress(
                                transfer_id,
                                received,
                                "complete",
                            );
                            emit(
                                &state.events,
                                Event::FileComplete {
                                    transfer_id,
                                    path: path.to_string_lossy().to_string(),
                                },
                            );
                        }
                        Err(error) => {
                            emit(
                                &state.events,
                                Event::FileFailed {
                                    transfer_id,
                                    error: error.to_string(),
                                },
                            );
                        }
                    }
                }
            }
        }
    }
}

fn emit(events: &broadcast::Sender<Event>, event: Event) {
    let _ = events.send(event);
}

async fn send_message(state: &mut NodeState, peer: &str, body: &str) -> Result<Uuid> {
    let person = state
        .storage
        .person(peer)?
        .ok_or_else(|| anyhow::anyhow!("unknown peer"))?;
    let id = Uuid::new_v4();
    let message = MessageRow {
        id,
        peer: peer.to_string(),
        direction: "out".into(),
        body: body.to_string(),
        state: "queued".into(),
        created_at: identity::unix_now(),
    };
    state.storage.insert_message(&message)?;

    // Writing to someone we hid turns our own visibility toggle back on so the
    // conversation can continue in both directions.
    if person.hidden {
        set_visibility(state, peer, true).await?;
    }

    if state.peers.contains_key(peer) {
        send_frame(
            state,
            peer,
            Frame::Control(Payload::Msg {
                id,
                body: body.to_string(),
                sent_at: message.created_at,
            }),
        )
        .await?;
        state.storage.update_message_state(id, "sent")?;
        emit(
            &state.events,
            Event::MessageState {
                message_id: id,
                state: "sent".into(),
            },
        );
    }
    Ok(id)
}

async fn prepare_file(state: &mut NodeState, peer: &str, path: PathBuf) -> Result<Uuid> {
    if state.storage.person(peer)?.is_none() {
        bail!("unknown peer");
    }
    let metadata = tokio::fs::metadata(&path)
        .await
        .with_context(|| format!("opening {}", path.display()))?;
    if !metadata.is_file() {
        bail!("not a file: {}", path.display());
    }
    let transfer_id = Uuid::new_v4();
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("file")
        .to_string();
    let row = TransferRow {
        id: transfer_id,
        peer: peer.to_string(),
        direction: "out".into(),
        path: path.to_string_lossy().to_string(),
        name,
        size: metadata.len(),
        offset: 0,
        blake3: String::new(),
        state: "preparing".into(),
        created_at: identity::unix_now(),
    };
    state.storage.insert_transfer(&row)?;

    let tx = state.self_tx.clone();
    let peer_owned = peer.to_string();
    let scan_path = path.clone();
    tokio::spawn(async move {
        match hash_file(&scan_path).await {
            Ok(hash) => {
                let _ = tx
                    .send(Command::OfferReady {
                        transfer_id,
                        peer: peer_owned,
                        path: scan_path,
                        hash,
                        size: metadata.len(),
                    })
                    .await;
            }
            Err(error) => {
                warn!("hashing failed: {error:#}");
            }
        }
    });
    Ok(transfer_id)
}

async fn offer_file(
    state: &mut NodeState,
    transfer_id: Uuid,
    peer: &str,
    path: PathBuf,
    hash: String,
    size: u64,
) -> Result<()> {
    let Some(connected) = state.peers.get(peer) else {
        // Peer is offline: keep the row so it is offered when they return.
        let mut transfer = state
            .storage
            .transfer(transfer_id)?
            .ok_or_else(|| anyhow::anyhow!("unknown transfer"))?;
        transfer.state = "paused".into();
        transfer.blake3 = hash;
        state.storage.insert_transfer(&transfer)?;
        return Ok(());
    };
    let out_tx = connected.out_tx.clone();
    let (accept_tx, accept_rx) = oneshot::channel();
    state.pending_accepts.insert(transfer_id, accept_tx);
    let mut transfer = state
        .storage
        .transfer(transfer_id)?
        .ok_or_else(|| anyhow::anyhow!("unknown transfer"))?;
    transfer.state = "offered".into();
    transfer.blake3 = hash.clone();
    state.storage.insert_transfer(&transfer)?;

    let name = transfer.name.clone();
    let events = state.events.clone();
    let storage = state.storage.clone();
    let peer = peer.to_string();
    tokio::spawn(async move {
        let result = send_file_task(
            transfer_id,
            peer,
            path,
            name,
            size,
            hash,
            out_tx,
            accept_rx,
            storage.clone(),
            events.clone(),
        )
        .await;
        if let Err(error) = result {
            let _ = storage.update_transfer_progress(transfer_id, 0, "paused");
            emit(
                &events,
                Event::FileFailed {
                    transfer_id,
                    error: error.to_string(),
                },
            );
        }
    });
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn send_file_task(
    transfer_id: Uuid,
    peer: String,
    path: PathBuf,
    name: String,
    size: u64,
    hash: String,
    out_tx: mpsc::Sender<Frame>,
    accept_rx: oneshot::Receiver<u64>,
    storage: Arc<Storage>,
    events: broadcast::Sender<Event>,
) -> Result<()> {
    let offer = FileOffer {
        transfer_id,
        name,
        size,
        blake3: hash,
    };
    out_tx
        .send(Frame::Control(Payload::FileOffer(offer)))
        .await
        .map_err(|_| anyhow::anyhow!("peer went offline before the offer was sent"))?;
    let offset = accept_rx
        .await
        .map_err(|_| anyhow::anyhow!("peer did not accept the file"))?;
    if offset > size {
        bail!("peer asked for an offset beyond the file size");
    }
    let mut file = tokio::fs::File::open(&path).await?;
    file.seek(std::io::SeekFrom::Start(offset)).await?;
    let mut buffer = vec![0u8; FILE_CHUNK_SIZE];
    let mut position = offset;
    loop {
        let read = file.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        let last = position + read as u64 >= size;
        let frame = Frame::Chunk {
            transfer_id,
            offset: position,
            last,
            data: buffer[..read].to_vec(),
        };
        out_tx
            .send(frame)
            .await
            .map_err(|_| anyhow::anyhow!("peer went offline during the transfer"))?;
        position += read as u64;
        let _ = storage.update_transfer_progress(transfer_id, position, "sending");
        emit(
            &events,
            Event::FileProgress {
                transfer_id,
                received: position,
                total: size,
            },
        );
    }
    let _ = storage.update_transfer_progress(transfer_id, position, "complete");
    emit(&events, Event::FileSent { transfer_id });
    let _ = peer;
    Ok(())
}

async fn resume_transfers(state: &mut NodeState, peer: &str) {
    let Ok(transfers) = state.storage.unfinished_outgoing_transfers(peer) else {
        return;
    };
    for transfer in transfers {
        if transfer.blake3.is_empty() {
            continue;
        }
        if let Err(error) = offer_file(
            state,
            transfer.id,
            peer,
            PathBuf::from(&transfer.path),
            transfer.blake3.clone(),
            transfer.size,
        )
        .await
        {
            warn!("resuming transfer failed: {error:#}");
        }
    }
}

async fn accept_file_offer(state: &mut NodeState, peer: &str, offer: FileOffer) -> Result<()> {
    let part_path = state
        .downloads_dir
        .join(format!("{}.part", offer.transfer_id));
    let existing = tokio::fs::metadata(&part_path)
        .await
        .map(|metadata| metadata.len())
        .unwrap_or(0);
    let offset = if existing > offer.size { 0 } else { existing };
    let incoming = IncomingFile::open(
        &state.downloads_dir,
        offer.transfer_id,
        &offer.name,
        offer.size,
        &offer.blake3,
        offset,
    )
    .await?;
    state.incoming.insert(offer.transfer_id, incoming);
    let row = TransferRow {
        id: offer.transfer_id,
        peer: peer.to_string(),
        direction: "in".into(),
        path: part_path.to_string_lossy().to_string(),
        name: offer.name.clone(),
        size: offer.size,
        offset,
        blake3: offer.blake3.clone(),
        state: "receiving".into(),
        created_at: identity::unix_now(),
    };
    state.storage.insert_transfer(&row)?;
    emit(
        &state.events,
        Event::FileOffer {
            transfer_id: offer.transfer_id,
            device_id: peer.to_string(),
            name: offer.name.clone(),
            size: offer.size,
            offset,
        },
    );
    send_frame(
        state,
        peer,
        Frame::Control(Payload::FileAccept {
            transfer_id: offer.transfer_id,
            offset,
        }),
    )
    .await
}

async fn set_visibility(state: &mut NodeState, peer: &str, visible: bool) -> Result<()> {
    if state.storage.person(peer)?.is_none() {
        bail!("unknown peer");
    }
    state.storage.set_hidden(peer, !visible)?;
    if let Some(connected) = state.peers.get(peer) {
        let _ = connected
            .out_tx
            .send(Frame::Control(Payload::Visibility { visible }))
            .await;
    }
    emit(
        &state.events,
        Event::PeerVisibility {
            device_id: peer.to_string(),
            visible,
        },
    );
    Ok(())
}

async fn send_frame(state: &mut NodeState, peer: &str, frame: Frame) -> Result<()> {
    let Some(connected) = state.peers.get(peer) else {
        bail!("peer is offline");
    };
    connected
        .out_tx
        .send(frame)
        .await
        .map_err(|_| anyhow::anyhow!("peer disconnected"))
}

async fn maybe_dial(state: &mut NodeState, address: &str) {
    if let Some(at) = state.dialed_at.get(address) {
        if at.elapsed() < state.dial_interval {
            return;
        }
    }
    state.dialed_at.insert(address.to_string(), Instant::now());
    let context = session_context(state);
    let tx = state.session_tx.clone();
    let address_owned = address.to_string();
    tokio::spawn(async move {
        match TcpStream::connect(&address_owned).await {
            Ok(stream) => {
                if let Err(error) = run_session(stream, true, context, tx).await {
                    debug!("outbound session to {address_owned} ended: {error:#}");
                }
            }
            Err(error) => {
                debug!("connecting to {address_owned} failed: {error}");
            }
        }
    });
}

fn session_context(state: &NodeState) -> SessionContext {
    SessionContext {
        identity: state.identity.clone(),
        noise_private: state.noise_private.clone(),
        storage: state.storage.clone(),
        device_id: state.device_id.clone(),
        name: state.name.clone(),
    }
}

async fn run_session(
    mut stream: TcpStream,
    initiator: bool,
    context: SessionContext,
    events: mpsc::Sender<SessionEvent>,
) -> Result<()> {
    let handshake = Handshake::new(initiator, &context.noise_private)?;
    let channel = handshake.run(&mut stream).await?;
    let handshake_hash = channel.handshake_hash().to_vec();
    let (mut transport, _, _) = channel.into_parts();

    let signature = BASE64.encode(
        context
            .identity
            .sign(&binding_message(&handshake_hash))
            .to_bytes(),
    );
    let probe = Hello {
        version: PROTOCOL_VERSION,
        device_id: context.device_id.clone(),
        name: String::new(),
        avatar: None,
        identity_created_at: context.identity.created_at(),
        signature,
    };
    crypto::write_frame(
        &mut transport,
        &mut stream,
        &Frame::Control(Payload::Hello(probe.clone())),
    )
    .await?;
    let peer_probe = read_hello(&mut transport, &mut stream, &handshake_hash).await?;
    let peer_id = peer_probe.device_id.clone();

    // If this peer is hidden, never send our name. The peer learns only our
    // device key and receives VISIBILITY(false).
    let hidden = context
        .storage
        .person(&peer_id)?
        .map(|person| person.hidden)
        .unwrap_or(false);
    if hidden {
        let _ = crypto::write_frame(
            &mut transport,
            &mut stream,
            &Frame::Control(Payload::Visibility { visible: false }),
        )
        .await;
        // Read the peer's answer before closing. Closing with unread data in
        // the socket buffer makes the kernel send a reset, which can destroy
        // the VISIBILITY frame on the peer's side.
        let _ = tokio::time::timeout(
            Duration::from_secs(3),
            read_next_control(&mut transport, &mut stream),
        )
        .await;
        let _ = stream.shutdown().await;
        let _ = events
            .send(SessionEvent::HiddenPeer { device_id: peer_id })
            .await;
        return Ok(());
    }

    let hello = Hello {
        name: context.name.clone(),
        ..probe
    };
    crypto::write_frame(
        &mut transport,
        &mut stream,
        &Frame::Control(Payload::Hello(hello)),
    )
    .await?;

    let peer_hello = match read_next_control(&mut transport, &mut stream).await? {
        Payload::Hello(hello) => hello,
        Payload::Visibility { visible: false } => {
            let _ = context.storage.set_hidden_by_peer(&peer_id, true);
            let _ = events
                .send(SessionEvent::HiddenByPeer { device_id: peer_id })
                .await;
            return Ok(());
        }
        Payload::Ack {
            state: AckState::NameTaken,
            ..
        } => {
            let _ = events
                .send(SessionEvent::Error {
                    device_id: Some(peer_id),
                    message: format!("name already taken: {}", context.name),
                })
                .await;
            return Ok(());
        }
        _ => bail!("peer did not answer the hello"),
    };
    if peer_hello.name.is_empty() {
        bail!("peer sent an empty name");
    }
    identity::verify_signature(
        &peer_hello.device_id,
        &binding_message(&handshake_hash),
        &peer_hello.signature,
    )?;
    if peer_hello.device_id != peer_probe.device_id {
        bail!("peer identity changed during the handshake");
    }

    // Unique names: the newer device is asked to rename.
    if let Some(existing) = context.storage.person_by_name(&peer_hello.name)? {
        if existing.device_id != peer_id {
            let we_are_older = (context.identity.created_at(), &context.device_id)
                < (peer_hello.identity_created_at, &peer_id);
            if we_are_older {
                let _ = crypto::write_frame(
                    &mut transport,
                    &mut stream,
                    &Frame::Control(Payload::Ack {
                        message_id: Uuid::nil(),
                        state: AckState::NameTaken,
                    }),
                )
                .await;
            }
            let _ = events
                .send(SessionEvent::NameConflict {
                    device_id: peer_id,
                    name: peer_hello.name.clone(),
                })
                .await;
            return Ok(());
        }
    }

    let person = Person {
        device_id: peer_id.clone(),
        name: peer_hello.name.clone(),
        avatar: peer_hello.avatar.clone(),
        hidden: false,
        hidden_by_peer: false,
        identity_created_at: peer_hello.identity_created_at,
        last_seen: Some(identity::unix_now()),
    };
    if let Err(error) = context.storage.upsert_person_keep_visibility(&person) {
        let _ = events
            .send(SessionEvent::Error {
                device_id: Some(peer_id),
                message: error.to_string(),
            })
            .await;
        return Ok(());
    }

    crypto::write_frame(
        &mut transport,
        &mut stream,
        &Frame::Control(Payload::Presence {
            state: PresenceState::Online,
        }),
    )
    .await?;

    let (mut read_half, mut write_half) = stream.into_split();
    let transport: SharedTransport = Arc::new(Mutex::new(transport));
    let (out_tx, mut out_rx) = mpsc::channel::<Frame>(OUT_QUEUE);
    let (shutdown, shutdown_rx) = watch::channel(false);
    let connection_id = Uuid::new_v4();

    let writer_transport = transport.clone();
    let mut writer_shutdown = shutdown.subscribe();
    let writer = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = writer_shutdown.changed() => {
                    if changed.is_err() || *writer_shutdown.borrow() {
                        break;
                    }
                }
                frame = out_rx.recv() => {
                    let Some(frame) = frame else { break };
                    let Ok(ciphertext) = crypto::encrypt_frame(&writer_transport, &frame) else {
                        break;
                    };
                    if crypto::write_wire(&mut write_half, &ciphertext).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    if events
        .send(SessionEvent::Up {
            connection_id,
            device_id: peer_id.clone(),
            name: peer_hello.name.clone(),
            initiator,
            out_tx,
            shutdown,
        })
        .await
        .is_err()
    {
        writer.abort();
        return Ok(());
    }

    let mut reader_shutdown = shutdown_rx;
    let reader_transport = transport.clone();
    loop {
        tokio::select! {
            changed = reader_shutdown.changed() => {
                if changed.is_err() || *reader_shutdown.borrow() {
                    break;
                }
            }
            wire = crypto::read_wire(&mut read_half) => {
                match wire {
                    Ok(ciphertext) => {
                        match crypto::decrypt_frame(&reader_transport, &ciphertext) {
                            Ok(frame) => {
                                if events.send(SessionEvent::Frame {
                                    device_id: peer_id.clone(),
                                    frame,
                                }).await.is_err() {
                                    break;
                                }
                            }
                            Err(error) => {
                                warn!("decrypting a frame failed: {error:#}");
                                break;
                            }
                        }
                    }
                    Err(_) => break,
                }
            }
        }
    }

    writer.abort();
    let _ = events
        .send(SessionEvent::Down {
            connection_id,
            device_id: peer_id,
        })
        .await;
    Ok(())
}

async fn read_next_control(
    transport: &mut snow::TransportState,
    stream: &mut TcpStream,
) -> Result<Payload> {
    match crypto::read_frame(transport, stream).await? {
        Frame::Control(payload) => Ok(payload),
        Frame::Chunk { .. } => bail!("unexpected file chunk during the handshake"),
    }
}

async fn read_hello(
    transport: &mut snow::TransportState,
    stream: &mut TcpStream,
    handshake_hash: &[u8],
) -> Result<Hello> {
    let payload = read_next_control(transport, stream).await?;
    let Payload::Hello(hello) = payload else {
        bail!("peer did not send HELLO");
    };
    if hello.version != PROTOCOL_VERSION {
        bail!("unsupported protocol version {}", hello.version);
    }
    identity::verify_signature(
        &hello.device_id,
        &binding_message(handshake_hash),
        &hello.signature,
    )?;
    Ok(hello)
}

fn binding_message(handshake_hash: &[u8]) -> Vec<u8> {
    let mut message = b"kinly-hello-v1".to_vec();
    message.extend_from_slice(handshake_hash);
    message
}
