# Writing with an agent

LeftBlank exposes the live macOS editor through MCP. Agents can discover documents and templates, read bounded source ranges, make undoable changes, manage project resources, inspect history and review typeset pages. MCP is macOS-only; the iPad app does not ship or launch the helper.

## Connect a coding agent

1. Enable **LeftBlank → Settings → Agent Access**.
2. Click **Copy installation prompt** and paste it into your coding-agent conversation.
3. Let the agent configure its own MCP client, check the helper and call `leftblank_get_status`. If that client requires a new session to load a server, the agent explains that after completing configuration.

The prompt contains the actual app path and the correct `leftblank` or `leftblank-preview` identity. The agent preserves other client settings and updates an existing entry instead of adding a duplicate. Codex uses its standard [local stdio configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli); other coding agents use their equivalent configuration mechanism. Users do not install a compiler, run terminal commands or edit JSON/TOML.

Direct and Preview distributions include `Contents/Helpers/LeftBlankMCP`. The App Store edition installs the standalone `LeftBlankMCP-macOS-arm64.zip` asset from an official versioned GitHub release. The prompt tells the agent to verify its SHA-256 and code signature, including the TeamIdentifier against the installed app. The standalone helper is signed without sandbox inheritance and uses `--app-bundle` to select the installed edition. Signed apps and helpers share a macOS-only `<Team ID>.lb.mcp` App Group; separate socket names keep Preview and standard access apart. Apple supports these Team-ID groups without provisioning-profile registration. The agent checks group membership as well as the team signature. An executable signed to inherit a parent's sandbox cannot be launched independently by a coding agent. Release automation publishes the same helper code accepted inside the notarized direct/Preview app.

Keep LeftBlank open while writing. Agent Access authorizes programs running as your macOS user to use the bridge; it is not a per-agent identity system. The preference stays on this Mac and is never synchronized through iCloud. Disabling access removes the listening socket and invalidates queued or suspended agent work. A native storage operation already accepted by the app may finish; check state before retrying a write after losing the connection. A separate account, API key, cloud service or listening network port is not required.

## Tools

All names have the `leftblank_` prefix. Tool descriptions stay concise; input/output schemas specify arguments and results, and annotations describe read-only, destructive, idempotent and external-access behavior.

| Workflow | Tools |
| --- | --- |
| Orientation | `get_status`, `list_documents`, `get_document`, `get_outline`, `search_document` |
| Live source | `open_document`, `create_document`, `edit_document`, `apply_edits`, `format_document` |
| Project source | `list_files`, `open_file`, `create_file` |
| Library | `rename_document`, `trash_document`, `restore_document` |
| Resources | `list_resources`, `import_resource` |
| Typesetting | `get_preview`, `render_page`, `export_pdf`, `export_project` |
| History | `list_history`, `get_history`, `restore_history` |
| Templates/packages | `list_templates`, `create_from_template`, `list_packages`, `import_package` |
| Display preferences | `get_settings`, `set_settings` |

Resources `leftblank://document/current` and `leftblank://settings` expose the same bounded live reads. The `write_in_leftblank` prompt supplies the writing workflow to clients that support MCP prompts. These resources are live, private and uncached.

## Read, edit and review

Start with `get_status`, then find/open a document or read the active buffer. IDs are opaque; project paths are relative display information. `get_document` defaults to 100 lines and accepts at most 200 lines, with a 16 KiB UTF-8 source budget. Follow `next_line` and `next_character` to continue, including within very long lines. Line numbers are one-based; characters and selection/edit offsets are zero-based UTF-16 code units. Outline and search return bounded pages with cursors. Search is literal, optionally case-sensitive.

Prefer `edit_document` for unique exact replacements. Each batch refers to the original text, validates every replacement before mutation, and becomes one native undo action:

```json
{
  "document_id": "ID from the last read",
  "expected_revision": "revision from the last read",
  "edits": [{"old_text": "A uniquely identifiable old sentence.", "new_text": "A clearer sentence."}]
}
```

