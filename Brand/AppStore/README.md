# 留白 App Store 上架素材

这套素材让第一次看到留白的人，知道自己能用它完成什么作品。推荐定位是「Mac 上的专注写作与精美排版」，同时展示 Typst 在技术笔记、数据报告、演示页、图解和视觉版式中的用途。商店的名称和文案均提供简体中文与英文。

## 直接查看和使用

- `contact-sheet.zh-Hans.jpg` 与 `contact-sheet.en-US.jpg`：两套宣传图的总览。
- `screenshots/zh-Hans/` 与 `screenshots/en-US/`：各八张 2880 × 1800 的无透明 PNG，按文件名前缀上传；同名 SVG 保留可编辑的排版源文件。
- `metadata/`：名称、副标题、关键词、推广文本、完整描述的独立文本文件，以及对应的 `fields.json`。上传时使用内容本身，不需要文件末尾的换行。
- `samples/`：十四份原创 Typst 样稿，含中英文各七种题材，可导入留白后继续修改。
- `raw/`：真实应用窗口的原始 JPEG，保留制作来源。
- `video/`：两条 24 秒、1920 × 1080、30 fps 的无声宣传短片，以及 App Preview 的录制分镜与字幕。
- `tools/`：重做宣传图、剪辑宣传片和校验素材的脚本。

PNG 的尺寸与色彩格式符合当前 Apple 的 Mac 截图规格。它们使用本地 release 构建的真实界面，尚未与最终 Mac App Store 构建逐项比对。短片用真实截图做平移缩放和淡入淡出，是可用于网站与社交媒体的宣传素材；它不是实际操作录屏，不应直接作为 App Preview 提交。正式预览视频按附带分镜录制。

## 命名和搜索

| 字段 | 简体中文 | English |
|---|---|---|
| 商店名称 | 留白 LeftBlank：写作与排版 | LeftBlank: Write & Typeset |
| 副标题 | 专注文章、技术笔记与报告，导出 PDF | Notes, reports & polished PDFs |
| 品牌名 | 留白 | LeftBlank |
| 品牌标语 | 此中有真意，欲辨已忘言 | Ink for your thoughts |

名称补上用途词，保留已经确定的品牌与 Σ 标记。副标题先告诉用户能产出什么，不用诗句承担功能解释。英文名保持一个单词的 LeftBlank 写法，帮助用户在商店、网站和 GitHub 之间识别同一个产品。

搜索词围绕具体意图：Typst 编辑器、公式笔记、技术文档、长文、图表、图解、演示页和海报。避免 Markdown、LaTeX、PPTX、AI 写作等会暗示当前并不具备的兼容或内置能力的词。演示页指以 Typst 编排并以 PDF 分享的页面，不承诺 PowerPoint 文件导出。

