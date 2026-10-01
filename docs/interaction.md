# Interaction and performance · 0.3

## Behavior

- Frequent actions have one-chord shortcuts. Which-key organizes discovery without requiring the complete path every time. The catalog supplies shared metadata to toolbar, command list, guide and native menus. Outline supports both `⌘4` and `⌘J → v → o`.
- The 0.3 catalog has 106 commands with individually assigned Phosphor Regular icons and 12 distinct category icons. Typesetting changes the document; Workspace changes the application interface; Editing & Code covers editing, syntax, modules and Universe.
- Compact actions show native hover help after 300 ms, with the name and shortest shortcut. The popover sizes to its content rather than expanding into a large card.
- The outline is an independent margin overlay that does not change text width. Fine marks expand on hover and collapse 180 ms after leaving. `⌘4` pins it; Esc or another `⌘4` dismisses it. The 0.3 design removed a separate border, shadow, full-row highlight and close control. Narrow windows use a subtle editor-color fade for readability.
- Command discovery occupies a fixed 320 pt bottom panel. Categories, search results, empty state and parameter forms share the same outer geometry. A fixed guide shows syntax and shortcuts. Pointer hover changes row background without moving keyboard selection or scrolling. Keyboard navigation only brings the target into view.
- Forms use two columns with internal scrolling, verified at an 820×540 pt window. The category grid supports directional navigation in three columns.

## Performance work

- Phosphor PDF images are cached by name rather than repeatedly opened and parsed during view updates.
- Search uses a normalized index and reuses result sets while query/group remain unchanged. Examples and discovery paths are cached. Indexed row iteration removes repeated searches.
- Each source revision builds word metrics and a UTF-16 line index once. Caret positions use binary search. Query and selection changes do not rescan the whole document.
- Source highlighting retains source-style and reading-style snapshots. Movement within one paragraph does no attribute work; crossing paragraphs restores only the previous and current ranges. Source, font or styling changes rebuild snapshots. Regexes are compiled once and excluded ranges use binary search.
- The editor tracks its applied font separately instead of using a mixed attributed string's font property to decide whether to restyle everything. Native undo and marked-text protection remain intact.

No custom Metal renderer was added. The measured bottlenecks were repeated CPU work, file reads and unnecessary layout coupling.

## Benchmarks and regression checks

Measurements used the same Mac, a Swift Debug build, and a real `NSTextView` document of 100,500 UTF-16 units. One test performed 500 command selections while reading search results, word count and caret position. Another moved the caret across paragraphs 30 times and refreshed real attributed text. Service startup and initial cache construction are excluded; these are not frame-rate measurements.

| Path | Before | First measurement after changes |
|---|---:|---:|
| 500 command-selection computations | 17.549 s | 0.0035 s |
| 30 paragraph-style refreshes | 13.438 s | 0.189 s |

Functional tests assert identical manuscript frames/insets with the outline expanded or collapsed, stable editor geometry through search/selection/forms, equivalent native shortcuts and discovery paths, cache updates after insertion/undo/font/Unicode selection changes, loadable icons and hover content no taller than 48 pt. Loose 1 s / 3 s performance thresholds allow coverage instrumentation and shared CI runners.

## Identity

The approved monochrome Sigma uses an ivory continuous stroke on charcoal, suggesting separate thoughts coming together into writing. A golden-ratio skeleton and sine pressure envelope generate ICNS, SVG, social previews and favicons from one source. ICNS includes 16–1024 pixel representations, with optical correction at small sizes. See [construction](../design/sigma/README.md) and [brand assets](../Brand/README.md).
