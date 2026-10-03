#!/usr/bin/env python3
"""End-to-end golden test: replay seven real club reports through the MCP tools.

test/fixtures/boylston holds anonymized SwissSys reports that US Chess accepted,
and the rated record US Chess published for each (uscf.json). Each event is
rebuilt from its report with the compiled MCP server (registration, sections,
manual rounds, results), exported, and compared two ways:

1. With the SwissSys report, field by field. Every difference must have a
   stated reason (see `explain`); anything unexplained fails.
2. With what US Chess rated. Meow may differ only where SwissSys's own report
   also differs: those are TD edits in the portal after upload.

Build first: dart build cli --target=tools/tournament_mcp.dart --output=build/tournament-cli
"""
from collections import Counter
from pathlib import Path
import json
import re
import struct
import tempfile
import unittest

from test_tournament_mcp import Client

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'test/fixtures/boylston'
CODE = re.compile(r'^([A-Z$#%*])\s*(\d*)\s*([WB]?)$')
# SwissSys double-game match codes as two game results (US Chess expands them).
DOUBLE = {'$': 'WW', '#': 'DW', 'W': 'WL', '%': 'DD', 'D': 'DL', 'L': 'LL'}
OUTCOME = {'Win': 'W', 'Loss': 'L', 'Draw': 'D', 'Unpaired': 'U', 'ByeFull': 'B',
           'ByeHalf': 'H', 'WinForfeit': 'X', 'Forfeit': 'F'}


def read_dbf(path):
    data = path.read_bytes()
    count, header, length = struct.unpack_from('<IHH', data, 4)
    fields, offset, pos = [], 1, 32
    while data[pos] != 0x0D:
        fields.append((data[pos:pos + 11].split(b'\0')[0].decode('ascii'), chr(data[pos + 11]), data[pos + 16]))
        pos += 32
    records = []
    for row in range(count):
        at, record = header + row * length + 1, {}
        for name, _, width in fields:
            record[name] = data[at:at + width].decode('cp1252').strip()
            at += width
        records.append(record)
    return {'fields': fields, 'records': records, 'year': data[1]}


def cells(record, count=None):
    values = [v for k, v in record.items() if k.startswith('D_RND')]
    return values[:count] if count else values


def is_double(section, details):
    return section['S_TRN_TYPE'] == '2' or any(
        c[:1] in '$#%' for r in details if r['D_SEC_NUM'] == section['S_SEC_NUM'] for c in cells(r))


def display(name):
    last, _, first = name.partition(',')
    return f'{first.strip()} {last.strip()}'.strip() or name


