#!/usr/bin/env python3
"""Small architecture and documentation gates, independent of Flutter analysis."""
from pathlib import Path
import re
import os
import subprocess
import xml.etree.ElementTree as ElementTree

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


def release_issues(root, ref=''):
    pubspec = re.search(r'^version:\s*([^+\s]+)', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    dart = re.search(r"const appVersion = '([^']+)';", (root / 'lib/version.dart').read_text(encoding='utf-8'))
    if pubspec is None or dart is None:
        return ['Could not read the package/export version']
    version = pubspec[1]
    issues = []
    if dart[1] != version:
        issues.append(f'Package version {version} does not match appVersion {dart[1]}')
    if len('MEOW ' + version) > 10:
        issues.append('The release version exceeds the ten-character DBF H_PROGRAM field')
    if ref.startswith('refs/tags/') and ref != 'refs/tags/v' + version:
        issues.append(f'Release tag {ref} does not match package version {version}')
    metainfo = root / 'packaging/flatpak/org.meowchess.meow_chess.metainfo.xml'
    try:
        # AppStream lists releases newest first; software centers show that one.
        newest = ElementTree.parse(metainfo).getroot().find('releases/release')
    except (OSError, ElementTree.ParseError):
        newest = None
    if newest is None:
        issues.append(f'Could not read the newest release in {metainfo.relative_to(root)}')
    elif newest.get('version') != version:
        issues.append(f'Newest metainfo release {newest.get("version")} does not match package version {version}')
    return issues


# Copied verbatim from elsewhere (a font license, a saved web page) or written
# by a tool, so their whitespace is not ours to fix.
WHITESPACE_EXEMPT = [
    ':(exclude,glob)assets/fonts/LICENSE-*',
    ':(exclude,glob)test/fixtures/**/*.html',
    ':(exclude,glob).impeccable/**',
]


def whitespace_issues(root):
    """Whitespace errors in every tracked file, not only uncommitted edits.

    A plain `git diff --check` compares the working tree to the index, which on
    a fresh CI checkout is nothing at all; diffing against the empty tree checks
    the whole working tree and index instead.
    """
    empty_tree = subprocess.run(
        ['git', 'hash-object', '-t', 'tree', '--stdin'], cwd=root, input='',
        capture_output=True, text=True, check=True).stdout.strip()
    issues = []
    for args in [[empty_tree], ['--cached', empty_tree]]:
        result = subprocess.run(
            ['git', 'diff', '--check', *args, '--', '.', *WHITESPACE_EXEMPT],
            cwd=root, capture_output=True, text=True)
        if result.returncode != 0:
            issues.append(result.stdout.strip() or result.stderr.strip())
    return issues


def main():
    issues = architecture_issues(root) + release_issues(root, os.environ.get('GITHUB_REF', ''))
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
    issues += whitespace_issues(root)
    if issues:
        raise SystemExit('\n'.join(issues))
    print('PASS: domain boundaries, application boundaries, local links, requirement IDs, release version, whitespace')


if __name__ == "__main__":
    main()
