#import "@preview/cetz:0.5.2": canvas, draw
#set page(paper: "a4", margin: 22mm)
#set text(font: ("Libertinus Serif", "PingFang SC"), fill: rgb("253238"), size: 12pt)
#let sage = rgb("dbe6df")
#let ink = rgb("253238")
#text(size: 30pt)[一张图，看懂缓存。]
#v(6mm)
把一次请求的两条路径，放在同一个视野里。

#v(15mm)
#align(center)[
#canvas(length: 1cm, {
 import draw: *
 rect((0, 3), (3.4, 4.5), radius: 0.15, fill: sage, stroke: none)
 rect((6, 3), (9.4, 4.5), radius: 0.15, fill: rgb("b8cebf"), stroke: none)
 rect((6, -1), (9.4, 0.5), radius: 0.15, fill: rgb("e5c7b5"), stroke: none)
 rect((0, -1), (3.4, 0.5), radius: 0.15, fill: rgb("e7e7df"), stroke: none)
 content((1.7, 3.75), text(size: 16pt)[请求])
 content((7.7, 3.75), text(size: 16pt)[缓存])
 content((7.7, -0.25), text(size: 16pt)[数据源])
 content((1.7, -0.25), text(size: 16pt)[返回结果])

 line((3.6, 3.75), (5.8, 3.75), stroke: ink + 0.9pt, mark: (end: ">"))
 line((7.7, 2.8), (7.7, 0.7), stroke: ink + 0.9pt, mark: (end: ">"))
 line((5.8, -0.25), (3.6, -0.25), stroke: ink + 0.9pt, mark: (end: ">"))
 line((6, 3.1), (3.4, 0.4), stroke: rgb("7b978b") + 0.9pt, mark: (end: ">"))
 content((8.8, 1.7), text(size: 10pt)[未命中])
 content((4.0, 2.1), text(size: 10pt)[命中])
})
]
#v(12mm)
#text(size: 18pt)[先看关系，再读解释。]
#v(5mm)
缓存命中时，直接返回已有结果；未命中时，从数据源读取。图解与正文放在一起，能让读者更快找到关键信息。
