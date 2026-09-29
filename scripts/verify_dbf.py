#!/usr/bin/env python3
"""Independently decode a synthetic 2C fixture using dbfread (pip: dbfread==2.0.7).

This checks serialization and reciprocal results, not federation acceptance.
"""
import argparse
from pathlib import Path
from dbfread import DBF

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('package', type=Path)
args = parser.parse_args()
header = list(DBF(str(args.package / 'THEXPORT.DBF'), encoding='ascii'))
sections = list(DBF(str(args.package / 'TSEXPORT.DBF'), encoding='ascii'))
details = list(DBF(str(args.package / 'TDEXPORT.DBF'), encoding='ascii'))
assert len(header) == 1 and header[0]['H_FORMAT'] == '2C'
assert int(header[0]['H_TOT_SECT']) == len(sections)
by_section = {r['S_SEC_NUM']: r for r in sections}
players = {(r['D_SEC_NUM'], r['D_PAIR_NUM']): r for r in details}
assert len(players) == len(details)
reciprocal = {'W': 'L', 'L': 'W', 'D': 'D'}
for row in details:
    section = by_section[row['D_SEC_NUM']]
    assert row['D_EVENT_ID'] == header[0]['H_EVENT_ID'] == section['S_EVENT_ID']
    assert len(row['D_MEM_ID']) == 8
    for number in range(1, int(section['S_TOT_RNDS']) + 1):
        field = f'D_RND{number:02}'
        code = row[field]
        if code[0] in reciprocal:
            assert code[-1] in 'WB'
            opponent = players[(row['D_SEC_NUM'], code[1:-1])]
            opposite_color = 'B' if code[-1] == 'W' else 'W'
            assert opponent[field] == reciprocal[code[0]] + row['D_PAIR_NUM'] + opposite_color
        else:
            assert code[0] in 'XZFBHU' and code[1:] == '0'
print(f'PASS: dbfread decoded {len(header)} event, {len(sections)} sections, '
      f'{len(details)} entrants; event references and reciprocal results agree.')
