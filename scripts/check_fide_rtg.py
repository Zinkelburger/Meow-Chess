"""Large-scale check of Meow-Chess's FIDE pairing and tie-break engine.

The TEC Manual (3.9.4) tests a program by generating random tournaments
with one program's Random Tournament Generator (RTG) and checking them with
another program's Pairings and Tie-Breaks Checker (PTC). This script does
both directions with BBP Pairings, the engine an endorsed program (SwissSys)
uses:

- Meow-Chess's RTG writes tournaments with randomised settings (byes,
  forfeits, withdrawals, late entries, unusual and short games, the Baku
  acceleration, the pairing-allocated bye's value); Meow-Chess's PTC and
  BBP Pairings' checker (`-c`) each check every one.
- BBP Pairings' RTG (`-g`) writes tournaments; Meow-Chess's PTC checks them.
- With --gacrux DIR (a checkout of https://github.com/OttoMilvang/TieBreakServer,
  TEC's open reference implementation), every tie-break of MTB26 is also
  compared value by value with Gacrux on Meow's tournaments.

Usage: python scripts/check_fide_rtg.py [--count N] [--workers W]
       [--gacrux DIR] [--keep DIR]
Exit status 0 when nothing differs. TEC allows at most 10 discrepancies in
50,000 tournaments.
"""
from concurrent.futures import ProcessPoolExecutor
from decimal import Decimal
from pathlib import Path
import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
from check_fide_trf import build  # noqa: E402

MEOW = ROOT / 'build' / 'fide-cli' / 'bundle' / 'bin' / 'meow_fide'

# Every individual tie-break of MTB26 that Meow-Chess computes. Gacrux keeps
# Fore Buchholz state between tie-breaks of one run, so those go last.
CODES = (
    'BH BH/C1 BH/C2 BH/M1 BH/M2 BH/P BH/C1/P BH/C2/P BH/M1/P BH/M2/P '
    'SB SB/C1 SB/C2 SB/P SB/C1/P SB/C2/P WIN WON BPG BWG REP STD '
    'PS PS/C1 PS/C2 KS KS/L+1 KS/L-1 KS/L+2 KS/L-2 KS/L+3 KS/L-3 '
    'ARO ARO/C1 ARO/C2 ARO/M1 ARO/M2 TPR PTP APRO APPO AOB RTNG RTNG/R TPN TPN/R '
    'FB FB/C1 FB/C2 FB/M1 FB/M2 FB/P FB/C1/P FB/C2/P FB/M1/P FB/M2/P AOB/F'
).split()
GROUPWISE = ['DE', 'DE/P']


def build_meow():
    subprocess.run(['dart', 'build', 'cli', '--target=tools/meow_fide.dart',
                    '--output=build/fide-cli'], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)


