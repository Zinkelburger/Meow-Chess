#!/usr/bin/env python3
"""Small architecture and documentation gates, independent of Flutter analysis."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
issues = []
for file in (root / 'lib/domain').glob('*.dart'):
    for line in file.read_text().splitlines():
        if line.startswith('import ') and any(x in line for x in ['flutter', 'dart:io', '../ui/', '../infrastructure/']):
            issues.append(f'{file.relative_to(root)}: domain depends on a platform or adapter')
for file in (root / 'lib/application').glob('*.dart'):
    if re.search(r"import ['\"].*(/ui/|/infrastructure/)", file.read_text()):
        issues.append(f'{file.relative_to(root)}: application depends on an adapter')
for file in [root / 'README.md', *(root / 'docs').glob('*.md')]:
    for target in re.findall(r'\]\(([^)]+)\)', file.read_text()):
        if '://' not in target and not target.startswith('#') and not (file.parent / target.split('#')[0]).exists():
            issues.append(f'{file.relative_to(root)}: missing link {target}')
requirements = (root / 'docs/REQUIREMENTS.md').read_text()
capabilities = (root / 'docs/FULL_FEATURE_MAP.md').read_text()
req_ids = re.findall(r'^\| ([A-Z]+\d+) \|', requirements, re.M)
cap_ids = re.findall(r'^\| (CAP-[A-Z]+\d+) \|', capabilities, re.M)
for label, values in [('requirements', req_ids), ('capabilities', cap_ids)]:
    if len(values) != len(set(values)):
        issues.append(f'Duplicate {label} IDs')
if set(req_ids) & set(cap_ids):
    issues.append('Catalog namespaces overlap')
subprocess.run(['git', 'diff', '--check'], cwd=root, check=True)
if issues:
    raise SystemExit('\n'.join(issues))
print('PASS: domain boundaries, application boundaries, local links, requirement IDs, whitespace')
