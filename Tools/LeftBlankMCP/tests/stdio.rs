use serde_json::{Value, json};
use std::{
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Stdio,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines},
    net::UnixListener,
    process::{Child, ChildStdin, ChildStdout, Command},
};

const BINARY: &str = env!("CARGO_BIN_EXE_LeftBlankMCP");
const MAX_MESSAGE_BYTES: usize = 8 * 1024 * 1024;
static FIXTURE_ID: AtomicUsize = AtomicUsize::new(0);

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let root = std::env::var_os("LEFTBLANK_TEST_TMP_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/Volumes/SSD/Developer/Codex/tmp"));
        assert!(
            root.is_absolute() && root.is_dir(),
            "Set LEFTBLANK_TEST_TMP_ROOT to an existing absolute short temporary directory (local macOS defaults to the external SSD)."
        );
        let path = root.join(format!(
            "m{:x}_{:x}",
            std::process::id(),
            FIXTURE_ID.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn socket(&self) -> PathBuf {
        self.0.join("Agents/bridge.sock")
    }

    fn mock(&self, handler: impl Fn(Value) -> Option<Value> + Send + Sync + 'static) -> MockBridge {
        let directory = self.0.join("Agents");
        std::fs::create_dir(&directory).unwrap();
        std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700)).unwrap();
        let listener = UnixListener::bind(self.socket()).unwrap();
        std::fs::set_permissions(self.socket(), std::fs::Permissions::from_mode(0o600)).unwrap();
        let handler = Arc::new(handler);
        let requests = Arc::new(AtomicUsize::new(0));
        let counter = requests.clone();
        let task = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let handler = handler.clone();
                let counter = counter.clone();
                tokio::spawn(async move {
                    let mut reader = BufReader::new(stream);
                    let mut line = String::new();
                    if reader.read_line(&mut line).await.unwrap_or(0) == 0 {
                        return;
                    }
                    counter.fetch_add(1, Ordering::Relaxed);
                    let request: Value = serde_json::from_str(&line).unwrap();
                    if let Some(response) = handler(request) {
                        let bytes = serde_json::to_vec(&response).unwrap();
                        let _ = reader.get_mut().write_all(&bytes).await;
                        let _ = reader.get_mut().write_all(b"\n").await;
                    }
                });
            }
        });
        MockBridge { task, requests }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
struct MockBridge {
    task: tokio::task::JoinHandle<()>,
    requests: Arc<AtomicUsize>,
}
impl Drop for MockBridge {
    fn drop(&mut self) {
        self.task.abort();
    }
}

struct Session {
    process: Child,
    input: ChildStdin,
    output: Lines<BufReader<ChildStdout>>,
    id: u64,
}
impl Session {
    async fn start(state: &Path) -> Self {
        let mut command = Command::new(BINARY);
        command.env("LEFTBLANK_STATE_DIR", state);
        Self::from_command(command).await
    }

