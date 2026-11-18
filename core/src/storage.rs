//! Encrypted local storage (SQLCipher) for people, messages, transfers and
//! settings.

use anyhow::{bail, Result};
use rusqlite::{params, Connection, OptionalExtension};
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::Mutex;
use std::time::Duration;
use uuid::Uuid;

const SCHEMA: &str = r#"
PRAGMA user_version = 1;

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS people (
    device_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    avatar TEXT,
    hidden INTEGER NOT NULL DEFAULT 0,
    hidden_by_peer INTEGER NOT NULL DEFAULT 0,
    identity_created_at INTEGER NOT NULL DEFAULT 0,
    last_seen INTEGER,
    created_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS people_name_unique ON people(name);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    peer TEXT NOT NULL,
    direction TEXT NOT NULL,
    body TEXT NOT NULL,
    state TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS messages_peer_created ON messages(peer, created_at);

CREATE TABLE IF NOT EXISTS transfers (
    id TEXT PRIMARY KEY,
    peer TEXT NOT NULL,
    direction TEXT NOT NULL,
    path TEXT NOT NULL,
    name TEXT NOT NULL,
    size INTEGER NOT NULL,
    offset INTEGER NOT NULL DEFAULT 0,
    blake3 TEXT NOT NULL,
    state TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
"#;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Person {
    pub device_id: String,
    pub name: String,
    pub avatar: Option<String>,
    pub hidden: bool,
    pub hidden_by_peer: bool,
    pub identity_created_at: u64,
    pub last_seen: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MessageRow {
    pub id: Uuid,
    pub peer: String,
    pub direction: String,
    pub body: String,
    pub state: String,
    pub created_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferRow {
    pub id: Uuid,
    pub peer: String,
    pub direction: String,
    pub path: String,
    pub name: String,
    pub size: u64,
    pub offset: u64,
    pub blake3: String,
    pub state: String,
    pub created_at: u64,
}

pub struct Storage {
    conn: Mutex<Connection>,
}

impl Storage {
    /// Opens (or creates) the encrypted database in `dir`.
    pub fn open(dir: &Path) -> Result<Self> {
        fs::create_dir_all(dir)?;
        let key = load_or_create_db_key(dir)?;
        let path = dir.join("kinly.db");
        let conn = Connection::open(&path)?;
        conn.busy_timeout(Duration::from_secs(10))?;
        let hex_key = hex::encode(key);
        conn.execute_batch(&format!("PRAGMA key = \"x'{hex_key}'\";"))?;
        // Ensure the key is correct before using the database.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))?;
        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO settings(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>> {
        let conn = self.conn.lock().unwrap();
        Ok(conn
            .query_row(
                "SELECT value FROM settings WHERE key = ?1",
                params![key],
                |row| row.get(0),
            )
            .optional()?)
    }

    /// Inserts or updates a person. Fails if the name is already bound to a
    /// different device.
    pub fn upsert_person(&self, person: &Person) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let name_owner: Option<String> = conn
            .query_row(
                "SELECT device_id FROM people WHERE name = ?1",
                params![person.name],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(owner) = name_owner {
            if owner != person.device_id {
                bail!("name already taken: {}", person.name);
            }
        }
        conn.execute(
            "INSERT INTO people
                (device_id, name, avatar, hidden, hidden_by_peer, identity_created_at, last_seen, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(device_id) DO UPDATE SET
                name = excluded.name,
                avatar = excluded.avatar,
                identity_created_at = excluded.identity_created_at,
                last_seen = excluded.last_seen",
            params![
                person.device_id,
                person.name,
                person.avatar,
                i64::from(person.hidden),
                i64::from(person.hidden_by_peer),
                person.identity_created_at as i64,
                person.last_seen.map(|v| v as i64),
                crate::identity::unix_now() as i64,
            ],
        )?;
        Ok(())
    }

    /// Inserts a person only if the device is new. Existing rows keep their
    /// visibility flags so hiding survives reconnects.
    pub fn upsert_person_keep_visibility(&self, person: &Person) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let name_owner: Option<String> = conn
            .query_row(
                "SELECT device_id FROM people WHERE name = ?1",
                params![person.name],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(owner) = name_owner {
            if owner != person.device_id {
                bail!("name already taken: {}", person.name);
            }
        }
        conn.execute(
            "INSERT INTO people
                (device_id, name, avatar, hidden, hidden_by_peer, identity_created_at, last_seen, created_at)
             VALUES (?1, ?2, ?3, 0, 0, ?4, ?5, ?6)
             ON CONFLICT(device_id) DO UPDATE SET
                name = excluded.name,
                avatar = excluded.avatar,
                identity_created_at = excluded.identity_created_at,
                last_seen = excluded.last_seen",
            params![
                person.device_id,
                person.name,
                person.avatar,
                person.identity_created_at as i64,
                person.last_seen.map(|v| v as i64),
                crate::identity::unix_now() as i64,
            ],
        )?;
        Ok(())
    }

    pub fn person(&self, device_id: &str) -> Result<Option<Person>> {
        let conn = self.conn.lock().unwrap();
        Ok(conn
            .query_row(
                "SELECT device_id, name, avatar, hidden, hidden_by_peer,
                        identity_created_at, last_seen
                 FROM people WHERE device_id = ?1",
                params![device_id],
                row_to_person,
            )
            .optional()?)
    }

    pub fn person_by_name(&self, name: &str) -> Result<Option<Person>> {
        let conn = self.conn.lock().unwrap();
        Ok(conn
            .query_row(
                "SELECT device_id, name, avatar, hidden, hidden_by_peer,
                        identity_created_at, last_seen
                 FROM people WHERE name = ?1",
                params![name],
                row_to_person,
            )
            .optional()?)
    }

    pub fn people(&self) -> Result<Vec<Person>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT device_id, name, avatar, hidden, hidden_by_peer,
                    identity_created_at, last_seen
             FROM people ORDER BY name COLLATE NOCASE",
        )?;
        let rows = stmt.query_map([], row_to_person)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn set_hidden(&self, device_id: &str, hidden: bool) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE people SET hidden = ?2 WHERE device_id = ?1",
            params![device_id, i64::from(hidden)],
        )?;
        Ok(())
    }

    pub fn set_hidden_by_peer(&self, device_id: &str, hidden: bool) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE people SET hidden_by_peer = ?2 WHERE device_id = ?1",
            params![device_id, i64::from(hidden)],
        )?;
        Ok(())
    }

    pub fn touch_last_seen(&self, device_id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE people SET last_seen = ?2 WHERE device_id = ?1",
            params![device_id, crate::identity::unix_now() as i64],
        )?;
        Ok(())
    }

    pub fn insert_message(&self, message: &MessageRow) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO messages(id, peer, direction, body, state, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                message.id.to_string(),
                message.peer,
                message.direction,
                message.body,
                message.state,
                message.created_at as i64,
            ],
        )?;
        Ok(())
    }

    pub fn update_message_state(&self, id: Uuid, state: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE messages SET state = ?2 WHERE id = ?1",
            params![id.to_string(), state],
        )?;
        Ok(())
    }

    /// Messages addressed to `peer` that have not been delivered yet.
    pub fn pending_messages(&self, peer: &str) -> Result<Vec<MessageRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, peer, direction, body, state, created_at
             FROM messages
             WHERE peer = ?1 AND direction = 'out' AND state IN ('queued', 'failed')
             ORDER BY created_at",
        )?;
        let rows = stmt.query_map(params![peer], row_to_message)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn messages(&self, peer: &str, limit: usize) -> Result<Vec<MessageRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, peer, direction, body, state, created_at
             FROM messages WHERE peer = ?1
             ORDER BY created_at DESC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![peer, limit as i64], row_to_message)?;
        let mut messages = rows.collect::<rusqlite::Result<Vec<_>>>()?;
        messages.reverse();
        Ok(messages)
    }

    pub fn insert_transfer(&self, transfer: &TransferRow) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO transfers
                (id, peer, direction, path, name, size, offset, blake3, state, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
             ON CONFLICT(id) DO UPDATE SET
                path = excluded.path,
                name = excluded.name,
                size = excluded.size,
                offset = excluded.offset,
                blake3 = excluded.blake3,
                state = excluded.state",
            params![
                transfer.id.to_string(),
                transfer.peer,
                transfer.direction,
                transfer.path,
                transfer.name,
                transfer.size as i64,
                transfer.offset as i64,
                transfer.blake3,
                transfer.state,
                transfer.created_at as i64,
            ],
        )?;
        Ok(())
    }

    pub fn transfer(&self, id: Uuid) -> Result<Option<TransferRow>> {
        let conn = self.conn.lock().unwrap();
        Ok(conn
            .query_row(
                "SELECT id, peer, direction, path, name, size, offset, blake3, state, created_at
                 FROM transfers WHERE id = ?1",
                params![id.to_string()],
                row_to_transfer,
            )
            .optional()?)
    }

    pub fn update_transfer_progress(&self, id: Uuid, offset: u64, state: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE transfers SET offset = ?2, state = ?3 WHERE id = ?1",
            params![id.to_string(), offset as i64, state],
        )?;
        Ok(())
    }

    /// Outgoing transfers that were interrupted and should be resumed when the
    /// peer comes back.
    pub fn unfinished_outgoing_transfers(&self, peer: &str) -> Result<Vec<TransferRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, peer, direction, path, name, size, offset, blake3, state, created_at
             FROM transfers
             WHERE peer = ?1 AND direction = 'out' AND state IN ('offered', 'sending', 'paused')
             ORDER BY created_at",
        )?;
        let rows = stmt.query_map(params![peer], row_to_transfer)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
}

