//! Encrypted channel: Noise XX handshake and encrypted framing over TCP.
//!
//! We use the `Noise_XX_25519_ChaChaPoly_BLAKE2s` pattern from the `snow`
//! library. The handshake hash is exposed so both sides can sign it with their
//! Ed25519 identity key (channel binding).

use crate::protocol::{self, Frame};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use snow::{Builder, HandshakeState, Keypair, TransportState};
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

pub const NOISE_PARAMS: &str = "Noise_XX_25519_ChaChaPoly_BLAKE2s";
/// Maximum size of a Noise transport message (including the 16-byte tag).
pub const MAX_CIPHERTEXT: usize = 65_535;

#[derive(Serialize, Deserialize)]
struct StoredStaticKey {
    private: String,
}

/// Loads the Noise static key pair from `dir`, or creates it on first run.
pub fn load_or_create_static_key(dir: &Path) -> Result<Keypair> {
    fs::create_dir_all(dir)?;
    let path = dir.join("noise-key.json");
    if path.exists() {
        let raw = fs::read_to_string(&path)?;
        let stored: StoredStaticKey = serde_json::from_str(&raw)?;
        let private = hex::decode(&stored.private)?;
        if private.len() != 32 {
            bail!("Noise static key has the wrong length");
        }
        // The public key is not needed to run a handshake: `snow` derives it
        // from the private key. Keep the field empty for the loaded key.
        Ok(Keypair {
            private,
            public: Vec::new(),
        })
    } else {
        let keypair = Builder::new(NOISE_PARAMS.parse()?).generate_keypair()?;
        let mut file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&path)?;
        file.write_all(
            serde_json::to_string_pretty(&StoredStaticKey {
                private: hex::encode(&keypair.private),
            })?
            .as_bytes(),
        )?;
        file.sync_all()?;
        Ok(keypair)
    }
}

/// One side of an in-progress Noise XX handshake.
pub struct Handshake {
    state: HandshakeState,
    initiator: bool,
}

impl Handshake {
    pub fn new(initiator: bool, private_key: &[u8]) -> Result<Self> {
        let builder = Builder::new(NOISE_PARAMS.parse()?).local_private_key(private_key)?;
        let state = if initiator {
            builder.build_initiator()?
        } else {
            builder.build_responder()?
        };
        Ok(Self { state, initiator })
    }

    /// Runs the three-message XX handshake and returns the secure channel.
    pub async fn run<S>(mut self, stream: &mut S) -> Result<SecureChannel>
    where
        S: AsyncRead + AsyncWrite + Unpin,
    {
        if self.initiator {
            write_handshake_message(stream, &mut self.state).await?;
            read_handshake_message(stream, &mut self.state).await?;
            write_handshake_message(stream, &mut self.state).await?;
        } else {
            read_handshake_message(stream, &mut self.state).await?;
            write_handshake_message(stream, &mut self.state).await?;
            read_handshake_message(stream, &mut self.state).await?;
        }
        if !self.state.is_handshake_finished() {
            bail!("Noise handshake did not finish");
        }
        let handshake_hash = self.state.get_handshake_hash().to_vec();
        let transport = self.state.into_transport_mode()?;
        Ok(SecureChannel {
            transport,
            handshake_hash,
            initiator: self.initiator,
        })
    }
}

pub struct SecureChannel {
    transport: TransportState,
    handshake_hash: Vec<u8>,
    initiator: bool,
}

impl SecureChannel {
    pub fn handshake_hash(&self) -> &[u8] {
        &self.handshake_hash
    }

    pub fn is_initiator(&self) -> bool {
        self.initiator
    }

    pub fn into_parts(self) -> (TransportState, Vec<u8>, bool) {
        (self.transport, self.handshake_hash, self.initiator)
    }
}