2026 年 10 月 2 日检索发现，「留白」已经用于照片边框、私人记录及视觉模板类产品，例如 [White Border](https://apps.apple.com/cn/app/id1232787087)、[留白 墨记](https://apps.apple.com/cn/app/id6758817898) 和 [留白 WHITE](https://apps.apple.com/cn/app/id6756087998)。因此建议将 LeftBlank 与用途词一起显示。公开搜索没有确认同名 LeftBlank 编辑器，但这不能证明名称可注册或不存在商标冲突；实际名称能否使用需要在 App Store Connect 创建应用时确认。

这些是基于产品功能的关键词建议，没有购买搜索量数据，也不宣称能保证排名。上线后观察实际搜索曝光、产品页访问和下载表现，再一次调整一组词。不要把竞争产品名放进关键词。

## 八张图的题材和顺序

| 顺序 | 场景 | 用户看到的作品 | 要表达的价值 |
|---|---|---|---|
| 01 | 文章与随笔 | 原创中文随笔或英文 essay，编辑与成稿并排 | 写下想法，也看见页面成形 |
| 02 | 技术与学习 | Little 定律、公式、Python 示例和数据表 | 把推导、代码与解释放在一起 |
| 03 | 工作与研究 | 写作时间柱状图、方案对比和报告正文 | 图表与论述在同一份文档里 |
| 04 | 演示与教学 | 两页 16:9 的原创演示稿，三块视觉卡片 | 演讲、课堂和 PDF 讲义的页面设计 |
| 05 | 图解与关系 | 请求、缓存、数据源与结果的矢量流程图 | 让结构和路径比纯文字更容易理解 |
| 06 | 海报与版式 | 城市观察主题的几何海报 | 排版也是一种视觉表达 |
| 07 | 工具与发现 | 真实 ⌘J 命令面板 | 工具可以逐层发现，不必先记住所有语法 |
| 08 | 长文与手稿 | 含多级章节的原创短篇手稿和大纲 | 长文导航与持续修改 |

首三张分别回答「这是什么」「有什么特别」「我能拿它做什么」。接下来的三张扩展创作题材，再用工具与长文场景收尾。截图中的代码是文档内容，不会自动执行。报告数据与正文属于虚构演示，不是产品的性能结果。

Typst 的能力会随着包与输出工具扩展。留白这套宣传以已经编译成功的作品为证据。动画可作为后续专题素材：例如动画讲解几何关系或图表变化；在没有验证应用自身的动画预览与导出之前，不将它写成留白的内置功能。

## 视觉设计

使用已有品牌的纸白 `#F4F4EF`、炭灰 `#24282D` 和象牙白 `#ECECE7`，辅以鼠尾草绿及少量陶土色。宣传标题使用宋体或 Georgia，界面仍保留其真实字体。固定的页码、细线与外边距形成写作手册的视觉秩序；首尾采用左右构图，中间场景使用更大的横向界面。

参考了 [iA Writer](https://ia.net/writer) 的单一信息与安静版面、[Ulysses](https://ulysses.app/) 的作品场景叙事、[Bear](https://bear.app/) 的字体层级和主色点缀。以上是对官方宣传页面的设计观察。没有复制这些产品的截图、文案、商标或设备图。

画面主体来自真实应用，不绘制虚构控件。宣传文字与外层背景是独立设计层，真实窗口使用等比缩放，海报页展示实际预览区的局部，不绘制额外控件。示例内的图表、图解、演示页与几何海报也来自实际编译的 Typst 源文件。保持文案清晰，避免同时堆叠多个卖点。

## 重做素材

从 SSD 上的该工作树执行。依赖 macOS、Python 3、librsvg 的 `rsvg-convert`、ImageMagick 的 `magick`；短片另需 `ffmpeg` 与 `ffprobe`。

```sh
export TMPDIR=/Volumes/SSD/Developer/Codex/tmp
export TMP=/Volumes/SSD/Developer/Codex/tmp
export TEMP=/Volumes/SSD/Developer/Codex/tmp
python3 Brand/AppStore/tools/render.py
python3 Brand/AppStore/tools/video.py
python3 Brand/AppStore/tools/validate.py
```

更换 `raw/` 中同名 JPEG 后，重跑脚本即可保留版式。原始 JPEG 用 CUA 从运行中的应用窗口采集。捕获时使用独立的 `LEFTBLANK_STATE_DIR` 演示库，避免把个人文档带进宣传图。用系统设置中的「应用语言」切换中英文，不翻译或重绘 UI。

原始构建基于 `26ec58c`，通过 `scripts/build.sh release` 构建。十四份样稿已用该工作树的 Tinymist 0.15.8 编译为页面图进行检查；新增样稿不依赖外部图片，图解只使用已经随应用分发的 CeTZ 0.5.2。检查文字、数学、图形、输入控件和页面结果后，生成最终 PNG。此验证不等于 App Store 分发验收。

## 提交前还需要确认的内容

这次完成的是素材，没有上传或提交应用。最终提交需要一个可用的 Mac App Store 构建，再核对截图中的每个场景、系统要求和描述。仓库现有发布文档主要覆盖 Developer ID 分发；App Sandbox 下的 Tinymist、文档与资源访问，以及本地代理连接，需要单独验证。

价格、销售区域、版权主体、支持网址、隐私政策网址、隐私标签与年龄分级取决于实际提交版本和账号信息，未在素材中虚构。当前文案不宣传 iCloud 同步、内置 AI、协作、PPTX 或动画导出，也没有宣称所有扩展包均能离线工作。确认最终版本后，可以再增加经过验证的场景。

## Apple 官方规格

核对日期为 2026 年 10 月 2 日。名称与副标题各不超过 30 字符；关键词不超过 100 字符；推广文本不超过 170 字符。当前文本均已校验。关键词不承担排名保证，推广文本也不是搜索关键词字段。见 [产品页指南](https://developer.apple.com/app-store/product-page/)。

Mac 截图要求 16:10，可用 2880 × 1800 等指定尺寸；每组 1 至 10 张，不含 alpha 通道。见 [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。

Mac App Preview 使用 1920 × 1080，15 至 30 秒，最多 30 fps，采用 Apple 接受的视频编码；提交时重新核对音轨等完整技术要求。见 [App Preview 规格](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) 与 [App Preview 制作指南](https://developer.apple.com/app-store/app-previews/)。
