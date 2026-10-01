#!/usr/bin/env python3
"""Generate Sumi's approved Σ identity from golden-ratio geometry.

python3 design/sigma/generate.py           # SVG and web manifest; stdlib only
python3 design/sigma/generate.py --raster  # Also PNG, ICO and ICNS; macOS + librsvg
"""

import argparse
import json
from math import cos, hypot, pi, sin, sqrt
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

PHI = (1 + sqrt(5)) / 2
HEIGHT = 540.0
WIDTH = HEIGHT / PHI
WEIGHT = HEIGHT / PHI**6
CORNER = HEIGHT / PHI**5
INK = "#ECECE7"
PAPER = "#24282D"


def mix(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def distance(a, b):
    return hypot(a[0] - b[0], a[1] - b[1])


def skeleton():
    """A capital sigma, traced from upper right to lower right."""
    left, top = (1024 - WIDTH) / 2, (1024 - HEIGHT) / 2
    right, bottom = left + WIDTH, top + HEIGHT
    return [(right, top), (left, top), (left + WIDTH / PHI, 512),
            (left, bottom), (right, bottom)]


def centerline():
    """Round each interior vertex with a tangent-continuous quadratic Bézier."""
    points = skeleton()
    samples = [points[0]]

    def line(end):
        start = samples[-1]
        count = max(1, int(distance(start, end) / 2))
        samples.extend(mix(start, end, i / count) for i in range(1, count + 1))

    for previous, corner, following in zip(points, points[1:], points[2:]):
        trim = min(CORNER, distance(previous, corner) / 3, distance(corner, following) / 3)
        entry = mix(corner, previous, trim / distance(corner, previous))
        exit = mix(corner, following, trim / distance(corner, following))
        line(entry)
        for i in range(1, 41):
            t = i / 40
            samples.append(mix(mix(entry, corner, t), mix(corner, exit, t), t))
    line(points[-1])
    return samples


def mark(weight=WEIGHT, ink=INK):
    points = centerline()
    # s is normalized arc length, not a sample index. A mild sine envelope
    # suggests pressure along one stroke while remaining legible at Dock size.
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + distance(a, b))
    edges = ([], [])
    tangents = []
    radii = []
    for i, point in enumerate(points):
        before, after = points[max(0, i - 1)], points[min(len(points) - 1, i + 1)]
        length = distance(before, after)
        tangent = ((after[0] - before[0]) / length, (after[1] - before[1]) / length)
        normal = (-tangent[1], tangent[0])
        radius = weight * (0.78 + 0.22 * sin(pi * lengths[i] / lengths[-1])) / 2
        tangents.append(tangent)
        radii.append(radius)
        for edge, sign in zip(edges, (1, -1)):
            edge.append((point[0] + sign * radius * normal[0], point[1] + sign * radius * normal[1]))

    def cap(point, tangent, radius, end):
        normal = (-tangent[1], tangent[0])
        sign = 1 if end else -1
        return [(point[0] + sign * radius * (cos(pi * i / 16) * normal[0] + sin(pi * i / 16) * tangent[0]),
                 point[1] + sign * radius * (cos(pi * i / 16) * normal[1] + sin(pi * i / 16) * tangent[1]))
                for i in range(1, 17)]

    contour = edges[0] + cap(points[-1], tangents[-1], radii[-1], True)
    contour += list(reversed(edges[1])) + cap(points[0], tangents[0], radii[0], False)
    path = "M" + " L".join(f"{x:.3f},{y:.3f}" for x, y in contour) + " Z"
    return f'<path d="{path}" fill="{ink}"/>'


def tile(compact=False, full_bleed=False):
    background = (f'<rect width="1024" height="1024" fill="{PAPER}"/>' if full_bleed else
                  f'<rect x="56" y="56" width="912" height="912" rx="206" fill="{PAPER}"/>')
    # At 16–32px the original stroke is less than half a pixel wide. Preserve
    # the same skeleton, with a modest optical weight/size correction.
    symbol = mark(weight=WEIGHT * (1.55 if compact else 1))
    if compact:
        symbol = f'<g transform="translate(512 512) scale(1.12) translate(-512 -512)">{symbol}</g>'
    return background + symbol