fn row_to_person(row: &rusqlite::Row<'_>) -> rusqlite::Result<Person> {
    Ok(Person {
        device_id: row.get(0)?,
        name: row.get(1)?,
        avatar: row.get(2)?,
        hidden: row.get::<_, i64>(3)? != 0,
        hidden_by_peer: row.get::<_, i64>(4)? != 0,
        identity_created_at: row.get::<_, i64>(5)? as u64,
        last_seen: row.get::<_, Option<i64>>(6)?.map(|v| v as u64),
    })
}

fn row_to_message(row: &rusqlite::Row<'_>) -> rusqlite::Result<MessageRow> {
    let id: String = row.get(0)?;
    Ok(MessageRow {
        id: Uuid::parse_str(&id).unwrap_or_else(|_| Uuid::nil()),
        peer: row.get(1)?,
        direction: row.get(2)?,
        body: row.get(3)?,
        state: row.get(4)?,
        created_at: row.get::<_, i64>(5)? as u64,
    })
}

fn row_to_transfer(row: &rusqlite::Row<'_>) -> rusqlite::Result<TransferRow> {
    let id: String = row.get(0)?;
    Ok(TransferRow {
        id: Uuid::parse_str(&id).unwrap_or_else(|_| Uuid::nil()),
        peer: row.get(1)?,
        direction: row.get(2)?,
        path: row.get(3)?,
        name: row.get(4)?,
        size: row.get::<_, i64>(5)? as u64,
        offset: row.get::<_, i64>(6)? as u64,
        blake3: row.get(7)?,
        state: row.get(8)?,
        created_at: row.get::<_, i64>(9)? as u64,
    })
}

