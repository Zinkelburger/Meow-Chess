#!/usr/bin/env python3
"""Builds the browser version (docs/WEB.md) into build/web.

With --site, also replaces the copy served by the Chess Auto Prep website
(python/twic-position-finder/frontend/public/meow-chess in that repository),
which is how a new Meow-Chess feature reaches chessautoprep.com/meow-chess/.

    python3 scripts/build_web.py
    python3 scripts/build_web.py --site ../Chess-Auto-Prep
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_HREF = '/meow-chess/'
SITE_DIR = 'python/twic-position-finder/frontend/public/meow-chess'
# Cloudflare Pages refuses any single file of 25 MiB or more.
PAGES_FILE_LIMIT = 25 * 1024 * 1024

# SQLite compiled for package:sqlite3/wasm.dart. It must match the sqlite3
# version in pubspec.lock; update both together.
SQLITE_VERSION = '3.6.0'
SQLITE_WASM_URL = (
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    f'sqlite3-{SQLITE_VERSION}/sqlite3.wasm'
)
SQLITE_WASM_SHA256 = '13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def locked_sqlite_version():
    lock = (ROOT / 'pubspec.lock').read_text()
    return re.search(
        r'\n  sqlite3:\n(?:    .*\n)*?    version: "([^"]+)"', lock
    ).group(1)


def fetch_sqlite_wasm():
    if locked_sqlite_version() != SQLITE_VERSION:
        sys.exit(
            f'pubspec.lock has sqlite3 {locked_sqlite_version()}, but this '
            f'script pins sqlite3.wasm {SQLITE_VERSION}. Update SQLITE_VERSION '
            'and SQLITE_WASM_SHA256 together.'
        )
    target = ROOT / 'web/sqlite3.wasm'
    if target.exists() and sha256(target.read_bytes()) == SQLITE_WASM_SHA256:
        return
    with urllib.request.urlopen(SQLITE_WASM_URL) as response:
        data = response.read()
    if sha256(data) != SQLITE_WASM_SHA256:
        sys.exit(f'{SQLITE_WASM_URL} does not match the pinned checksum.')
    target.write_bytes(data)


def git(*args):
    return subprocess.run(
        ['git', *args], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()


def build():
    fetch_sqlite_wasm()
    subprocess.run(
        [
            'flutter', 'build', 'web',
            '--target', 'lib/main_web.dart',
            '--release',
            '--base-href', BASE_HREF,
            # CanvasKit is served with the app instead of from Google's CDN.
            '--no-web-resources-cdn',
            '--no-wasm-dry-run',
        ],
        cwd=ROOT,
        check=True,
    )
    output = ROOT / 'build/web'
    # Debug symbols for CanvasKit, which no visitor downloads.
    for symbols in output.rglob('*.symbols'):
        symbols.unlink()
    dirty = bool(git('status', '--porcelain', '--untracked-files=no'))
    (output / 'meow-build.json').write_text(
        json.dumps(
            {
                'commit': git('rev-parse', 'HEAD'),
                'describe': git('describe', '--tags', '--always'),
                'uncommittedChanges': dirty,
                'built': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            },
            indent=2,
        )
        + '\n'
    )
    for path in output.rglob('*'):
        if path.is_file() and path.stat().st_size >= PAGES_FILE_LIMIT:
            sys.exit(f'{path.relative_to(output)} exceeds the Pages file limit.')
    return output, dirty


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument(
        '--site',
        type=Path,
        help='the Chess-Auto-Prep checkout whose copy to replace',
    )
    args = parser.parse_args()
    output, dirty = build()
    if args.site is None:
        print(f'Built {output}')
        return
    target = args.site.resolve() / SITE_DIR
    if not target.parent.is_dir():
        sys.exit(f'{target.parent} does not exist; is --site a Chess-Auto-Prep checkout?')
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(output, target)
    print(f'Copied {output} to {target}')
    if dirty:
        print('Warning: built with uncommitted changes; meow-build.json says so.')


if __name__ == '__main__':
    main()
