#set page(paper: "a4", margin: 24mm)
#set text(font: ("Libertinus Serif", "PingFang SC"), size: 11pt)

#heading(level: 1, "A practical note on editable reconstruction")

#text("A useful importer should recover text without confusing content recovery with faithful page reconstruction. Writers need a clean draft that they can review and continue editing.")

#text("The reading order matters as much as individual characters. A two-column document must be read down the first column before the second column. Headers, footnotes, and captions complicate this decision.")

#text("This benchmark uses owned synthetic pages with fixed ground truth. It cannot estimate customer satisfaction or accuracy on the distribution of real documents.")

#text("A line-break hyphen should be reviewed: an inter- face split across two lines is still a single word. Typography, tables, and embedded illustrations need separate checks.")
