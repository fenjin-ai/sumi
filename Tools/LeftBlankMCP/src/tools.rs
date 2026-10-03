use crate::bridge::{Failure, MAX_RESOURCE_BYTES, MAX_SOURCE_BYTES};
use base64::{Engine, engine::general_purpose::STANDARD};
use rmcp::model::{Tool, ToolAnnotations};
use serde_json::{Map, Value, json};
use std::{path::Path, sync::Arc};
use tokio::io::AsyncReadExt;

pub struct ToolDefinition {
    pub operation: &'static str,
    pub tool: Tool,
    validator: jsonschema::Validator,
}

impl ToolDefinition {
    pub async fn arguments(&self, arguments: Value) -> Result<Value, Failure> {
        // Validation uses the same schema clients receive. No network/file
        // schema resolution features are compiled into this helper.
        self.validator.validate(&arguments).map_err(|error| {
            Failure::new(
                "invalid_arguments",
                format!(
                    "Invalid {} arguments at {}. Check this tool's input schema.",
                    self.operation,
                    error.instance_path()
                ),
            )
        })?;
        if arguments
            .get("query")
            .and_then(Value::as_str)
            .is_some_and(|query| query.len() > 1024)
        {
            return Err(Failure::new(
                "invalid_arguments",
                "Queries are limited to 1024 UTF-8 bytes.",
            ));
        }
        for field in ["text", "old_text", "new_text"] {
            if arguments
                .get(field)
                .and_then(Value::as_str)
                .is_some_and(|text| text.len() > MAX_SOURCE_BYTES)
            {
                return Err(Failure::new(
                    "document_too_large",
                    "Source is limited to 2 MiB.",
                ));
            }
        }
        if let Some(edits) = arguments.get("edits").and_then(Value::as_array) {
            let bytes = edits
                .iter()
                .flat_map(|edit| {
                    ["text", "old_text", "new_text"]
                        .map(|field| edit.get(field).and_then(Value::as_str).map_or(0, str::len))
                })
                .sum::<usize>();
            if bytes > MAX_SOURCE_BYTES {
                return Err(Failure::new(
                    "document_too_large",
                    "A batch of source edits is limited to 2 MiB.",
                ));
            }
        }
        if self.operation == "import_resource" {
            return import_arguments(arguments).await;
        }
        Ok(arguments)
    }
}

async fn import_arguments(mut arguments: Value) -> Result<Value, Failure> {
    let local_path = arguments["local_path"]
        .as_str()
        .expect("schema validated local_path");
    let path = Path::new(local_path);
    if !path.is_absolute() {
        return Err(Failure::new(
            "invalid_resource_path",
            "local_path must be an absolute path.",
        ));
    }
    // Open first, then inspect the descriptor and read with a cap. A changing
    // file cannot bypass the size check or turn this into an unbounded read.
    let mut file = tokio::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
        .open(path)
        .await
        .map_err(|_| {
            Failure::new(
                "resource_unavailable",
                "Cannot read the requested local resource.",
            )
        })?;
    let metadata = file.metadata().await.map_err(|_| {
        Failure::new(
            "resource_unavailable",
            "Cannot inspect the requested local resource.",
        )
    })?;
    if !metadata.is_file() {
        return Err(Failure::new(
            "invalid_resource_path",
            "local_path must identify a regular file.",
        ));
    }
    if metadata.len() > MAX_RESOURCE_BYTES as u64 {
        return Err(Failure::new(
            "resource_too_large",
            "Resource imports are limited to 4 MiB.",
        ));
    }
    let mut bytes = Vec::new();
    (&mut file)
        .take((MAX_RESOURCE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .await
        .map_err(|_| {
            Failure::new(
                "resource_unavailable",
                "Cannot read the requested local resource.",
            )
        })?;
    if bytes.len() > MAX_RESOURCE_BYTES {
        return Err(Failure::new(
            "resource_too_large",
            "Resource imports are limited to 4 MiB.",
        ));
    }
    let name = arguments
        .get("name")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            path.file_name()
                .and_then(|name| name.to_str())
                .map(str::to_owned)
        })
        .ok_or_else(|| Failure::new("invalid_resource_path", "Provide a UTF-8 resource name."))?;
    let values = arguments.as_object_mut().expect("schema validated object");
    values.remove("local_path");
    values.insert("name".into(), Value::String(name));
    values.insert("data_base64".into(), Value::String(STANDARD.encode(bytes)));
    Ok(arguments)
}