async fn write_handshake_message<S>(stream: &mut S, state: &mut HandshakeState) -> Result<()>
where
    S: AsyncWrite + Unpin,
{
    let mut message = vec![0u8; MAX_CIPHERTEXT];
    let len = state.write_message(&[], &mut message)?;
    stream.write_all(&(len as u32).to_be_bytes()).await?;
    stream.write_all(&message[..len]).await?;
    stream.flush().await?;
    Ok(())
}

async fn read_handshake_message<S>(stream: &mut S, state: &mut HandshakeState) -> Result<()>
where
    S: AsyncRead + Unpin,
{
    let mut len_bytes = [0u8; 4];
    stream.read_exact(&mut len_bytes).await?;
    let len = u32::from_be_bytes(len_bytes) as usize;
    if len == 0 || len > MAX_CIPHERTEXT {
        bail!("invalid Noise handshake message length: {len}");
    }
    let mut message = vec![0u8; len];
    stream.read_exact(&mut message).await?;
    let mut payload = vec![0u8; MAX_CIPHERTEXT];
    state.read_message(&message, &mut payload)?;
    Ok(())
}

/// Encrypts and writes one frame.
pub async fn write_frame<W>(
    transport: &mut TransportState,
    writer: &mut W,
    frame: &Frame,
) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    let plaintext = protocol::encode(frame)?;
    let mut ciphertext = vec![0u8; plaintext.len() + 16];
    let len = transport.write_message(&plaintext, &mut ciphertext)?;
    writer.write_all(&(len as u32).to_be_bytes()).await?;
    writer.write_all(&ciphertext[..len]).await?;
    writer.flush().await?;
    Ok(())
}

/// Reads and decrypts one frame.
pub async fn read_frame<R>(transport: &mut TransportState, reader: &mut R) -> Result<Frame>
where
    R: AsyncRead + Unpin,
{
    let mut len_bytes = [0u8; 4];
    reader.read_exact(&mut len_bytes).await?;
    let len = u32::from_be_bytes(len_bytes) as usize;
    if len == 0 || len > MAX_CIPHERTEXT {
        bail!("invalid encrypted frame length: {len}");
    }
    let mut ciphertext = vec![0u8; len];
    reader.read_exact(&mut ciphertext).await?;
    let mut plaintext = vec![0u8; len];
    let plaintext_len = transport.read_message(&ciphertext, &mut plaintext)?;
    protocol::decode(&plaintext[..plaintext_len])
}

/// A Noise transport state shared by the reader and writer tasks.
///
/// The mutex is only held during encryption/decryption (never across I/O), so
/// the reader can wait for bytes while the writer sends a frame.
pub type SharedTransport = std::sync::Arc<std::sync::Mutex<TransportState>>;

/// Encrypts one frame into a Noise message.
pub fn encrypt_frame(transport: &SharedTransport, frame: &Frame) -> Result<Vec<u8>> {
    let plaintext = protocol::encode(frame)?;
    let mut ciphertext = vec![0u8; plaintext.len() + 16];
    let mut guard = transport
        .lock()
        .map_err(|_| anyhow::anyhow!("transport lock poisoned"))?;
    let len = guard.write_message(&plaintext, &mut ciphertext)?;
    ciphertext.truncate(len);
    Ok(ciphertext)
}

/// Decrypts one Noise message into a frame.
pub fn decrypt_frame(transport: &SharedTransport, ciphertext: &[u8]) -> Result<Frame> {
    let mut plaintext = vec![0u8; ciphertext.len()];
    let mut guard = transport
        .lock()
        .map_err(|_| anyhow::anyhow!("transport lock poisoned"))?;
    let len = guard.read_message(ciphertext, &mut plaintext)?;
    protocol::decode(&plaintext[..len])
}

/// Writes a length-prefixed encrypted message.
pub async fn write_wire<W>(writer: &mut W, ciphertext: &[u8]) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    writer
        .write_all(&(ciphertext.len() as u32).to_be_bytes())
        .await?;
    writer.write_all(ciphertext).await?;
    writer.flush().await?;
    Ok(())
}

