//! File transfer helpers: hashing, sanitizing names, incremental receive with
//! resume support.

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use tokio::fs::{File, OpenOptions};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt, SeekFrom};

const HASH_BUFFER: usize = 256 * 1024;

/// Computes the BLAKE3 hash of a file, hex encoded.
pub async fn hash_file(path: &Path) -> Result<String> {
    let mut file = File::open(path)
        .await
        .with_context(|| format!("opening {}", path.display()))?;
    let mut hasher = blake3::Hasher::new();
    let mut buffer = vec![0u8; HASH_BUFFER];
    loop {
        let read = file.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

/// Keeps only a safe file name (no directories, no control characters).
pub fn safe_file_name(name: &str) -> String {
    let base = Path::new(name)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("file");
    let cleaned: String = base
        .chars()
        .map(|c| {
            if c.is_control() || matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') {
                '_'
            } else {
                c
            }
        })
        .collect();
    if cleaned.trim().is_empty() {
        "file".to_string()
    } else {
        cleaned
    }
}

/// A file being received. Bytes are written to `<transfer_id>.part` and the
/// file is renamed into place after the hash is verified.
pub struct IncomingFile {
    file: File,
    part_path: PathBuf,
    final_path: PathBuf,
    size: u64,
    written: u64,
    hasher: blake3::Hasher,
    expected_hash: String,
}

impl IncomingFile {
    /// Opens (or resumes) an incoming transfer. `offset` is the number of bytes
    /// already present in the `.part` file.
    pub async fn open(
        downloads_dir: &Path,
        transfer_id: uuid::Uuid,
        name: &str,
        size: u64,
        expected_hash: &str,
        offset: u64,
    ) -> Result<Self> {
        tokio::fs::create_dir_all(downloads_dir).await?;
        let part_path = downloads_dir.join(format!("{transfer_id}.part"));
        let final_path = unique_path(downloads_dir, &safe_file_name(name)).await;
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&part_path)
            .await?;
        let existing = file.metadata().await?.len();
        let mut hasher = blake3::Hasher::new();
        if existing > offset {
            file.set_len(offset).await?;
        }
        if offset > 0 {
            file.seek(SeekFrom::Start(0)).await?;
            let mut buffer = vec![0u8; HASH_BUFFER];
            let mut remaining = offset;
            while remaining > 0 {
                let want = remaining.min(buffer.len() as u64) as usize;
                let read = file.read(&mut buffer[..want]).await?;
                if read == 0 {
                    bail!("partial file is shorter than the resume offset");
                }
                hasher.update(&buffer[..read]);
                remaining -= read as u64;
            }
        }
        file.seek(SeekFrom::Start(offset)).await?;
        Ok(Self {
            file,
            part_path,
            final_path,
            size,
            written: offset,
            hasher,
            expected_hash: expected_hash.to_string(),
        })
    }

    pub fn written(&self) -> u64 {
        self.written
    }

    pub fn size(&self) -> u64 {
        self.size
    }

    pub async fn write_chunk(&mut self, offset: u64, data: &[u8]) -> Result<()> {
        if offset != self.written {
            bail!(
                "file chunk out of order: expected offset {}, got {offset}",
                self.written
            );
        }
        if self.written + data.len() as u64 > self.size {
            bail!("file chunk exceeds the announced size");
        }
        self.file.write_all(data).await?;
        self.hasher.update(data);
        self.written += data.len() as u64;
        Ok(())
    }

    /// Flushes, verifies size and hash, and moves the file into place.
    pub async fn finish(mut self) -> Result<PathBuf> {
        self.file.flush().await?;
        self.file.sync_all().await?;
        if self.written != self.size {
            bail!(
                "file size mismatch: expected {}, received {}",
                self.size,
                self.written
            );
        }
        let actual = self.hasher.finalize().to_hex().to_string();
        if actual != self.expected_hash {
            bail!(
                "file hash mismatch: expected {}, got {actual}",
                self.expected_hash
            );
        }
        tokio::fs::rename(&self.part_path, &self.final_path).await?;
        Ok(self.final_path)
    }
}

async fn unique_path(dir: &Path, name: &str) -> PathBuf {
    let candidate = dir.join(name);
    if !tokio::fs::try_exists(&candidate).await.unwrap_or(false) {
        return candidate;
    }
    let path = Path::new(name);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("file");
    let extension = path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let file_name = match extension {
            Some(extension) => format!("{stem} ({index}).{extension}"),
            None => format!("{stem} ({index})"),
        };
        let candidate = dir.join(file_name);
        if !tokio::fs::try_exists(&candidate).await.unwrap_or(false) {
            return candidate;
        }
    }
    dir.join(format!("{stem}-{}", uuid::Uuid::new_v4()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_names() {
        assert_eq!(safe_file_name("../../etc/passwd"), "passwd");
        assert_eq!(safe_file_name("photo.jpg"), "photo.jpg");
        assert_eq!(safe_file_name("a\u{0}b"), "a_b");
        assert_eq!(safe_file_name(""), "file");
    }

    #[tokio::test]
    async fn receives_and_verifies_a_file() {
        let dir = std::env::temp_dir().join(format!("kinly-files-{}", uuid::Uuid::new_v4()));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let source = dir.join("source.bin");
        let data = vec![42u8; 300 * 1024];
        tokio::fs::write(&source, &data).await.unwrap();
        let hash = hash_file(&source).await.unwrap();

        let transfer_id = uuid::Uuid::new_v4();
        let mut incoming = IncomingFile::open(
            &dir,
            transfer_id,
            "received.bin",
            data.len() as u64,
            &hash,
            0,
        )
        .await
        .unwrap();
        for (index, chunk) in data.chunks(crate::protocol::FILE_CHUNK_SIZE).enumerate() {
            incoming
                .write_chunk(
                    index as u64 * crate::protocol::FILE_CHUNK_SIZE as u64,
                    chunk,
                )
                .await
                .unwrap();
        }
        let path = incoming.finish().await.unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), data);
        tokio::fs::remove_dir_all(dir).await.ok();
    }

    #[tokio::test]
    async fn resumes_from_a_partial_file() {
        let dir = std::env::temp_dir().join(format!("kinly-files-{}", uuid::Uuid::new_v4()));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let transfer_id = uuid::Uuid::new_v4();
        let data: Vec<u8> = (0..200_000u32).map(|value| (value % 251) as u8).collect();
        let hash = blake3::hash(&data).to_hex().to_string();
        let part = dir.join(format!("{transfer_id}.part"));
        tokio::fs::write(&part, &data[..75_000]).await.unwrap();

        let mut incoming = IncomingFile::open(
            &dir,
            transfer_id,
            "resumed.bin",
            data.len() as u64,
            &hash,
            75_000,
        )
        .await
        .unwrap();
        for (index, chunk) in data[75_000..].chunks(32 * 1024).enumerate() {
            let offset = 75_000 + index as u64 * 32 * 1024;
            incoming.write_chunk(offset, chunk).await.unwrap();
        }
        let path = incoming.finish().await.unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), data);
        tokio::fs::remove_dir_all(dir).await.ok();
    }
}