`apply_edits` also supports `{start, end, text}` ranges with an exclusive end. Ambiguous text, missing text, overlaps and split Unicode boundaries fail before mutation. On `revision_conflict`, read again and merge. Source writes, resource imports, history restoration, formatting and exports check the requested revision. Undoing to the same text does not revive an earlier revision. Edits cannot grow source beyond 2 MiB; larger documents remain readable and may receive size-preserving edits. Edit/open/create results return metadata rather than repeating the manuscript.

`list_files` discovers project source; `open_file` preserves the previous buffer through normal saving. `create_file` accepts safe relative `.typ` paths and does not switch the active file. Resource import reads a local file in the helper, copies at most 4 MiB into the document's resource store and returns a relative path. Typst source imports are limited to 2 MiB. The app never reads an arbitrary path supplied over its bridge.

Use `get_preview` for bounded diagnostics before requesting a visual review. `stale` indicates an older successful preview. `render_page` compiles the requested live revision and returns one PNG image (one-based page, default width 800, allowed 200–1600). `export_pdf` returns a private export path without an image. Both reuse a successful compilation while the revision and project-file metadata remain unchanged; failed compilation or a changed source/resource fails rather than substituting an old PDF. Project export flushes unsaved writing and copies project resources. Signed builds first export into the shared group. The helper then copies the requested artifact into a private ordinary `Application Support/LeftBlankAgentExports` folder so the coding agent can read the delivery without container-access permission. Handoff rejects paths outside the export folder, symlinks and projects above 10,000 entries or 512 MiB. The agent cannot choose an arbitrary export destination.

History reads use the same bounded source slicing. Restoration preserves the previous source and uses native undo. Template/package discovery uses the bundled or cached catalog; selecting a template or declared package may download its content through the app's normal package workflow. Trash is recoverable; no permanent-delete tool is exposed. Settings only cover layout, font size, appearance, preview darkness and source styling.

## Implementation

```text
Coding-agent MCP client
        │ bounded stdio, official Rust SDK
        ▼
Tools/LeftBlankMCP
        │ private same-user Unix socket, bridge version 2
        ▼
Swift WorkspaceAutomation → live editor / undo / library / compiler
```

The helper pins [rmcp 3.5.0](https://crates.io/crates/rmcp/3.5.0) and dependencies in `Tools/LeftBlankMCP/Cargo.lock`. The app owns editing and storage in Swift; it does not load an MCP SDK. The official Rust SDK is currently Tier 1 in the [SDK overview](https://modelcontextprotocol.io/docs/sdk). Build scripts select Rust 1.92.0 and macOS 14+ on Apple Silicon. SwiftPM no longer includes the Swift SDK or its transitive packages, and the iPad package graph has no MCP executable.

The socket directory is owner-only (0700), the socket is 0600, and both endpoints check the peer's operating-system user ID. Signed builds use an [App Group](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups) socket; this avoids additional permission prompts for private app-container access. Development/older distributions retain ordinary or shortened sandbox socket paths to fit Darwin's 104-byte limit. The helper selects the signed group, or checks legacy standard and sandbox locations for the selected edition and refuses ambiguous live bridges. `--describe` returns installation metadata; `--check` returns JSON and a nonzero exit status when access or bridge-version compatibility is unavailable.

Messages are capped at 8 MiB, bridge requests time out after 30 seconds and writes are never retried automatically after a disconnect. Source text, resource names and compiler/package output are untrusted data. Logs use stderr; stdout contains MCP messages only. There is no general shell, arbitrary filesystem query, permanent deletion, iCloud-setting or permission-changing tool.

`scripts/test.sh` runs Rust stdio/IPC tests, Swift socket and live-workspace tests, real Tinymist compilation, revision conflicts, atomic edits, native undo, library/resource/history/template flows and PDF/page review. Rust and Swift have independent coverage reports and 80% line-coverage gates. HURL is not used for this stdio/Unix-socket integration.
