#set page(paper: "a4", margin: 23mm, numbering: "1")
#set text(font: ("Libertinus Serif", "PingFang SC"), size: 10pt, fill: rgb("253238"))
#set par(leading: 0.85em)
#show heading.where(level: 1): set text(size: 27pt, weight: "regular")
#show heading.where(level: 2): set text(size: 14pt, weight: "regular")

= A clearer way forward
_Project report · a fictional example_

== Decision

Keep the next release focused on a reliable writing workflow. Make the essential actions easy to find, and measure the result before adding more features.

== A week of writing


#let bar(label, hours, amount) = grid(columns: (22mm, 1fr, 15mm), gutter: 3mm, align: horizon,
 label, rect(width: amount, height: 6mm, fill: rgb("7b978b"), stroke: none, radius: 1mm), hours)
#bar([MON], [1.5 h], 42mm)
#v(3mm)
#bar([TUE], [2.0 h], 56mm)
#v(3mm)
#bar([WED], [1.0 h], 28mm)
#v(3mm)
#bar([THU], [3.0 h], 84mm)
#v(3mm)
#bar([FRI], [2.5 h], 70mm)
#v(5mm)
== Compare the options

#table(columns: (1fr, 1fr, 1fr), inset: 9pt,
 stroke: 0.5pt + rgb("b7c8bf"),
 fill: (x,y) => if y == 0 { rgb("e6ece6") },
 table.header([*Approach*], [*Benefit*], [*Tradeoff*]),
 [Improve core flow], [Clearer everyday use], [Fewer new features],
 [Add more features], [Broader coverage], [More complexity],
 [Build integrations], [New workflows], [External dependencies],
)

== Plan the next step

+ Observe how a new writer creates a document.
+ Improve the point where they pause or lose context.
+ Repeat the exercise with a fresh document.

== Define success

A writer can create, revise, preview, and share a document without losing their place. Record what happens, rather than assuming that a larger feature list means a better experience.