fn string() -> Value {
    json!({"type":"string"})
}
fn nonempty() -> Value {
    json!({"type":"string","minLength":1})
}
fn integer(minimum: u64, maximum: u64) -> Value {
    json!({"type":"integer","minimum":minimum,"maximum":maximum})
}
fn boolean() -> Value {
    json!({"type":"boolean"})
}
fn nullable(schema: Value) -> Value {
    json!({"anyOf":[schema,{"type":"null"}]})
}
fn array(items: Value) -> Value {
    json!({"type":"array","items":items})
}
fn enumeration(values: &[&str]) -> Value {
    json!({"type":"string","enum":values})
}
fn object(properties: &[(&str, Value)], required: &[&str], strict: bool) -> Value {
    json!({"type":"object","properties":properties.iter().map(|(key,value)|((*key).into(),value.clone())).collect::<Map<_,_>>(),"required":required,"additionalProperties":!strict})
}
fn metadata(extra: &[(&str, Value)], required_extra: &[&str]) -> Value {
    let mut fields = vec![
        ("document_id", string()),
        ("file_id", string()),
        ("title", string()),
        ("revision", string()),
        ("unsaved", boolean()),
        ("total_lines", integer(1, u64::MAX)),
        (
            "selection",
            object(
                &[
                    ("start", integer(0, u64::MAX)),
                    ("end", integer(0, u64::MAX)),
                ],
                &["start", "end"],
                true,
            ),
        ),
    ];
    fields.extend_from_slice(extra);
    let mut required = vec!["document_id", "revision"];
    required.extend_from_slice(required_extra);
    object(&fields, &required, false)
}
fn page_input(limit: u64) -> Vec<(&'static str, Value)> {
    vec![("cursor", string()), ("limit", integer(1, limit))]
}
fn identity() -> Vec<(&'static str, Value)> {
    vec![
        ("document_id", nonempty()),
        ("expected_revision", nonempty()),
    ]
}
fn definition(
    operation: &'static str,
    description: &'static str,
    input: Value,
    output: Value,
    annotations: ToolAnnotations,
) -> ToolDefinition {
    let validator = jsonschema::validator_for(&input).expect("static tool input schema");
    let tool = Tool::new(
        format!("leftblank_{operation}"),
        description,
        Arc::new(input.as_object().expect("object schema").clone()),
    )
    .with_raw_output_schema(Arc::new(
        output.as_object().expect("object output schema").clone(),
    ))
    .with_annotations(annotations);
    ToolDefinition {
        operation,
        tool,
        validator,
    }
}

