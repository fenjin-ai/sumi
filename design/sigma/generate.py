#!/usr/bin/env python3
"""Construct a Sumi Σ study from golden-ratio geometry, using only the stdlib.

Run: python3 design/sigma/generate.py
Outputs are siblings of this script. These are concept assets, not the app icon.
"""

from math import cos, hypot, pi, sin, sqrt
from pathlib import Path

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


def mark(written=False):
    points = centerline()
    if not written:
        path = "M" + " L".join(f"{x:.3f},{y:.3f}" for x, y in points)
        return f'<path d="{path}" fill="none" stroke="{INK}" stroke-width="{WEIGHT:.3f}" stroke-linecap="round"/>'

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
        radius = WEIGHT * (0.78 + 0.22 * sin(pi * lengths[i] / lengths[-1])) / 2
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
    return f'<path d="{path}" fill="{INK}"/>'


def tile(written=False):
    return f'<rect x="56" y="56" width="912" height="912" rx="206" fill="{PAPER}"/>' + mark(written)


def svg(body, width=1024, height=1024):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n'


def main():
    directory = Path(__file__).resolve().parent
    for name, written in [("geometric", False), ("written", True)]:
        (directory / f"{name}.svg").write_text(svg(tile(written)))
    board = '<rect width="1440" height="900" fill="#191C20"/>'
    for x, written, title, subtitle in [(120, False, "01  几何 Σ", "等宽笔画 · 清楚保留求和符号"),
                                        (800, True, "02  书写 Σ", "一笔路径 · 用正弦函数轻微调节粗细")]:
        board += f'<g transform="translate({x} 72) scale(.5)">{tile(written)}</g>'
        board += f'<g transform="translate({x + 205} 625) scale(.08)">{tile(written)}</g>'
        board += f'<text x="{x + 256}" y="760" text-anchor="middle" fill="{INK}" font-family="PingFang SC, sans-serif" font-size="21">{title}</text>'
        board += f'<text x="{x + 256}" y="800" text-anchor="middle" fill="#989FA8" font-family="PingFang SC, sans-serif" font-size="16">{subtitle}</text>'
    (directory / "comparison.svg").write_text(svg(board, 1440, 900))


if __name__ == "__main__":
    main()