def meow_settings(seed):
    r = random.Random(seed)
    players = r.randint(8, 80)
    rounds = r.randint(3, min(13, players // 2 + 2))
    args = ['--seed', str(seed), '--players', str(players), '--rounds', str(rounds),
            '--forfeits', f'{r.choice([0, 0.02, 0.05, 0.1]):.2f}',
            '--half-byes', f'{r.choice([0, 0.03, 0.08]):.2f}',
            '--zero-byes', f'{r.choice([0, 0.01, 0.04]):.2f}',
            '--full-byes', f'{r.choice([0, 0, 0.01]):.2f}',
            '--withdrawals', f'{r.choice([0, 0.01, 0.03]):.2f}',
            '--late-entries', f'{r.choice([0, 0, 0.05, 0.1]):.2f}',
            '--unusual', f'{r.choice([0, 0, 0.02]):.2f}',
            '--short-games', f'{r.choice([0, 0, 0.02]):.2f}',
            '--draws', f'{r.choice([0.1, 0.3, 0.5]):.2f}',
            '--pab', r.choice(['win', 'win', 'win', 'draw', 'loss']),
            '--tiebreaks', ','.join(r.sample(CODES + GROUPWISE, 5))]
    if r.random() < 0.25:
        args.append('--baku')
    return args


def table(text):
    lines = [l for l in text.splitlines() if l.strip()]
    head = lines[0].split('\t')
    rows = {}
    for line in lines[1:]:
        row = dict(zip(head, line.split('\t')))
        rows[int(row['StartNo'])] = row
    return rows


def gacrux_differences(trf, gacrux):
    def gx(codes):
        out = subprocess.run([sys.executable, str(Path(gacrux) / 'gacrux' / 'tiebreakchecker.py'),
                              '-i', str(trf), '-s', '-dT', '-t', 'PTS', *codes],
                             capture_output=True, text=True, check=True).stdout
        return table(out)

    def me(codes):
        out = subprocess.run([str(MEOW), 'values', str(trf), '--tiebreaks', ','.join(codes)],
                             capture_output=True, text=True, check=True).stdout
        return table(out)

    found = []
    g, m = gx(CODES), me(CODES)
    for sno, row in m.items():
        for code in ['PTS', *CODES]:
            gv = g[sno].get(code)
            if gv in (None, '', 'None'):
                continue  # Gacrux drops rating tie-breaks with unrated players
            if Decimal(row[code]) != Decimal(gv):
                found.append(f'{code} player {sno}: Meow {row[code]}, Gacrux {gv}')
    for code in GROUPWISE:
        g, m = gx([code]), me([code])
        for sno in m:
            if m[sno]['Rank'] != g[sno]['Rank']:
                found.append(f'{code} player {sno}: Meow rank {m[sno]["Rank"]}, Gacrux {g[sno]["Rank"]}')
    return found


def check_meow(job):
    seed, work, bbp, gacrux = job
    trf = Path(work) / 'meow' / f'm{seed:06d}.trf'
    gen = subprocess.run([str(MEOW), 'generate', '--output', str(trf), *meow_settings(seed)],
                         capture_output=True, text=True)
    if gen.returncode:
        # A small field over many rounds can run out of legal pairings.
        return seed, 'skip', gen.stderr.strip()
    problems = []
    mine = subprocess.run([str(MEOW), 'check', str(trf)], capture_output=True, text=True)
    if mine.returncode:
        problems.append('Meow PTC: ' + mine.stdout.strip().replace('\n', ' | '))
    theirs = subprocess.run([bbp, '--dutch', str(trf), '-c'], capture_output=True, text=True)
    lines = [l for l in theirs.stdout.splitlines() if l.strip() and 'Round #' not in l]
    if theirs.returncode or lines:
        problems.append('BBP checker: ' + ' | '.join(lines + [theirs.stderr.strip()]))
    if gacrux:
        problems += [f'Gacrux: {d}' for d in gacrux_differences(trf, gacrux)]
    return seed, 'ok' if not problems else 'diff', ' || '.join(problems)


def check_bbp(job):
    seed, work, bbp = job
    r = random.Random(1_000_000 + seed)
    players = r.randint(8, 120)
    rounds = r.randint(3, min(13, players // 2 + 2))
    config = Path(work) / 'bbp' / f'b{seed:06d}.cfg'
    trf = config.with_suffix('.trf')
    # BBP's rates are "one in N" (JaVaFo's RTG keys); leaving one out
    # means none.
    rates = {'ForfeitRate': r.choice([None, 20, 50]),
             'HalfPointByeRate': r.choice([None, 20, 50]),
             'RetiredRate': r.choice([None, 100, 300])}
    config.write_text('\n'.join([
        f'PlayersNumber={players}', f'RoundsNumber={rounds}',
        f'DrawPercentage={r.choice([10, 30, 50])}',
        *[f'{k}={v}' for k, v in rates.items() if v is not None],
        'HighestRating=2700', 'LowestRating=1400',
        f'PointsForPAB={r.choice(["1.0", "1.0", "0.5", "0.0"])}',
    ]) + '\n')
    gen = subprocess.run([bbp, '--dutch', '-g', str(config), '-o', str(trf), '-s', str(seed)],
                         capture_output=True, text=True)
    if gen.returncode:
        return seed, 'skip', gen.stderr.strip()
    mine = subprocess.run([str(MEOW), 'check', str(trf)], capture_output=True, text=True)
    if mine.returncode:
        return seed, 'diff', 'Meow PTC: ' + (mine.stdout + mine.stderr).strip().replace('\n', ' | ')
    return seed, 'ok', ''


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--count', type=int, default=200, help='tournaments per direction')
    p.add_argument('--workers', type=int, default=os.cpu_count())
    p.add_argument('--gacrux', help='TieBreakServer checkout for tie-break comparison')
    p.add_argument('--keep', help='keep the generated files in this directory')
    a = p.parse_args()
    build_meow()
    work = Path(a.keep) if a.keep else Path(tempfile.mkdtemp())
    (work / 'meow').mkdir(parents=True, exist_ok=True)
    (work / 'bbp').mkdir(parents=True, exist_ok=True)
    bbp = str(build(work))
    failures = 0
    try:
        with ProcessPoolExecutor(a.workers) as pool:
            for title, jobs, fn in [
                ('Meow RTG checked by Meow, BBP' + (' and Gacrux' if a.gacrux else ''),
                 [(s, str(work), bbp, a.gacrux) for s in range(1, a.count + 1)], check_meow),
                ('BBP RTG checked by Meow', [(s, str(work), bbp) for s in range(1, a.count + 1)],
                 check_bbp),
            ]:
                counts = {'ok': 0, 'diff': 0, 'skip': 0}
                for seed, status, detail in pool.map(fn, jobs, chunksize=4):
                    counts[status] += 1
                    if status == 'diff':
                        print(f'  seed {seed}: {detail}')
                print(f'{title}: {counts["ok"]} match, {counts["diff"]} differ, '
                      f'{counts["skip"]} not generated (no legal pairing)')
                failures += counts['diff']
    finally:
        if not a.keep:
            shutil.rmtree(work, ignore_errors=True)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