pub fn definitions() -> Vec<ToolDefinition> {
    let mut tools = Vec::new();
    let mut add = |operation,
                   description,
                   properties: Vec<(&str, Value)>,
                   required: Vec<&str>,
                   output,
                   read,
                   destructive,
                   idempotent,
                   open| {
        tools.push(definition(
            operation,
            description,
            object(&properties, &required, true),
            output,
            ToolAnnotations::new()
                .read_only(read)
                .destructive(destructive)
                .idempotent(idempotent)
                .open_world(open),
        ));
    };
    add(
        "get_status",
        "Read connection state and active document metadata.",
        vec![],
        vec![],
        object(
            &[
                ("enabled", boolean()),
                ("bridge_version", integer(2, 2)),
                ("active_document", nullable(metadata(&[], &[]))),
                ("library_home", boolean()),
            ],
            &["enabled", "bridge_version", "active_document"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = page_input(50);
    args.extend([
        ("query", json!({"type":"string","maxLength":1024})),
        ("trashed", boolean()),
    ]);
    add(
        "list_documents",
        "Find library documents; paginated metadata and short match snippets.",
        args,
        vec![],
        object(
            &[
                (
                    "documents",
                    array(object(
                        &[
                            ("id", string()),
                            ("title", string()),
                            ("snippet", string()),
                            ("modified_at", string()),
                            ("trashed", boolean()),
                        ],
                        &["id", "title"],
                        false,
                    )),
                ),
                ("active_document_id", nullable(string())),
                ("next_cursor", nullable(string())),
                ("total", integer(0, u64::MAX)),
            ],
            &["documents", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    add(
        "get_document",
        "Read the live unsaved buffer in bounded lines; continue with next_line/next_character.",
        vec![
            ("document_id", nonempty()),
            ("start_line", integer(1, u64::MAX)),
            ("start_character", integer(0, u64::MAX)),
            ("line_count", integer(1, 200)),
        ],
        vec![],
        metadata(
            &[
                ("text", string()),
                ("start_line", integer(1, u64::MAX)),
                ("start_character", integer(0, u64::MAX)),
                ("line_count", integer(0, 200)),
                ("next_line", nullable(integer(1, u64::MAX))),
                ("next_character", nullable(integer(0, u64::MAX))),
                ("truncated", boolean()),
            ],
            &["text", "start_line", "truncated"],
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = page_input(100);
    args.push(("document_id", nonempty()));
    add(
        "get_outline",
        "Read a paginated source heading outline with line and UTF-16 positions.",
        args,
        vec!["document_id"],
        metadata(
            &[
                (
                    "headings",
                    array(object(
                        &[
                            ("title", string()),
                            ("level", integer(1, u64::MAX)),
                            ("line", integer(1, u64::MAX)),
                            ("character", integer(0, u64::MAX)),
                            ("start", integer(0, u64::MAX)),
                            ("end", integer(0, u64::MAX)),
                        ],
                        &["title", "level", "line"],
                        false,
                    )),
                ),
                ("next_cursor", nullable(string())),
            ],
            &["headings", "next_cursor"],
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = page_input(50);
    args.extend([
        ("document_id", nonempty()),
        (
            "query",
            json!({"type":"string","minLength":1,"maxLength":1024}),
        ),
        ("case_sensitive", boolean()),
    ]);
    add(
        "search_document",
        "Search the active source; return bounded match snippets and positions.",
        args,
        vec!["document_id", "query"],
        metadata(
            &[
                (
                    "matches",
                    array(object(
                        &[
                            ("line", integer(1, u64::MAX)),
                            ("character", integer(0, u64::MAX)),
                            ("start", integer(0, u64::MAX)),
                            ("end", integer(0, u64::MAX)),
                            ("text", string()),
                        ],
                        &["line", "start", "end", "text"],
                        false,
                    )),
                ),
                ("next_cursor", nullable(string())),
            ],
            &["matches", "next_cursor"],
        ),
        true,
        false,
        true,
        false,
    );
    add(
        "open_document",
        "Open a library document, preserving the current buffer through the normal save flow.",
        vec![("document_id", nonempty())],
        vec!["document_id"],
        metadata(&[], &[]),
        false,
        false,
        true,
        false,
    );
    add(
        "create_document",
        "Create and open a library document; return metadata.",
        vec![("title", nonempty()), ("text", string())],
        vec!["title", "text"],
        metadata(&[], &[]),
        false,
        false,
        false,
        false,
    );
    let mut args = identity();
    args.push(("edits",json!({"type":"array","minItems":1,"maxItems":100,"items":object(&[("old_text",nonempty()),("new_text",string())],&["old_text","new_text"],true)})));
    add(
        "edit_document",
        "Atomically replace unique exact text matches in the active file. Use its latest revision; re-read on conflict.",
        args,
        vec!["document_id", "expected_revision", "edits"],
        metadata(&[("changed_edits", integer(0, 100))], &[]),
        false,
        true,
        false,
        false,
    );
    let mut args = identity();
    args.push(("edits",json!({"type":"array","minItems":1,"maxItems":100,"items":object(&[("start",integer(0,u64::MAX)),("end",integer(0,u64::MAX)),("text",string())],&["start","end","text"],true)})));
    add(
        "apply_edits",
        "Apply atomic undoable edits using zero-based UTF-16 offsets and exclusive end. Prefer edit_document for exact text replacement.",
        args,
        vec!["document_id", "expected_revision", "edits"],
        metadata(&[("changed_edits", integer(0, 100))], &[]),
        false,
        true,
        false,
        false,
    );
    let mut args = page_input(100);
    args.push(("document_id", nonempty()));
    add(
        "list_files",
        "List paginated project files with opaque IDs and relative display paths.",
        args,
        vec!["document_id"],
        object(
            &[
                ("document_id", string()),
                ("revision", string()),
                (
                    "files",
                    array(object(
                        &[
                            ("file_id", string()),
                            ("path", string()),
                            ("kind", enumeration(&["source", "resource"])),
                            ("size", integer(0, u64::MAX)),
                            ("active", boolean()),
                            ("main", boolean()),
                        ],
                        &["file_id", "path", "kind"],
                        false,
                    )),
                ),
                ("next_cursor", nullable(string())),
            ],
            &["document_id", "files", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    add(
        "open_file",
        "Open a project source file, preserving the active buffer through the normal save flow.",
        vec![("document_id", nonempty()), ("file_id", nonempty())],
        vec!["document_id", "file_id"],
        metadata(&[], &[]),
        false,
        false,
        true,
        false,
    );
    let mut args = identity();
    args.extend([("path", nonempty()), ("text", string())]);
    add(
        "create_file",
        "Create a new relative .typ project file; return its ID without changing the active buffer.",
        args,
        vec!["document_id", "expected_revision", "path", "text"],
        object(
            &[
                ("document_id", string()),
                ("revision", string()),
                ("file_id", string()),
                ("path", string()),
            ],
            &["document_id", "revision", "file_id", "path"],
            false,
        ),
        false,
        false,
        false,
        false,
    );
    add(
        "rename_document",
        "Rename a library document.",
        vec![("document_id", nonempty()), ("title", nonempty())],
        vec!["document_id", "title"],
        object(
            &[
                ("document_id", string()),
                ("title", string()),
                ("active_document_id", nullable(string())),
            ],
            &["document_id", "title"],
            false,
        ),
        false,
        true,
        true,
        false,
    );
    add(
        "trash_document",
        "Move a library document to recoverable trash. Active documents require their latest revision.",
        identity(),
        vec!["document_id"],
        object(
            &[
                ("document_id", string()),
                ("trashed", boolean()),
                ("active_document_id", nullable(string())),
            ],
            &["document_id", "trashed"],
            false,
        ),
        false,
        true,
        true,
        false,
    );
    add(
        "restore_document",
        "Restore a document from library trash.",
        vec![("document_id", nonempty())],
        vec!["document_id"],
        object(
            &[
                ("document_id", string()),
                ("trashed", boolean()),
                ("active_document_id", nullable(string())),
            ],
            &["document_id"],
            false,
        ),
        false,
        false,
        true,
        false,
    );
    let kinds = enumeration(&["image", "bibliography", "document", "module"]);
    let mut args = page_input(50);
    args.extend([("document_id", nonempty()), ("kind", kinds.clone())]);
    add(
        "list_resources",
        "List paginated document resources and safe relative paths.",
        args,
        vec!["document_id", "kind"],
        object(
            &[
                (
                    "resources",
                    array(object(
                        &[
                            ("file_id", string()),
                            ("name", string()),
                            ("relative_path", string()),
                        ],
                        &["file_id", "name", "relative_path"],
                        false,
                    )),
                ),
                ("revision", string()),
                ("next_cursor", nullable(string())),
                ("total", integer(0, u64::MAX)),
            ],
            &["resources", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = identity();
    args.extend([
        ("kind", kinds),
        ("name", nonempty()),
        ("local_path", nonempty()),
    ]);
    add(
        "import_resource",
        "Copy a local resource (up to 4 MiB) into the project. Return its relative path for source references.",
        args,
        vec!["document_id", "expected_revision", "kind", "local_path"],
        object(
            &[
                ("document_id", string()),
                ("revision", string()),
                ("file_id", string()),
                ("relative_path", string()),
                ("name", string()),
            ],
            &["document_id", "revision", "file_id", "relative_path"],
            false,
        ),
        false,
        false,
        false,
        true,
    );
    add(
        "format_document",
        "Format the active Typst source as an undoable change after checking its current revision.",
        identity(),
        vec!["document_id", "expected_revision"],
        metadata(&[], &[]),
        false,
        true,
        false,
        false,
    );
    add(
        "get_preview",
        "Read bounded compilation diagnostics. stale=true means preview is from an older revision.",
        identity(),
        vec!["document_id"],
        object(
            &[
                ("document_id", string()),
                ("revision", string()),
                ("ready", boolean()),
                ("has_successful_preview", boolean()),
                ("truncated", boolean()),
                ("stale", boolean()),
                (
                    "diagnostics",
                    array(object(
                        &[
                            ("message", string()),
                            ("severity", integer(1, 4)),
                            ("uri", string()),
                            ("line", nullable(integer(0, u64::MAX))),
                            ("character", nullable(integer(0, u64::MAX))),
                        ],
                        &["message"],
                        false,
                    )),
                ),
            ],
            &["stale", "diagnostics"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = identity();
    args.extend([
        ("page", integer(1, u64::MAX)),
        ("width", integer(200, 1600)),
    ]);
    add(
        "render_page",
        "Compile the requested revision and return one page image. Page defaults to 1; width defaults to 800.",
        args,
        vec!["document_id", "expected_revision"],
        object(
            &[
                ("document_id", string()),
                ("revision", string()),
                ("page", integer(1, u64::MAX)),
                ("page_count", integer(1, u64::MAX)),
            ],
            &["revision", "page", "page_count"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let export = object(
        &[
            ("path", string()),
            ("uri", string()),
            ("revision", string()),
            ("page_count", integer(1, u64::MAX)),
        ],
        &["path", "uri", "revision"],
        false,
    );
    add(
        "export_pdf",
        "Compile the current unsaved revision to a PDF in LeftBlank's private export folder; return its path.",
        identity(),
        vec!["document_id", "expected_revision"],
        export.clone(),
        false,
        false,
        false,
        false,
    );
    add(
        "export_project",
        "Export the managed project including current source and resources; return its path.",
        identity(),
        vec!["document_id", "expected_revision"],
        export,
        false,
        false,
        false,
        false,
    );
    let mut args = page_input(50);
    args.push(("document_id", nonempty()));
    add(
        "list_history",
        "List saved history for the active document.",
        args,
        vec!["document_id"],
        object(
            &[
                (
                    "revisions",
                    array(object(
                        &[
                            ("revision_id", string()),
                            ("created_at", string()),
                            ("bytes", integer(0, u64::MAX)),
                            ("reason", string()),
                        ],
                        &["revision_id", "created_at", "bytes"],
                        false,
                    )),
                ),
                ("revision", string()),
                ("next_cursor", nullable(string())),
                ("total", integer(0, u64::MAX)),
            ],
            &["revisions", "revision", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    add(
        "get_history",
        "Read a saved revision in bounded line ranges.",
        vec![
            ("document_id", nonempty()),
            ("revision_id", nonempty()),
            ("start_line", integer(1, u64::MAX)),
            ("start_character", integer(0, u64::MAX)),
            ("line_count", integer(1, 200)),
        ],
        vec!["document_id", "revision_id"],
        object(
            &[
                ("text", string()),
                ("start_line", integer(1, u64::MAX)),
                ("line_count", integer(0, 200)),
                ("start_character", integer(0, u64::MAX)),
                ("next_character", nullable(integer(0, u64::MAX))),
                ("total_lines", integer(1, u64::MAX)),
                ("next_line", nullable(integer(1, u64::MAX))),
                ("truncated", boolean()),
            ],
            &["text", "start_line", "truncated"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = identity();
    args.push(("revision_id", nonempty()));
    add(
        "restore_history",
        "Restore a saved revision as an undoable editor change after checking the current revision.",
        args,
        vec!["document_id", "expected_revision", "revision_id"],
        metadata(&[], &[]),
        false,
        true,
        false,
        false,
    );
    let mut args = page_input(50);
    args.push(("query", json!({"type":"string","maxLength":1024})));
    let catalogue_fields = vec![
        ("title", string()),
        ("kind", enumeration(&["builtin", "universe"])),
        ("version", string()),
        ("description", string()),
        ("reference", string()),
        ("documentation_url", string()),
        ("compatible", boolean()),
    ];
    let mut template_fields = catalogue_fields.clone();
    template_fields.push(("template_id", string()));
    add(
        "list_templates",
        "Find paginated built-in and cached Typst Universe document templates.",
        args.clone(),
        vec![],
        object(
            &[
                (
                    "templates",
                    array(object(&template_fields, &["template_id", "title"], false)),
                ),
                ("total", integer(0, u64::MAX)),
                ("next_cursor", nullable(string())),
            ],
            &["templates", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut package_fields = catalogue_fields;
    package_fields.push(("package_id", string()));
    add(
        "list_packages",
        "Find paginated cached Typst Universe packages and pinned import references.",
        args,
        vec![],
        object(
            &[
                (
                    "packages",
                    array(object(&package_fields, &["package_id", "title"], false)),
                ),
                ("total", integer(0, u64::MAX)),
                ("next_cursor", nullable(string())),
            ],
            &["packages", "next_cursor"],
            false,
        ),
        true,
        false,
        true,
        false,
    );
    let mut args = identity();
    args.push(("package_id", nonempty()));
    add(
        "import_package",
        "Insert a discovered pinned package import as an undoable source change.",
        args,
        vec!["document_id", "expected_revision", "package_id"],
        metadata(&[], &[]),
        false,
        false,
        false,
        false,
    );
    add(
        "create_from_template",
        "Create and open a document using a discovered template.",
        vec![("template_id", nonempty()), ("title", nonempty())],
        vec!["template_id"],
        metadata(&[], &[]),
        false,
        false,
        false,
        false,
    );
    let settings = vec![
        ("layout", enumeration(&["writing", "split", "preview"])),
        ("font_size", integer(12, 28)),
        ("preview_dark", boolean()),
        ("styled_source", boolean()),
        ("appearance", enumeration(&["system", "light", "dark"])),
    ];
    add(
        "get_settings",
        "Read writing and preview preferences.",
        vec![],
        vec![],
        object(&settings, &[], false),
        true,
        false,
        true,
        false,
    );
    add(
        "set_settings",
        "Change safe display preferences.",
        settings.clone(),
        vec![],
        object(&settings, &[], false),
        false,
        false,
        true,
        false,
    );
    tools
}
