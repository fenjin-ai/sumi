# Sumi · Σ construction

Approved on 2026-10-01 for the app, repository and web assets. Python's standard library computes the shape without font outlines, stock logo artwork or an image-generation model. See [Brand](../../Brand/README.md) for exported assets and website integration.

## Meaning

- **Σ** retains the recognizable outline and summation meaning of capital Sigma. The brand metaphor is separate thoughts coming together into writing; the mathematical symbol itself is not claimed to mean writing.
- **S** connects Sigma's name with Sumi's initial. Viewers do not need to interpret the mark as a Latin S as well.
- **Writing** is suggested by a continuous path from the upper right to the lower right, with a slight change in stroke pressure. No pen, caret or paper symbol is attached.

The golden ratio provides an adjustable construction rule, not a guarantee of beauty. Distinctiveness, small-size recognition and stroke balance still require visual judgment.

## Geometry

Let `φ = (1 + √5) / 2`, height `H = 540`, and width `W = H / φ`. Relative to the top-left of the glyph, the center path has five vertices:

```text
(W, 0) → (0, 0) → (W/φ, H/2) → (0, H) → (W, H)
```

The three internal vertices use quadratic Bézier transitions. Each trim length is `H / φ⁵`, limited to a third of the adjoining segment lengths:

```text
B(u) = (1-u)² A + 2u(1-u) P + u² C,  0 ≤ u ≤ 1
```

`P` is the original vertex; `A` and `C` lie on the adjacent segments. This preserves the tangent direction at the joins. The base width is `w₀ = H / φ⁶ ≈ 30.09`.

Stroke width varies with **normalized arc length** `t ∈ [0, 1]`:

```text
w(t) = w₀ · (0.78 + 0.22 sin(πt))
```

The ends are lighter and the middle slightly heavier. π participates in the generated outline rather than appearing as an extra decorative symbol. Offsetting along both path normals by `w(t)/2` and closing the ends produces a standalone filled contour.

## Generation

```sh
python3 design/sigma/generate.py
# macOS with librsvg's rsvg-convert; also writes PNG, ICO and ICNS
python3 design/sigma/generate.py --raster
```

The generator writes `Brand/` and `Resources/AppIcon.svg`; `--raster` also updates `Resources/AppIcon.icns` and `Resources/AppIconLight.icns`. SVG uses a scalable 1024-pixel coordinate system. The 16/32-pixel app icons and favicons use the same skeleton with optical corrections of 1.55× stroke width and 1.12× glyph size. Light and dark transparent marks share the same contour.

Change `HEIGHT`, `WIDTH`, `WEIGHT`, `CORNER` or the pressure function in the generator, then regenerate all assets. Do not edit individual copies by hand. Temporary files live in the repository's `build/` directory and are cleaned up automatically.
