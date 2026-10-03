"""Generate owned, deterministic evaluation pages on the SSD (no user documents)."""
import json
import pathlib
import subprocess
import sys
import textwrap

ROOT = pathlib.Path(sys.argv[1]).resolve()
REPO = pathlib.Path(__file__).resolve().parents[2]
if not str(ROOT).startswith('/Volumes/SSD/Developer/'):
    raise ValueError('Evaluation artifacts must be on the external SSD.')
ROOT.mkdir(parents=True, exist_ok=True)
COMPILER = REPO / '.tools/tinymist'
FONT = REPO / 'Sources/LeftBlankCore/Resources/Fonts'
pages = []


def compile_page(page_id, lines, extra=''):
    source = ['#set page(paper: "a4", margin: 0pt)',
              '#set text(font: ("Noto Sans SC", "Libertinus Serif"), size: 11pt)']
    for text, size, x, y in lines:
        source.append(f'#place(top + left, dx: {x}pt, dy: {y}pt)[#text(size: {size}pt, {json.dumps(text, ensure_ascii=False)})]')
    source.append(extra)
    typ = ROOT / f'{page_id}.typ'
    typ.write_text('\n'.join(source) + '\n')
    subprocess.run([str(COMPILER), 'compile', '--root', str(ROOT), '--font-path', str(FONT), str(typ), str(ROOT / f'{page_id}.pdf')], check=True)
    pages.append(dict(id=page_id, file=f'{page_id}.pdf', expectedText='\n'.join(line[0] for line in lines)))


zh = [
    '研究笔记：让文稿重新可编辑',
    '我们希望把一张清晰的截图或一页文档转换成可以继续修改的源码。',
    '第一阶段优先恢复文字、简单标题和段落，用户可以核对识别结果。',
    '本地处理能够减少上传敏感资料的需要，也可以在离线时继续工作。',
    '但是，读出所有文字，并不意味着原来的版式已经被准确地恢复。',
    '双栏文章需要先读完左栏，再读右栏，避免把不同段落交叉拼接。',
    '表格还需要保留单元格之间的关系，否则金额和项目名称可能错配。',
    '中文引号、括号和标点需要检查；英文单词不能在换行时被错误拆开。',
    '我们应该同时评估识别准确率、阅读顺序、标题层级和编辑便利程度。',
    '评估方法',
    '这些样本使用固定的原文生成，可以明确比较输入和输出之间的差异。',
    '接下来再收集经过授权的真实文档，覆盖截图、扫描件和复杂的表格。',
    '产品应当把这项能力称为内容恢复，并且提供容易使用的人工校对。',
]
zh_lines = [(zh[0], 24, 48, 48)]
zh_lines += [(text, 17 if i == 9 else 11, 48, 110 + (i - 1) * 30) for i, text in enumerate(zh[1:], 1)]
compile_page('chinese', zh_lines)

en_title = 'A practical note on editable reconstruction'
en_paragraphs = [
    'A useful importer should recover text without confusing content recovery with faithful page reconstruction. Writers need a clean draft that they can review and continue editing.',
    'The reading order matters as much as individual characters. A two-column document must be read down the first column before the second column. Headers, footnotes, and captions complicate this decision.',
    'This benchmark uses owned synthetic pages with fixed ground truth. It cannot estimate customer satisfaction or accuracy on the distribution of real documents.',
    'A line-break hyphen should be reviewed: an inter-\nface split across two lines is still a single word. Typography, tables, and embedded illustrations need separate checks.',
]
en_lines = [(en_title, 23, 48, 48)]
y = 108
for paragraph in en_paragraphs:
    for part in paragraph.split('\n'):
        for line in textwrap.wrap(part, width=82):
            en_lines.append((line, 11, 48, y))
            y += 18
    y += 16
compile_page('english', en_lines)

left = [f'L{i}: The first column keeps its own sequence.' for i in range(1, 9)]
right = [f'R{i}: The second column follows after the first.' for i in range(1, 9)]
for page_id, title, title_x, size in [
    ('columns-wide', 'A two-column report with a full-width heading', 38, 24),
    ('columns-short', 'Weekly Notes', 212, 24),
]:
    lines = [(title, size, title_x, 45)]
    lines += [(text, 10, 38, 110 + i * 26) for i, text in enumerate(left)]
    lines += [(text, 10, 319, 110 + i * 26) for i, text in enumerate(right)]
    compile_page(page_id, lines)

