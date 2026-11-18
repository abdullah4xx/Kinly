//! Device identity: an Ed25519 key pair created on first run.
//!
//! The public key is the real identity of a device; the display name is only a
//! label bound to that key.

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// Maximum display name length, in characters.
pub const MAX_NAME_LEN: usize = 32;

#[derive(Serialize, Deserialize)]
struct StoredIdentity {
    secret: String,
    created_at: u64,
}

/// A device identity backed by an Ed25519 key pair.
pub struct Identity {
    signing_key: SigningKey,
    created_at: u64,
}

impl Identity {
    /// Loads the identity from `dir`, or creates one on first run.
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        fs::create_dir_all(dir)?;
        let path = dir.join("identity.json");
        if path.exists() {
            let raw = fs::read_to_string(&path)
                .with_context(|| format!("reading identity from {}", path.display()))?;
            let stored: StoredIdentity = serde_json::from_str(&raw)?;
            let secret: [u8; 32] = hex::decode(&stored.secret)
                .context("identity secret is not valid hex")?
                .try_into()
                .map_err(|_| anyhow::anyhow!("identity secret has the wrong length"))?;
            Ok(Self {
                signing_key: SigningKey::from_bytes(&secret),
                created_at: stored.created_at,
            })
        } else {
            let secret: [u8; 32] = rand::random();
            let created_at = unix_now();
            let identity = Self {
                signing_key: SigningKey::from_bytes(&secret),
                created_at,
            };
            let stored = StoredIdentity {
                secret: hex::encode(secret),
                created_at,
            };
            let mut file = fs::OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(0o600)
                .open(&path)?;
            file.write_all(serde_json::to_string_pretty(&stored)?.as_bytes())?;
            file.sync_all()?;
            Ok(identity)
        }
    }

    /// Public identity, hex encoded (64 characters).
    pub fn device_id(&self) -> String {
        hex::encode(self.signing_key.verifying_key().as_bytes())
    }

    pub fn verifying_key(&self) -> VerifyingKey {
        self.signing_key.verifying_key()
    }

    /// Unix time at which the identity was created. Used to resolve duplicate
    /// names: the newer device is the one asked to rename.
    pub fn created_at(&self) -> u64 {
        self.created_at
    }

    pub fn sign(&self, message: &[u8]) -> Signature {
        self.signing_key.sign(message)
    }
}

/// Verifies `signature` (base64) over `message` with the public key encoded in
/// `device_id` (hex). Returns the verifying key on success.
pub fn verify_signature(device_id: &str, message: &[u8], signature: &str) -> Result<VerifyingKey> {
    let key_bytes: [u8; 32] = hex::decode(device_id)
        .context("device id is not valid hex")?
        .try_into()
        .map_err(|_| anyhow::anyhow!("device id has the wrong length"))?;
    let verifying_key = VerifyingKey::from_bytes(&key_bytes)?;
    let sig_bytes: [u8; 64] = BASE64
        .decode(signature)
        .context("signature is not valid base64")?
        .try_into()
        .map_err(|_| anyhow::anyhow!("signature has the wrong length"))?;
    let signature = Signature::from_bytes(&sig_bytes);
    verifying_key.verify_strict(message, &signature)?;
    Ok(verifying_key)
}

/// Validates a display name. Names are unique, so they must also be usable as
/// labels: no control characters and no surrounding whitespace.
pub fn validate_name(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() {
        bail!("name must not be empty");
    }
    if name.chars().count() > MAX_NAME_LEN {
        bail!("name must be at most {MAX_NAME_LEN} characters");
    }
    if name.chars().any(|c| c.is_control()) {
        bail!("name must not contain control characters");
    }
    Ok(name.to_string())
}

pub fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_round_trip() {
        let dir = std::env::temp_dir().join(format!("kinly-identity-{}", uuid::Uuid::new_v4()));
        let first = Identity::load_or_create(&dir).unwrap();
        let second = Identity::load_or_create(&dir).unwrap();
        assert_eq!(first.device_id(), second.device_id());
        assert_eq!(first.device_id().len(), 64);
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn signs_and_verifies() {
        let dir = std::env::temp_dir().join(format!("kinly-identity-{}", uuid::Uuid::new_v4()));
        let identity = Identity::load_or_create(&dir).unwrap();
        let message = b"channel binding";
        let signature = identity.sign(message);
        let encoded = BASE64.encode(signature.to_bytes());
        let verified =
            verify_signature(&identity.device_id(), message, &encoded).expect("valid signature");
        assert_eq!(verified, identity.verifying_key());
        assert!(verify_signature(&identity.device_id(), b"other", &encoded).is_err());
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn rejects_bad_names() {
        assert!(validate_name("  ").is_err());
        assert!(validate_name("Kin\u{1}ly").is_err());
        assert_eq!(validate_name(" عبدالله ").unwrap(), "عبدالله");
        assert!(validate_name(&"a".repeat(MAX_NAME_LEN + 1)).is_err());
    }
}
