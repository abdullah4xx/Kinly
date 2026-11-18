//! End-to-end tests: two nodes on the loopback interface, mDNS disabled.
//!
//! These cover the Phase 1 acceptance criteria that can run without hardware:
//! discovery through a manual peer, the encrypted handshake, text messages,
//! file transfer, hiding and unique names.

use kinly_core::node::{self, Config, Event, NodeHandle};
use kinly_core::storage::Person;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::broadcast;
use tokio::time::{sleep, timeout};

struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let path = std::env::temp_dir().join(format!("kinly-e2e-{tag}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

async fn start(name: &str, dir: &TempDir, peers: Vec<String>, dial_ms: u64) -> NodeHandle {
    let mut config = Config::new(name, dir.path());
    config.enable_mdns = false;
    config.peers = peers;
    config.dial_interval = Duration::from_millis(dial_ms);
    node::start(config).await.unwrap()
}

async fn wait_for_person(handle: &NodeHandle, name: &str) -> Person {
    timeout(Duration::from_secs(15), async {
        loop {
            if let Ok(people) = handle.people().await {
                if let Some(person) = people.into_iter().find(|person| person.name == name) {
                    return person;
                }
            }
            sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{name} never appeared"))
}

async fn wait_event<F>(events: &mut broadcast::Receiver<Event>, mut matches: F) -> Event
where
    F: FnMut(&Event) -> bool,
{
    timeout(Duration::from_secs(15), async {
        loop {
            match events.recv().await {
                Ok(event) => {
                    if matches(&event) {
                        return event;
                    }
                }
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => panic!("event stream closed"),
            }
        }
    })
    .await
    .expect("event never arrived")
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_nodes_exchange_messages_files_and_hide() {
    let dir_a = TempDir::new("a");
    let dir_b = TempDir::new("b");

    let bob = start("Bob", &dir_b, Vec::new(), 200).await;
    let mut bob_events = bob.subscribe();

    let alice = start(
        "Alice",
        &dir_a,
        vec![format!("127.0.0.1:{}", bob.port)],
        200,
    )
    .await;
    let mut alice_events = alice.subscribe();

    // Discovery + handshake both ways.
    wait_for_person(&alice, "Bob").await;
    wait_for_person(&bob, "Alice").await;

    // Text messages.
    let message_id = alice
        .send_message(&bob.device_id, "hello bob")
        .await
        .unwrap();
    let received = wait_event(
        &mut bob_events,
        |event| matches!(event, Event::Message { message, .. } if message.body == "hello bob"),
    )
    .await;
    match received {
        Event::Message { device_id, .. } => assert_eq!(device_id, alice.device_id),
        _ => unreachable!(),
    }
    wait_event(&mut alice_events, |event| {
        matches!(
            event,
            Event::MessageState { message_id: id, state } if *id == message_id && state == "delivered"
        )
    })
    .await;

    let reply_id = bob
        .send_message(&alice.device_id, "hello alice")
        .await
        .unwrap();
    assert!(!reply_id.is_nil());
    wait_event(
        &mut alice_events,
        |event| matches!(event, Event::Message { message, .. } if message.body == "hello alice"),
    )
    .await;

    // File transfer with hash verification.
    let source = dir_a.path().join("photo.bin");
    let payload: Vec<u8> = (0..2 * 1024 * 1024u32)
        .map(|value| (value.wrapping_mul(31) % 251) as u8)
        .collect();
    tokio::fs::write(&source, &payload).await.unwrap();
    let transfer_id = alice
        .send_file(&bob.device_id, source.clone())
        .await
        .unwrap();
    let completed = wait_event(
        &mut bob_events,
        |event| matches!(event, Event::FileComplete { transfer_id: id, .. } if *id == transfer_id),
    )
    .await;
    let saved = match completed {
        Event::FileComplete { path, .. } => PathBuf::from(path),
        _ => unreachable!(),
    };
    assert_eq!(tokio::fs::read(&saved).await.unwrap(), payload);

    // Hiding: Alice hides from Bob; Bob's side is told and stops seeing Alice.
    alice.set_visibility(&bob.device_id, false).await.unwrap();
    wait_event(&mut bob_events, |event| {
        matches!(
            event,
            Event::PeerVisibility { device_id, visible: false } if device_id == &alice.device_id
        )
    })
    .await;
    let hidden_on_bob = wait_for_person(&bob, "Alice").await;
    assert!(hidden_on_bob.hidden_by_peer);

    // Writing while hidden turns the toggle back on so the conversation works.
    alice
        .send_message(&bob.device_id, "knock knock")
        .await
        .unwrap();
    wait_event(&mut bob_events, |event| {
        matches!(
            event,
            Event::PeerVisibility { device_id, visible: true } if device_id == &alice.device_id
        )
    })
    .await;
    wait_event(
        &mut bob_events,
        |event| matches!(event, Event::Message { message, .. } if message.body == "knock knock"),
    )
    .await;
    let visible_again = wait_for_person(&alice, "Bob").await;
    assert!(!visible_again.hidden);

    // Unique names: a third device claiming "Alice" is rejected by the older
    // device, which keeps the name bound to Alice's key.
    let dir_c = TempDir::new("c");
    let mallory = start(
        "Alice",
        &dir_c,
        vec![format!("127.0.0.1:{}", bob.port)],
        200,
    )
    .await;
    let conflict = wait_event(
        &mut bob_events,
        |event| matches!(event, Event::NameConflict { name, .. } if name == "Alice"),
    )
    .await;
    match conflict {
        Event::NameConflict { device_id, .. } => assert_eq!(device_id, mallory.device_id),
        _ => unreachable!(),
    }
    sleep(Duration::from_millis(500)).await;
    let people_on_bob = bob.people().await.unwrap();
    assert_eq!(
        people_on_bob
            .iter()
            .filter(|person| person.name == "Alice")
            .count(),
        1
    );
    assert!(people_on_bob
        .iter()
        .all(|person| person.device_id != mallory.device_id));
    mallory.shutdown().await;

    alice.shutdown().await;
    bob.shutdown().await;
    sleep(Duration::from_millis(200)).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_hidden_device_never_sends_its_name() {
    let dir_a = TempDir::new("hidden-a");
    let dir_b = TempDir::new("hidden-b");

    let bob = start("Bob", &dir_b, Vec::new(), 200).await;
    let mut bob_events = bob.subscribe();

    let alice = start(
        "Alice",
        &dir_a,
        vec![format!("127.0.0.1:{}", bob.port)],
        200,
    )
    .await;
    wait_for_person(&alice, "Bob").await;
    wait_for_person(&bob, "Alice").await;

    // Alice hides Bob, then Alice restarts. On the next handshake Alice must
    // not send her name; Bob only receives VISIBILITY(false).
    alice.set_visibility(&bob.device_id, false).await.unwrap();
    wait_event(&mut bob_events, |event| {
        matches!(
            event,
            Event::PeerVisibility { device_id, visible: false } if device_id == &alice.device_id
        )
    })
    .await;
    let alice_id = alice.device_id.clone();
    alice.shutdown().await;
    sleep(Duration::from_millis(300)).await;

    let alice_again = start(
        "Alice",
        &dir_a,
        vec![format!("127.0.0.1:{}", bob.port)],
        200,
    )
    .await;
    let hidden = wait_event(&mut bob_events, |event| {
        matches!(
            event,
            Event::PeerVisibility { device_id, visible: false } if device_id == &alice_id
        )
    })
    .await;
    match hidden {
        Event::PeerVisibility { .. } => {}
        _ => unreachable!(),
    }

    // No peer-up event from the hidden device: its name never reached Bob.
    let result = timeout(Duration::from_millis(500), async {
        loop {
            match bob_events.recv().await {
                Ok(Event::PeerUp { device_id, name }) if device_id == alice_id => {
                    panic!("hidden device came online as {name}");
                }
                Ok(_) => {}
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return,
            }
        }
    })
    .await;
    assert!(
        result.is_err(),
        "unexpected traffic after the hidden handshake"
    );

    alice_again.shutdown().await;
    bob.shutdown().await;
    sleep(Duration::from_millis(200)).await;
}

/// Starts a TCP proxy that records every byte in both directions.
async fn sniffing_proxy(target_port: u16) -> (u16, Arc<Mutex<Vec<u8>>>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let captured = Arc::new(Mutex::new(Vec::new()));
    let sink = captured.clone();
    tokio::spawn(async move {
        while let Ok((client, _)) = listener.accept().await {
            let Ok(server) = TcpStream::connect(("127.0.0.1", target_port)).await else {
                continue;
            };
            let sink = sink.clone();
            tokio::spawn(async move {
                let (mut client_read, mut client_write) = client.into_split();
                let (mut server_read, mut server_write) = server.into_split();
                let client_to_server = {
                    let sink = sink.clone();
                    async move {
                        let mut buffer = [0u8; 16 * 1024];
                        loop {
                            let read = match client_read.read(&mut buffer).await {
                                Ok(0) | Err(_) => break,
                                Ok(read) => read,
                            };
                            sink.lock().unwrap().extend_from_slice(&buffer[..read]);
                            if server_write.write_all(&buffer[..read]).await.is_err() {
                                break;
                            }
                        }
                        let _ = server_write.shutdown().await;
                    }
                };
                let server_to_client = async move {
                    let mut buffer = [0u8; 16 * 1024];
                    loop {
                        let read = match server_read.read(&mut buffer).await {
                            Ok(0) | Err(_) => break,
                            Ok(read) => read,
                        };
                        sink.lock().unwrap().extend_from_slice(&buffer[..read]);
                        if client_write.write_all(&buffer[..read]).await.is_err() {
                            break;
                        }
                    }
                    let _ = client_write.shutdown().await;
                };
                tokio::join!(client_to_server, server_to_client);
            });
        }
    });
    (port, captured)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_packet_capture_contains_no_plaintext() {
    let dir_a = TempDir::new("sniff-a");
    let dir_b = TempDir::new("sniff-b");

    let bob = start("Bob", &dir_b, Vec::new(), 200).await;
    let mut bob_events = bob.subscribe();
    let (proxy_port, captured) = sniffing_proxy(bob.port).await;

    let alice = start(
        "Alice",
        &dir_a,
        vec![format!("127.0.0.1:{proxy_port}")],
        200,
    )
    .await;
    wait_for_person(&alice, "Bob").await;
    wait_for_person(&bob, "Alice").await;

    let marker = "plaintext-marker-8c41f0";
    alice.send_message(&bob.device_id, marker).await.unwrap();
    wait_event(
        &mut bob_events,
        |event| matches!(event, Event::Message { message, .. } if message.body == marker),
    )
    .await;
    sleep(Duration::from_millis(300)).await;

    let bytes = captured.lock().unwrap().clone();
    assert!(bytes.len() > 512, "the capture looks empty");
    // The name is exchanged inside the encrypted channel too.
    for needle in [marker.as_bytes(), b"Alice", b"Bob"] {
        assert!(
            !bytes.windows(needle.len()).any(|window| window == needle),
            "found plaintext {:?} in {} captured bytes",
            String::from_utf8_lossy(needle),
            bytes.len()
        );
    }

    alice.shutdown().await;
    bob.shutdown().await;
    sleep(Duration::from_millis(200)).await;
}
