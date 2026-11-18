//! Kinly command line client.
//!
//! Phase 1 of the plan: two processes on a LAN (or one machine) discover each
//! other, exchange encrypted text messages and files, and can hide from each
//! other. The Flutter app reuses the same `kinly-core` node.
//!
//! Author: Abdullah (@abdullah4xx)

use anyhow::{Context, Result};
use clap::Parser;
use kinly_core::node::{self, Config, Event, NodeHandle};
use kinly_core::storage::Storage;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::AsyncBufReadExt;
use tokio::sync::mpsc;

#[derive(Parser, Debug)]
#[command(
    name = "kinly",
    about = "Kinly: offline end-to-end encrypted family chat"
)]
struct Args {
    /// Name shown to the other people on the network.
    #[arg(short, long)]
    name: Option<String>,
    /// Data directory (defaults to ~/.local/share/kinly).
    #[arg(short, long)]
    data: Option<PathBuf>,
    /// TCP port to listen on (0 picks a random free port).
    #[arg(short, long, default_value_t = 0)]
    port: u16,
    /// Manual peer address host:port (repeatable, useful without mDNS).
    #[arg(long)]
    peer: Vec<String>,
    /// Disable mDNS discovery.
    #[arg(long)]
    no_mdns: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::WARN)
        .init();

    let args = Args::parse();
    let data_dir = args.data.clone().unwrap_or_else(|| {
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("kinly")
    });
    std::fs::create_dir_all(&data_dir)
        .with_context(|| format!("creating {}", data_dir.display()))?;

    let name = match args.name.clone() {
        Some(name) => name,
        None => {
            let storage = Storage::open(&data_dir)?;
            storage
                .get_setting("name")?
                .context("no name yet, start with --name <your name>")?
        }
    };

    let mut config = Config::new(name, data_dir);
    config.listen_port = args.port;
    config.peers = args.peer.clone();
    config.enable_mdns = !args.no_mdns;

    let handle = node::start(config).await?;
    println!("Kinly - offline end-to-end encrypted chat");
    println!("  name:      {}", handle.name());
    println!("  device:    {}", handle.device_id);
    println!("  port:      {}", handle.port);
    if args.no_mdns {
        println!("  discovery: off");
    }
    println!("Type /help for the commands. /quit to exit.");
    println!();

    let mut names: HashMap<String, String> = handle
        .people()
        .await?
        .into_iter()
        .map(|person| (person.device_id, person.name))
        .collect();
    let mut online: HashSet<String> = HashSet::new();
    let mut percent: HashMap<uuid::Uuid, u64> = HashMap::new();

    let (line_tx, mut line_rx) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        let mut reader = tokio::io::BufReader::new(tokio::io::stdin());
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line).await {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if line_tx.send(line.trim_end().to_string()).is_err() {
                        break;
                    }
                }
            }
        }
    });

    let mut events = handle.subscribe();
    let quit = loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => break true,
            line = line_rx.recv() => {
                let Some(line) = line else { break true };
                if !handle_command(&handle, &mut names, &line).await? {
                    break false;
                }
            }
            event = events.recv() => {
                let Ok(event) = event else { break true };
                print_event(&handle, &mut names, &mut online, &mut percent, event).await?;
            }
        }
    };
    let _ = quit;

    println!("bye.");
    handle.shutdown().await;
    // Give the actor a moment to close sessions and the advertisement.
    tokio::time::sleep(Duration::from_millis(100)).await;
    Ok(())
}

/// Handles one input line. Returns false on /quit.
async fn handle_command(
    handle: &NodeHandle,
    names: &mut HashMap<String, String>,
    line: &str,
) -> Result<bool> {
    let line = line.trim();
    if line.is_empty() {
        return Ok(true);
    }
    let mut parts = line.splitn(3, char::is_whitespace);
    let command = parts.next().unwrap_or_default().to_lowercase();
    match command.as_str() {
        "/quit" | "/exit" => return Ok(false),
        "/help" => {
            println!(
                "  /list                 known people and their status\n\
                 \x20 /msg <name> <text>    send a text message\n\
                 \x20 /send <name> <path>  send a file\n\
                 \x20 /history <name>      last 30 messages with a person\n\
                 \x20 /hide <name>         hide yourself from a person\n\
                 \x20 /show <name>         become visible to a person again\n\
                 \x20 /whoami              your name and device ID\n\
                 \x20 /quit                exit"
            );
        }
        "/whoami" => {
            println!("{} ({})", handle.name(), handle.device_id);
        }
        "/list" => {
            let people = handle.people().await?;
            if people.is_empty() {
                println!("nobody yet - is the other device on the same network?");
            }
            for person in people {
                names.insert(person.device_id.clone(), person.name.clone());
                println!(
                    "  {:<20} {:<10} you:{:<6} them:{}",
                    person.name,
                    if person.hidden { "hidden" } else { "visible" },
                    if person.hidden_by_peer {
                        "hidden"
                    } else {
                        "visible"
                    },
                    person.device_id
                );
            }
        }
        "/msg" => {
            let Some(rest) = line.get(command.len()..) else {
                return Ok(true);
            };
            let rest = rest.trim_start();
            let Some((name, body)) = rest.split_once(char::is_whitespace) else {
                println!("usage: /msg <name> <text>");
                return Ok(true);
            };
            let body = body.trim();
            if body.is_empty() {
                println!("usage: /msg <name> <text>");
                return Ok(true);
            }
            match resolve(handle, names, name).await {
                Some(device_id) => {
                    let id = handle.send_message(&device_id, body).await?;
                    println!("-> {}: {} ({})", name, body, short(id));
                }
                None => println!("unknown name: {name} (try /list)"),
            }
        }
        "/send" => {
            let Some(rest) = line.get(command.len()..) else {
                return Ok(true);
            };
            let rest = rest.trim_start();
            let Some((name, path)) = rest.split_once(char::is_whitespace) else {
                println!("usage: /send <name> <path>");
                return Ok(true);
            };
            match resolve(handle, names, name).await {
                Some(device_id) => {
                    let id = handle
                        .send_file(&device_id, PathBuf::from(path.trim()))
                        .await?;
                    println!("sending {path} to {name} ({})", short(id));
                }
                None => println!("unknown name: {name} (try /list)"),
            }
        }
        "/history" => {
            let Some(name) = parts.next() else {
                println!("usage: /history <name>");
                return Ok(true);
            };
            match resolve(handle, names, name).await {
                Some(device_id) => {
                    for message in handle.history(&device_id, 30).await? {
                        println!(
                            "  {} {} {}",
                            if message.direction == "in" {
                                "<-"
                            } else {
                                "->"
                            },
                            message.body,
                            message.state
                        );
                    }
                }
                None => println!("unknown name: {name}"),
            }
        }
        "/hide" | "/show" => {
            let Some(name) = parts.next() else {
                println!("usage: {command} <name>");
                return Ok(true);
            };
            match resolve(handle, names, name).await {
                Some(device_id) => {
                    let visible = command == "/show";
                    handle.set_visibility(&device_id, visible).await?;
                    if visible {
                        println!("you are visible to {name}");
                    } else {
                        println!("you are hidden from {name}");
                    }
                }
                None => println!("unknown name: {name}"),
            }
        }
        other => println!("unknown command: {other} (try /help)"),
    }
    Ok(true)
}

