# Fixed intelligence effect evaluation

This is an opt-in native evaluation of the real `LocalIntelligence.suggest` and
`ReferencePageImporter.importPage` entry points. It records quality misses as data;
a passing harness test means the measurements completed, not that the feature
meets a quality threshold. It is skipped in ordinary CI. No DB, Hurl, OrbStack,
cloud model or personal documents are involved.

The frozen request set has 100 cases, 50 Chinese and 50 English. Each of five
categories has 20 cases: direct operations, paraphrases, parameters, ambiguity and
unsupported requests. All commands use the existing insertion catalogue.
Expected values are fixed before inference. Scoring compares the command and all
effective fields, including defaults, so omitted explicit parameters fail.
`none` requires a clean unsupported result; `reject` accepts a clean refusal or
a validation error for invalid bounded parameters. General generation errors
never count as correct. A validation error on a `none` case is reported separately
as a safe refusal and does not increase the strict score.

The fixtures are owned synthetic material, not a sample of production traffic.
Six native PDFs exercise Chinese and English text, columns, a table and document
structure. Four raster/scan variants share the Chinese ground truth. A final PDF
has a scanned image and a small unrelated text layer. This last input tests
whether partial native text causes the importer to skip the image's content.

The page metric removes whitespace and applies Unicode NFKC normalization before
computing Levenshtein character error rate. Character bag recall ignores order
and helps distinguish omitted characters from reading-order corruption. Neither
metric evaluates layout, paragraph breaks or editable table/list semantics;
rendered comparisons and generated source must be reviewed separately. The
plain-text formula in the outline fixture does not establish math recovery.

## Reproduce on an eligible Mac

Run from an SSD worktree. Set `evaluation_root` to a new directory under
`/Volumes/SSD/Developer/Codex/tmp`. The model must be available; the harness
asserts this condition. This records the currently installed system model, which
may change with OS/model updates.

```sh
source scripts/environment.sh
evaluation_root=$(mktemp -d /Volumes/SSD/Developer/Codex/tmp/leftblank-effects.XXXXXX)
cp design/intelligence-evaluation/requests.json "$evaluation_root/requests.json"
python3 design/intelligence-evaluation/build-pages.py "$evaluation_root"
LEFTBLANK_EVALUATION=1 LEFTBLANK_EVALUATION_ROOT="$evaluation_root" \
  swift test --filter IntelligenceEvaluationTests
python3 design/intelligence-evaluation/analyze.py "$evaluation_root"
```

The Python environment needs Pillow. `analyze.py` also needs Poppler; use the
bundled runtime and set `PDFTOPPM` if `pdftoppm` is not in `PATH`. The compiler uses
the checked-out `.tools/tinymist` and bundled Noto Sans SC font. Generated PDFs,
images and build artifacts stay on the SSD. Each request result is written
atomically, so an interrupted run preserves completed observations.

The [October 3 report](../../docs/intelligence-effect-evaluation-2026-10-03.md)
records the first run and two stability repeats. Raw request responses, page
metrics, generated Typst and representative comparisons are in `results-2026-10-03/`. There was
no prompt, rule or importer tuning between these runs. The rules-only comparison
scores the recorded rule response against the same expected effective fields;
it is not a model-only experiment or a comparison to ordinary catalogue search.
