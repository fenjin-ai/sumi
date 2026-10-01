# Sumi

[![CI](https://github.com/fenjin-ai/sumi/actions/workflows/ci.yml/badge.svg)](https://github.com/fenjin-ai/sumi/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/fenjin-ai/sumi/branch/main/graph/badge.svg)](https://app.codecov.io/github/fenjin-ai/sumi)

Sumi 是一款面向 macOS 的原生 Typst 写作编辑器。它采用 Nano Emacs 启发的安静深色界面，以可发现的键盘命令帮助用户写出 Typst，用 Tinymist 提供语言服务和实时排版预览。

文稿始终是普通 `.typ` 文件。Swift 负责应用和编辑交互，Tinymist 作为应用管理的独立进程运行。

- [产品需求](docs/requirements.md)
- [技术架构与交互规范](docs/architecture.md)
- [实施与验收记录](docs/progress.md)
- [0.2 编辑体验与工程化](docs/editor-evolution.md)

当前为 **0.2.0** 开发预览版。目标 macOS 14+，本地验证环境为 Apple Silicon / macOS 27；仅支持 Apple Silicon，CI 在 macOS 15 arm64 上构建。

## 使用

打开 `build/Sumi.app`。应用自带 Tinymist，无需另外安装 Typst、Rust 或 Homebrew。入门文稿见 [留白.typ](Examples/留白.typ)。

| 操作 | 快捷键 |
|---|---|
| 发现命令 | `⌘J`，设置中可改为 `⌘K` |
| 命令分组 | `i` 插入、`s` 样式、`p` 页面、`m` 数学、`l` 布局、`r` 文献、`c` 代码、`v` 视图、`f` 文件 |
| 搜索命令 | 打开面板后按 `/`，支持中文和英文关键词 |
| 返回 / 退出面板 | `Esc` |
| 插入后的占位内容 | `Tab` / `⇧Tab` 切换，`Esc` 结束 |
| 写作 / 并排 / 成稿 | `⌘1` / `⌘2` / `⌘3` |
| 新建 / 打开 / 保存 | `⌘N` / `⌘O` / `⌘S` |
| 另存为 / 导出 PDF | `⇧⌘S` / `⇧⌘E` |
| Typst 补全 / 查找 | `⌃.` / `⌘F` |

例如：`⌘J → i → t` 打开表格参数，填列数和行数后插入；选中文字后 `⌘J → s → b` 加粗。每次命令插入可以一次撤销。正文、代码和数学仍可直接输入完整 Typst。

共有 **97 个命令**，其中 **74 个 Typst 插入命令**。数学下有基本运算、公式结构、符号与字形三级发现路径；例如 `⌘J → m → b → f` 插入分式，在公式中自动使用数学语法。列表支持方向键与回车，并显示语法示例、完整键路径和官方文档。

`⌘J → c → u` 打开 Universe 包发现，按用途和分类搜索官方索引、查看版本和文档、插入固定版本的导入语句。默认浏览绘图包。索引缓存 24 小时，网络不可用时保留离线浏览；不兼容当前 Typst 引擎的包会提示所需版本。

编辑区默认启用阅读样式：光标离开后，标题、粗体、斜体与行内代码弱化标记；光标回到段落就显示完整源码。源文件、复制和撤销仍使用原始文本，`⌘J → v → t` 可关闭。公式、图表使用旁边的真实成稿预览。`⌘J → c` 还可发现格式化、缩进、取消缩进和注释。

预览百分比相对于面板适应宽度。双击成稿定位源码；移动源码选区会请求预览定位。预览保留最近成功的成稿，底部状态和“文稿检查”显示当前编译问题。导出遇到编译错误会失败，不会把旧 PDF 当作最新版本。

预览栏的「原色 / 深色」切换仅改变屏幕阅读配色，图片保持原色，导出 PDF 不变。Tinymist 按可见区域渲染以减少显示开销；这不等于错误文稿可以任意局部编译。输入未完成时保留最后成功成稿，并显示等待更新提示。

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

脚本下载并校验固定 SHA-256 的 Tinymist **0.15.8**（Typst 0.15.1），构建 `.app` 并进行本机临时签名，输出为 `build/Sumi.app`。测试运行真实原生窗口、编辑器、Workspace、WKWebView 和 Tinymist，覆盖命令发现、插入/撤销/重做、未保存内容、中文、多文件引用、全部插入命令编译、错误恢复和 PDF 内容。小型边界测试补充覆盖文本范围、协议分帧和索引验证。

`scripts/test.sh` 会生成 `build/coverage/summary.md`、HTML 与原始覆盖率数据，并对**所有应用和核心 Swift 源文件的唯一可执行源码行**执行 **80%** 门槛。SwiftUI 编译器会将同一源码行实例化多次，因此使用 LCOV 按文件/行去重，不排除界面文件。直接运行 `swift test` 会跳过显式启用的集成场景，也不执行覆盖率门槛。

GitHub Actions 对 PR 和 main 运行 Apple Silicon CI 并上传覆盖率与构建产物。推送与应用版本一致的标签（例如 `v0.2.0`）触发测试、打包与 GitHub Release，包含 arm64 ZIP 和 SHA-256。正式发布流程要求 **Developer ID 签名、Apple 公证及票据装订全部成功**，缺少凭据时停止发布；配置和验证方法见 [签名说明](docs/signing.md)。普通 CI 产物仍为临时签名开发包。

源码划分为 `Sources/SumiLauncher` 启动器、`Sources/Sumi` 可测试的原生应用库、`Sources/SumiCore` 协议与文本/文件逻辑；`Tests/SumiAppTests` 验证应用功能流程。第三方许可证和固定版本记录在 `Resources/ThirdParty.txt`。

## 当前边界

这是可运行的本地首版：单窗口、一个活动编辑缓冲区，暂无 Vim、云同步、折叠、插件或任意成稿直接编辑。从主文稿预览/诊断跳转子文件时保留编译入口；手动打开或另存为会采用新的入口。

中文文本、组合输入期间不重设样式、撤销和保存有自动验证；完整拼音候选输入流程仍需人工确认。macOS 14 实机、大型长文性能和完整 VoiceOver 流程尚未验证。仍属开发预览版，尚未做 Developer ID 签名和公证。详见[验收记录](docs/progress.md)。
