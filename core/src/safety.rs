//! Human-verifiable safety codes.
//!
//! A safety code is derived from both identity public keys (the device IDs) in
//! sorted order, so both devices show the same 60 digits. Comparing the code
//! out of band confirms that the encrypted session is with the expected key.

use anyhow::{Context, Result};
use blake3::Hasher;

/// Domain separator so the code cannot be confused with any other hash we use.
const DOMAIN: &[u8] = b"kinly-safety-v1";

/// Number of five-digit groups in a safety code (60 digits, like Signal).
const GROUPS: usize = 12;

fn key_bytes(device_id: &str) -> Result<[u8; 32]> {
    hex::decode(device_id)
        .context("device id is not valid hex")?
        .try_into()
        .map_err(|_| anyhow::anyhow!("device id has the wrong length"))
}

/// The shared 60-digit code for a pair of devices.
pub fn safety_code(first: &str, second: &str) -> Result<String> {
    let mut keys = [key_bytes(first)?, key_bytes(second)?];
    keys.sort();

    let mut hasher = Hasher::new();
    hasher.update(DOMAIN);
    hasher.update(&keys[0]);
    hasher.update(&keys[1]);

    let mut output = hasher.finalize_xof();
    let mut buffer = [0u8; GROUPS * 8];
    output.fill(&mut buffer);

    let groups: Vec<String> = buffer
        .as_chunks::<8>()
        .0
        .iter()
        .map(|bytes| format!("{:05}", u64::from_le_bytes(*bytes) % 100_000))
        .collect();
    Ok(groups.join(" "))
}

/// A short fingerprint of this device's identity, grouped in fours.
pub fn fingerprint(device_id: &str) -> Result<String> {
    let key = key_bytes(device_id)?;
    let mut hasher = Hasher::new();
    hasher.update(b"kinly-fingerprint-v1");
    hasher.update(&key);
    let digest = hasher.finalize();
    let hex = hex::encode(&digest.as_bytes()[..16]);
    let groups: Vec<&str> = hex
        .as_bytes()
        .chunks(4)
        .map(|chunk| std::str::from_utf8(chunk).unwrap_or_default())
        .collect();
    Ok(groups.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(byte: u8) -> String {
        hex::encode([byte; 32])
    }

    #[test]
    fn both_sides_see_the_same_code() {
        let a = id(1);
        let b = id(2);
        assert_eq!(safety_code(&a, &b).unwrap(), safety_code(&b, &a).unwrap());
    }

    #[test]
    fn code_is_sixty_digits_in_twelve_groups() {
        let code = safety_code(&id(3), &id(4)).unwrap();
        let groups: Vec<&str> = code.split(' ').collect();
        assert_eq!(groups.len(), GROUPS);
        for group in groups {
            assert_eq!(group.len(), 5);
            assert!(group.chars().all(|c| c.is_ascii_digit()));
        }
    }

    #[test]
    fn different_pairs_get_different_codes() {
        let first = safety_code(&id(5), &id(6)).unwrap();
        let second = safety_code(&id(5), &id(7)).unwrap();
        assert_ne!(first, second);
    }

    #[test]
    fn fingerprint_is_grouped_hex() {
        let value = fingerprint(&id(8)).unwrap();
        let groups: Vec<&str> = value.split(' ').collect();
        assert_eq!(groups.len(), 8);
        assert!(groups.iter().all(|group| group.len() == 4));
        assert!(value.chars().all(|c| c.is_ascii_hexdigit() || c == ' '));
    }

    #[test]
    fn rejects_bad_keys() {
        assert!(safety_code("nope", &id(1)).is_err());
        assert!(safety_code(&id(1), "00").is_err());
        assert!(fingerprint("").is_err());
    }
}
