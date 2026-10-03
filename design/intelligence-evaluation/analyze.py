"""Score the recorded run and render visual comparisons; no inference is re-run."""
import collections
import json
import math
import os
import pathlib
import shutil
import statistics
import subprocess
import sys
import unicodedata
from PIL import Image, ImageDraw

ROOT = pathlib.Path(sys.argv[1]).resolve()
REPO = pathlib.Path(__file__).resolve().parents[2]
POPPLER = os.environ.get('PDFTOPPM') or shutil.which('pdftoppm')


def normalized(text):
    return ''.join(c for c in unicodedata.normalize('NFKC', text) if not c.isspace())


def edit_distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j - 1] + (x != y)))
        row = nxt
    return row[-1]


def percentile(values, q):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * q) - 1)]


def render(pdf, png):
    if not POPPLER:
        raise RuntimeError('Set PDFTOPPM to the bundled or installed pdftoppm executable.')
    subprocess.run([POPPLER, '-f', '1', '-singlefile', '-scale-to', '1100', '-png', str(pdf), str(png.with_suffix(''))], check=True, stdout=subprocess.DEVNULL)


requests = json.loads((ROOT / 'request-results.json').read_text()) if (ROOT / 'request-results.json').exists() else []
summary = {}
for group in ('category', 'language', 'route'):
    summary[group] = {}
    for label in dict.fromkeys(r[group] for r in requests):
        values = [r for r in requests if r[group] == label]
        summary[group][label] = dict(correct=sum(r['correct'] for r in values), total=len(values), p50=statistics.median(r['seconds'] for r in values), p95=percentile([r['seconds'] for r in values], .95))
summary['total'] = dict(correct=sum(r['correct'] for r in requests), total=len(requests), errors=sum('error' in r for r in requests))
(ROOT / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(summary, ensure_ascii=False, indent=2))
for r in requests:
    if not r['correct']:
        print('MISS', r['id'], r['request'], 'expected', r['expected'], 'actual', r.get('suggestion', r.get('error')), 'route', r['route'])

if not (ROOT / 'page-results.json').exists():
    sys.exit(0)
pages = json.loads((ROOT / 'page-results.json').read_text())
for page in pages:
    expected, actual = normalized(page['expectedText']), normalized(page['extractedText'])
    overlap = sum((collections.Counter(expected) & collections.Counter(actual)).values())
    page['normalizedCharacterErrorRate'] = edit_distance(expected, actual) / len(expected)
    page['characterBagRecall'] = overlap / len(expected)
    page['characterBagPrecision'] = overlap / max(1, len(actual))
    typ = ROOT / (page['id'] + '-reconstructed.typ')
    pdf = typ.with_suffix('.pdf')
    compilation = subprocess.run([str(REPO / '.tools/tinymist'), 'compile', '--root', str(ROOT), '--font-path', str(REPO / 'Sources/LeftBlankCore/Resources/Fonts'), str(typ), str(pdf)], capture_output=True, text=True)
    page['compiled'] = compilation.returncode == 0
    page['compilerOutput'] = compilation.stderr
    if page['compiled']:
        output = typ.with_suffix('.png')
        render(pdf, output)
        original = ROOT / page['file']
        if original.suffix == '.pdf':
            original = original.with_suffix('.png')
            render(ROOT / page['file'], original)
        # Side-by-side preserves a shared page scale; empty space remains visible.
        canvas = Image.new('RGB', (1200, 900), 'white')
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 8), f"{page['id']} | input", fill='black')
        draw.text((620, 8), 'reconstructed', fill='black')
        for path, x in [(original, 0), (output, 600)]:
            image = Image.open(path).convert('RGB')
            image.thumbnail((580, 850))
            canvas.paste(image, (x + 10, 35))
        canvas.save(ROOT / (page['id'] + '-comparison.png'))
    print('PAGE', page['id'], 'CER', round(page['normalizedCharacterErrorRate'], 4), 'bag recall', round(page['characterBagRecall'], 4), 'seconds', round(page['seconds'], 3), 'headings', page['headingCount'], 'tables', page['tableCount'], 'lists', page['listCount'], 'compiled', page['compiled'])
(ROOT / 'page-metrics.json').write_text(json.dumps(pages, ensure_ascii=False, indent=2) + '\n')
