# Local intelligence: product evaluation

Status: researched and prototyped on October 1, 2026; no model runs in the shipping editor yet.

## Decision

Use a deterministic recommendation system first, with an optional Foundation Models adapter for natural-language intent. A writing tool should remain useful without Apple Intelligence, and ordinary typing, command discovery, saving and preview must never wait for inference. Keep macOS 14 compatibility; conditionally offer the on-device model on macOS 26 or later when `SystemLanguageModel.default.availability` is available. Do not silently substitute a cloud model.

| Experience | First implementation | Where a model can help |
| --- | --- | --- |
| Learn a shortcut after repeated toolbar use | Local counts by stable command ID, input origin, cooldown and dismissal | None needed |
| Find “a numbered Python block” | Search the bilingual command catalogue immediately | Select a command ID from a small retrieved candidate set |
| Find a drawing package | Search the cached Universe catalogue and curated categories | Rank real package IDs and give a short explanation |
| Improve a document's appearance | Offer tested typography presets with an explicit before/after preview | Classify intent, such as lecture notes, letter or technical report |
| Write or repair Typst | Existing insertion templates, Tinymist diagnostics and optional coding-agent MCP | Do not depend on a small model to produce correct code or mathematics |

Apple explicitly describes summarization, extraction and classification as suitable tasks, and cautions against using the on-device model for code, basic mathematics and logical reasoning. Guided generation gives a useful output shape, but cannot guarantee a correct recommendation. Validate every command/package/preset ID against the actual catalogue. Package descriptions and document text are untrusted data, not instructions to execute actions.

## Interaction

Keep existing search results available immediately. An optional, fixed-height “Suggestions” row can appear inside command search or the package browser after an explicit request; never insert a floating panel over the manuscript. Keep the currently selected result stable when suggestions arrive. Show at most three candidates, each with a short reason and the real shortcut. Applying one uses the same command and undo path as a manual action.

For shortcut learning, count successful actions from toolbar/menu/palette separately from keyboard use. After a few repeated pointer actions, show one short hint in the existing compact learning help. Stop after dismissal or demonstrated shortcut use, and cap frequency across the entire app. Store only per-command aggregates locally; do not retain printable keystrokes, document text, raw click trails or cross-app activity. Provide an off switch and reset. These statistics should not enter diagnostic logs, iCloud preferences or model prompts.

Document-based recommendations are explicit opt-in. Use the current selection, nearby heading and lightweight structure summary, not the entire library. Prefer normal document rendering for preset previews. An on-device language model cannot certify visual page quality from source alone.

## Scheduling and correctness

A dedicated actor owns a cancellable task and one session per request. The main actor only captures an immutable snapshot and presents a validated result. Start after an idle debounce or a deliberate action, never from the synchronous text-change callback. Skip during IME composition, continuous input, low-power mode, serious thermal pressure or memory pressure. Bound pending work to one request; replacing it cancels the old task. Cancellation does not imply zero immediate device load, so also reject results whose document ID, revision, selection or query generation no longer matches.

Avoid an ever-growing chat history. Retrieve a small candidate set first, bound source excerpts and output length, and make fresh sessions. macOS 26 documentation specifies a 4,096-token context shared by instructions, input, schemas and output. Newer APIs/models may differ; version prompts and verify supported SDK APIs rather than relying on beta-only features. Prewarm only when a person opens the relevant discovery UI and model use is likely. Release idle sessions. Use the Foundation Models Instruments track and app signposts to measure inference, keystroke-to-display latency and energy together.

Fallback on unavailability, download pending, unsupported language, refusal, rate limiting, context overflow, timeout or invalid IDs: keep the ordinary command/package results. No modal errors or disabled editor. Do not advertise generated text as guaranteed fact.

## Local exploratory probe

A standalone, unshipped probe used `SystemLanguageModel.default`, a fresh `LanguageModelSession` per question and a small `@Generable` result. Only four synthetic English/Chinese requests were supplied; no personal writing was read. The local macOS 27 machine reported `available`:

| Synthetic request | Selected ID | Elapsed |
| --- | --- | --- |
| I want a table with three columns | table | 1.515 s |
| Add line numbers to my Python block (Chinese) | codly | 0.453 s |
| I want a vector geometry diagram | cetz | 0.424 s |
| Show the document's headings (Chinese) | outline | 0.406 s |

This is a feasibility smoke test, not a quality or latency guarantee; four obvious candidates do not establish useful recommendation accuracy. Initial loading was visibly slower than subsequent requests, reinforcing asynchronous presentation. The probe is kept under `design/intelligence/` for reproducibility and is outside the app build.

Before shipping, compare rules-only search against rules-plus-model on at least 100 bilingual, ambiguous and out-of-catalogue requests, plus long text and prompt-injection cases. Measure useful top-three selection, invalid-ID rate (must be zero after validation), dismissal rate and p95 keystroke latency while generation runs. Test supported macOS versions, unavailable models, offline use, cancellation, low power and thermal pressure. Set an initial engineering budget of no synchronous inference, no additional main-thread task over 8 ms, no measurable input-latency regression above 5 ms, and at most one in-flight request. These are acceptance targets, not measured results.

## References

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Capabilities and availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Session prewarming](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:))
- [Framework updates and model-version changes](https://developer.apple.com/documentation/updates/foundationmodels)