def svg(body, width=1024, height=1024):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n'


def social_preview():
    return svg(
        '<rect width="1280" height="640" fill="#191C20"/>'
        f'<g transform="translate(112 146) scale(.34)">{tile()}</g>'
        f'<text x="532" y="301" fill="{INK}" font-family="Helvetica Neue, Arial, sans-serif" font-size="88" font-weight="400" letter-spacing="-2">Sumi</text>'
        '<text x="537" y="366" fill="#A7ADB5" font-family="Helvetica Neue, Arial, sans-serif" font-size="26">A quiet space to write.</text>'
        '<text x="537" y="453" fill="#8F979F" font-family="PingFang SC, sans-serif" font-size="20" letter-spacing="3">给想法一点留白</text>', 1280, 640)


def render(source, target, size=None):
    command = ["rsvg-convert", str(source), "-o", str(target)]
    if size:
        command += ["-w", str(size), "-h", str(size)]
    subprocess.run(command, check=True)


def write_ico(path, images):
    """ICO directory containing standard PNG frames; no extra image library."""
    frames = [(size, image.read_bytes()) for size, image in images]
    offset = 6 + 16 * len(frames)
    directory = bytearray(struct.pack("<HHH", 0, 1, len(frames)))
    for size, data in frames:
        directory.extend(struct.pack("<BBBBHHII", size, size, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    path.write_bytes(directory + b"".join(data for _, data in frames))


def export_rasters(root, brand):
    for command in ("rsvg-convert", "iconutil"):
        if not shutil.which(command):
            raise SystemExit(f"Missing {command}; install librsvg on macOS to export raster assets.")
    scratch = root / "build"
    scratch.mkdir(exist_ok=True)
    # Explicit repository-local scratch keeps all development artifacts on SSD.
    with tempfile.TemporaryDirectory(prefix="brand-", dir=scratch) as temporary:
        temporary = Path(temporary)
        iconset = temporary / "Sumi.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = size * scale
                source = brand / ("web/favicon.svg" if pixels <= 32 else "logo.svg")
                render(source, iconset / f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png", pixels)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources/AppIcon.icns")], check=True)
        for size in (512, 1024):
            render(brand / "logo.svg", brand / f"logo-{size}.png", size)
        render(brand / "social-preview.svg", brand / "social-preview.png")
        web = brand / "web"
        frames = []
        for size in (16, 32, 48):
            path = web / f"favicon-{size}x{size}.png"
            render(web / "favicon.svg", path, size)
            frames.append((size, path))
        write_ico(web / "favicon.ico", frames)
        for size in (192, 512):
            render(brand / "logo.svg", web / f"icon-{size}.png", size)
        full_bleed = temporary / "full-bleed.svg"
        full_bleed.write_text(svg(tile(full_bleed=True)))
        render(full_bleed, web / "apple-touch-icon.png", 180)
        render(full_bleed, web / "icon-maskable-512.png", 512)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raster", action="store_true", help="also regenerate PNG, ICO and the application ICNS")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    brand = root / "Brand"
    web = brand / "web"
    web.mkdir(parents=True, exist_ok=True)
    logo = svg(tile())
    (brand / "logo.svg").write_text(logo)
    (root / "Resources/AppIcon.svg").write_text(logo)
    (brand / "mark-light.svg").write_text(svg(mark()))
    (brand / "mark-dark.svg").write_text(svg(mark(ink=PAPER)))
    (brand / "social-preview.svg").write_text(social_preview())
    (web / "favicon.svg").write_text(svg(tile(compact=True)))
    manifest = {
        "name": "Sumi", "short_name": "Sumi", "theme_color": PAPER, "background_color": PAPER,
        "icons": [
            {"src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
            {"src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
            {"src": "icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"}
        ]
    }
    (web / "site.webmanifest").write_text(json.dumps(manifest, indent=2) + "\n")
    if options.raster:
        export_rasters(root, brand)
    print(f"Generated Sumi Σ assets in {brand}")


if __name__ == "__main__":
    main()
