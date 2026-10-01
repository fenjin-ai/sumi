# Sumi brand assets

The approved mark is a continuous capital **Σ**, in ivory `#ECECE7` on charcoal `#24282D`. Every asset comes from one [geometry generator](../design/sigma/generate.py). The [construction notes](../design/sigma/README.md) describe the golden-ratio skeleton and pressure equation.

The public tagline is **A quiet space to write.** Branding speaks to writing and thinking; implementation details belong in feature and developer documentation. The app may use a localized tagline in its interface.

![Sumi](logo-512.png)

| Asset | Use |
|---|---|
| `logo.svg`, `logo-512.png`, `logo-1024.png` | Approved mark on a rounded tile; PNG corners remain transparent |
| `mark-light.svg`, `mark-dark.svg` | Transparent monochrome mark for dark or light backgrounds |
| `social-preview.png`, `social-preview.svg` | 1280×640 GitHub / Open Graph card |
| `../Resources/AppIcon.svg`, `../Resources/AppIcon.icns` | macOS application icon, with ICNS representations from 16 to 1024 pixels |
| `web/favicon.svg`, `web/favicon.ico` | Website favicon; ICO contains 16, 32 and 48 pixel frames |
| `web/favicon-16x16.png`, `web/favicon-32x32.png`, `web/favicon-48x48.png` | PNG favicons |
| `web/apple-touch-icon.png` | Opaque 180×180 Apple Touch icon |
| `web/icon-192.png`, `web/icon-512.png` | General web manifest icons |
| `web/icon-maskable-512.png` | Full-bleed background with the mark inside the maskable safe area |
| `web/site.webmanifest` | Brand colors and icon paths, relative to the manifest |

## Regeneration

With librsvg installed on macOS, run from the repository root:

```sh
python3 design/sigma/generate.py --raster
```

The script uses system `iconutil` to package ICNS and wraps PNG frames directly into ICO. It does not depend on Pillow or ImageMagick. Without `--raster`, it writes SVG and the manifest only. Building the app uses committed assets and does not require generation tools.

## Website integration

Copy the contents of `web/` to the website's `public/` directory, then add:

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#24282D">
```

Adjust paths for a site deployed below the domain root. Use `social-preview.png` for sharing, with its deployed absolute HTTPS URL in `og:image`. The manifest declares brand assets only; a future website must choose its own installation behavior, start URL and scope.

GitHub **Settings → General → Social preview** uses `social-preview.png`. The repository README uses `logo.svg`. These assets do not replace the organization avatar.
