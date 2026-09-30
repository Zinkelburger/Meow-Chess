#!/usr/bin/env python3
"""Independently decode US Chess 2C using dbfread==2.0.7; not portal acceptance.

Field contracts transcribed from the US Chess 2C specification (September 2025
character-field correction), https://secure2.uschess.org/TD_Affil/fileformat.php.
The optional expected-event.json compares every result with the source event,
so mutually consistent but wrong output cannot pass on reciprocity alone.
"""
import argparse
import datetime
import json
from pathlib import Path
import struct
from dbfread import DBF

HEADER = [('H_FORMAT', 5), ('H_PROGRAM', 10), ('H_EVENT_ID', 12), ('H_NAME', 35),
          ('H_TOT_SECT', 2), ('H_BEG_DATE', 8), ('H_END_DATE', 8), ('H_AFF_ID', 8),
          ('H_CITY', 21), ('H_STATE', 2), ('H_ZIPCODE', 10), ('H_COUNTRY', 21),
          ('H_SENDCROS', 1), ('H_CTD_ID', 8), ('H_ATD_ID', 8), ('H_OTHER_TD', 255)]
SECTION = [('S_EVENT_ID', 12), ('S_SEC_NUM', 2), ('S_SEC_NAME', 30), ('S_R_SYSTEM', 1),
           ('S_TIMECTL', 40), ('S_CTD_ID', 8), ('S_ATD_ID', 8), ('S_TRN_TYPE', 1),
           ('S_TOT_RNDS', 2), ('S_LST_PAIR', 4), ('S_BEG_DATE', 8), ('S_END_DATE', 8),
           ('S_SCH_LVL', 1), ('S_GR_PRIX', 1), ('S_GP_PTS', 3), ('S_FIDE', 1)]
DETAIL = [('D_EVENT_ID', 12), ('D_SEC_NUM', 2), ('D_PAIR_NUM', 4), ('D_MEM_ID', 8),
          ('D_NAME', 30), ('D_STATE', 2), ('D_RATING', 4)]


def decode(folder, filename, fields):
    path = folder / filename
    table = DBF(str(path), encoding='ascii', load=True)
    contract = [(name, 'D' if name.endswith('_DATE') else 'C', width) for name, width in fields]
    assert [(f.name, f.type, f.length) for f in table.fields] == contract, filename
    raw = path.read_bytes()
    count, header_size, record_size = struct.unpack_from('<IHH', raw, 4)
    assert raw[0] == 3 and raw[-1] == 26, filename
    assert header_size == 32 + 32 * len(fields) + 1 and raw[header_size - 1] == 13
    assert record_size == 1 + sum(width for _, width in fields)
    assert len(raw) == header_size + count * record_size + 1
    assert count == len(table.records) > 0
    for index in range(count):
        offset = header_size + index * record_size
        assert raw[offset] == 32, 'Unexpected deleted row'
        offset += 1
        for name, kind, width in contract:
            value = raw[offset:offset + width]
            assert all(32 <= b <= 126 for b in value), (name, value)
            if kind == 'C' and name in {'H_TOT_SECT', 'S_SEC_NUM', 'S_TOT_RNDS', 'S_LST_PAIR', 'S_GP_PTS', 'D_SEC_NUM', 'D_PAIR_NUM', 'D_RATING'}:
                assert value == value.strip().ljust(width, b' '), (name, value)
            offset += width
    return table.records