    async fn from_command(mut command: Command) -> Self {
        let mut process = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let input = process.stdin.take().unwrap();
        let output = BufReader::new(process.stdout.take().unwrap()).lines();
        let mut session = Self {
            process,
            input,
            output,
            id: 0,
        };
        let initialization=session.request("initialize",json!({"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"wire-test","version":"1"}})).await;
        assert_eq!(initialization["result"]["protocolVersion"], "2025-11-25");
        assert_eq!(initialization["result"]["serverInfo"]["name"], "LeftBlank");
        session
            .write(json!({"jsonrpc":"2.0","method":"notifications/initialized"}))
            .await;
        session
    }
    async fn write(&mut self, message: Value) {
        self.input
            .write_all(&serde_json::to_vec(&message).unwrap())
            .await
            .unwrap();
        self.input.write_all(b"\n").await.unwrap();
    }
    async fn request(&mut self, method: &str, params: Value) -> Value {
        self.id += 1;
        self.write(json!({"jsonrpc":"2.0","id":self.id,"method":method,"params":params}))
            .await;
        loop {
            let line = tokio::time::timeout(Duration::from_secs(10), self.output.next_line())
                .await
                .expect("MCP response timeout")
                .expect("read MCP stdout")
                .expect("helper unexpectedly closed stdout");
            let response: Value =
                serde_json::from_str(&line).expect("stdout contains only JSON-RPC");
            if response["id"] == self.id {
                return response;
            }
        }
    }
    async fn tool(&mut self, name: &str, arguments: Value) -> Value {
        self.request(
            "tools/call",
            json!({"name":format!("leftblank_{name}"),"arguments":arguments}),
        )
        .await
    }
    async fn close(mut self) {
        self.input.shutdown().await.unwrap();
        drop(self.input);
        assert!(
            tokio::time::timeout(Duration::from_secs(5), self.process.wait())
                .await
                .unwrap()
                .unwrap()
                .success()
        );
    }
}

fn metadata() -> Value {
    json!({"document_id":"doc","file_id":"main","title":"Sample","revision":"revision-1","unsaved":true,"selection":{"start":0,"end":0},"total_lines":1})
}

#[tokio::test]
async fn stdio_negotiates_tools_resources_prompts_and_bridge_errors() {
    let fixture = Fixture::new();
    let bridge=fixture.mock(|request| {
        match request["operation"].as_str().unwrap() {
            "get_status" => Some(json!({"result":{"enabled":true,"bridge_version":2,"active_document":metadata(),"library_home":false}})),
            "get_document" => {
                let mut result=metadata();
                result.as_object_mut().unwrap().extend(json!({"text":"= 中文 😀 unsaved","start_line":1,"line_count":1,"next_line":null,"truncated":false}).as_object().unwrap().clone());
                Some(json!({"result":result}))
            },
            "get_settings" => Some(json!({"result":{"layout":"writing"}})),
            "render_page" => Some(json!({"result":{"revision":"revision-1","page":1,"page_count":1,"image_png":"aW1hZ2U="}})),
            _ => Some(json!({"error":{"code":"revision_conflict","message":"Read the latest revision."}})),
        }
    });
    let mut session = Session::start(&fixture.0).await;
    let status = session.tool("get_status", json!({})).await;
    assert_eq!(status["result"]["structuredContent"]["bridge_version"], 2);
    let result = session.request("tools/list", json!({})).await;
    let tools = result["result"]["tools"].as_array().unwrap();
    assert_eq!(tools.len(), 31);
    for tool in tools {
        assert_eq!(tool["inputSchema"]["type"], "object");
        assert_eq!(tool["inputSchema"]["additionalProperties"], false);
        assert_eq!(tool["outputSchema"]["type"], "object");
        assert!(tool["annotations"]["openWorldHint"].is_boolean());
    }
    let read = session.tool("get_document", json!({})).await;
    assert_eq!(
        read["result"]["structuredContent"]["text"],
        "= 中文 😀 unsaved"
    );
    assert!(
        read["result"]["content"][0]["text"]
            .as_str()
            .unwrap()
            .contains("中文")
    );
    let conflict=session.tool("edit_document",json!({"document_id":"doc","expected_revision":"stale","edits":[{"old_text":"unsaved","new_text":"saved"}]})).await;
    assert_eq!(conflict["result"]["isError"], true);
    assert_eq!(
        conflict["result"]["structuredContent"]["code"],
        "revision_conflict"
    );
    let count = bridge.requests.load(Ordering::Relaxed);
    for arguments in [
        json!({"line_count":201}),
        json!({"start_line":0}),
        json!({"unexpected":"text"}),
    ] {
        let invalid = session.tool("get_document", arguments).await;
        assert_eq!(invalid["result"]["isError"], true);
        assert_eq!(
            invalid["result"]["structuredContent"]["code"],
            "invalid_arguments"
        );
    }
    assert_eq!(
        bridge.requests.load(Ordering::Relaxed),
        count,
        "invalid inputs must not reach app"
    );
    assert_eq!(
        session.tool("shell", json!({})).await["error"]["code"],
        -32602
    );
    let resources = session.request("resources/list", json!({})).await;
    assert_eq!(
        resources["result"]["resources"].as_array().unwrap().len(),
        2
    );
    let resource = session
        .request("resources/read", json!({"uri":"leftblank://settings"}))
        .await;
    assert!(
        resource["result"]["contents"][0]["text"]
            .as_str()
            .unwrap()
            .contains("writing")
    );
    assert_eq!(
        session.request("prompts/list", json!({})).await["result"]["prompts"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let prompt = session
        .request(
            "prompts/get",
            json!({"name":"write_in_leftblank","arguments":{"task":"Write a note"}}),
        )
        .await;
    assert!(
        prompt["result"]["messages"][0]["content"]["text"]
            .as_str()
            .unwrap()
            .contains("Write a note")
    );
    let image = session
        .tool(
            "render_page",
            json!({"document_id":"doc","expected_revision":"revision-1"}),
        )
        .await;
    assert_eq!(image["result"]["content"][1]["type"], "image");
    assert_eq!(image["result"]["content"][1]["data"], "aW1hZ2U=");
    assert!(
        image["result"]["structuredContent"]
            .get("image_png")
            .is_none()
    );
    drop(bridge);
    let offline = session.tool("get_document", json!({})).await;
    assert_eq!(
        offline["result"]["structuredContent"]["code"],
        "access_unavailable"
    );
    session.close().await;
}

#[tokio::test]
async fn cli_reports_connection_state_and_bundle_identity() {
    let fixture = Fixture::new();
    let offline = Command::new(BINARY)
        .env("LEFTBLANK_STATE_DIR", &fixture.0)
        .arg("--check")
        .output()
        .await
        .unwrap();
    assert!(!offline.status.success());
    let value: Value = serde_json::from_slice(&offline.stdout).unwrap();
    assert_eq!(value["connected"], false);
    assert_eq!(value["error"]["code"], "access_unavailable");
    let _bridge = fixture.mock(|request| {
        assert_eq!(request["operation"], "get_status");
        Some(json!({"result":{"enabled":true,"bridge_version":2,"active_document":null,"library_home":true}}))
    });
    let online = Command::new(BINARY)
        .env("LEFTBLANK_STATE_DIR", &fixture.0)
        .arg("--check")
        .output()
        .await
        .unwrap();
    assert!(online.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&online.stdout).unwrap()["connected"],
        true
    );
    let bundle = fixture.0.join("LeftBlank Preview.app");
    std::fs::create_dir_all(bundle.join("Contents")).unwrap();
    let mut info = plist::Dictionary::new();
    info.insert(
        "CFBundleIdentifier".into(),
        plist::Value::String("app.leftblank.writer.preview".into()),
    );
    info.insert(
        "CFBundleShortVersionString".into(),
        plist::Value::String("9.8.7".into()),
    );
    plist::Value::Dictionary(info)
        .to_file_xml(bundle.join("Contents/Info.plist"))
        .unwrap();
    let descriptor = Command::new(BINARY)
        .env_remove("LEFTBLANK_STATE_DIR")
        .args(["--describe", "--app-bundle"])
        .arg(&bundle)
        .output()
        .await
        .unwrap();
    assert!(descriptor.status.success());
    let value: Value = serde_json::from_slice(&descriptor.stdout).unwrap();
    assert_eq!(value["version"], "9.8.7");
    assert_eq!(value["name"], "leftblank-preview");
    assert_eq!(value["distribution"], "preview");
    assert!(
        value["socket_paths"]
            .as_array()
            .unwrap()
            .iter()
            .any(|path| path.as_str().unwrap().ends_with(
                "Library/Containers/app.leftblank.writer.preview/Data/Agents/bridge.sock"
            ))
    );
    let invalid = Command::new(BINARY)
        .args(["--check", "--app-bundle"])
        .arg(fixture.0.join("missing.app"))
        .output()
        .await
        .unwrap();
    assert!(!invalid.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&invalid.stdout).unwrap()["error"]["code"],
        "invalid_app_bundle"
    );
}

#[tokio::test]
async fn reports_incompatible_old_app_through_cli_and_mcp() {
    let fixture = Fixture::new();
    let _bridge=fixture.mock(|request| {
        assert_eq!(request["operation"],"get_status");
        Some(json!({"error":{"code":"unknown_operation","message":"This operation is not available in LeftBlank."}}))
    });
    let check = Command::new(BINARY)
        .env("LEFTBLANK_STATE_DIR", &fixture.0)
        .arg("--check")
        .output()
        .await
        .unwrap();
    assert!(!check.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&check.stdout).unwrap()["error"]["code"],
        "bridge_incompatible"
    );
    let mut session = Session::start(&fixture.0).await;
    let result = session.tool("get_status", json!({})).await;
    assert_eq!(result["result"]["isError"], true);
    assert_eq!(
        result["result"]["structuredContent"]["code"],
        "bridge_incompatible"
    );
    session.close().await;
    let wrong_version = Fixture::new();
    let _bridge = wrong_version.mock(|_| {
        Some(json!({"result":{"enabled":true,"bridge_version":1,"active_document":null}}))
    });
    let check = Command::new(BINARY)
        .env("LEFTBLANK_STATE_DIR", &wrong_version.0)
        .arg("--check")
        .output()
        .await
        .unwrap();
    assert!(!check.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&check.stdout).unwrap()["error"]["code"],
        "bridge_incompatible"
    );
}

#[tokio::test]
async fn rejects_unsafe_socket_and_bounded_bridge_response() {
    let fixture = Fixture::new();
    let _bridge =
        fixture.mock(|_| Some(json!({"result":{"text":"x".repeat(MAX_MESSAGE_BYTES+1)}})));
    std::fs::set_permissions(
        fixture.0.join("Agents"),
        std::fs::Permissions::from_mode(0o755),
    )
    .unwrap();
    let mut session = Session::start(&fixture.0).await;
    let unsafe_directory = session.tool("get_document", json!({})).await;
    assert_eq!(
        unsafe_directory["result"]["structuredContent"]["code"],
        "unsafe_socket_directory"
    );
    std::fs::set_permissions(
        fixture.0.join("Agents"),
        std::fs::Permissions::from_mode(0o700),
    )
    .unwrap();
    std::fs::set_permissions(fixture.socket(), std::fs::Permissions::from_mode(0o666)).unwrap();
    assert_eq!(
        session.tool("get_document", json!({})).await["result"]["structuredContent"]["code"],
        "unsafe_socket"
    );
    std::fs::set_permissions(fixture.socket(), std::fs::Permissions::from_mode(0o600)).unwrap();
    let oversized = session.tool("get_document", json!({})).await;
    assert_eq!(
        oversized["result"]["structuredContent"]["code"],
        "message_too_large"
    );
    session.close().await;
}

#[tokio::test]
async fn import_copies_only_bounded_regular_local_resource_into_private_request() {
    let fixture = Fixture::new();
    let source = fixture.0.join("图.csv");
    std::fs::write(&source, b"a,b\n1,2\n").unwrap();
    let _bridge=fixture.mock(|request| {
        assert_eq!(request["operation"],"import_resource");
        let arguments=&request["arguments"];
        assert!(arguments.get("local_path").is_none());
        assert_eq!(arguments["name"],"图.csv");
        assert_eq!(arguments["data_base64"],"YSxiCjEsMgo=");
        Some(json!({"result":{"document_id":"doc","revision":"revision-1","file_id":"csv","relative_path":"resources/图.csv","name":"图.csv"}}))
    });
    let mut session = Session::start(&fixture.0).await;
    let copied=session.tool("import_resource",json!({"document_id":"doc","expected_revision":"revision-1","kind":"document","local_path":source})).await;
    assert_eq!(copied["result"]["isError"], false);
    assert_eq!(
        copied["result"]["structuredContent"]["relative_path"],
        "resources/图.csv"
    );
    assert!(
        copied["result"]["structuredContent"]
            .get("data_base64")
            .is_none()
    );
    let invalid=session.tool("import_resource",json!({"document_id":"doc","expected_revision":"revision-1","kind":"document","local_path":fixture.0})).await;
    assert_eq!(
        invalid["result"]["structuredContent"]["code"],
        "invalid_resource_path"
    );
    let too_large = fixture.0.join("large.bin");
    let file = std::fs::File::create(&too_large).unwrap();
    file.set_len(4 * 1024 * 1024 + 1).unwrap();
    let invalid=session.tool("import_resource",json!({"document_id":"doc","expected_revision":"revision-1","kind":"document","local_path":too_large})).await;
    assert_eq!(
        invalid["result"]["structuredContent"]["code"],
        "resource_too_large"
    );
    session.close().await;
}

#[tokio::test]
async fn closes_stdio_on_oversized_frame() {
    let fixture = Fixture::new();
    let mut session = Session::start(&fixture.0).await;
    let oversized = vec![b' '; MAX_MESSAGE_BYTES + 1];
    let _ = session.input.write_all(&oversized).await;
    let _ = session.input.write_all(b"\n").await;
    assert!(
        tokio::time::timeout(Duration::from_secs(5), session.process.wait())
            .await
            .unwrap()
            .unwrap()
            .success()
    );
}

#[tokio::test]
async fn signed_group_discovery_and_export_handoff_do_not_expose_private_paths() {
    let fixture = Fixture::new();
    let bundle = fixture.0.join("LeftBlank.app");
    std::fs::create_dir_all(bundle.join("Contents")).unwrap();
    let mut info = plist::Dictionary::new();
    info.insert(
        "CFBundleIdentifier".into(),
        plist::Value::String("app.leftblank.writer".into()),
    );
    info.insert(
        "LeftBlankAgentGroup".into(),
        plist::Value::String("ABCDEFGHIJ.lb.mcp".into()),
    );
    plist::Value::Dictionary(info)
        .to_file_xml(bundle.join("Contents/Info.plist"))
        .unwrap();
    let descriptor = Command::new(BINARY)
        .env_remove("LEFTBLANK_STATE_DIR")
        .args(["--describe", "--app-bundle"])
        .arg(&bundle)
        .output()
        .await
        .unwrap();
    assert!(descriptor.status.success());
    let value: Value = serde_json::from_slice(&descriptor.stdout).unwrap();
    assert_eq!(value["socket_paths"].as_array().unwrap().len(), 1);
    assert!(
        value["socket_paths"][0]
            .as_str()
            .unwrap()
            .ends_with("Library/Group Containers/ABCDEFGHIJ.lb.mcp/Agents/s.sock")
    );
    let exports = fixture.0.join("AgentExports");
    std::fs::create_dir(&exports).unwrap();
    let pdf = exports.join("writing note.pdf");
    std::fs::write(&pdf, b"%PDF-Test delivery").unwrap();
    let project = exports.join("project");
    std::fs::create_dir(&project).unwrap();
    std::fs::write(project.join("main.typ"), b"= Unsaved writing").unwrap();
    let outside = fixture.0.join("private-note.pdf");
    std::fs::write(&outside, b"private").unwrap();
    let source_pdf = pdf.clone();
    let source_project = project.clone();
    let unsafe_source = outside.clone();
    let _bridge = fixture.mock(move |request| {
        let source = if request["arguments"]["expected_revision"] == "unsafe" { &unsafe_source }
        else if request["operation"] == "export_pdf" { &source_pdf } else { &source_project };
        Some(json!({"result":{"document_id":"doc","revision":"revision-1","path":source,"page_count":1}}))
    });
    let delivered = fixture.0.join("Delivered");
    let mut command = Command::new(BINARY);
    command
        .env("LEFTBLANK_STATE_DIR", &fixture.0)
        .env("LEFTBLANK_EXPORT_DIR", &delivered)
        .arg("--app-bundle")
        .arg(&bundle);
    let mut session = Session::from_command(command).await;
    let args = json!({"document_id":"doc","expected_revision":"revision-1"});
    let pdf_result = session.tool("export_pdf", args.clone()).await;
    let result = &pdf_result["result"]["structuredContent"];
    let destination = PathBuf::from(result["path"].as_str().unwrap());
    assert!(destination.starts_with(&delivered));
    assert_eq!(
        std::fs::read(&destination).unwrap(),
        std::fs::read(&pdf).unwrap()
    );
    assert!(
        result["uri"]
            .as_str()
            .unwrap()
            .contains("writing%20note.pdf")
    );
    let project_result = session.tool("export_project", args).await;
    let destination = PathBuf::from(
        project_result["result"]["structuredContent"]["path"]
            .as_str()
            .unwrap(),
    );
    assert_eq!(
        std::fs::read(destination.join("main.typ")).unwrap(),
        b"= Unsaved writing"
    );
    let refused = session
        .tool(
            "export_pdf",
            json!({"document_id":"doc","expected_revision":"unsafe"}),
        )
        .await;
    assert_eq!(
        refused["result"]["structuredContent"]["code"],
        "unsafe_export"
    );
    std::os::unix::fs::symlink(&outside, project.join("escape")).unwrap();
    let refused = session
        .tool(
            "export_project",
            json!({"document_id":"doc","expected_revision":"revision-1"}),
        )
        .await;
    assert_eq!(
        refused["result"]["structuredContent"]["code"],
        "unsafe_export"
    );
    session.close().await;
}
