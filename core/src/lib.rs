//! Kinly core: protocol, crypto, discovery, storage, and file transfer.
//!
//! See `PLAN.md` for scope and phases. All networking, crypto and storage
//! live here; the Flutter app only displays state and sends commands.

pub mod crypto;
pub mod discovery;
pub mod files;
pub mod identity;
pub mod node;
pub mod protocol;
pub mod storage;

/// Returns the crate version.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!version().is_empty());
    }
}
