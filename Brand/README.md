# Sumi 品牌资源

正式标志为“一笔写成的 Σ”：象牙白 `#ECECE7`，炭灰 `#24282D`。所有字形由同一个[数学构形生成器](../design/sigma/generate.py)输出，[构形说明](../design/sigma/README.md)包含黄金比例与笔压公式。

品牌文案：**给想法一点留白。** / **A quiet space to write.** 面向写作与思考表达价值；实现技术放在功能说明和开发文档中。

![Sumi](logo-512.png)

| 文件 | 用途 |
|---|---|
| `logo.svg`、`logo-512.png`、`logo-1024.png` | 带圆角底板的正式图标；PNG 保留四角透明 |
| `mark-light.svg`、`mark-dark.svg` | 深色或浅色背景上的透明单色字形 |
| `social-preview.png`、`social-preview.svg` | 1280×640 GitHub / Open Graph 分享预览图 |
| `../Resources/AppIcon.svg`、`../Resources/AppIcon.icns` | macOS 应用图标，ICNS 包含 16–1024px 各档 |
| `web/favicon.svg`、`web/favicon.ico` | 网站 favicon；ICO 包含 16、32、48px 图层 |
| `web/favicon-{16,32,48}x{16,32,48}.png` | 对应尺寸的 PNG favicon |
| `web/apple-touch-icon.png` | 180×180 Apple Touch 图标，不透明底色 |
| `web/icon-192.png`、`web/icon-512.png` | Web Manifest 通用图标 |
| `web/icon-maskable-512.png` | 满版底色，字形处于安全区域的 maskable 图标 |
| `web/site.webmanifest` | 图标与品牌颜色清单，图标路径相对于清单 |

## 重新生成

在 macOS 安装 librsvg 后，从仓库根目录执行：

```sh
python3 design/sigma/generate.py --raster
```

脚本使用系统 `iconutil` 打包 ICNS，直接封装 PNG 帧生成 ICO；不依赖 Pillow 或 ImageMagick。不带 `--raster` 只生成 SVG 和 manifest。应用构建直接使用已提交资源，不需要安装这些生成工具。

## 网站接入

将 `web/` 内的文件复制到网站的 `public/` 根目录，HTML 加入：

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#24282D">
```

子路径部署时同步调整这些地址。分享卡片使用 `social-preview.png`，网站的 `og:image` 应填写实际部署后的完整 HTTPS 地址。manifest 只声明品牌资源，站点的安装行为、起始页面与作用域由未来网站配置。

GitHub 的 Settings → General → Social preview 使用这里的 `social-preview.png`。README 使用 `logo.svg`。本资源不替换 fenjin-ai 组织头像。