def verify(folder):
    header = decode(folder, 'THEXPORT.DBF', HEADER)
    sections = decode(folder, 'TSEXPORT.DBF', SECTION)
    assert len(header) == 1 and header[0]['H_FORMAT'] == '2C'
    assert int(header[0]['H_TOT_SECT']) == len(sections)
    rounds = {int(row['S_TOT_RNDS']) for row in sections}
    assert len(rounds) == 1
    count = rounds.pop()
    assert 1 <= count <= 32
    details = decode(folder, 'TDEXPORT.DBF', DETAIL + [(f'D_RND{n:02}', 7) for n in range(1, count + 1)])
    by_section = {r['S_SEC_NUM']: r for r in sections}
    assert len(by_section) == len(sections)
    players = {(r['D_SEC_NUM'], r['D_PAIR_NUM']): r for r in details}
    assert len(players) == len(details)
    for row in sections:
        assert row['S_TRN_TYPE'] == 'S' and row['S_R_SYSTEM'] in 'RDQ'
        entries = [r for r in details if r['D_SEC_NUM'] == row['S_SEC_NUM']]
        assert len(entries) == int(row['S_LST_PAIR'])
        assert {int(r['D_PAIR_NUM']) for r in entries} == set(range(1, len(entries) + 1))
    reciprocal = {'W': 'L', 'L': 'W', 'D': 'D'}
    for row in details:
        section = by_section[row['D_SEC_NUM']]
        assert row['D_EVENT_ID'] == header[0]['H_EVENT_ID'] == section['S_EVENT_ID']
        assert len(row['D_MEM_ID']) == 8 and row['D_MEM_ID'].isdigit()
        for number in range(1, count + 1):
            field = f'D_RND{number:02}'
            code = row[field]
            assert code, (row, field)
            if code[0] in reciprocal:
                assert code[-1] in 'WB'
                assert code[1:-1] != row['D_PAIR_NUM'], 'Self opponent'
                opponent = players[(row['D_SEC_NUM'], code[1:-1])]
                color = 'B' if code[-1] == 'W' else 'W'
                assert opponent[field] == reciprocal[code[0]] + row['D_PAIR_NUM'] + color
            else:
                assert code[0] in 'XZFBHU' and code[1:] == '0'
    expected = folder / 'expected-event.json'
    if expected.exists():
        event = json.loads(expected.read_text(encoding='utf-8'))
        people = {p['id']: p for p in event['players']}
        assert header[0]['H_NAME'] == event['name']
        assert header[0]['H_CTD_ID'] == event['tdId']
        assert header[0]['H_AFF_ID'] == event['affiliateId']
        assert header[0]['H_BEG_DATE'] == header[0]['H_END_DATE'] == datetime.date.fromisoformat(event['date'])
        assert len(sections) == len(event['sections'])
        # Explicit outcome oracle; independent of Dart score/played getters.
        outcomes = {'whiteWin': ('W', 'L'), 'blackWin': ('L', 'W'), 'draw': ('D', 'D'),
                    'whiteForfeit': ('X', 'F'), 'blackForfeit': ('F', 'X'), 'doubleForfeit': ('F', 'F')}
        for index, section in enumerate(event['sections'], 1):
            numbers = {pid: str(i) for i, pid in enumerate(section['players'], 1)}
            exported = by_section[str(index)]
            assert exported['S_SEC_NAME'] == section['name']
            assert exported['S_TIMECTL'] == event['timeControl']
            assert int(exported['S_TOT_RNDS']) == len(section['rounds'])
            for pid, number in numbers.items():
                row = players[(str(index), number)]
                assert row['D_MEM_ID'] == people[pid]['memberId']
                assert row['D_NAME'] == people[pid]['name']
                assert row['D_RATING'] == str(people[pid]['rating'])
                for rnd in section['rounds']:
                    game = next((g for g in rnd['games'] if pid in (g['white'], g['black'])), None)
                    if game:
                        white = game['white'] == pid
                        code = outcomes[game['outcome']][0 if white else 1]
                        suffix = numbers[game['black'] if white else game['white']] + ('W' if white else 'B') if code in 'WDL' else '0'
                        value = code + suffix
                    else:
                        bye = next(b for b in rnd['byes'] if b['player'] == pid)
                        value = {0: 'U0', 1: 'H0', 2: 'B0'}[bye['points']]
                    assert row[f'D_RND{rnd["number"]:02}'] == value, (pid, rnd['number'], value)
        print('PASS: every exported ID, rating and result agrees with the source event.')
    print(f'PASS: independent 2C schema, padding and reciprocal results: {len(sections)} sections, {len(details)} entrants, {count} rounds.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    verify(parser.parse_args().package)