fn load_or_create_db_key(dir: &Path) -> Result<[u8; 32]> {
    let path = dir.join("db.key");
    if path.exists() {
        let raw = fs::read_to_string(&path)?;
        let key: [u8; 32] = hex::decode(raw.trim())
            .map_err(|_| anyhow::anyhow!("database key is not valid hex"))?
            .try_into()
            .map_err(|_| anyhow::anyhow!("database key has the wrong length"))?;
        Ok(key)
    } else {
        let key: [u8; 32] = rand::random();
        let mut file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&path)?;
        file.write_all(hex::encode(key).as_bytes())?;
        file.sync_all()?;
        Ok(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir() -> std::path::PathBuf {
        std::env::temp_dir().join(format!("kinly-storage-{}", Uuid::new_v4()))
    }

    fn person(name: &str) -> Person {
        Person {
            device_id: "ab".repeat(32),
            name: name.into(),
            avatar: None,
            hidden: false,
            hidden_by_peer: false,
            identity_created_at: 1,
            last_seen: None,
        }
    }

    #[test]
    fn stores_and_reloads_people() {
        let dir = temp_dir();
        {
            let storage = Storage::open(&dir).unwrap();
            storage.upsert_person(&person("Abdullah")).unwrap();
            storage.set_setting("name", "Abdullah").unwrap();
        }
        let storage = Storage::open(&dir).unwrap();
        assert_eq!(storage.people().unwrap().len(), 1);
        assert_eq!(
            storage.get_setting("name").unwrap().as_deref(),
            Some("Abdullah")
        );
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn enforces_unique_names() {
        let dir = temp_dir();
        let storage = Storage::open(&dir).unwrap();
        storage.upsert_person(&person("Abdullah")).unwrap();
        let mut other = person("Abdullah");
        other.device_id = "cd".repeat(32);
        assert!(storage.upsert_person(&other).is_err());
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn database_file_is_encrypted() {
        let dir = temp_dir();
        let storage = Storage::open(&dir).unwrap();
        storage.upsert_person(&person("VerySecretName")).unwrap();
        drop(storage);
        let raw = fs::read(dir.join("kinly.db")).unwrap();
        let needle = b"VerySecretName";
        assert!(
            !raw.windows(needle.len()).any(|window| window == needle),
            "plaintext found in the database file"
        );
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn queues_messages_for_offline_peers() {
        let dir = temp_dir();
        let storage = Storage::open(&dir).unwrap();
        storage.upsert_person(&person("Abdullah")).unwrap();
        let message = MessageRow {
            id: Uuid::new_v4(),
            peer: person("Abdullah").device_id,
            direction: "out".into(),
            body: "hello".into(),
            state: "queued".into(),
            created_at: 1,
        };
        storage.insert_message(&message).unwrap();
        let pending = storage.pending_messages(&message.peer).unwrap();
        assert_eq!(pending.len(), 1);
        storage
            .update_message_state(message.id, "delivered")
            .unwrap();
        assert!(storage.pending_messages(&message.peer).unwrap().is_empty());
        fs::remove_dir_all(dir).ok();
    }
}
