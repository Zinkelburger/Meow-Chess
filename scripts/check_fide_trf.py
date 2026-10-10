"""Replays Meow's FIDE Swiss events through BBP Pairings' own checker.

Builds the BBP Pairings command-line tool from the vendored source, has the
random FIDE event test write each finished event as TRF26, then runs
`bbpPairings --dutch <file> -c` on every file. The checker re-pairs each
round from the file and reports any round whose recorded pairings differ;
a clean run means the TRF Meow writes describes exactly what the engine
paired from (ranks, colours, byes, forfeits, absences).
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'third_party' / 'bbpPairings'


def build(out: Path) -> Path:
    compiler = shutil.which('g++') or shutil.which('clang++')
    if compiler is None:
        sys.exit('A C++20 compiler (g++ or clang++) is required.')
    exe = out / 'bbpPairings'
    sources = sorted(str(p) for p in (SOURCE / 'src').rglob('*.cpp'))
    subprocess.run([compiler, '-std=c++20', '-O2', '-Wno-deprecated-declarations',
                    f'-I{SOURCE / "src"}', *sources, '-o', str(exe)], check=True)
    return exe


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        exe = build(work)
        dump = work / 'trf'
        dump.mkdir()
        flutter = shutil.which('flutter') or 'flutter'
        subprocess.run([flutter, 'test', 'test/domain/fide_random_test.dart'], cwd=ROOT,
                       env={**os.environ, 'MEOW_TRF_DUMP': str(dump)}, check=True)
        files = sorted(dump.glob('*.trf'))
        if not files:
            print('FAIL: the test wrote no TRF files')
            return 1
        bad = 0
        for f in files:
            result = subprocess.run([str(exe), '--dutch', str(f), '-c'],
                                    capture_output=True, text=True)
            text = result.stdout + result.stderr
            if result.returncode != 0 or 'Checker pairings' in text:
                bad += 1
                print(f'FAIL {f.name} (exit {result.returncode})')
                print(text)
        if bad:
            return 1
        print(f'PASS: {len(files)} FIDE events replay identically through the BBP Pairings checker')
        return 0


if __name__ == '__main__':
    sys.exit(main())