rows = [['Item', 'Quantity', 'Price (USD)'], ['Notebook', '3', '18.00'], ['Pencil', '12', '6.00'],
        ['Folder', '4', '8.00'], ['Total', '19', '32.00']]
lines = [('Order summary / 采购清单', 25, 48, 48)]
lines += [(cell, 12, 55 + c * 164, 128 + r * 38) for r, row in enumerate(rows) for c, cell in enumerate(row)]
lines += [('Please verify every quantity and price before continuing.', 11, 48, 365)]
extra = '#place(top + left, dx: 48pt, dy: 116pt)[#rect(width: 492pt, height: 190pt, stroke: 0.5pt)]'
compile_page('table', lines, extra)

lines = [
    ('A structured project note', 25, 48, 48),
    ('1. Overview', 18, 48, 112),
    ('This page contains headings, a checklist, a formula, and a small figure.', 10, 48, 148),
    ('1.1. Next steps', 14, 48, 190),
    ('• Review the recognized characters.', 10, 56, 223),
    ('• Keep the source editable.', 10, 56, 247),
    ('1. Check the reading order.', 10, 56, 271),
    ('2. Compare the resulting page.', 10, 56, 295),
    ('Energy relation: E = mc²', 10, 48, 344),
    ('Figure: input → processing → editable source', 10, 48, 385),
    ('2. Limitations', 18, 48, 486),
    ('This figure includes shapes that cannot be represented by OCR text alone.', 10, 48, 520),
]
extra = '#place(top + left, dx: 48pt, dy: 420pt)[#rect(width: 140pt, height: 30pt, fill: rgb("dae9f2"), stroke: none)]\n#place(top + left, dx: 220pt, dy: 420pt)[#circle(radius: 15pt, fill: rgb("e8dec9"), stroke: none)]'
compile_page('outline', lines, extra)

# Screenshots and scans share exactly the Chinese page's ground truth.
from PIL import Image, ImageFilter
for page_id, ppi in [('chinese-image', 144), ('chinese-lowres', 60)]:
    subprocess.run([str(COMPILER), 'compile', '--root', str(ROOT), '--font-path', str(FONT), '--ppi', str(ppi), str(ROOT / 'chinese.typ'), str(ROOT / f'{page_id}.png')], check=True)
    pages.append(dict(id=page_id, file=f'{page_id}.png', expectedText='\n'.join(zh)))
image = Image.open(ROOT / 'chinese-image.png').convert('RGB')
image.rotate(3.5, resample=Image.Resampling.BICUBIC, expand=True, fillcolor='white').filter(ImageFilter.GaussianBlur(0.65)).save(ROOT / 'chinese-skew.png')
pages.append(dict(id='chinese-skew', file='chinese-skew.png', expectedText='\n'.join(zh)))
image.save(ROOT / 'chinese-scan.pdf', resolution=144)
pages.append(dict(id='chinese-scan', file='chinese-scan.pdf', expectedText='\n'.join(zh)))
# A common failure class: a scanned image plus a partial, unrepresentative native text layer.
partial = '#set page(paper: "a4", margin: 0pt)\n#place(top + left)[#image("chinese-image.png", width: 100%)]\n#place(top + left, dx: 48pt, dy: 780pt)[#text(fill: white, "Scanned document")]\n'
(ROOT / 'partial-text-layer.typ').write_text(partial)
subprocess.run([str(COMPILER), 'compile', '--root', str(ROOT), str(ROOT / 'partial-text-layer.typ'), str(ROOT / 'partial-text-layer.pdf')], check=True)
pages.append(dict(id='partial-text-layer', file='partial-text-layer.pdf', expectedText='\n'.join(zh)))
(ROOT / 'pages.json').write_text(json.dumps(pages, ensure_ascii=False, indent=2) + '\n')
print(f'Generated {len(pages)} reference inputs at {ROOT}')