async fn resolve(
    handle: &NodeHandle,
    names: &mut HashMap<String, String>,
    name: &str,
) -> Option<String> {
    let people = handle.people().await.ok()?;
    let found = people
        .iter()
        .find(|person| person.name == name)
        .or_else(|| {
            people
                .iter()
                .find(|person| person.name.eq_ignore_ascii_case(name))
        })?;
    names.insert(found.device_id.clone(), found.name.clone());
    Some(found.device_id.clone())
}

async fn print_event(
    handle: &NodeHandle,
    names: &mut HashMap<String, String>,
    online: &mut HashSet<String>,
    percent: &mut HashMap<uuid::Uuid, u64>,
    event: Event,
) -> Result<()> {
    let _ = handle;
    match event {
        Event::PeerUp { device_id, name } => {
            names.insert(device_id.clone(), name.clone());
            online.insert(device_id);
            println!("[*] {name} is online");
        }
        Event::PeerDown { device_id } => {
            online.remove(&device_id);
            println!("[*] {} is offline", display_name(names, &device_id));
        }
        Event::ProfileChanged { name, .. } => {
            println!("[*] profile updated: {name}");
        }
        Event::PeerVisibility { device_id, visible } => {
            let name = display_name(names, &device_id);
            if visible {
                println!("[*] you are visible to {name}");
            } else {
                println!("[*] {name} is hidden");
            }
        }
        Event::Message { message, .. } => {
            let name = display_name(names, &message.peer);
            if message.direction == "in" {
                println!("{name}: {}", message.body);
            }
        }
        Event::MessageState { message_id, state } => match state.as_str() {
            "failed" | "name_taken" => {
                println!("[!] message {} {state}", short(message_id));
            }
            _ => {}
        },
        Event::Typing { device_id, typing } => {
            if typing {
                println!("[*] {} is typing", display_name(names, &device_id));
            }
        }
        Event::FileOffer {
            transfer_id,
            device_id,
            name,
            size,
            offset,
        } => {
            println!(
                "[*] {} is sending {name} ({} bytes, resuming at {offset})",
                display_name(names, &device_id),
                size
            );
            percent.insert(transfer_id, 0);
        }
        Event::FileProgress {
            transfer_id,
            received,
            total,
        } => {
            if let Some(value) = received
                .checked_mul(100)
                .and_then(|value| value.checked_div(total))
            {
                let shown = percent.entry(transfer_id).or_insert(0);
                if value >= *shown + 10 || received == total {
                    *shown = value;
                    println!("    {value}% ({received}/{total})");
                }
            }
        }
        Event::FileComplete { transfer_id, path } => {
            percent.remove(&transfer_id);
            println!("[*] file saved to {path}");
        }
        Event::FileFailed { transfer_id, error } => {
            percent.remove(&transfer_id);
            println!("[!] transfer {} failed: {error}", short(transfer_id));
        }
        Event::FileSent { transfer_id } => {
            percent.remove(&transfer_id);
            println!("[*] file sent ({})", short(transfer_id));
        }
        Event::CallSignal {
            device_id, payload, ..
        } => {
            println!(
                "[*] call signal from {}: {payload}",
                display_name(names, &device_id)
            );
        }
        Event::NameConflict { name, .. } => {
            println!("[!] the name \"{name}\" is already used by another device");
        }
        Event::Error { message } => println!("[!] {message}"),
    }
    Ok(())
}

fn display_name(names: &HashMap<String, String>, device_id: &str) -> String {
    names
        .get(device_id)
        .cloned()
        .unwrap_or_else(|| device_id.chars().take(8).collect())
}

fn short(id: uuid::Uuid) -> String {
    id.to_string().chars().take(8).collect()
}
