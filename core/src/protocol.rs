//! Wire protocol: encrypted frames exchanged inside a Noise session.
//!
//! Every frame is one Noise transport message. The plaintext starts with a
//! one-byte kind, followed by either a JSON control payload or file data.

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Maximum plaintext size of a single Noise transport message.
pub const MAX_PLAINTEXT: usize = 65_519;

/// File data carried by a single chunk frame.
pub const FILE_CHUNK_SIZE: usize = 32 * 1024;

/// Control frames are JSON.
pub const KIND_CONTROL: u8 = 0x01;
/// File chunk frames carry raw bytes.
pub const KIND_CHUNK: u8 = 0x02;

pub const PROTOCOL_VERSION: u16 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AckState {
    Delivered,
    Read,
    Failed,
    NameTaken,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PresenceState {
    Online,
    Offline,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hello {
    pub version: u16,
    /// Ed25519 public key, hex encoded.
    pub device_id: String,
    pub name: String,
    /// Optional avatar, base64 encoded (PNG or JPEG).
    pub avatar: Option<String>,
    /// Unix time at which the identity was created.
    pub identity_created_at: u64,
    /// Ed25519 signature over the Noise handshake hash. Binds the identity to
    /// this encrypted session and proves possession of the private key.
    pub signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileOffer {
    pub transfer_id: Uuid,
    pub name: String,
    pub size: u64,
    /// BLAKE3 hash of the whole file, hex encoded.
    pub blake3: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallSignal {
    pub call_id: Uuid,
    /// Opaque signaling payload (SDP / ICE), produced by WebRTC on the app side.
    pub payload: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Payload {
    Hello(Hello),
    Msg {
        id: Uuid,
        body: String,
        sent_at: u64,
    },
    Ack {
        message_id: Uuid,
        state: AckState,
    },
    Typing {
        typing: bool,
    },
    FileOffer(FileOffer),
    FileAccept {
        transfer_id: Uuid,
        /// Byte offset the receiver already has; transfer resumes from here.
        offset: u64,
    },
    FileCancel {
        transfer_id: Uuid,
        reason: String,
    },
    CallSignal(CallSignal),
    /// `visible == false` means the sender is hiding from the receiver.
    Visibility {
        visible: bool,
    },
    Presence {
        state: PresenceState,
    },
}

/// Decrypted frame.
#[derive(Debug, Clone)]
pub enum Frame {
    Control(Payload),
    Chunk {
        transfer_id: Uuid,
        offset: u64,
        last: bool,
        data: Vec<u8>,
    },
}

impl Frame {
    pub fn control(payload: Payload) -> Self {
        Frame::Control(payload)
    }
}

pub fn encode(frame: &Frame) -> Result<Vec<u8>> {
    match frame {
        Frame::Control(payload) => {
            let body = serde_json::to_vec(payload)?;
            let mut out = Vec::with_capacity(body.len() + 1);
            out.push(KIND_CONTROL);
            out.extend_from_slice(&body);
            if out.len() > MAX_PLAINTEXT {
                bail!("control frame is too large");
            }
            Ok(out)
        }
        Frame::Chunk {
            transfer_id,
            offset,
            last,
            data,
        } => {
            if data.len() > FILE_CHUNK_SIZE {
                bail!("file chunk is too large");
            }
            let mut out = Vec::with_capacity(data.len() + 26);
            out.push(KIND_CHUNK);
            out.extend_from_slice(transfer_id.as_bytes());
            out.extend_from_slice(&offset.to_be_bytes());
            out.push(u8::from(*last));
            out.extend_from_slice(data);
            Ok(out)
        }
    }
}

pub fn decode(plaintext: &[u8]) -> Result<Frame> {
    let (kind, rest) = plaintext
        .split_first()
        .ok_or_else(|| anyhow::anyhow!("empty frame"))?;
    match *kind {
        KIND_CONTROL => Ok(Frame::Control(serde_json::from_slice(rest)?)),
        KIND_CHUNK => {
            if rest.len() < 25 {
                bail!("truncated file chunk");
            }
            let transfer_id = Uuid::from_slice(&rest[..16])?;
            let offset = u64::from_be_bytes(rest[16..24].try_into()?);
            let last = rest[24] != 0;
            Ok(Frame::Chunk {
                transfer_id,
                offset,
                last,
                data: rest[25..].to_vec(),
            })
        }
        other => bail!("unknown frame kind {other}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_offer() -> FileOffer {
        FileOffer {
            transfer_id: Uuid::new_v4(),
            name: "photo.jpg".into(),
            size: 1234,
            blake3: "ab".repeat(32),
        }
    }

    #[test]
    fn control_round_trip() {
        let frame = Frame::Control(Payload::Msg {
            id: Uuid::new_v4(),
            body: "مرحبا".into(),
            sent_at: 42,
        });
        let decoded = decode(&encode(&frame).unwrap()).unwrap();
        match decoded {
            Frame::Control(Payload::Msg { body, sent_at, .. }) => {
                assert_eq!(body, "مرحبا");
                assert_eq!(sent_at, 42);
            }
            _ => panic!("wrong frame"),
        }
    }

    #[test]
    fn file_offer_round_trip() {
        let offer = sample_offer();
        let frame = Frame::Control(Payload::FileOffer(offer.clone()));
        match decode(&encode(&frame).unwrap()).unwrap() {
            Frame::Control(Payload::FileOffer(decoded)) => {
                assert_eq!(decoded.transfer_id, offer.transfer_id);
                assert_eq!(decoded.size, offer.size);
            }
            _ => panic!("wrong frame"),
        }
    }

    #[test]
    fn chunk_round_trip() {
        let id = Uuid::new_v4();
        let data = vec![7u8; 1024];
        let frame = Frame::Chunk {
            transfer_id: id,
            offset: 4096,
            last: true,
            data: data.clone(),
        };
        match decode(&encode(&frame).unwrap()).unwrap() {
            Frame::Chunk {
                transfer_id,
                offset,
                last,
                data: decoded,
            } => {
                assert_eq!(transfer_id, id);
                assert_eq!(offset, 4096);
                assert!(last);
                assert_eq!(decoded, data);
            }
            _ => panic!("wrong frame"),
        }
    }

    #[test]
    fn rejects_oversized_chunk() {
        let frame = Frame::Chunk {
            transfer_id: Uuid::new_v4(),
            offset: 0,
            last: false,
            data: vec![0u8; FILE_CHUNK_SIZE + 1],
        };
        assert!(encode(&frame).is_err());
    }
}
