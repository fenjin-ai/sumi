#set page(paper: "a4", margin: 23mm, numbering: "1")
#set text(font: ("Libertinus Serif", "PingFang SC"), size: 11pt, fill: rgb("253238"))
#set par(leading: 0.85em)
#show heading.where(level: 1): set text(size: 30pt, weight: "regular")
#show heading.where(level: 2): set text(size: 17pt, weight: "regular")

= 队列的形状
_技术笔记 · 系统与推导_

== 从一个关系开始

Little 定律连接了系统中的平均任务数、平均到达速率，以及任务在系统中停留的平均时间：

$ L = lambda W $

若平均到达速率为 $lambda = 120$ 次每秒，平均停留时间为 $W = 0.25$ 秒，则系统内平均任务数为 $L = 30$。

== 把想法写成代码

```python
arrival_rate = 120
average_time = 0.25
in_system = arrival_rate * average_time
print(in_system)  # 30
```

== 把假设写清楚

这个关系描述稳定系统中的长期平均值，并不预测某一次请求的延迟。

#table(columns: (1fr, 1fr), inset: 8pt,
 table.header([*观测量*], [*平均值*]),
 [到达速率], [每秒 120 次请求],
 [停留时间], [0.25 秒],
 [系统内任务数], [30],
)
