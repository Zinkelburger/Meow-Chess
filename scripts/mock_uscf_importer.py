#!/usr/bin/env python3
"""Offline stand-in for the US Chess (MUIR) 2C importer, based on accepted files.

The baseline is empirical: the seven SwissSys packages in test/fixtures/boylston
were uploaded to MUIR and accepted, so everything they contain is accepted here,
including all-C descriptors (dates as C(8)), a 26 or 126 year byte, nonzero
reserved header bytes, blank event IDs, S_SCH_LVL, S_GP_PTS and D_STATE, loose
time-control spellings, round-robin type R, SwissSys double-game codes, and X0/F0/Z0
cells with no opponent. Their uscf.json files hold what MUIR rated from them.

Checks stay strict where MUIR clearly is strict, or where the damage is
unambiguous: exact file names, the field list and widths, header/record lengths
consistent with the file size, the EOF byte, reciprocal results, pairing numbers
1..S_LST_PAIR, consistent section numbers, member-ID shape, real dates and ASCII.
Some extra strictness is defensive and not proven: field order, colors on
played games, U0 in padding columns, and S_R_SYSTEM limited to R/D/Q. This is
a stress test of our output, NOT a replica or certification of MUIR.

Schema: https://secure2.uschess.org/TD_Affil/fileformat.php. No app imports,
no third-party DBF reader, no network. Standard library only.
"""
import argparse
from datetime import date
import json
from pathlib import Path
import re
import struct
import sys

DATES = 'CD'  # MUIR accepted C(8) dates (SwissSys); the published spec says D(8).
# (name, allowed descriptor types, width). Intentionally independent of the Dart writer.
HEADER = [('H_FORMAT', 'C', 5), ('H_PROGRAM', 'C', 10), ('H_EVENT_ID', 'C', 12),
          ('H_NAME', 'C', 35), ('H_TOT_SECT', 'C', 2), ('H_BEG_DATE', DATES, 8),
          ('H_END_DATE', DATES, 8), ('H_AFF_ID', 'C', 8), ('H_CITY', 'C', 21),
          ('H_STATE', 'C', 2), ('H_ZIPCODE', 'C', 10), ('H_COUNTRY', 'C', 21),
          ('H_SENDCROS', 'C', 1), ('H_CTD_ID', 'C', 8), ('H_ATD_ID', 'C', 8),
          ('H_OTHER_TD', 'C', 255)]
SECTION = [('S_EVENT_ID', 'C', 12), ('S_SEC_NUM', 'C', 2), ('S_SEC_NAME', 'C', 30),
           ('S_R_SYSTEM', 'C', 1), ('S_TIMECTL', 'C', 40), ('S_CTD_ID', 'C', 8),
           ('S_ATD_ID', 'C', 8), ('S_TRN_TYPE', 'C', 1), ('S_TOT_RNDS', 'C', 2),
           ('S_LST_PAIR', 'C', 4), ('S_BEG_DATE', DATES, 8), ('S_END_DATE', DATES, 8),
           ('S_SCH_LVL', 'C', 1), ('S_GR_PRIX', 'C', 1), ('S_GP_PTS', 'C', 3),
           ('S_FIDE', 'C', 1)]
DETAIL = [('D_EVENT_ID', 'C', 12), ('D_SEC_NUM', 'C', 2), ('D_PAIR_NUM', 'C', 4),
          ('D_MEM_ID', 'C', 8), ('D_NAME', 'C', 30), ('D_STATE', 'C', 2),
          ('D_RATING', 'C', 4)]
DATE_FIELDS = {name for name, kind, _ in HEADER + SECTION if kind == DATES}
TAB_OK = {'D_NAME'}  # Accepted: a SwissSys name with a TAB after the comma.

CELL = re.compile(r'([WDLXFZBHU$#%])(0|[1-9][0-9]{0,3})([WB]?)')
PLAYED = set('WDL$#%')        # needs an opponent and a color
NO_OPPONENT = set('BHUZ')     # opponent must be 0; X/F may name one or not
DOUBLE_ONLY = set('$#%')
RECIPROCAL = {False: {'W': 'L', 'L': 'W', 'D': 'D', 'X': 'F', 'F': 'X'},
              True: {'$': 'L', 'L': '$', '#': 'D', 'D': '#', 'W': 'W', '%': '%', 'X': 'F', 'F': 'X'}}
