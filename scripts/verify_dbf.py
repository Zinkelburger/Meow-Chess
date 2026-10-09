#!/usr/bin/env python3
"""Independently decode US Chess 2C using dbfread==2.0.7; not portal acceptance.

Field contracts transcribed from the US Chess 2C specification (September 2025
character-field correction), https://secure2.uschess.org/TD_Affil/fileformat.php.
H_OTHER_TD follows 2C's 255-byte character field, not a memo field. Every
field, dates included, is character type with blank event IDs, as in every
SwissSys report US Chess accepted (test/fixtures/boylston). S_TIMECTL uses the
spelling US Chess stores for rated sections (G/60;d5, 40/90,SD/30;+30).
Rating systems are re-derived from S_TIMECTL with rule 5C (Official Rules of
Chess, 7th edition): total = all control minutes + delay/increment seconds.
expected-event.json compares every entrant and result with the source event,
so mutually consistent but wrong output cannot pass on reciprocity alone. It is
required unless --reciprocity-only says a package has no source event.
Checks raise DbfCheckError rather than assert, so they also run under python -O.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import struct
import sys
import unicodedata
from dbfread import DBF

HEADER = [('H_FORMAT', 5), ('H_PROGRAM', 10), ('H_EVENT_ID', 12), ('H_NAME', 35),
          ('H_TOT_SECT', 2), ('H_BEG_DATE', 8), ('H_END_DATE', 8), ('H_AFF_ID', 8),
          ('H_CITY', 21), ('H_STATE', 2), ('H_ZIPCODE', 10), ('H_COUNTRY', 21),
          ('H_SENDCROS', 1), ('H_CTD_ID', 8), ('H_ATD_ID', 8), ('H_OTHER_TD', 255)]
SECTION = [('S_EVENT_ID', 12), ('S_SEC_NUM', 2), ('S_SEC_NAME', 30), ('S_R_SYSTEM', 1),
           ('S_TIMECTL', 40), ('S_CTD_ID', 8), ('S_ATD_ID', 8), ('S_TRN_TYPE', 1),
           ('S_TOT_RNDS', 2), ('S_LST_PAIR', 4), ('S_BEG_DATE', 8), ('S_END_DATE', 8),
           ('S_SCH_LVL', 1), ('S_GR_PRIX', 1), ('S_GP_PTS', 3), ('S_FIDE', 1)]
STATES = set('''AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN
MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY
PR VI GU AS MP AA AE AP'''.split())
TIMECTL = re.compile(r'^(G/(\d+)|((\d+/\d+,)+SD/\d+));(d|\+)(\d+)$')
MEMBER = re.compile(r'\d{8}')


class DbfCheckError(Exception):
    """An export that the independent 2C checks reject."""


def check(condition, *detail):
    if not condition:
        raise DbfCheckError(*detail or ('check failed',))


def rating_system(timectl):
    match = TIMECTL.match(timectl)
    check(match, ('S_TIMECTL form', timectl))
    minutes = [int(m) for m in re.findall(r'/(\d+)', match.group(1))]
    total = sum(minutes) + int(match.group(6))
    if total <= 10:
        # Blitz has no 2C letter; US Chess rated SwissSys's D by time control.
        check(total >= 5 and minutes[0] >= 3, ('not ratable', timectl))
        return 'D'
    check(minutes[0] >= 5, ('primary time', timectl))
    if total > 65:
        return 'R'
    if total >= 30:
        return 'D'
    return 'Q'


def report_name(player):
    '''Independent of the Dart rules; the fixture keeps to cases both cover.'''
    raw = player.get('reportName') or player['name']
    plain = unicodedata.normalize('NFKD', raw).encode('ascii', 'ignore').decode()
    plain = ' '.join(plain.split()).upper()
    if player.get('reportName') or ',' in plain:
        return plain
    given, family = plain.rsplit(' ', 1)
    return f'{family}, {given}'


DETAIL = [('D_EVENT_ID', 12), ('D_SEC_NUM', 2), ('D_PAIR_NUM', 4), ('D_MEM_ID', 8),
          ('D_NAME', 30), ('D_STATE', 2), ('D_RATING', 4)]


def decode(folder, filename, fields):
    path = folder / filename
    table = DBF(str(path), encoding='ascii', load=True)
    contract = [(name, 'C', width) for name, width in fields]
    check([(f.name, f.type, f.length) for f in table.fields] == contract, filename)
    raw = path.read_bytes()
    count, header_size, record_size = struct.unpack_from('<IHH', raw, 4)
    check(raw[0] == 3 and raw[-1] == 26, filename)
    check(header_size == 32 + 32 * len(fields) + 1 and raw[header_size - 1] == 13)
    check(record_size == 1 + sum(width for _, width in fields))
    check(len(raw) == header_size + count * record_size + 1)
    check(count == len(table.records) > 0)
    for index in range(count):
        offset = header_size + index * record_size
        check(raw[offset] == 32, 'Unexpected deleted row')
        offset += 1
        for name, kind, width in contract:
            value = raw[offset:offset + width]
            check(all(32 <= b <= 126 for b in value), (name, value))
            if kind == 'C' and name in {'H_TOT_SECT', 'S_SEC_NUM', 'S_TOT_RNDS', 'S_LST_PAIR', 'S_GP_PTS', 'D_SEC_NUM', 'D_PAIR_NUM', 'D_RATING'}:
                check(value == value.strip().ljust(width, b' '), (name, value))
            offset += width
    return table.records


def verify(folder, reciprocity_only=False):
    header = decode(folder, 'THEXPORT.DBF', HEADER)
    sections = decode(folder, 'TSEXPORT.DBF', SECTION)
    check(len(header) == 1 and header[0]['H_FORMAT'] == '2C')
    h = header[0]
    check(int(h['H_TOT_SECT']) == len(sections))
    check(re.fullmatch(r'A\d{7}', h['H_AFF_ID']), 'Affiliate ID form')
    check(re.fullmatch(r'\d{8}', h['H_CTD_ID']) and h['H_CTD_ID'] != '0' * 8)
    check(h['H_STATE'] in STATES and h['H_COUNTRY'] == 'USA')
    check(re.fullmatch(r'\d{5}(-\d{4})?', h['H_ZIPCODE']))
    check(h['H_CITY'] and h['H_NAME'] and h['H_SENDCROS'] in 'TAN')
    for field in ('H_BEG_DATE', 'H_END_DATE'):
        try:
            datetime.datetime.strptime(h[field], '%Y%m%d')
        except ValueError:
            raise DbfCheckError(field, h[field]) from None
    check(h['H_BEG_DATE'] <= h['H_END_DATE'])
    check(h['H_EVENT_ID'] == '', 'Event IDs are left for US Chess to assign')
    check(h['H_ATD_ID'] == '' or (MEMBER.fullmatch(h['H_ATD_ID']) and h['H_ATD_ID'] != '0' * 8))
    others = h['H_OTHER_TD'].split(',') if h['H_OTHER_TD'] else []
    check(all(MEMBER.fullmatch(x) and x != '0' * 8 for x in others), h['H_OTHER_TD'])
    rounds = {int(row['S_TOT_RNDS']) for row in sections}
    check(all(1 <= n <= 32 for n in rounds))
    count = max(rounds)
    details = decode(folder, 'TDEXPORT.DBF', DETAIL + [(f'D_RND{n:02}', 7) for n in range(1, count + 1)])
    by_section = {r['S_SEC_NUM']: r for r in sections}
    check(len(by_section) == len(sections))
    players = {(r['D_SEC_NUM'], r['D_PAIR_NUM']): r for r in details}
    check(len(players) == len(details))
    for row in sections:
        check(row['S_TRN_TYPE'] in ('S', 'R') and row['S_R_SYSTEM'] in ('R', 'D', 'Q'))
        check(row['S_R_SYSTEM'] == rating_system(row['S_TIMECTL']), 'Rule 5C')
        check(row['S_SCH_LVL'] in ('N', 'S', 'P', 'J'))
        check((row['S_GR_PRIX'], row['S_GP_PTS'], row['S_FIDE']) == ('N', '0', 'N'))
        check((row['S_BEG_DATE'], row['S_END_DATE']) == (h['H_BEG_DATE'], h['H_END_DATE']))
        check(row['S_EVENT_ID'] == h['H_EVENT_ID'] and row['S_SEC_NAME'])
        check((row['S_CTD_ID'], row['S_ATD_ID']) == (h['H_CTD_ID'], h['H_ATD_ID']))
        entries = [r for r in details if r['D_SEC_NUM'] == row['S_SEC_NUM']]
        check(len(entries) == int(row['S_LST_PAIR']))
        check({int(r['D_PAIR_NUM']) for r in entries} == set(range(1, len(entries) + 1)))
    reciprocal = {'W': 'L', 'L': 'W', 'D': 'D'}
    for section in by_section:
        ids = [r['D_MEM_ID'] for r in details if r['D_SEC_NUM'] == section]
        check(len(ids) == len(set(ids)), 'Member ID repeated in a section')
    for row in details:
        section = by_section[row['D_SEC_NUM']]
        check(row['D_EVENT_ID'] == header[0]['H_EVENT_ID'] == section['S_EVENT_ID'])
        check(len(row['D_MEM_ID']) == 8 and row['D_MEM_ID'].isdigit())
        check(row['D_MEM_ID'] != '0' * 8, 'Placeholder member ID')
        check(re.fullmatch(r"[A-Z0-9 ,.'-]+", row['D_NAME']), row['D_NAME'])
        # US Chess accepts a blank state and keeps the member record's.
        check(row['D_STATE'] == '' or re.fullmatch(r'[A-Z]{2}', row['D_STATE']), 'Player state')
        check(0 <= int(row['D_RATING']) <= 4000)
        for number in range(1, count + 1):
            field = f'D_RND{number:02}'
            code = row[field]
            check(code, (row, field))
            if number > int(section['S_TOT_RNDS']):
                check(code == 'U0', ('Unused round must be U0', row, field))
                continue
            if code[0] in reciprocal:
                check(code[-1] in 'WB')
                check(code[1:-1] != row['D_PAIR_NUM'], 'Self opponent')
                check((row['D_SEC_NUM'], code[1:-1]) in players, ('Unknown opponent', row, field))
                opponent = players[(row['D_SEC_NUM'], code[1:-1])]
                color = 'B' if code[-1] == 'W' else 'W'
                check(opponent[field] == reciprocal[code[0]] + row['D_PAIR_NUM'] + color)
            else:
                check(code[0] in 'XZFBHU' and code[1:] == '0')
    expected = folder / 'expected-event.json'
    check(expected.exists() or reciprocity_only,
          f'{expected} is missing; pass --reciprocity-only to skip the source-event oracle')
    if expected.exists():
        event = json.loads(expected.read_text(encoding='utf-8'))
        people = {p['id']: p for p in event['players']}
        check(header[0]['H_NAME'] == event['name'])
        check(header[0]['H_CTD_ID'] == event['tdId'])
        check(header[0]['H_AFF_ID'] == event['affiliateId'])
        check(h['H_BEG_DATE'] == event['date'].replace('-', ''))
        check(h['H_END_DATE'] == (event.get('endDate') or event['date']).replace('-', ''))
        check(h['H_ATD_ID'] == event.get('assistantTdId', ''))
        check(others == re.findall(r'\d{8}', event.get('otherTdIds', '')))
        check((h['H_CITY'], h['H_STATE'], h['H_ZIPCODE']) == (event['city'], event['state'], event['zip']))
        check(len(sections) == len(event['sections']))
        # Explicit outcome oracle; independent of Dart score/played getters.
        outcomes = {'whiteWin': ('W', 'L'), 'blackWin': ('L', 'W'), 'draw': ('D', 'D'),
                    'whiteForfeit': ('X', 'F'), 'blackForfeit': ('F', 'X'), 'doubleForfeit': ('F', 'F')}
        for index, section in enumerate(event['sections'], 1):
            numbers = {pid: str(i) for i, pid in enumerate(section['players'], 1)}
            exported = by_section[str(index)]
            check(exported['S_SEC_NAME'] == section['name'])
            # A phantom or dropped entrant must not hide behind reciprocity.
            entrants = sum(1 for r in details if r['D_SEC_NUM'] == str(index))
            check(entrants == len(section['players']), ('Entrant count', section['name'], entrants, len(section['players'])))
            # Same numbers in the same order as the TD entered, in 2C notation.
            # Same numbers in the same order; US Chess appends d0 when none.
            source = re.findall(r'\d+', section.get('timeControl') or event['timeControl'])
            written = re.findall(r'\d+', exported['S_TIMECTL'])
            check(written in (source, source + ['0']), (written, source))
            check(exported['S_SCH_LVL'] == event.get('level', 'N'))
            round_robin = section.get('format', 'swiss') != 'swiss' and not section.get('doubleGames')
            check(exported['S_TRN_TYPE'] == ('R' if round_robin else 'S'))
            double = section.get('doubleGames', False)
            check(int(exported['S_TOT_RNDS']) == len(section['rounds']) * (2 if double else 1))
            for pid, number in numbers.items():
                row = players[(str(index), number)]
                check(row['D_MEM_ID'] == people[pid]['memberId'], ('Member ID', pid, row['D_MEM_ID']))
                check(row['D_NAME'] == report_name(people[pid]), row['D_NAME'])
                check(row['D_STATE'] == people[pid]['state'])
                check(row['D_RATING'] == str(people[pid]['rating']))
                column = 0
                for rnd in section['rounds']:
                    bye = next((b['points'] for b in rnd['byes'] if b['player'] == pid), 0)
                    # Each game of a double round is its own reported round;
                    # a double-round bye is shared between the two games.
                    legs = [(1, (bye + 1) // 2), (2, bye - (bye + 1) // 2)] if double else [(None, bye)]
                    for leg, points in legs:
                        column += 1
                        game = next((g for g in rnd['games'] if pid in (g['white'], g['black'])
                                     and (leg is None or g.get('leg', 1) == leg)), None)
                        if game:
                            white = game['white'] == pid
                            code = outcomes[game['outcome']][0 if white else 1]
                            suffix = numbers[game['black'] if white else game['white']] + ('W' if white else 'B') if code in 'WDL' else '0'
                            value = code + suffix
                        else:
                            value = {0: 'U0', 1: 'H0', 2: 'B0'}[points]
                        check(row[f'D_RND{column:02}'] == value, (pid, rnd['number'], leg, value))
        print('PASS: every exported ID, rating and result agrees with the source event.')
    print(f'PASS: independent 2C schema, padding and reciprocal results: {len(sections)} sections, {len(details)} entrants, {count} physical round columns.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--reciprocity-only', action='store_true',
                        help='Allow a package without expected-event.json (schema and reciprocity checks only).')
    args = parser.parse_args()
    try:
        verify(args.package, args.reciprocity_only)
    # A file that cannot be read or decoded at all is rejected the same way as
    # one that decodes but breaks a rule: a FAIL line, never a traceback.
    except (DbfCheckError, OSError, LookupError, ValueError, struct.error) as error:
        print(f'FAIL: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
