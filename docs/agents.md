# Writing with an agent

Sumi lets a coding agent work in the document you are already writing. The agent can read the current unsaved text, make undoable edits, check compilation, and inspect a rendered page. You stay in the same editor.

## Connect Codex

1. Open **Sumi → Settings → Agent Access** and enable local access.
2. Copy the connection command shown there and run it in your terminal. For an app installed in Applications:

   ```sh
   codex mcp add sumi -- '/Applications/Sumi.app/Contents/Helpers/SumiMCP'
   ```

3. Start a new Codex session, or restart its MCP connections. `codex mcp list` shows the configured server; `/mcp` shows active connections in the CLI.
4. Ask, for example: “Read my current Sumi document. Make the introduction clearer, preserve my equations, and show me the rendered first page.”

The command uses Codex's standard local stdio integration, verified against its CLI help and [official OpenAI documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli). Other MCP clients can launch the same executable with no arguments. A separate Sumi account, cloud service, API key, or listening network port is not required.

Keep Sumi open while working. Disable Agent Access to stop new operations immediately. Enabling it allows programs running as your macOS user to use the bridge; it is not a per-agent identity system. The preference stays on this Mac and is never synchronized through iCloud. Sumi does not silently install configuration into other applications.

If you prefer a file workflow, let the agent write a `.typ` document and import or open it in Sumi. The live integration is useful when you want the agent to see your selection, avoid overwriting unsaved work, and review the current rendered result.

## Available tools

| Tool | Purpose |
| --- | --- |
| `sumi_list_documents` | Search the library by title or content and return document IDs. |
| `sumi_get_document` | Read live text, selection, document ID, and revision. |
| `sumi_open_document` | Open a library ID through the normal document preservation flow. |
| `sumi_create_document` | Create and open a document in the library. |
| `sumi_apply_edits` | Apply a batch of source edits as one native undo action. |
| `sumi_get_preview` | Read compilation state and diagnostics, including whether the preview is stale. |
| `sumi_export_pdf` | Compile the unsaved document and return a PDF path plus a PNG of the requested page. |
| `sumi_get_settings` | Read layout, app appearance, editor font size, preview appearance, and source styling. |
| `sumi_set_settings` | Change those five display settings. App appearance accepts `system`, `light`, or `dark`. |

Resources `sumi://document/current` and `sumi://settings` provide the same live read access. The `write_in_sumi` prompt explains the read–edit–review workflow to clients that support MCP prompts.

### Editing contract

Always read before editing. Pass the returned `document_id` and `revision` as `expected_revision`. An edit contains `start`, `end`, and `text`; offsets are zero-based UTF-16 code units, matching AppKit and the language server. `end` is exclusive. All ranges refer to the same original text.

```json
{
  "document_id": "ID returned by Sumi",
  "expected_revision": "revision returned by Sumi",
  "edits": [{"start": 0, "end": 0, "text": "= A new introduction\n\n"}]
}
```

A changed document returns `revision_conflict`; re-read and merge instead of blindly retrying. Overlapping ranges, split Unicode surrogate pairs, more than 100 edits, and source larger than 2 MiB are rejected before mutation. Undo restores the previous source through the same native path as normal typing. Revisions include the app session and monotonic editor revision, so undoing to the same text does not revive a stale edit token.

An incomplete document may retain an older successful preview. Treat `stale` accordingly. Export compiles the requested live revision and fails if the source changes or compilation fails; it never substitutes an old PDF. Exports are written to Sumi's `AgentExports` app-support directory. The agent cannot choose an arbitrary destination. The optional `page` argument selects a one-based page for visual review.

## Implementation and boundaries

```text
Codex or another MCP client
        │ stdio (official MCP SDK)
        ▼
SumiMCP bundled helper
        │ private same-user Unix socket
        ▼
Sumi main actor → live workspace → native undo / library / compiler
```

`SumiAutomation` owns the bounded app/helper protocol; `SumiMCPServer` maps it to MCP tools, resources, and prompts. The app does not load the protocol SDK. MCP source text and compiler messages are untrusted data; server instructions explicitly prohibit treating them as commands. Logs record operation names, not source bodies or tool arguments.

The socket directory is owner-only (0700), the socket is 0600, and both endpoints check the peer's operating-system user ID. There are at most eight concurrent connections, bounded message sizes, and socket I/O timeouts. Stopping access invalidates queued work and removes the listening socket. There is no general shell, filesystem, deletion, iCloud configuration, or permission-changing tool. Existing Typst compilation can still load the document's declared package dependencies as it normally does.

### SDK decision, reviewed 2026-10-01

We use the official [Swift SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1), released May 7, 2026, and pin it in SwiftPM. Its supported 2025-11-25 protocol covers our tools, resources, prompts, and stdio transport. It is maintained, although it trails the latest specification.

The official [Rust SDK](https://github.com/modelcontextprotocol/rust-sdk) supports the 2026-07-28 specification and is [Tier 2, while Swift is Tier 3](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/docs/2026-07-28/sdk.mdx). Rust is a strong option when newer protocol features become necessary. For this local editor integration, Swift keeps one build toolchain and shared data types. The separate helper is an intentional migration boundary: replacing it does not require changing editing or document storage.

Build with Xcode 26 or newer (Swift 6.2+); CI selects Xcode 26.3 explicitly. `Package.resolved` locks the SDK and its dependencies. `scripts/test.sh` includes real stdin/stdout protocol negotiation, tool/resource/prompt discovery, Unix-socket access and revocation, live-buffer edits, stale revisions, native undo, library ID boundaries, display settings, compilation errors, and PDF/page-image export. The MCP implementation targets participate in the same application coverage gate.