def replay(folder, root):
    """Rebuild one report through MCP. Returns (export folder, notes)."""
    header = read_dbf(folder / 'THEXPORT.DBF')['records'][0]
    sections = read_dbf(folder / 'TSEXPORT.DBF')['records']
    details = read_dbf(folder / 'TDEXPORT.DBF')['records']
    notes = []
    c = Client(root)
    try:
        b, e = header['H_BEG_DATE'], header['H_END_DATE']
        c.call('create_event', path='replay.meow', name=header['H_NAME'], date=f'{b[:4]}-{b[4:6]}-{b[6:]}',
               endDate=f'{e[:4]}-{e[4:6]}-{e[6:]}', timeControl=sections[0]['S_TIMECTL'],
               tdId=header['H_CTD_ID'], assistantTdId=header['H_ATD_ID'], otherTdIds=header['H_OTHER_TD'],
               affiliateId=header['H_AFF_ID'], city=header['H_CITY'], state=header['H_STATE'],
               zip=header['H_ZIPCODE'], level=sections[0]['S_SCH_LVL'] or 'N', practice=False)
        person = {}
        for sec in sections:
            rows = sorted((r for r in details if r['D_SEC_NUM'] == sec['S_SEC_NUM']), key=lambda r: int(r['D_PAIR_NUM']))
            rounds = int(sec['S_TOT_RNDS'])
            double = is_double(sec, details)
            codes = {int(r['D_PAIR_NUM']): cells(r, rounds) for r in rows}
            fmt = 'quad' if sec['S_TRN_TYPE'] == 'R' and len(rows) == 4 else 'swiss'
            section = c.call('create_section', name=sec['S_SEC_NAME'], players=[], format=fmt, plannedRounds=rounds,
                             boardStart=1, doubleGames=double, timeControl=sec['S_TIMECTL'],
                             sideGames='side' in sec['S_SEC_NAME'].lower())['section']
            ids = {}
            for r in rows:
                fields = dict(name=display(r['D_NAME']), memberId=r['D_MEM_ID'], rating=int(r['D_RATING'] or 0),
                              state=r['D_STATE'], reportName=r['D_NAME'], checkedIn=True)
                if r['D_MEM_ID'] in person:
                    entry = c.call('add_section_entry', playerId=person[r['D_MEM_ID']], sectionId=section['id'])['entry']
                    c.call('update_player', playerId=entry['id'], **fields)
                else:
                    entry = c.call('add_players', players=[fields])['added'][0]
                    c.call('move_players', players=[entry['id']], sectionId=section['id'])
                    person[r['D_MEM_ID']] = entry['id']
                ids[int(r['D_PAIR_NUM'])] = entry['id']
            for rnd in range(rounds):
                games, outcomes, byes, used = [], [], [], set()
                lone = lambda letter: [p for p, cs in codes.items() if re.fullmatch(letter + r'0?', cs[rnd])]
                # 2C forfeits carry no opponent; Meow records a forfeit as a game.
                for x, f in zip(lone('X'), lone('F')):
                    games.append({'white': ids[x], 'black': ids[f], 'board': len(games) + 1})
                    outcomes.append('whiteForfeit')
                    used |= {x, f}
                for p, cs in codes.items():
                    if p in used:
                        continue
                    m = CODE.match(cs[rnd])
                    letter, opponent, colour = m[1], int(m[2] or 0), m[3]
                    if opponent == 0:
                        points = {'B': 2, 'H': 1, 'U': 0, 'X': 2, 'Z': 1, 'F': 0}[letter]
                        if letter in 'XZF':
                            notes.append(f'{cs[rnd]} without a counterpart written as a {points / 2:g}-point bye')
                        byes.append({'player': ids[p], 'points': points * (2 if double else 1),
                                     'reason': f'Report {cs[rnd]}', 'allocated': letter == 'B'})
                        used.add(p)
                        continue
                    other = CODE.match(codes[opponent][rnd])
                    assert int(other[2]) == p, ('not reciprocal', sec['S_SEC_NAME'], rnd + 1, p, opponent)
                    white, black = (p, opponent) if colour == 'W' or (not colour and other[3] == 'B') else (opponent, p)
                    result = m[1] if white == p else other[1]
                    if double:
                        # The order of the two games is not in the report.
                        first, second = DOUBLE[result]
                        games.append({'white': ids[white], 'black': ids[black], 'board': len(games) // 2 + 1, 'leg': 1})
                        games.append({'white': ids[black], 'black': ids[white], 'board': len(games) // 2 + 1, 'leg': 2})
                        outcomes += [{'W': 'whiteWin', 'D': 'draw', 'L': 'blackWin'}[first],
                                     {'W': 'blackWin', 'D': 'draw', 'L': 'whiteWin'}[second]]
                    else:
                        games.append({'white': ids[white], 'black': ids[black], 'board': len(games) + 1})
                        outcomes.append({'W': 'whiteWin', 'D': 'draw', 'L': 'blackWin'}[result])
                    used |= {p, opponent}
                c.call('post_manual_round', sectionId=section['id'], games=games, byes=byes, reason='Report replay')
                posted = next(s for s in c.call('get_event')['sections'] if s['id'] == section['id'])['rounds'][-1]
                if posted['games']:
                    c.call('start_round', sectionId=section['id'])
                for game, outcome in zip(posted['games'], outcomes):
                    c.call('record_result', gameId=game['id'], outcome=outcome)
        result = c.call('export_event', directory='export')
        assert result['dbfIssues'] == [], result['dbfIssues']
        c.call('close_event')
        return Path(result['directory']), notes
    finally:
        c.close()


def legs(code, double):
    """A report cell as a sorted list of (result, opponent) game results."""
    m = CODE.match(code)
    opponent = m[2] if m[2] not in ('', '0') else None
    if not double:
        return [(m[1], opponent)]
    results = DOUBLE.get(m[1]) if opponent else m[1] * 2
    return sorted((r, opponent) for r in results)


def explain(field, theirs, ours, context):
    """Why a SwissSys/Meow difference is intended, or None if it is not."""
    if field == 'H_PROGRAM':
        return 'program identity'
    if field == 'S_TIMECTL' and re.fullmatch(r'(G/\d+|(\d+/\d+,)+SD/\d+);[d+]\d+', ours) and \
            re.findall(r'\d+', theirs) in (re.findall(r'\d+', ours), re.findall(r'\d+', ours)[:-1]):
        return 'US Chess canonical spelling of the same control'
    if field == 'S_R_SYSTEM' and context['rule5c'] == ours:
        return 'rule 5C category (US Chess derives it from the time control too)'
    if field == 'S_SCH_LVL' and theirs == '' and ours == 'N':
        return 'blank classification entered as non-scholastic'
    if field == 'S_GP_PTS' and theirs == '' and ours == '0':
        return '2C asks for 0 in non-Grand-Prix sections'
    if field == 'D_NAME' and ' '.join(theirs.upper().replace(',', ', ').split()) == ' '.join(ours.replace(',', ', ').split()):
        return 'capitals and spacing'
    if field in ('S_TRN_TYPE', 'S_TOT_RNDS') and context['double']:
        return 'double rounds reported game by game'
    return None


def compare_with_swisssys(folder, export, notes):
    problems, explained = [], Counter()
    theirs = {n: read_dbf(folder / n) for n in ('THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF')}
    ours = {n: read_dbf(export / n) for n in theirs}
    for name in theirs:
        if {t for _, t, _ in ours[name]['fields']} != {'C'}:
            problems.append(f'{name}: non-character fields')
        if name != 'TDEXPORT.DBF' and [f for f in theirs[name]['fields']] != [f for f in ours[name]['fields']]:
            problems.append(f'{name}: field descriptors differ')
    sections = theirs['TSEXPORT.DBF']['records']
    details = theirs['TDEXPORT.DBF']['records']
    doubles = {s['S_SEC_NUM'] for s in sections if is_double(s, details)}
    pairs = [(theirs['THEXPORT.DBF']['records'][0], ours['THEXPORT.DBF']['records'][0], {'double': False, 'rule5c': None})]
    for a, b in zip(sections, ours['TSEXPORT.DBF']['records']):
        pairs.append((a, b, {'double': a['S_SEC_NUM'] in doubles, 'rule5c': b['S_R_SYSTEM']}))
    key = lambda r: (r['D_SEC_NUM'], r['D_MEM_ID'])
    mine = {key(r): r for r in ours['TDEXPORT.DBF']['records']}
    if [key(r) for r in details] != [key(r) for r in ours['TDEXPORT.DBF']['records']]:
        problems.append('detail records differ in order or membership')
    unpaired = Counter(n.split()[0] for n in notes)
    for r in details:
        b = mine[key(r)]
        double = r['D_SEC_NUM'] in doubles
        pairs.append(({k: v for k, v in r.items() if not k.startswith('D_RND')},
                      {k: v for k, v in b.items() if not k.startswith('D_RND')}, {'double': double, 'rule5c': None}))
        rounds = int(next(s for s in sections if s['S_SEC_NUM'] == r['D_SEC_NUM'])['S_TOT_RNDS'])
        source, written = cells(r, rounds), cells(b)
        for i, code in enumerate(source):
            got = written[2 * i:2 * i + 2] if double else [written[i]]
            want = legs(code, double)
            have = sorted(x for c in got for x in legs(c, False))
            # Single games must match exactly, colour included. A double code
            # gives only the match total, so its two games compare as a pair.
            if (got == [re.sub(r'\s', '', code)]) if not double else want == have:
                continue
            if code in ('X0', 'Z0') and unpaired[code] and have == [({'X0': 'B', 'Z0': 'H'}[code], None)]:
                explained[f'{code} without a counterpart written as the bye US Chess rated'] += 1
                unpaired[code] -= 1
                continue
            problems.append(f"{r['D_NAME']} round {i + 1}: SwissSys {code} vs Meow {got}")
        extra = written[len(source) * (2 if double else 1):]
        if any(c != 'U0' for c in extra):
            problems.append(f"{r['D_NAME']}: unused columns are not U0")
    for a, b, context in pairs:
        for field in a.keys() & b.keys():
            if a[field] == b[field]:
                continue
            reason = explain(field, a[field], b[field], context)
            if reason:
                explained[f'{field}: {reason}'] += 1
            else:
                problems.append(f'{field}: SwissSys {a[field]!r} vs Meow {b[field]!r}')
    return problems, explained


# Reports that are not the revision US Chess rated, so the rated record cannot
# judge them. Each needs a reason; their field-by-field comparison still runs.
NOT_THE_RATED_REVISION = {
    'may-ladder': 'US Chess rated a later revision (May 7-28, six rounds, other '
                  'pairings and byes); this report is dated June 11 with three',
}


def rated_differences(report, rated, doubles=()):
    """Cells where a report disagrees with what US Chess rated. `doubles` names
    sections whose double rounds the report writes as two columns; the order of
    the two games is not in the source, so each pair is compared as a whole."""
    sections = read_dbf(report / 'TSEXPORT.DBF')['records']
    details = read_dbf(report / 'TDEXPORT.DBF')['records']
    header = read_dbf(report / 'THEXPORT.DBF')['records'][0]
    out = set()
    officials = {o['memberId'] for o in rated['officials']}
    for td in [header['H_CTD_ID'], header['H_ATD_ID'], *header['H_OTHER_TD'].split(',')]:
        if td and td not in officials:
            out.add(('official not credited', td))
    for sec in sections:
        number = int(sec['S_SEC_NUM'])
        published = next((s for s in rated['sections'] if s['number'] == number), None)
        if published is None:
            out.add(('section missing', number))
            continue
        swisssys_double = is_double(sec, details)
        span = 2 if swisssys_double or sec['S_SEC_NUM'] in doubles else 1
        players = {p['memberId']: p for p in published['players']}
        rows = [r for r in details if r['D_SEC_NUM'] == sec['S_SEC_NUM']]
        by_pair = {r['D_PAIR_NUM']: r['D_MEM_ID'] for r in rows}
        for r in rows:
            p = players.get(r['D_MEM_ID'])
            if p is None:
                out.add((number, r['D_MEM_ID'], 'not rated'))
                continue
            results = {x['round']: (OUTCOME[x['outcome']], x['opponentMemberId']) for x in p['rounds']}
            colours = {x['round']: (x.get('color') or '')[:1] for x in p['rounds']}
            written = cells(r, int(sec['S_TOT_RNDS']))
            groups = [[c] for c in written] if swisssys_double or span == 1 else [
                written[i:i + 2] for i in range(0, len(written), 2)]
            for i, group in enumerate(groups):
                rounds = tuple(range(i * span + 1, i * span + span + 1))
                # Colours are compared for single games only: US Chess's record
                # of expanded double games can show both games as White.
                colour = lambda c: '' if span == 2 else CODE.match(c)[3]
                mine = sorted((x, by_pair.get(o), colour(c)) for c in group for x, o in legs(c, swisssys_double))
                theirs = sorted((*results.get(n, ('U', None)), '' if span == 2 else colours.get(n, ''))
                                for n in rounds)
                # 2C forfeits and byes carry no opponent or colour; US Chess may add them.
                strip = lambda games: sorted((x, o, k) if x in 'WDL' else (x, None, '') for x, o, k in games)
                if strip(mine) != strip(theirs):
                    out.add((number, r['D_MEM_ID'], rounds))
    return out


class BoylstonReplay(unittest.TestCase):
    pass


def make_test(folder):
    def test(self):
        rated = json.loads((folder / 'uscf.json').read_text())
        with tempfile.TemporaryDirectory(prefix='meow-boylston-') as temp:
            export, notes = replay(folder, Path(temp))
            problems, explained = compare_with_swisssys(folder, export, notes)
            self.assertEqual(problems, [], f'Unexplained differences from the accepted report: {problems[:10]}')
            if folder.name in NOT_THE_RATED_REVISION:
                print(f"\n  {folder.name}: rated record not compared: {NOT_THE_RATED_REVISION[folder.name]}")
            else:
                source = read_dbf(folder / 'TSEXPORT.DBF')['records']
                details = read_dbf(folder / 'TDEXPORT.DBF')['records']
                doubles = {s['S_SEC_NUM'] for s in source if is_double(s, details)}
                swisssys = rated_differences(folder, rated)
                meow = rated_differences(export, rated, doubles)
                self.assertEqual(sorted(meow - swisssys, key=str), [],
                                 'Meow differs from the rated record where SwissSys did not')
            print(f'\n  {folder.name}: {dict(explained)}')
    return test


if not FIXTURES.is_dir():
    @unittest.skip(f'{FIXTURES} is not present (kept out of this checkout)')
    class BoylstonReplay(unittest.TestCase):  # noqa: F811
        def test_fixtures(self):
            pass
else:
    for fixture in sorted(p for p in FIXTURES.iterdir() if p.is_dir()):
        setattr(BoylstonReplay, f'test_{fixture.name.replace("-", "_")}', make_test(fixture))


if __name__ == '__main__':
    unittest.main(verbosity=2)
