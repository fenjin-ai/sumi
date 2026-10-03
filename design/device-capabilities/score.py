"""Record objective checks; open-ended fidelity/relevance is reviewed separately."""
import collections
import decimal
import json
import math
import pathlib
import re
import statistics
import subprocess
import sys

cases_path = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
repo = pathlib.Path(__file__).resolve().parents[2]
cases = {c['id']: c for c in json.loads(cases_path.read_text())}
observations = json.loads((output / 'observations.json').read_text())
scored = []
for row in observations:
    case = cases[row['id']]
    expected = case.get('expected', {})
    result = json.loads(row['responseJSON']) if row.get('responseJSON') else None
    checks = {}
    if 'exact' in expected:
        checks['strictExact'] = result == expected['exact']
    if case['category'] == 'extraction' and result:
        # Factual preservation is separate from the frozen numeric-only string requirement.
        normalized = dict(result)
        normalized['budget'] = re.sub(r'\s*(?:USD|元)\s*$', '', normalized.get('budget', ''))
        checks['factsAfterUnitSuffixRemoval'] = normalized == expected['exact']
    if case['category'] == 'groundedQA':
        checks['strictAnswerAndEvidence'] = bool(result is not None and result.get('answer') == expected['answer'] and
            (result.get('evidence') == '' if expected['answer'] == '' else bool(result.get('evidence')) and result['evidence'] in expected['source']))
    if case['category'] == 'extractiveSummary':
        selected = result.get('sentences', []) if result else []
        checks['verbatimOnly'] = bool(selected) and all(s in expected['sourceSentences'] for s in selected)
        checks['allThreeSalientSentences'] = set(selected) == set(expected['sentences']) and len(selected) == 3
    if case['category'] == 'rewrite':
        text = result.get('rewritten', '') if result else ''
        checks['literalNamesNumbersDates'] = bool(text) and all(s in text for s in expected['mustKeep'])
        checks['shorter'] = len(text) < len(case['input'])
    if case['category'] == 'toolCalling':
        checks['expectedToolRoute'] = [call['name'] for call in row['toolCalls']] == expected['tools']
        if expected['tools'] == ['countWords']:
            checks['exactToolArgument'] = row['toolCalls'] == [{'name': 'countWords', 'argument': 'red green blue'}]
    if case['category'] == 'arithmetic':
        try:
            checks['numericAnswer'] = decimal.Decimal(result['answer']) == decimal.Decimal(expected['numeric'])
        except (decimal.InvalidOperation, KeyError, TypeError):
            checks['numericAnswer'] = False
    if case['category'] == 'vision':
        actual = result.get('answer', '') if result else ''
        compact = lambda s: re.sub(r'\s+', '', s).replace(':', '：')
        checks['exactAnswerIgnoringWhitespaceAndColonStyle'] = compact(actual) == compact(expected['answer'])
    if case['category'] == 'code':
        source = result.get('source', '') if result else ''
        checks['literalRequiredText'] = all(s in source for s in expected['mustKeep'])
        checks['noMarkdownFences'] = '```' not in source
        safe = bool(source) and not re.search(r'#\s*(?:read|include|import|image)\b', source)
        checks['noFileOrPackageAccess'] = safe
        if safe:
            path = output / (row['id'] + '.typ')
            path.write_text(source)
            try:
                proc = subprocess.run([str(repo / '.tools/tinymist'), 'compile', '--root', str(output.resolve()), '--font-path', str(repo / 'Sources/LeftBlankCore/Resources/Fonts'), str(path.resolve()), str(path.with_suffix('.pdf').resolve())], timeout=10, capture_output=True, text=True)
                checks['compiled'] = proc.returncode == 0
                row['compilerError'] = proc.stderr
            except subprocess.TimeoutExpired:
                checks['compiled'] = False
                row['compilerError'] = 'Compiler timeout'
    row['checks'] = checks
    row['decoded'] = result
    scored.append(row)
summary = {}
for category in dict.fromkeys(r['category'] for r in scored):
    rows = [r for r in scored if r['category'] == category]
    timing = sorted(r['seconds'] for r in rows)
    metrics = collections.defaultdict(lambda: [0, 0])
    for row in rows:
        for key, value in row['checks'].items():
            metrics[key][0] += int(value)
            metrics[key][1] += 1
    summary[category] = dict(total=len(rows), errors=sum(r.get('error') is not None for r in rows), checks=dict(metrics), wallSecondsIncludingTokenCountingP50=statistics.median(timing), wallSecondsIncludingTokenCountingP95=timing[math.ceil(len(timing)*.95)-1])
(output / 'scored.json').write_text(json.dumps(scored, ensure_ascii=False, indent=2)+'\n')
(output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(summary, ensure_ascii=False, indent=2))
