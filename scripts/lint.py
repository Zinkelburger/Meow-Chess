#!/usr/bin/env python3
"""Small architecture and documentation gates, independent of Flutter analysis."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
def architecture_issues(root):
    """Resolve Dart imports/exports, including nested files and package URIs."""
    issues = []
    for layer, forbidden in [('domain', {'application', 'infrastructure', 'ui'}),
                             ('application', {'infrastructure', 'ui'})]:
        for file in (root / 'lib' / layer).rglob('*.dart'):
            directives = re.finditer(r"^\s*(?:import|export)\s+['\"]([^'\"]+)['\"]",
                                     file.read_text(encoding='utf-8'), re.M)
            for directive in directives:
                target = directive[1]
                if target.startswith('package:meow_chess/'):
                    resolved = (root / 'lib' / target.removeprefix('package:meow_chess/')).resolve()
                elif ':' not in target:
                    resolved = (file.parent / target).resolve()
                else:
                    resolved = None
                blocked = layer == 'domain' and (target.startswith('package:flutter/') or target == 'dart:io')
                if resolved is not None:
                    blocked |= any(resolved.is_relative_to(root / 'lib' / name) for name in forbidden)
                if blocked:
                    issues.append(f'{file.relative_to(root)}: {layer} depends on forbidden {target}')
    return issues


def main():
    issues = architecture_issues(root)
    for file in [root / 'README.md', *(root / 'docs').glob('*.md')]:
        for target in re.findall(r'\]\(([^)]+)\)', file.read_text(encoding='utf-8')):
            if '://' not in target and not target.startswith('#') and not (file.parent / target.split('#')[0]).exists():
                issues.append(f'{file.relative_to(root)}: missing link {target}')
    requirements = (root / 'docs/REQUIREMENTS.md').read_text(encoding='utf-8')
    capabilities = (root / 'docs/FULL_FEATURE_MAP.md').read_text(encoding='utf-8')
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


if __name__ == "__main__":
    main()
