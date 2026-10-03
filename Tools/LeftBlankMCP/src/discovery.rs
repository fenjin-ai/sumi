use crate::bridge::{Bridge, Failure, MAX_MESSAGE_BYTES};
use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
pub struct Descriptor {
    pub name: String,
    pub version: String,
    pub distribution: String,
    pub bundle_id: String,
    pub app_bundle: Option<PathBuf>,
    pub transport: &'static str,
    pub socket_paths: Vec<PathBuf>,
    pub maximum_message_bytes: usize,
}

pub struct Configuration {
    pub descriptor: Descriptor,
    pub bridge: Bridge,
}

impl Configuration {
    pub fn discover(app_bundle: Option<PathBuf>) -> Result<Self, Failure> {
        let explicit_bundle = app_bundle.is_some();
        let bundle = app_bundle.or_else(|| {
            std::env::current_exe()
                .ok()?
                .ancestors()
                .find(|path| path.extension().is_some_and(|extension| extension == "app"))
                .map(Path::to_path_buf)
        });
        let mut agent_group = None;
        let mut bundle_id = "app.leftblank.writer".to_string();
        let mut version = env!("CARGO_PKG_VERSION").to_string();
        if let Some(path) = &bundle {
            let info = plist::Value::from_file(path.join("Contents/Info.plist")).map_err(|_| {
                Failure::new(
                    "invalid_app_bundle",
                    "The selected app bundle has no readable Info.plist.",
                )
            })?;
            let values = info.as_dictionary().ok_or_else(|| {
                Failure::new(
                    "invalid_app_bundle",
                    "The selected app has an invalid Info.plist.",
                )
            })?;
            if let Some(value) = values
                .get("CFBundleIdentifier")
                .and_then(plist::Value::as_string)
            {
                bundle_id = value.into();
            }
            if let Some(value) = values
                .get("LeftBlankAgentGroup")
                .and_then(plist::Value::as_string)
            {
                let valid = value.strip_suffix(".lb.mcp").is_some_and(|team| {
                    team.len() == 10
                        && team
                            .bytes()
                            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
                });
                if !valid {
                    return Err(Failure::new(
                        "invalid_app_bundle",
                        "Invalid LeftBlank agent group identity.",
                    ));
                }
                agent_group = Some(value.to_owned());
            }
            if let Some(value) = values
                .get("CFBundleShortVersionString")
                .and_then(plist::Value::as_string)
            {
                version = value.into();
            }
            if !matches!(
                bundle_id.as_str(),
                "app.leftblank.writer" | "app.leftblank.writer.preview"
            ) {
                return Err(Failure::new(
                    "invalid_app_bundle",
                    "Select LeftBlank.app or LeftBlank Preview.app.",
                ));
            }
            if explicit_bundle && !path.is_absolute() {
                return Err(Failure::new(
                    "invalid_app_bundle",
                    "--app-bundle requires an absolute app path.",
                ));
            }
        }
        let preview = bundle_id.ends_with(".preview");
        let folder = if preview {
            "LeftBlank Preview"
        } else {
            "LeftBlank"
        };
        let socket_paths = if let Some(state) = std::env::var_os("LEFTBLANK_STATE_DIR") {
            let path = PathBuf::from(state);
            if !path.is_absolute() {
                return Err(Failure::new(
                    "invalid_state_directory",
                    "LEFTBLANK_STATE_DIR must be absolute.",
                ));
            }
            vec![path.join("Agents/bridge.sock")]
        } else {
            let home = std::env::var_os("HOME")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .ok_or_else(|| {
                    Failure::new(
                        "home_unavailable",
                        "Cannot locate the user's home directory.",
                    )
                })?;
            if let Some(group) = &agent_group {
                vec![
                    home.join("Library/Group Containers")
                        .join(group)
                        .join("Agents")
                        .join(if preview { "p.sock" } else { "s.sock" }),
                ]
            } else {
                vec![
                    home.join("Library/Application Support")
                        .join(folder)
                        .join("Agents/bridge.sock"),
                    home.join("Library/Containers")
                        .join(&bundle_id)
                        .join("Data/Library/Application Support")
                        .join(folder)
                        .join("Agents/bridge.sock"),
                    home.join("Library/Containers")
                        .join(&bundle_id)
                        .join("Data/Agents/bridge.sock"),
                ]
            }
        };
        let group_exports = agent_group.map(|_| {
            socket_paths[0]
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join("AgentExports")
        });
        Ok(Self {
            bridge: Bridge {
                socket_paths: socket_paths.clone(),
                group_exports,
            },
            descriptor: Descriptor {
                name: if preview {
                    "leftblank-preview"
                } else {
                    "leftblank"
                }
                .into(),
                version,
                distribution: if preview { "preview" } else { "standard" }.into(),
                bundle_id,
                app_bundle: bundle,
                transport: "stdio",
                socket_paths,
                maximum_message_bytes: MAX_MESSAGE_BYTES,
            },
        })
    }
}
