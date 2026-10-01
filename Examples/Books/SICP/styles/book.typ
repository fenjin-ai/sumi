// Local book typography. The main document imports and applies this function.
#let book(body) = {
  set document(title: "Structure and Interpretation of Computer Programs", author: ("Harold Abelson", "Gerald Jay Sussman", "Julie Sussman"))
  set page(paper: "a4", margin: (x: 24mm, y: 22mm), numbering: "1")
  set text(font: "Libertinus Serif", size: 10pt, lang: "en")
  set par(justify: true, leading: 0.65em)
  set heading(numbering: none)
  set figure(numbering: none)
  show raw: set text(font: "DejaVu Sans Mono", size: 8pt)
  show raw.where(block: true): block.with(fill: luma(97%), inset: 8pt, radius: 3pt)
  show heading.where(level: 1): it => { pagebreak(weak: true); it }
  body
}
#let horizontalRule = line(length: 100%, stroke: 0.5pt + luma(75%))
#let divider = horizontalRule
