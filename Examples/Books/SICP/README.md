# SICP in Sumi

Open `main.typ` to read and edit the complete book. The PDF preview follows
this entry point even when you navigate to a definition in another file.

- `main.typ`: the complete text, equations and Scheme examples.
- `styles/book.typ`: typography, page geometry and code block styling.
  The entry point uses `#import "styles/book.typ": book, horizontalRule, divider`
  followed by `#show: book`. Change the style here without editing the prose.
- `fig/`: all 84 original vector illustrations, using relative paths.
- `ATTRIBUTION.md` and `LICENSE`: source credit and CC BY-SA 4.0 terms.

You can split your own books into chapters with `#include "chapters/intro.typ"`.
Keep those files inside the same document folder. Import a whole folder into
Sumi when it has local dependencies; importing a single file copies only that
file. Export the source project to preserve the entire folder.

The downloadable example includes the source, styles, illustrations and license.
It does not include the precompiled PDF or upstream Texinfo archival source;
those remain available in the Sumi repository. Each addition to the library
creates an independent copy. No Scheme code is executed.
