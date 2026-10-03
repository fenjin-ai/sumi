use crate::bridge::Failure;
use serde_json::Value;
use std::{
    os::unix::fs::{DirBuilderExt, MetadataExt},
    path::{Path, PathBuf},
};

// A coding agent is not a member of the signed app group. Deliver explicitly
// requested exports into an ordinary private folder it can read, without
// granting it access to the app/group container or copying the library.
pub async fn handoff(mut result: Value, root: PathBuf) -> Result<Value, Failure> {
    let source = result["path"]
        .as_str()
        .map(PathBuf::from)
        .ok_or_else(|| Failure::new("invalid_response", "The export has no file path."))?;
    let destination = tokio::task::spawn_blocking(move || copy_export(&source, &root))
        .await
        .map_err(|_| {
            Failure::new(
                "export_unavailable",
                "Cannot deliver the exported artifact.",
            )
        })??;
    result["path"] = Value::String(destination.to_string_lossy().into_owned());
    let encoded: String = destination
        .to_string_lossy()
        .bytes()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || b"/-._~".contains(&byte) {
                (byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect();
    result["uri"] = Value::String(format!("file://{encoded}"));
    Ok(result)
}

fn copy_export(source: &Path, export_root: &Path) -> Result<PathBuf, Failure> {
    let invalid = || {
        Failure::new(
            "unsafe_export",
            "The exported artifact must be inside LeftBlank's private export directory.",
        )
    };
    let root = std::fs::canonicalize(export_root).map_err(|_| invalid())?;
    if source.parent() != Some(root.as_path())
        || source != std::fs::canonicalize(source).map_err(|_| invalid())?
    {
        return Err(invalid());
    }
    let destination_root = std::env::var_os("LEFTBLANK_EXPORT_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| {
                PathBuf::from(home).join("Library/Application Support/LeftBlankAgentExports")
            })
        })
        .filter(|path| path.is_absolute())
        .ok_or_else(invalid)?;
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&destination_root)
        .map_err(io_failure)?;
    let info = std::fs::symlink_metadata(&destination_root).map_err(io_failure)?;
    if !info.is_dir()
        || info.uid() != unsafe { libc::getuid() }
        || info.mode() & 0o077 != 0
        || destination_root != std::fs::canonicalize(&destination_root).map_err(io_failure)?
    {
        return Err(invalid());
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| invalid())?
        .as_nanos();
    let bucket = destination_root.join(format!("{}-{nonce}", std::process::id()));
    std::fs::DirBuilder::new()
        .mode(0o700)
        .create(&bucket)
        .map_err(io_failure)?;
    let destination = bucket.join(source.file_name().ok_or_else(invalid)?);
    let mut bytes = 0u64;
    let mut files = 0usize;
    if let Err(error) = copy_tree(source, &destination, &mut bytes, &mut files) {
        let _ = std::fs::remove_dir_all(&bucket);
        return Err(error);
    }
    Ok(destination)
}

fn copy_tree(
    source: &Path,
    destination: &Path,
    bytes: &mut u64,
    files: &mut usize,
) -> Result<(), Failure> {
    let info = std::fs::symlink_metadata(source).map_err(io_failure)?;
    *files += 1;
    *bytes = bytes.saturating_add(info.len());
    if *files > 10_000 || *bytes > 512 * 1024 * 1024 {
        return Err(Failure::new(
            "export_too_large",
            "Agent exports are limited to 10,000 entries and 512 MiB.",
        ));
    }
    if info.is_dir() {
        std::fs::DirBuilder::new()
            .mode(0o700)
            .create(destination)
            .map_err(io_failure)?;
        for item in std::fs::read_dir(source).map_err(io_failure)? {
            let item = item.map_err(io_failure)?;
            copy_tree(
                &item.path(),
                &destination.join(item.file_name()),
                bytes,
                files,
            )?;
        }
    } else if info.is_file() {
        std::fs::copy(source, destination).map_err(io_failure)?;
    } else {
        return Err(Failure::new(
            "unsafe_export",
            "Export artifacts cannot contain symbolic links or special files.",
        ));
    }
    Ok(())
}

fn io_failure(_: std::io::Error) -> Failure {
    Failure::new(
        "export_unavailable",
        "Cannot copy the exported artifact into the agent export folder.",
    )
}
