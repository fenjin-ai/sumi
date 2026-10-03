# Local intelligence: product evaluation

Status: researched and prototyped on October 1, 2026. On October 3, the user approved a first implementation of natural-language typesetting and one-image/first-PDF-page reconstruction into editable Typst. The Mac-first implementation and local regression tests are complete; it has not been released. The original probe below remains historical evidence.

See [Apple Intelligence integration roadmap](apple-intelligence-roadmap.md) for the six researched product ideas, the approved reconstruction scope, SDK compatibility and Private Cloud Compute enrollment status.

## Decision

Use a deterministic recommendation system first, with an optional Foundation Models adapter for natural-language intent. A writing tool should remain useful without Apple Intelligence, and ordinary typing, command discovery, saving and preview must never wait for inference. Keep macOS 14 compatibility; conditionally offer the on-device model on macOS 26 or later when `SystemLanguageModel.default.availability` is available. Do not silently substitute a cloud model.

| Proposed experience | Practical starting point | Where a model can help |
| --- | --- | --- |
| Learn a shortcut after repeated toolbar use | Local counts by stable command ID, input origin, cooldown and dismissal | None needed |
| Find “a Python code block” | Search the bilingual command catalogue immediately | Select a validated insertion command from a bounded schema |
| Find a drawing package | Search the cached Universe catalogue and curated categories | Rank real package IDs and give a short explanation |
| Improve a document's appearance | Offer tested typography presets with an explicit before/after preview | Classify intent, such as lecture notes, letter or technical report |
| Write or repair Typst | Existing insertion templates, Tinymist diagnostics and optional coding-agent MCP | Do not depend on a small model to produce correct code or mathematics |
| Recover one image/PDF page as editable content | Local PDF text extraction or Vision OCR, bounded blocks and deterministic Typst generation | Classify headings and paragraphs from extracted text into validated structure |

Apple explicitly describes summarization, extraction and classification as suitable tasks, and cautions against using the on-device model for code, basic mathematics and logical reasoning. Guided generation gives a useful output shape, but cannot guarantee a correct recommendation. Validate every command/package/preset ID against the actual catalogue. Package descriptions and document text are untrusted data, not instructions to execute actions.

## Interaction

Keep existing search results available immediately. An optional, fixed-height “Suggestions” row can appear inside command search or the package browser after an explicit request; never insert a floating panel over the manuscript. Keep the currently selected result stable when suggestions arrive. Show at most three candidates, each with a short reason and the real shortcut. Applying one uses the same command and undo path as a manual action.

For shortcut learning, count successful actions from toolbar/menu/palette separately from keyboard use. After a few repeated pointer actions, show one short hint in the existing compact learning help. Stop after dismissal or demonstrated shortcut use, and cap frequency across the entire app. Store only per-command aggregates locally; do not retain printable keystrokes, document text, raw click trails or cross-app activity. Provide an off switch and reset. These statistics should not enter diagnostic logs, iCloud preferences or model prompts.

Document-based recommendations are explicit opt-in. Use the current selection, nearby heading and lightweight structure summary, not the entire library. Prefer normal document rendering for preset previews. An on-device language model cannot certify visual page quality from source alone.

The implemented reconstruction starts with one image or the first PDF page and simple headings/paragraphs. The initial import uses PDFKit/Vision on macOS 14+ without model inference. Natural-language command selection uses optional text-only Foundation Models inference on macOS 26+. It does not require SDK 27 image attachments, preserving the pinned Xcode 26.3 build. Model output is structured data; deterministic code escapes literal content and generates source. Reconstruction opens a new editable library draft and compiles through the normal preview pipeline, preserving the original document. Typesetting suggestions prepare the existing command form and change the current document only after explicit confirmation, using native undo. Exact layout, formula or original-source recovery is not promised. Keep shared validation/generation in `LeftBlankCore` for later iPad use.

## Scheduling and correctness

The implemented services run extraction and inference in cancellable detached tasks. Model classification and command-specific parameter extraction use fresh sessions. The main actor only captures an immutable snapshot and presents a validated result. The initial feature starts only after a deliberate action, never from the synchronous text-change callback. IME composition is protected by the existing command-palette flow. Low-power/thermal scheduling and pressure measurements remain evaluation targets. Bound pending work to one request; replacing it cancels the old task. Cancellation does not imply zero immediate device load, so also reject results whose document ID, revision, selection or query generation no longer matches.

Avoid an ever-growing chat history. Retrieve a small candidate set first, bound source excerpts and output length, and make fresh sessions. macOS 26 documentation specifies a 4,096-token context shared by instructions, input, schemas and output. Newer APIs/models may differ; version prompts and verify supported SDK APIs rather than relying on beta-only features. Prewarm only when a person opens the relevant discovery UI and model use is likely. Release idle sessions. Use the Foundation Models Instruments track and app signposts to measure inference, keystroke-to-display latency and energy together.

Fallback on unavailability, download pending, unsupported language, refusal, rate limiting, context overflow, timeout or invalid IDs: keep the ordinary command/package results. No modal errors or disabled editor. Do not advertise generated text as guaranteed fact.

## October 3 implementation evidence

Command search now has an explicit **Understand Request** action. Local rules handle simple bilingual requests. When rules do not match and Apple Intelligence is available, a constrained dynamic schema selects a real insertion command. A fresh second schema contains only the selected command's fields. The editable command form remains the acceptance point, including commands with no fields. Source generation stays in the existing insertion code; manuscript text is not model input.

**Documents → Reconstruct from Image or PDF…** imports one image or the first PDF page as a new managed draft. PDFKit extracts native text; Vision performs local OCR when necessary. The initial importer groups simple headings and paragraphs, bounds input to 30 MB and 24 million image pixels, downsamples before OCR, and escapes all recognized text. Complex table detection, assets, formulas and exact layout are outside this version. Importing and editing a draft and exporting a valid PDF are exercised through the real app pipeline. If writing changes during import, the draft is retained in the library without navigating away from current writing.

The complete repository test script and lint check passed. Shared code also built for an iOS 17 simulator target. Native tests inject results for cancellation and mutation checks; a separate `LEFTBLANK_MODEL=1` smoke test passed three synthetic Chinese/English requests on the available local macOS 27 model, including field extraction and an unsupported action. This does not replace the 100-request quality evaluation below or establish performance on macOS 26/14. No personal writing was used in model testing.

## Local exploratory probe

Recorded October 1, 2026; this is not verification of the implementation approved on October 3.

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
