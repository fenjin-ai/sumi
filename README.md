# Sumi

Sumi 是一款面向 macOS 的原生 Typst 写作编辑器。它采用 Nano Emacs 启发的安静深色界面，以可发现的键盘命令帮助用户写出 Typst，用 Tinymist 提供语言服务和实时排版预览。

文稿始终是普通 `.typ` 文件。Swift 负责应用和编辑交互，Tinymist 作为应用管理的独立进程运行。

- [产品需求](docs/requirements.md)
- [技术架构与交互规范](docs/architecture.md)
- [实施与验收记录](docs/progress.md)

当前为 **0.1.1** 本地预览版。目标 macOS 14+，当前验证环境为 Apple Silicon / macOS 27。

## 使用

打开 `build/Sumi.app`。应用自带 Tinymist，无需另外安装 Typst、Rust 或 Homebrew。入门文稿见 [留白.typ](Examples/留白.typ)。

| 操作 | 快捷键 |
|---|---|
| 发现命令 | `⌘J`，设置中可改为 `⌘K` |
| 命令分组 | `i` 插入、`s` 样式、`p` 页面、`v` 视图、`f` 文件 |
| 搜索命令 | 打开面板后按 `/`，支持中文和英文关键词 |
| 返回 / 退出面板 | `Esc` |
| 插入后的占位内容 | `Tab` / `⇧Tab` 切换，`Esc` 结束 |
| 写作 / 并排 / 成稿 | `⌘1` / `⌘2` / `⌘3` |
| 新建 / 打开 / 保存 | `⌘N` / `⌘O` / `⌘S` |
| 另存为 / 导出 PDF | `⇧⌘S` / `⇧⌘E` |
| Typst 补全 / 查找 | `⌃.` / `⌘F` |

例如：`⌘J → i → t` 打开表格参数，填列数和行数后插入；选中文字后 `⌘J → s → b` 加粗。每次命令插入可以一次撤销。正文、代码和数学仍可直接输入完整 Typst。

预览百分比相对于面板适应宽度。双击成稿定位源码；移动源码选区会请求预览定位。预览保留最近成功的成稿，底部状态和“文稿检查”显示当前编译问题。导出遇到编译错误会失败，不会把旧 PDF 当作最新版本。

已有文件停顿约 650ms 后自动保存；未命名文稿保存在本地恢复副本。新建或打开其他文稿会先保存或归档当前草稿。`文件 → 恢复草稿副本` 可找回归档副本。外部程序修改同一文件时，Sumi 停止覆盖并提示重新加载或另存为。

应用状态位于 `~/Library/Application Support/Sumi/`，包括 `recovery.json`、草稿副本和导出缓存；命令入口偏好存于系统 UserDefaults。第一次引用未缓存的外部 Typst 包可能联网下载。

## 诊断日志

遇到异常时，可通过 `视图 → 打开诊断日志` 或 `⌘J → v → g` 在 Finder 中定位日志。日志目录为 `~/Library/Application Support/Sumi/Logs/`，当前文件 `events.jsonl`，最多保留 3 个轮转文件，每个约 1 MiB。

日志包含会话 ID、应用版本、毫秒时间、事件序号、快捷键/导航键、命令 ID、插入开始/完成/失败、选区与文稿版本，以及保存/导出和排版服务异常。普通键入只记录 `text` 事件，不记录正文、剪贴板内容、参数值或搜索词；系统错误描述可能包含文件路径。日志只在本机存储。发生崩溃时保留这些文件和 macOS 的崩溃报告即可，不需要记住最后执行的命令。

## 构建与测试

需要 Xcode 的 Swift 6 工具链、macOS SDK，以及已挂载的 `/Volumes/SSD/Developer`。在 SSD 上的仓库或工作树中运行：

```sh
scripts/build.sh release
scripts/test.sh
```

脚本下载并校验 Tinymist **0.15.8**，构建 `.app` 并进行本机临时签名。输出为 `build/Sumi.app`。测试启动同一 Swift LSP 客户端和真实 Tinymist，验证未保存内容、中文、多文件引用、20 个语法命令、编译失败和 PDF 内容。`swift test` 单独运行时跳过需要显式启用的集成测试。

源码划分为 `Sources/Sumi` 原生应用、`Sources/SumiCore` 协议与文本/文件逻辑、`Tests/SumiCoreTests` 自动化验证。许可证和固定版本记录在 `Resources/ThirdParty.txt`。

## 当前边界

这是可运行的本地首版：单窗口、一个活动编辑缓冲区，暂无 Vim、云同步、折叠、插件或任意成稿直接编辑。从主文稿预览/诊断跳转子文件时保留编译入口；手动打开或另存为会采用新的入口。

中文文本、撤销和保存已验证，完整拼音候选输入流程仍需人工确认。Intel、macOS 14 实机、大型长文性能和完整 VoiceOver 流程尚未验证。仅本机临时签名，尚未做 Developer ID 签名和公证，不作为公开发行包。详见[验收记录](docs/progress.md)。