SINGLE_POINTS = {'W': 1, 'D': .5, 'L': 0, 'X': 1, 'F': 0, 'B': 1, 'H': .5, 'U': 0}
# SwissSys double-game codes -> the two rated legs (leg order is not recorded).
# `results` keep the cells as written; `legs` are what we expect US Chess to rate.
LEGS = {'$': 'WW', '#': 'WD', 'W': 'WL', '%': 'DD', 'D': 'DL', 'L': 'LL',
        'X': 'XX', 'F': 'FF', 'B': 'BB', 'H': 'HH', 'U': 'UU'}


class ImportFailure(ValueError):
    pass


def require(condition, where, message):
    if not condition:
        raise ImportFailure(f'{where}: {message}')


def number(value, where, low, high):
    require(re.fullmatch(r'0|[1-9][0-9]*', value), where,
            'expected canonical left-justified decimal')
    result = int(value)
    require(low <= result <= high, where, f'outside {low}..{high}')
    return result


def member(value, where, optional=False, placeholder=False):
    """Eight digits. Blank (optional fields) and 00000000 (players) are 'unassigned'."""
    if (optional or placeholder) and value == '':
        return False
    require(re.fullmatch(r'[0-9]{8}', value) and (placeholder or value != '00000000'),
            where, 'expected eight-digit non-placeholder ID')
    return value != '00000000'


def calendar(value, where):
    require(re.fullmatch(r'[0-9]{8}', value), where, 'expected YYYYMMDD')
    try:
        return date(int(value[:4]), int(value[4:6]), int(value[6:]))
    except ValueError as error:
        raise ImportFailure(f'{where}: invalid calendar date') from error


def time_control(value):
    """Loose parse of the spellings MUIR accepted -> (canonical, total minutes, category)."""
    text = re.sub(r'\s+', '', value).upper()
    bonus = r'(?:[;,]?(D|\+)/?(\d+))?'
    m = re.fullmatch(r'G/?(\d+)' + bonus, text)
    if m:
        controls, kind, extra = [int(m[1])], m[2], int(m[3] or 0)
        canonical = f'G/{m[1]}'
    else:
        # One or more timed controls (40/120,20/60), then an optional SD.
        m = re.fullmatch(r'(\d+/\d+(?:[,;]\d+/\d+)*)(?:[,;]SD/?(\d+))?' + bonus, text)
        if not m:
            return None
        periods = re.findall(r'(\d+)/(\d+)', m[1])
        controls = [int(minutes) for _, minutes in periods] + ([int(m[2])] if m[2] else [])
        kind, extra = m[3], int(m[4] or 0)
        canonical = ','.join(f'{moves}/{minutes}' for moves, minutes in periods) + (f',SD/{m[2]}' if m[2] else '')
    if kind:
        canonical += f";{'d' if kind == 'D' else '+'}{extra}"
    total = sum(controls) + extra  # rule 5C: minutes + delay/increment seconds
    if total > 65:
        category = 'R'
    elif total >= 30:
        category = 'D'
    elif total > 10:
        category = 'Q' if controls[0] >= 5 else None
    else:
        category = 'B' if total >= 5 and controls[0] >= 3 else None
    return canonical, total, category