/// Reads a length-prefixed encrypted message.
pub async fn read_wire<R>(reader: &mut R) -> Result<Vec<u8>>
where
    R: AsyncRead + Unpin,
{
    let mut len_bytes = [0u8; 4];
    reader.read_exact(&mut len_bytes).await?;
    let len = u32::from_be_bytes(len_bytes) as usize;
    if len == 0 || len > MAX_CIPHERTEXT {
        bail!("invalid encrypted frame length: {len}");
    }
    let mut ciphertext = vec![0u8; len];
    reader.read_exact(&mut ciphertext).await?;
    Ok(ciphertext)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{Payload, FILE_CHUNK_SIZE};

    fn keypair() -> Keypair {
        Builder::new(NOISE_PARAMS.parse().unwrap())
            .generate_keypair()
            .unwrap()
    }

    #[tokio::test]
    async fn handshake_and_exchange_frames() {
        let alice_key = keypair();
        let bob_key = keypair();
        let (mut alice_io, mut bob_io) = tokio::io::duplex(MAX_CIPHERTEXT * 2);

        let alice = tokio::spawn(async move {
            Handshake::new(true, &alice_key.private)
                .unwrap()
                .run(&mut alice_io)
                .await
                .map(|channel| (channel, alice_io))
        });
        let bob = tokio::spawn(async move {
            Handshake::new(false, &bob_key.private)
                .unwrap()
                .run(&mut bob_io)
                .await
                .map(|channel| (channel, bob_io))
        });

        let (alice, mut alice_io) = alice.await.unwrap().unwrap();
        let (bob, mut bob_io) = bob.await.unwrap().unwrap();

        assert_eq!(alice.handshake_hash(), bob.handshake_hash());
        assert!(alice.is_initiator());
        assert!(!bob.is_initiator());

        let (mut alice_transport, hash, _) = alice.into_parts();
        let (mut bob_transport, bob_hash, _) = bob.into_parts();
        assert_eq!(hash, bob_hash);

        let frame = Frame::Control(Payload::Msg {
            id: uuid::Uuid::new_v4(),
            body: "hello".into(),
            sent_at: 1,
        });
        write_frame(&mut alice_transport, &mut alice_io, &frame)
            .await
            .unwrap();
        let received = read_frame(&mut bob_transport, &mut bob_io).await.unwrap();
        match received {
            Frame::Control(Payload::Msg { body, .. }) => assert_eq!(body, "hello"),
            _ => panic!("wrong frame"),
        }
    }

    #[tokio::test]
    async fn transfers_a_file_chunk() {
        let alice_key = keypair();
        let bob_key = keypair();
        let (mut alice_io, mut bob_io) = tokio::io::duplex(MAX_CIPHERTEXT * 4);

        let alice = tokio::spawn(async move {
            Handshake::new(true, &alice_key.private)
                .unwrap()
                .run(&mut alice_io)
                .await
                .map(|channel| (channel, alice_io))
        });
        let bob = tokio::spawn(async move {
            Handshake::new(false, &bob_key.private)
                .unwrap()
                .run(&mut bob_io)
                .await
                .map(|channel| (channel, bob_io))
        });

        let (alice, mut alice_io) = alice.await.unwrap().unwrap();
        let (bob, mut bob_io) = bob.await.unwrap().unwrap();
        let (mut alice_transport, _, _) = alice.into_parts();
        let (mut bob_transport, _, _) = bob.into_parts();

        let id = uuid::Uuid::new_v4();
        let frame = Frame::Chunk {
            transfer_id: id,
            offset: 0,
            last: false,
            data: vec![9u8; FILE_CHUNK_SIZE],
        };
        write_frame(&mut alice_transport, &mut alice_io, &frame)
            .await
            .unwrap();
        match read_frame(&mut bob_transport, &mut bob_io).await.unwrap() {
            Frame::Chunk {
                transfer_id, data, ..
            } => {
                assert_eq!(transfer_id, id);
                assert_eq!(data.len(), FILE_CHUNK_SIZE);
            }
            _ => panic!("wrong frame"),
        }
    }
}
