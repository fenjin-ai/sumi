# Sumi

Sumi 是一款面向 macOS 的原生 Typst 写作编辑器。它采用 Nano Emacs 启发的安静深色界面，以可发现的键盘命令帮助用户写出 Typst，用 Tinymist 提供语言服务和实时排版预览。

文稿始终是普通 `.typ` 文件。Swift 负责应用和编辑交互，Tinymist 作为应用管理的独立进程运行。

- [产品需求](docs/requirements.md)
- [技术架构与交互规范](docs/architecture.md)
- [实施与验收记录](docs/progress.md)

当前工作名为 Sumi。最低目标系统为 macOS 14，首先验证 Apple Silicon。