def read_table(folder, filename, schema, rounds_after=None):
    """Read one DBF. `rounds_after` names the last fixed field before D_RNDnn columns."""
    path = folder / filename
    # Case-sensitive filename check even on Windows. Sidecars are ignored.
    require(filename in {p.name for p in folder.iterdir()}, filename, 'missing file with exact name')
    raw = path.read_bytes()
    require(len(raw) >= 33, filename, 'truncated header')
    require(raw[0] == 3, filename, 'expected dBASE III without memo (version 0x03)')
    # Year byte: SwissSys writes 26, dBASE says 126 for 2026; any value is accepted.
    try:
        date(2000 + raw[1] % 100, raw[2], raw[3])
    except ValueError as error:
        raise ImportFailure(f'{filename}: invalid DBF update date') from error
    count, header, size = struct.unpack_from('<IHH', raw, 4)
    # Bytes 12..31 are reserved; SwissSys leaves nonzero garbage at 16..19 and MUIR accepted it.
    require(header >= 65 and (header - 33) % 32 == 0, filename, 'wrong header length / field count')
    require(header <= len(raw) and raw[header - 1] == 13, filename, 'missing header terminator')
    fields = (header - 33) // 32
    if rounds_after is None:
        require(fields == len(schema), filename, 'wrong header length / field count')
        layout = list(schema)
    else:
        extra = fields - len(schema)
        require(extra >= 1, filename, 'wrong header length / field count (no D_RNDnn columns)')
        layout = list(schema) + [(f'D_RND{n:02}', 'C', 7) for n in range(1, extra + 1)]
    expected_size = 1 + sum(width for _, _, width in layout)
    require(size == expected_size, filename, 'wrong record length')
    require(count > 0 and len(raw) == header + count * size + 1,
            filename, 'record count / file length mismatch')
    require(raw[-1] == 26, filename, 'missing EOF marker 0x1A')
    for index, (name, kinds, width) in enumerate(layout):
        at = 32 + index * 32
        ok = (raw[at:at + 11] == name.encode('ascii').ljust(11, b'\0') and chr(raw[at + 11]) in kinds
              and raw[at + 16] == width and raw[at + 17] == 0)
        require(ok, f'{filename}.{name}', 'descriptor mismatch (order, name, type or width)')
    rows = []
    for index in range(count):
        at = header + index * size
        where = f'{filename} record {index + 1}'
        require(raw[at] == 32, where, 'deleted or invalid record marker')
        at += 1
        row = {}
        for name, _, width in layout:
            cell = raw[at:at + width]
            require(all(32 <= b <= 126 or (b == 9 and name in TAB_OK) for b in cell),
                    f'{where}.{name}', 'non-ASCII or control byte')
            value = cell.decode('ascii').rstrip(' ')
            require(not value.startswith(' '), f'{where}.{name}', 'leading spaces / right justification')
            if name in DATE_FIELDS:
                calendar(value, f'{where}.{name}')
            row[name] = value
            at += width
        rows.append(row)
    return rows, len(layout) - len(schema)


