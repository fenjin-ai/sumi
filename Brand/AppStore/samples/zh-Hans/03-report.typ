#set page(paper: "a4", margin: 23mm, numbering: "1")
#set text(font: ("Libertinus Serif", "PingFang SC"), size: 10pt, fill: rgb("253238"))
#set par(leading: 0.85em)
#show heading.where(level: 1): set text(size: 27pt, weight: "regular")
#show heading.where(level: 2): set text(size: 14pt, weight: "regular")

= 让下一步更清楚
_项目报告 · 虚构示例_

== 建议

下一次发布聚焦可靠的写作流程。让关键操作容易找到，在观察实际使用效果之后，再决定增加哪些功能。

== 一周里的写作时间


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
== 比较不同方案

#table(columns: (1fr, 1fr, 1fr), inset: 9pt,
 stroke: 0.5pt + rgb("b7c8bf"),
 fill: (x,y) => if y == 0 { rgb("e6ece6") },
 table.header([*方案*], [*收益*], [*取舍*]),
 [完善核心流程], [日常使用更顺畅], [新增功能较少],
 [扩展功能范围], [覆盖更多需求], [增加使用复杂度],
 [增加外部集成], [连接新的流程], [引入外部依赖],
)

== 下一步计划

+ 观察新用户如何创建第一份文档。
+ 改善让他们停顿或丢失上下文的环节。
+ 用一份新文档再次验证。

== 如何判断效果

用户能够创建、修改、预览和分享文档，始终知道自己写到了哪里。记录真实的使用过程，而不是假设更长的功能清单意味着更好的体验。
