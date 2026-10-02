#set page(paper: "a4", margin: 23mm, numbering: "1")
#set text(font: ("Libertinus Serif", "PingFang SC"), size: 11pt, fill: rgb("253238"))
#set par(leading: 0.85em)
#show heading.where(level: 1): set text(size: 30pt, weight: "regular")
#show heading.where(level: 2): set text(size: 17pt, weight: "regular")

= The shape of a queue
_Engineering notes · systems and reasoning_

== Start with a relationship

Little's law connects the average number of items in a system, their arrival rate, and their time in the system:

$ L = lambda W $

With an average arrival rate of $lambda = 120$ requests per second and an average time of $W = 0.25$ seconds, the average number of requests in the system is $L = 30$.

== Make the idea concrete

```python
arrival_rate = 120
average_time = 0.25
in_system = arrival_rate * average_time
print(in_system)  # 30
```

== Keep the assumptions visible

This relationship describes long-run averages in a stable system. It does not predict the latency of an individual request.

#table(columns: (1fr, 1fr), inset: 8pt,
 table.header([*Quantity*], [*Average*]),
 [Arrival rate], [120 requests / second],
 [Time in system], [0.25 seconds],
 [Requests in system], [30],
)
