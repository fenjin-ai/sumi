use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    os::{fd::AsRawFd, unix::fs::MetadataExt},
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::UnixStream,
};

pub const MAX_MESSAGE_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_SOURCE_BYTES: usize = 2 * 1024 * 1024;
pub const MAX_RESOURCE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Failure {
    pub code: String,
    pub message: String,
}

impl Failure {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn unavailable() -> Self {
        Self::new(
            "access_unavailable",
            "Open LeftBlank and enable Agent Access in its settings.",
        )
    }
}

impl std::fmt::Display for Failure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for Failure {}

#[derive(Serialize)]
struct Request<'a> {
    operation: &'a str,
    arguments: Value,
}

#[derive(Deserialize)]
struct Response {
    result: Option<Value>,
    error: Option<Failure>,
}

#[derive(Clone)]
pub struct Bridge {
    pub socket_paths: Vec<PathBuf>,
    pub group_exports: Option<PathBuf>,
}

impl Bridge {
    pub async fn send(&self, operation: &str, arguments: Value) -> Result<Value, Failure> {
        let message = serde_json::to_vec(&Request {
            operation,
            arguments,
        })
        .map_err(|_| Failure::new("invalid_arguments", "Cannot encode the tool arguments."))?;
        if message.len() > MAX_MESSAGE_BYTES {
            return Err(Failure::new(
                "message_too_large",
                "The agent message exceeds 8 MiB.",
            ));
        }
        let result = tokio::time::timeout(Duration::from_secs(30), self.exchange(&message))
            .await
            .map_err(|_| Failure::new("connection_timeout", "LeftBlank did not respond within 30 seconds. The operation may already have completed; read its state before retrying."))?;
        if operation == "get_status" {
            match &result {
                Ok(value) if value["bridge_version"].as_u64() != Some(2) => {
                    return Err(incompatible());
                }
                Err(error) if error.code == "unknown_operation" => return Err(incompatible()),
                _ => {}
            }
        }
        result
    }

    async fn exchange(&self, message: &[u8]) -> Result<Value, Failure> {
        // Locate a single live bridge before sending anything. Repeating a write
        // after disconnect would risk committing it twice.
        let mut connection = None;
        let mut unsafe_path = None;
        for path in &self.socket_paths {
            match verify_path(path) {
                Ok(()) => {}
                Err(error) if error.code == "access_unavailable" => continue,
                Err(error) => {
                    unsafe_path = Some(error);
                    continue;
                }
            }
            if let Ok(stream) = UnixStream::connect(path).await {
                verify_peer(&stream)?;
                if connection.is_some() {
                    return Err(Failure::new(
                        "ambiguous_bridge",
                        "Multiple LeftBlank bridges are running for this app. Close the duplicate app instance and retry.",
                    ));
                }
                connection = Some(stream);
            }
        }
        let mut stream =
            connection.ok_or_else(|| unsafe_path.unwrap_or_else(Failure::unavailable))?;
        stream.write_all(message).await.map_err(connection_closed)?;
        stream.write_all(b"\n").await.map_err(connection_closed)?;
        let mut bytes = Vec::new();
        // A capped reader bounds allocation even when the peer omits a newline.
        let mut reader = BufReader::new(stream).take((MAX_MESSAGE_BYTES + 1) as u64);
        reader
            .read_until(b'\n', &mut bytes)
            .await
            .map_err(connection_closed)?;
        if bytes.last() == Some(&b'\n') {
            bytes.pop();
        } else if bytes.len() <= MAX_MESSAGE_BYTES {
            return Err(Failure::new(
                "connection_closed",
                "LeftBlank closed the connection before completing its response. Read state before retrying a write.",
            ));
        }
        if bytes.len() > MAX_MESSAGE_BYTES {
            return Err(Failure::new(
                "message_too_large",
                "LeftBlank's response exceeds 8 MiB.",
            ));
        }
        let response: Response = serde_json::from_slice(&bytes).map_err(|_| {
            Failure::new(
                "invalid_response",
                "LeftBlank returned an invalid bridge response.",
            )
        })?;
        if let Some(error) = response.error {
            return Err(error);
        }
        response
            .result
            .ok_or_else(|| Failure::new("invalid_response", "LeftBlank's response has no result."))
    }
}

fn connection_closed(_: std::io::Error) -> Failure {
    Failure::new(
        "connection_closed",
        "The local LeftBlank connection closed. Read state before retrying a write.",
    )
}

fn incompatible() -> Failure {
    Failure::new(
        "bridge_incompatible",
        "Update LeftBlank and its MCP helper to matching current versions, then re-enable Agent Access.",
    )
}

fn verify_path(path: &Path) -> Result<(), Failure> {
    let directory = path.parent().ok_or_else(Failure::unavailable)?;
    let info = std::fs::symlink_metadata(directory).map_err(|_| Failure::unavailable())?;
    let uid = unsafe { libc::getuid() };
    if !info.is_dir() || info.uid() != uid || info.mode() & 0o077 != 0 {
        return Err(Failure::new(
            "unsafe_socket_directory",
            "The agent bridge directory must belong to you and have private permissions (0700).",
        ));
    }
    let socket = std::fs::symlink_metadata(path).map_err(|_| Failure::unavailable())?;
    if socket.mode() & u32::from(libc::S_IFMT) != u32::from(libc::S_IFSOCK)
        || socket.uid() != uid
        || socket.mode() & 0o077 != 0
    {
        return Err(Failure::new(
            "unsafe_socket",
            "The agent bridge must be a private socket owned by the current user.",
        ));
    }
    Ok(())
}

fn verify_peer(stream: &UnixStream) -> Result<(), Failure> {
    let mut uid = 0;
    let mut gid = 0;
    let result = unsafe { libc::getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) };
    if result != 0 || uid != unsafe { libc::getuid() } {
        return Err(Failure::new(
            "unsafe_peer",
            "The LeftBlank bridge must belong to the current user.",
        ));
    }
    Ok(())
}