def import_package(folder):
    folder = Path(folder)
    warnings = []
    headers, _ = read_table(folder, 'THEXPORT.DBF', HEADER)
    require(len(headers) == 1, 'THEXPORT.DBF', 'expected exactly one event')
    h = headers[0]
    require(h['H_FORMAT'] == '2C', 'H_FORMAT', 'unsupported format')
    for field in ('H_PROGRAM', 'H_NAME', 'H_CITY'):
        require(h[field], field, 'required value is empty')
    require(re.fullmatch(r'A[0-9]{7}', h['H_AFF_ID']), 'H_AFF_ID', 'invalid affiliate')
    member(h['H_CTD_ID'], 'H_CTD_ID')
    member(h['H_ATD_ID'], 'H_ATD_ID', optional=True)
    others = [v.strip() for v in h['H_OTHER_TD'].split(',')] if h['H_OTHER_TD'] else []
    for value in others:
        member(value, 'H_OTHER_TD')
    require(h['H_COUNTRY'] == 'USA' and re.fullmatch(r'[A-Z]{2}', h['H_STATE']),
            'H_COUNTRY/H_STATE', 'unsupported location')
    require(re.fullmatch(r'[0-9]{5}(-[0-9]{4})?', h['H_ZIPCODE']), 'H_ZIPCODE', 'invalid ZIP')
    require(h['H_SENDCROS'] in ('N', 'A', 'T'), 'H_SENDCROS', 'invalid code')
    require(h['H_BEG_DATE'] <= h['H_END_DATE'], 'H_END_DATE', 'date precedes start')

    sections, _ = read_table(folder, 'TSEXPORT.DBF', SECTION)
    require(number(h['H_TOT_SECT'], 'H_TOT_SECT', 1, 99) == len(sections),
            'H_TOT_SECT', 'section count mismatch')
    section_map = {}
    for index, s in enumerate(sections, 1):
        where = f'section {index}'
        require(s['S_SEC_NUM'] == str(index), where, 'sections must be numbered in order from 1')
        require(s['S_EVENT_ID'] == h['H_EVENT_ID'], where, 'event ID mismatch')
        require(s['S_SEC_NAME'] and s['S_TIMECTL'], where, 'empty name / time control')
        parsed = time_control(s['S_TIMECTL'])
        require(parsed is not None, where + '.S_TIMECTL', f"unrecognized time control {s['S_TIMECTL']!r}")
        require(s['S_TRN_TYPE'] in ('S', 'R', '2'), where, 'unsupported pairing type (expected S, R or 2)')
        require(s['S_R_SYSTEM'] in ('R', 'D', 'Q'), where, 'unsupported rating system')
        if parsed[2] != s['S_R_SYSTEM']:
            warnings.append(f"{where}: S_R_SYSTEM {s['S_R_SYSTEM']} but {s['S_TIMECTL']!r} rates as "
                            f'{parsed[2]} (MUIR derives the category from the time control)')
        require(s['S_SCH_LVL'] in ('', 'N', 'S', 'P', 'J'), where, 'invalid classification')
        require(s['S_GR_PRIX'] == 'N' and s['S_GP_PTS'] in ('', '0') and s['S_FIDE'] == 'N',
                where, 'mock supports non-GP, non-FIDE only')
        require(h['H_BEG_DATE'] <= s['S_BEG_DATE'] <= s['S_END_DATE'] <= h['H_END_DATE'],
                where, 'section dates outside event')
        member(s['S_CTD_ID'], where + '.S_CTD_ID', optional=True)
        member(s['S_ATD_ID'], where + '.S_ATD_ID', optional=True)
        number(s['S_TOT_RNDS'], where + '.S_TOT_RNDS', 1, 32)
        section_map[str(index)] = (s, parsed)

    maximum = max(int(s['S_TOT_RNDS']) for s, _ in section_map.values())
    details, columns = read_table(folder, 'TDEXPORT.DBF', DETAIL, rounds_after='D_RATING')
    require(columns >= maximum, 'TDEXPORT.DBF',
            f'{columns} D_RNDnn columns but S_TOT_RNDS {maximum} (field count)')
    players = {}
    for row in details:
        sec, pair = row['D_SEC_NUM'], row['D_PAIR_NUM']
        where = f'section {sec}, player {pair}'
        require(sec in section_map, where, 'unknown section')
        require(row['D_EVENT_ID'] == h['H_EVENT_ID'], where, 'event ID mismatch')
        number(pair, where + '.D_PAIR_NUM', 1, 9999)
        require((sec, pair) not in players, where, 'duplicate pairing number')
        if not member(row['D_MEM_ID'], where + '.D_MEM_ID', placeholder=True):
            warnings.append(f'{where}: no member ID (must be resolved in MUIR)')
        require(row['D_NAME'], where, 'empty player name')
        require(row['D_STATE'] == '' or re.fullmatch(r'[A-Z]{2}', row['D_STATE']), where, 'invalid player state')
        number(row['D_RATING'], where + '.D_RATING', 0, 4000)
        players[sec, pair] = row

    imported = []
    for sec, (section, parsed) in section_map.items():
        rows = sorted((r for r in details if r['D_SEC_NUM'] == sec), key=lambda r: int(r['D_PAIR_NUM']))
        count = number(section['S_LST_PAIR'], f'section {sec}.S_LST_PAIR', 2, 9999)
        require([r['D_PAIR_NUM'] for r in rows] == [str(n) for n in range(1, count + 1)],
                f'section {sec}', 'pairing numbers / player count mismatch')
        ids = [r['D_MEM_ID'] for r in rows if r['D_MEM_ID'] not in ('', '00000000')]
        require(len(set(ids)) == len(ids), f'section {sec}', 'duplicate member ID')
        rounds = int(section['S_TOT_RNDS'])
        cells = {}
        for row in rows:
            for n in range(1, columns + 1):
                cell = row[f'D_RND{n:02}']
                where = f'section {sec}, player {row["D_PAIR_NUM"]}, round {n}'
                if n > rounds:
                    # Padding must never become extra rounds or byes.
                    require(cell == 'U0', where, 'unused round must be U0')
                    continue
                match = CELL.fullmatch(cell)
                require(match, where, f'invalid result cell {cell!r}')
                code, opponent, color = match.groups()
                if code in PLAYED:
                    require(opponent != '0' and color, where, f'invalid result cell {cell!r} (played game needs opponent and color)')
                elif code in NO_OPPONENT:
                    require(opponent == '0', where, f'bye/unpaired code cannot name an opponent ({cell!r})')
                cells[row['D_PAIR_NUM'], n] = (code, opponent, color)
        # A double section whose every match was split (W against W) has no
        # double-only code, and SwissSys may write it as type S (May Ladder).
        # W against W is nonreciprocal for single games, so it only reads as double.
        played = [(key, c) for key, c in cells.items() if c[0] in PLAYED]
        splits = bool(played) and all(c[0] == 'W' and cells.get((c[1], key[1]), ('',))[0] == 'W'
                                      for key, c in played)
        double = section['S_TRN_TYPE'] == '2' or splits or any(c[0] in DOUBLE_ONLY for c in cells.values())
        for (pair, n), (code, opponent, color) in cells.items():
            if opponent == '0':
                continue  # X0/F0/Z0/B0/H0/U0: accepted unmatched (SwissSys writes X0/F0)
            where = f'section {sec}, player {pair}, round {n}'
            require(opponent != pair, where, 'self opponent')
            require((sec, opponent) in players, where, 'unknown opponent')
            other = cells[opponent, n]
            want = RECIPROCAL[double].get(code)
            require(want is not None, where, f'code {code} is not valid in a {"double" if double else "single"}-game section')
            require(other[0] == want and other[1] == pair and
                    (not color or not other[2] or {color, other[2]} == {'W', 'B'}),
                    where, 'nonreciprocal result / color')
        # Observed in the rated records (April Ladder, Spring Festival): within a round,
        # unmatched X0 and F0 were rated as forfeit pairings, matched in pairing-number
        # order; a leftover X0 was rated as a full-point bye and Z0 as a half-point bye.
        rated = {}
        for n in range(1, rounds + 1):
            unmatched = {code: sorted(int(p) for (p, r), c in cells.items() if r == n and c[:2] == (code, '0'))
                         for code in 'XF'}
            for x, f in zip(unmatched['X'], unmatched['F']):
                rated[str(x), n], rated[str(f), n] = ('X', str(f)), ('F', str(x))
            for x in unmatched['X'][len(unmatched['F']):]:
                rated[str(x), n] = ('B', '0')
        entrants = []
        for row in rows:
            pair = row['D_PAIR_NUM']
            results, legs, score = [], [], 0
            for n in range(1, rounds + 1):
                code, opponent, color = cells[pair, n]
                results.append(code + opponent + color)
                code, opponent = rated.get((pair, n), ('H' if code == 'Z' else code, opponent))
                if double:
                    flip = {'W': 'B', 'B': 'W'}.get(color, '')
                    pair_legs = [(LEGS[code][0], color), (LEGS[code][1], flip)]
                else:
                    pair_legs = [(code, color)]
                for leg, leg_color in pair_legs:
                    legs.append(leg + opponent + leg_color)
                    score += SINGLE_POINTS[leg]
            entrants.append({'pairing': int(pair), 'memberId': row['D_MEM_ID'], 'name': row['D_NAME'],
                             'state': row['D_STATE'], 'rating': int(row['D_RATING']),
                             'points': score, 'results': results, 'legs': legs})
        canonical, total, category = parsed
        imported.append({'number': int(sec), 'name': section['S_SEC_NAME'], 'pairingType': section['S_TRN_TYPE'],
                         'doubleGames': double, 'rounds': rounds, 'ratedRounds': rounds * (2 if double else 1),
                         'timeControl': canonical, 'totalMinutes': total, 'ratingSystem': category,
                         'declaredRatingSystem': section['S_R_SYSTEM'], 'players': entrants})
    return {'status': 'mock-imported', 'event': h['H_NAME'], 'physicalRoundColumns': columns,
            'officials': {'chief': h['H_CTD_ID'], 'assistant': h['H_ATD_ID'] or None, 'other': others},
            'sections': imported, 'warnings': warnings}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(import_package(args.package), indent=2))
    except (ImportFailure, OSError) as error:
        print(f'REJECTED: {error}', file=sys.stderr)
        sys.exit(1)
