# LeftBlank MCP helper

This standalone macOS binary serves MCP over stdio using the official Rust SDK.
It forwards bounded NDJSON requests to the live Swift app over a
private same-user Unix socket. There is no HTTP listener or iPad target.

The default process mode is MCP. Keep stdout for JSON-RPC; diagnostics go to
stderr. `--describe` prints JSON installation metadata without requiring the app
to be open. `--check` prints JSON connection status and exits nonzero when Agent
Access is unavailable or the app does not support bridge version 2.
`--app-bundle /Applications/LeftBlank.app` selects the app
distribution and version explicitly for a separately installed helper; a bundled
helper discovers its parent app automatically. Preview and standard libraries
stay separate. Signed builds select the app's Team-ID App Group and a channel-specific socket. Development builds also support ordinary Application Support and legacy sandbox socket locations. Requested group exports are copied into a private ordinary agent delivery folder, without exposing app/group-container paths to the coding-agent client.

The app/helper bridge rejects nonprivate socket directories and sockets,
unexpected file types, other-user ownership, and other-user peers. Each exchange
has a 30-second deadline and an 8 MiB message cap. Connection errors never
automatically retry a mutation, because it may already have completed in the app.
The app remains authoritative for revision checks, undo and document access.

Tools expose enforced JSON input schemas and typed output schemas. Reads are
bounded and paginated; writes return metadata. `edit_document` replaces unique
exact text matches with an expected revision; legacy UTF-16 `apply_edits` is also
available. `render_page` separates image content from structured JSON. PDF export
does not request an image. `import_resource` accepts an explicit absolute local
file path, reads a regular file capped at 4 MiB, and sends its bytes privately to
the app without exposing base64 in tool results.

For App Store distribution, install this helper separately as a normal signed
executable. It must not use `com.apple.security.inherit`: coding agents launch
it independently of the app. The app's compiler child has a different lifecycle.

Build and test with Cargo. Keep Cargo's normal `target` directory inside this
SSD checkout. On the development Mac:

```sh
export CARGO_HOME=/Volumes/SSD/Developer/Codex/cargo-mcp
export TMPDIR=/Volumes/SSD/Developer/Codex/tmp
export TMP="$TMPDIR" TEMP="$TMPDIR"
cargo +1.92.0 test --locked --manifest-path Tools/LeftBlankMCP/Cargo.toml
cargo +1.92.0 build --release --locked --manifest-path Tools/LeftBlankMCP/Cargo.toml
```

The executable integration tests launch the real stdio helper and a private
in-memory Unix socket peer; they do not connect to a database or use containers.
Local fixtures default to `/Volumes/SSD/Developer/Codex/tmp`. CI can set
`LEFTBLANK_TEST_TMP_ROOT` to an existing short absolute temporary directory;
Darwin limits Unix socket path length. `LEFTBLANK_STATE_DIR` overrides discovery
for bridge tests and development.
