#import "@preview/cetz:0.5.2": canvas, draw
#set page(paper: "a4", margin: 22mm)
#set text(font: ("Libertinus Serif", "PingFang SC"), fill: rgb("253238"), size: 12pt)
#let sage = rgb("dbe6df")
#let ink = rgb("253238")
#text(size: 30pt)[A cache, at a glance.]
#v(6mm)
Two paths for a request. One clear explanation.

#v(15mm)
#align(center)[
#canvas(length: 1cm, {
 import draw: *
 rect((0, 3), (3.4, 4.5), radius: 0.15, fill: sage, stroke: none)
 rect((6, 3), (9.4, 4.5), radius: 0.15, fill: rgb("b8cebf"), stroke: none)
 rect((6, -1), (9.4, 0.5), radius: 0.15, fill: rgb("e5c7b5"), stroke: none)
 rect((0, -1), (3.4, 0.5), radius: 0.15, fill: rgb("e7e7df"), stroke: none)
 content((1.7, 3.75), text(size: 16pt)[Request])
 content((7.7, 3.75), text(size: 16pt)[Cache])
 content((7.7, -0.25), text(size: 16pt)[Source])
 content((1.7, -0.25), text(size: 16pt)[Response])

 line((3.6, 3.75), (5.8, 3.75), stroke: ink + 0.9pt, mark: (end: ">"))
 line((7.7, 2.8), (7.7, 0.7), stroke: ink + 0.9pt, mark: (end: ">"))
 line((5.8, -0.25), (3.6, -0.25), stroke: ink + 0.9pt, mark: (end: ">"))
 line((6, 3.1), (3.4, 0.4), stroke: rgb("7b978b") + 0.9pt, mark: (end: ">"))
 content((8.8, 1.7), text(size: 10pt)[Miss])
 content((4.0, 2.1), text(size: 10pt)[Hit])
})
]
#v(12mm)
#text(size: 18pt)[See the relationship. Then read the detail.]
#v(5mm)
On a hit, return the cached result. On a miss, read the source. Keep the diagram and the explanation together so the reader can follow both.
