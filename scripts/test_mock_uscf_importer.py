#!/usr/bin/env python3
"""Check the mock importer against what US Chess accepted and rated.

1. The seven pseudonymized SwissSys packages in test/fixtures/boylston (all
   accepted by MUIR) must import, and what we decode from them must match their
   rated record (uscf.json), except for the listed portal edits.
2. Meow's generated packages (artifacts/dbf-contract and artifacts/dbf-importer,
   written by scripts/check_exports.py) must import and match their source
   events. These tests are skipped if the packages have not been generated.
3. Damaged copies of a fixture must each fail with a specific message.

Standard library only. No real identities are read or written.
"""
from collections import Counter
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

from mock_uscf_importer import HEADER, SECTION, ImportFailure, import_package

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'test/fixtures/boylston'
EVENTS = ('april-ladder', 'fall-equinox-swiss', 'march-quads', 'may-ladder',
          'rated-friday-night-blitz', 'springfestival', 'tornado-147')
BASE = FIXTURES / 'tornado-147'  # 2 sections x 4 rounds, H0/B0/U0, blank D_STATE
MEOW_BASE = ROOT / 'artifacts/dbf-contract'
MATRIX = ROOT / 'artifacts/dbf-importer'
OUTCOME = {'Win': 'W', 'Loss': 'L', 'Draw': 'D', 'Unpaired': 'U', 'ByeFull': 'B',
           'ByeHalf': 'H', 'WinForfeit': 'X', 'Forfeit': 'F'}

# Where the rated record differs from the accepted DBF because the TD edited the
# event in the US Chess portal after upload. Keys: (event, section, pairing number).
# Each entry must really differ; a stale entry fails the test.
MAY_DOUBLE = 'May Ladder G45 double: the rated rounds were re-entered in the portal and differ from the DBF'
SCORE_EXCEPTIONS = {('may-ladder', 1, p): MAY_DOUBLE for p in (2, 3, 4, 5, 6, 7)}
ROUND_EXCEPTIONS = {('may-ladder', 1, p): MAY_DOUBLE for p in range(1, 8)}
MEMBER_EXCEPTIONS = {('april-ladder', 2, 9): 'member ID corrected in the portal after upload'}
ROUND_COUNT_EXCEPTIONS = {('springfestival', 3): 'side game: rated with 5 rounds, DBF S_TOT_RNDS is 1'}


def rated(event):
    return json.loads((FIXTURES / event / 'uscf.json').read_text())


def pairs(event):
    """(event, imported section, rated section, {member: imported}, {member: rated})"""
    result, record = import_package(FIXTURES / event), rated(event)
    for mine, theirs in zip(result['sections'], record['sections']):
        yield (mine, theirs, {p['memberId']: p for p in mine['players']},
               {p['memberId']: p for p in theirs['players']})


class FixtureTests(unittest.TestCase):
    """Real SwissSys output that MUIR accepted, compared with what MUIR rated."""

    def test_all_fixtures_accepted(self):
        self.assertEqual(sorted(p.name for p in FIXTURES.iterdir() if p.is_dir()), sorted(EVENTS))
        for event in EVENTS:
            with self.subTest(event=event):
                result = import_package(FIXTURES / event)
                self.assertEqual(result['status'], 'mock-imported')
                self.assertEqual(len(result['sections']), len(rated(event)['sections']))

    def test_sections_match_rated_record(self):
        seen = set()
        for event in EVENTS:
            for mine, theirs, _, _ in pairs(event):
                key = (event, mine['number'])
                with self.subTest(section=key):
                    self.assertEqual(mine['number'], theirs['number'])
                    self.assertEqual(mine['name'], theirs['name'])
                    self.assertEqual(len(mine['players']), theirs['playerCount'])
                    # MUIR derives the category from the time control, not S_R_SYSTEM.
                    self.assertEqual(mine['ratingSystem'], theirs['ratingSystem'])
                    self.assertEqual(mine['timeControl'], theirs['timeControl'])
                    if key in ROUND_COUNT_EXCEPTIONS:
                        seen.add(key)
                        self.assertNotEqual(mine['ratedRounds'], theirs['roundCount'], ROUND_COUNT_EXCEPTIONS[key])
                    else:
                        self.assertEqual(mine['ratedRounds'], theirs['roundCount'])
        self.assertEqual(seen, set(ROUND_COUNT_EXCEPTIONS))

    def test_double_games_expand_to_two_rated_rounds(self):
        blitz = import_package(FIXTURES / 'rated-friday-night-blitz')['sections'][0]
        self.assertEqual((blitz['pairingType'], blitz['doubleGames'], blitz['rounds'], blitz['ratedRounds']),
                         ('2', True, 6, 12))
        self.assertEqual((blitz['declaredRatingSystem'], blitz['ratingSystem']), ('D', 'B'))
        may = import_package(FIXTURES / 'may-ladder')['sections']
        self.assertEqual([(s['pairingType'], s['doubleGames'], s['ratedRounds']) for s in may],
                         [('S', True, 6), ('S', False, 4)])

    def test_members_match_rated_record(self):
        seen = set()
        for event in EVENTS:
            for mine, _, mine_by, theirs_by in pairs(event):
                odd = {(event, mine['number'], mine_by[m]['pairing']) for m in set(mine_by) - set(theirs_by)}
                odd_rated = {(event, mine['number'], theirs_by[m]['pairingNumber'])
                             for m in set(theirs_by) - set(mine_by)}
                self.assertEqual(odd, odd_rated)
                for key in odd:
                    self.assertIn(key, MEMBER_EXCEPTIONS)
                seen |= odd
        self.assertEqual(seen, set(MEMBER_EXCEPTIONS))

    def test_scores_match_rated_record(self):
        seen, checked = set(), 0
        for event in EVENTS:
            for mine, _, mine_by, theirs_by in pairs(event):
                for member in set(mine_by) & set(theirs_by):
                    player, record = mine_by[member], theirs_by[member]
                    key = (event, mine['number'], player['pairing'])
                    with self.subTest(player=key):
                        if key in SCORE_EXCEPTIONS:
                            seen.add(key)
                            self.assertNotEqual(player['points'], record['score'], SCORE_EXCEPTIONS[key])
                        else:
                            checked += 1
                            self.assertEqual(player['points'], record['score'])
        self.assertEqual(seen, set(SCORE_EXCEPTIONS))
        self.assertEqual(checked, 199)  # every player present in both records

    def test_rounds_match_rated_record(self):
        """Per DBF round: the rated outcomes (both legs for doubles), opponents and colors."""
        mismatched = set()
        for event in EVENTS:
            for mine, theirs, mine_by, theirs_by in pairs(event):
                pairing = {p['memberId']: p['pairingNumber'] for p in theirs['players']}
                legs = 2 if mine['doubleGames'] else 1
                for member in set(mine_by) & set(theirs_by):
                    player, record = mine_by[member], theirs_by[member]
                    key = (event, mine['number'], player['pairing'])
                    by_round = {r['round']: r for r in record['rounds']}
                    for index, cell in enumerate(player['results']):
                        ours = player['legs'][index * legs:(index + 1) * legs]
                        theirs_legs = [by_round.get(index * legs + leg + 1) for leg in range(legs)]
                        want = Counter((OUTCOME[r['outcome']], str(pairing.get(r['opponentMemberId'], 0)))
                                       if r else ('U', '0') for r in theirs_legs)
                        got = Counter((leg[0], leg[1:].rstrip('WB')) for leg in ours)
                        same = got == want
                        if same and legs == 1 and theirs_legs[0] and theirs_legs[0]['color'] in ('White', 'Black'):
                            same = ours[0][-1] == theirs_legs[0]['color'][0]
                        if not same:
                            mismatched.add(key)
                        if key not in ROUND_EXCEPTIONS:
                            self.assertTrue(same, f'{key} round {index + 1}: {cell} -> {ours} vs {dict(want)}')
        self.assertEqual(mismatched, set(ROUND_EXCEPTIONS))

    def test_unmatched_forfeits_are_modeled_as_rated(self):
        april = import_package(FIXTURES / 'april-ladder')['sections'][1]['players']
        self.assertEqual([(p['results'][1], p['legs'][1]) for p in april if p['pairing'] in (1, 2, 7, 8)],
                         [('F0', 'F2'), ('X0', 'X1'), ('F0', 'F8'), ('X0', 'X7')])
        spring = {p['pairing']: p for p in import_package(FIXTURES / 'springfestival')['sections'][0]['players']}
        self.assertEqual(spring[27]['legs'][2], 'B0')
        self.assertEqual(spring[24]['legs'][2], 'H0')

    def test_padding_is_not_imported_as_rounds(self):
        result = import_package(FIXTURES / 'april-ladder')
        self.assertEqual(result['physicalRoundColumns'], 6)
        self.assertEqual(result['sections'][0]['rounds'], 4)
        self.assertTrue(all(len(p['results']) == 4 for p in result['sections'][0]['players']))

    def test_only_three_dbfs_needed(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            for path in BASE.glob('*.DBF'):
                shutil.copy(path, folder / path.name)
            self.assertEqual(import_package(folder), import_package(BASE))

    def test_cli_failure_is_nonzero_even_with_python_optimization(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp)
            header_cell(folder, 'H_FORMAT', '1A')
            result = subprocess.run([sys.executable, '-O', str(ROOT / 'scripts/mock_uscf_importer.py'),
                                     str(folder)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, '')
            self.assertIn('H_FORMAT: unsupported format', result.stderr)

    def test_cli_success_emits_parseable_import(self):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/mock_uscf_importer.py'),
                                 str(BASE)], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'mock-imported')


@unittest.skipUnless((MEOW_BASE / 'TDEXPORT.DBF').exists(), 'run scripts/check_exports.py to generate Meow packages')
class MeowPackageTests(unittest.TestCase):
    """Meow's own exports, scored against the event they were written from."""

    def test_all_packages_and_source_scores(self):
        folders = [MEOW_BASE, *sorted(p for p in MATRIX.iterdir() if (p / 'expected-event.json').exists())] \
            if MATRIX.exists() else [MEOW_BASE]
        for folder in folders:
            with self.subTest(package=folder.name):
                result = import_package(folder)
                source = json.loads((folder / 'expected-event.json').read_text())
                people = {p['id']: p for p in source['players']}
                self.assertEqual(len(result['sections']), len(source['sections']))
                for imported, section in zip(result['sections'], source['sections']):
                    # Meow writes each double-game round as two ordinary rounds.
                    rounds = len(section['rounds']) * (2 if section.get('doubleGames') else 1)
                    self.assertEqual(imported['rounds'], rounds)
                    self.assertEqual(imported['ratedRounds'], rounds)
                    self.assertEqual(len(imported['players']), len(section['players']))
                    for player, pid in zip(imported['players'], section['players']):
                        self.assertEqual(player['memberId'], people[pid]['memberId'])
                        self.assertEqual(len(player['results']), rounds)
                        score = 0
                        for rnd in section['rounds']:
                            for bye in rnd['byes']:
                                if bye['player'] == pid:
                                    score += bye['points'] / 2
                            for game in rnd['games']:
                                # Explicit source oracle independent of the mock's result codes.
                                points = {'whiteWin': (1, 0), 'blackWin': (0, 1),
                                          'draw': (.5, .5), 'whiteForfeit': (1, 0),
                                          'blackForfeit': (0, 1), 'doubleForfeit': (0, 0)}[game['outcome']]
                                if game['white'] == pid:
                                    score += points[0]
                                if game['black'] == pid:
                                    score += points[1]
                        self.assertEqual(player['points'], score)


# --- byte-level mutation helpers -------------------------------------------------

def copy_base(temp, source=BASE):
    folder = Path(temp) / 'export'
    shutil.copytree(source, folder, ignore=shutil.ignore_patterns('*.json'))
    return folder


def patch_bytes(folder, filename, offset, value):
    path = folder / filename
    data = bytearray(path.read_bytes())
    data[offset:offset + len(value)] = value
    path.write_bytes(data)


def layout(folder, filename):
    raw = (folder / filename).read_bytes()
    count, header, size = struct.unpack_from('<IHH', raw, 4)
    fields, at = [], 32
    while raw[at] != 13:
        fields.append((raw[at:at + 11].split(b'\0')[0].decode(), raw[at + 16]))
        at += 32
    return raw, count, header, size, fields


def cell(folder, filename, field, value, row=0):
    raw, _, header, size, fields = layout(folder, filename)
    offset = header + row * size + 1
    for name, width in fields:
        if name == field:
            data = value.encode('ascii') if isinstance(value, str) else value
            if len(data) > width:
                raise ValueError('Mutation would overflow a field')
            patch_bytes(folder, filename, offset, data.ljust(width, b' '))
            return
        offset += width
    raise ValueError(field)


def read_cell(folder, filename, field, row=0):
    raw, _, header, size, fields = layout(folder, filename)
    offset = header + row * size + 1
    for name, width in fields:
        if name == field:
            return raw[offset:offset + width].decode('ascii').rstrip()
        offset += width
    raise ValueError(field)


def header_cell(folder, field, value):
    cell(folder, 'THEXPORT.DBF', field, value)


def section_cell(folder, field, value, row=0):
    cell(folder, 'TSEXPORT.DBF', field, value, row)


def detail_cell(folder, field, value, row=0):
    cell(folder, 'TDEXPORT.DBF', field, value, row)


def descriptor(filename, index, offset, value):
    return lambda f: patch_bytes(f, filename, 32 + index * 32 + offset, value)


def td_header(f):
    return layout(f, 'TDEXPORT.DBF')[2]


def bad_file(folder, transform):
    path = folder / 'TDEXPORT.DBF'
    path.write_bytes(transform(path.read_bytes()))


def swap_descriptors(folder):
    path = folder / 'TDEXPORT.DBF'
    raw = bytearray(path.read_bytes())
    raw[32:64], raw[64:96] = raw[64:96], raw[32:64]
    path.write_bytes(raw)


def duplicate_member(folder):
    detail_cell(folder, 'D_MEM_ID', read_cell(folder, 'TDEXPORT.DBF', 'D_MEM_ID', row=1))


def date_field(name):
    schema = HEADER if name.startswith('H_') else SECTION
    return [n for n, _, _ in schema].index(name)


# Base: tornado-147. Row 0 is section 1 pairing 1 (round 1 'D8W'); pairing 2 has 'W9B'.
# Each mutation must fail for the stated reason, not an unrelated parse error.
CASES = [
    ('missing_file', lambda f: (f / 'TSEXPORT.DBF').unlink(), 'missing file'),
    ('lowercase_filename', lambda f: (f / 'TSEXPORT.DBF').rename(f / 'tsexport.dbf'), 'missing file'),
    ('memo_dialect', lambda f: patch_bytes(f, 'TDEXPORT.DBF', 0, b'\x83'), 'dBASE III'),
    ('bad_update_date', lambda f: patch_bytes(f, 'TDEXPORT.DBF', 2, b'\x00'), 'update date'),
    ('record_count', lambda f: patch_bytes(f, 'TDEXPORT.DBF', 4, struct.pack('<I', 29)), 'file length mismatch'),
    ('header_length', lambda f: patch_bytes(f, 'TDEXPORT.DBF', 8, b'\x01\x00'), 'header length'),
    ('record_length', lambda f: patch_bytes(f, 'TDEXPORT.DBF', 10, b'\x01\x00'), 'record length'),
    ('field_order', swap_descriptors, 'descriptor mismatch'),
    ('numeric_field', descriptor('TDEXPORT.DBF', 0, 11, b'N'), 'descriptor mismatch'),
    ('wrong_width', descriptor('TDEXPORT.DBF', 0, 16, b'\x0b'), 'descriptor mismatch'),
    ('decimal_count', descriptor('TDEXPORT.DBF', 0, 17, b'\x01'), 'descriptor mismatch'),
    ('renamed_field', descriptor('TDEXPORT.DBF', 4, 0, b'D_NOM'), 'descriptor mismatch'),
    ('numeric_date', descriptor('THEXPORT.DBF', date_field('H_BEG_DATE'), 11, b'N'), 'descriptor mismatch'),
    ('other_td_254', descriptor('THEXPORT.DBF', 15, 16, b'\xfe'), 'descriptor mismatch'),
    ('header_terminator', lambda f: patch_bytes(f, 'TDEXPORT.DBF', td_header(f) - 1, b'\x00'), 'terminator'),
    ('deleted_record', lambda f: patch_bytes(f, 'TDEXPORT.DBF', td_header(f), b'*'), 'record marker'),
    ('truncated', lambda f: bad_file(f, lambda r: r[:-8]), 'file length mismatch'),
    ('extra_bytes', lambda f: bad_file(f, lambda r: r + b'\x00'), 'file length mismatch'),
    ('missing_eof', lambda f: bad_file(f, lambda r: r[:-1] + b'\x00'), 'EOF'),
    ('format', lambda f: header_cell(f, 'H_FORMAT', '1A'), 'unsupported format'),
    ('affiliate', lambda f: header_cell(f, 'H_AFF_ID', 'B1234567'), 'invalid affiliate'),
    ('chief_td_blank', lambda f: header_cell(f, 'H_CTD_ID', ''), 'eight-digit'),
    ('other_td', lambda f: header_cell(f, 'H_OTHER_TD', '90000001,1234'), 'H_OTHER_TD: expected eight-digit'),
    ('section_count', lambda f: header_cell(f, 'H_TOT_SECT', '3'), 'section count mismatch'),
    ('right_justification', lambda f: header_cell(f, 'H_TOT_SECT', ' 2'), 'leading spaces'),
    ('leading_zero_count', lambda f: header_cell(f, 'H_TOT_SECT', '02'), 'canonical'),
    ('bad_date', lambda f: header_cell(f, 'H_END_DATE', '20260230'), 'calendar date'),
    ('date_order', lambda f: header_cell(f, 'H_END_DATE', '20260417'), 'precedes start'),
    ('tab_outside_name', lambda f: header_cell(f, 'H_CITY', b'Bos\tton'), 'control byte'),
    ('event_link', lambda f: section_cell(f, 'S_EVENT_ID', 'OTHER'), 'event ID mismatch'),
    ('detail_event_link', lambda f: detail_cell(f, 'D_EVENT_ID', 'OTHER'), 'event ID mismatch'),
    ('duplicate_section', lambda f: section_cell(f, 'S_SEC_NUM', '1', row=1), 'sections must be numbered'),
    ('time_control', lambda f: section_cell(f, 'S_TIMECTL', 'fast'), 'unrecognized time control'),
    ('pairing_type', lambda f: section_cell(f, 'S_TRN_TYPE', 'X'), 'unsupported pairing type'),
    ('rating_system', lambda f: section_cell(f, 'S_R_SYSTEM', 'Z'), 'unsupported rating system'),
    ('section_dates', lambda f: section_cell(f, 'S_END_DATE', '20260419'), 'section dates outside event'),
    ('round_limit', lambda f: section_cell(f, 'S_TOT_RNDS', '33'), 'outside 1..32'),
    ('round_schema', lambda f: section_cell(f, 'S_TOT_RNDS', '5'), 'field count'),
    ('player_count', lambda f: section_cell(f, 'S_LST_PAIR', '17'), 'player count mismatch'),
    ('unknown_section', lambda f: detail_cell(f, 'D_SEC_NUM', '3'), 'unknown section'),
    ('duplicate_pair', lambda f: detail_cell(f, 'D_PAIR_NUM', '2'), 'duplicate pairing number'),
    ('duplicate_member', duplicate_member, 'duplicate member ID'),
    ('short_member', lambda f: detail_cell(f, 'D_MEM_ID', '123456'), 'eight-digit'),
    ('bad_state', lambda f: detail_cell(f, 'D_STATE', 'M1'), 'player state'),
    ('blank_rating', lambda f: detail_cell(f, 'D_RATING', ''), 'D_RATING: expected canonical'),
    ('non_ascii', lambda f: detail_cell(f, 'D_NAME', b'JOS\xc9'), 'non-ASCII'),
    ('nul_padding', lambda f: detail_cell(f, 'D_NAME', b'NAME\x00'), 'control byte'),
    ('unknown_opponent', lambda f: detail_cell(f, 'D_RND01', 'W99W'), 'unknown opponent'),
    ('self_opponent', lambda f: detail_cell(f, 'D_RND01', 'W1W'), 'self opponent'),
    ('nonreciprocal', lambda f: detail_cell(f, 'D_RND01', 'W2W'), 'nonreciprocal'),
    ('same_color', lambda f: detail_cell(f, 'D_RND01', 'D8B'), 'nonreciprocal result / color'),
    ('forfeit_opponent', lambda f: detail_cell(f, 'D_RND01', 'X2'), 'nonreciprocal'),
    ('double_code_reciprocity', lambda f: detail_cell(f, 'D_RND01', '$8W'), 'nonreciprocal'),
    ('bye_with_opponent', lambda f: detail_cell(f, 'D_RND01', 'B8'), 'cannot name an opponent'),
    ('member_as_opponent', lambda f: detail_cell(f, 'D_RND01', 'W12345W'), 'invalid result cell'),
    ('blank_round', lambda f: detail_cell(f, 'D_RND01', ''), 'invalid result cell'),
    ('missing_color', lambda f: detail_cell(f, 'D_RND01', 'D8'), 'invalid result cell'),
    ('lowercase_code', lambda f: detail_cell(f, 'D_RND01', 'd8W'), 'invalid result cell'),
]


def negative_test(mutate, message):
    def test(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp)
            mutate(folder)
            with self.assertRaisesRegex(ImportFailure, message):
                import_package(folder)
    return test


class RejectionTests(unittest.TestCase):
    def test_padding_cannot_contain_even_a_reciprocal_game(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp, FIXTURES / 'april-ladder')  # section 1: 4 rounds in 6 columns
            detail_cell(folder, 'D_RND05', 'W2W', row=0)
            detail_cell(folder, 'D_RND05', 'L1B', row=1)
            with self.assertRaisesRegex(ImportFailure, 'unused round must be U0'):
                import_package(folder)


for name, mutation, reason in CASES:
    setattr(RejectionTests, f'test_reject_{name}', negative_test(mutation, reason))


# Inputs MUIR accepted (or Meow's planned output) that an over-strict reader would refuse.
def all_dates(kind):
    def mutate(f):
        for name in ('H_BEG_DATE', 'H_END_DATE'):
            descriptor('THEXPORT.DBF', date_field(name), 11, kind)(f)
        for name in ('S_BEG_DATE', 'S_END_DATE'):
            descriptor('TSEXPORT.DBF', date_field(name), 11, kind)(f)
    return mutate


def matched_forfeit(f):
    detail_cell(f, 'D_RND01', 'X8')       # pairing 1 vs 8 (row 7), previously a draw
    detail_cell(f, 'D_RND01', 'F1', row=7)


ACCEPTED = [
    ('d_dates', all_dates(b'D'), None),
    ('year_byte_126', lambda f: [patch_bytes(f, n, 1, bytes([126])) for n in ('THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF')], None),
    ('reserved_bytes', lambda f: [patch_bytes(f, n, 12, b'\xa5' * 20) for n in ('THEXPORT.DBF', 'TSEXPORT.DBF', 'TDEXPORT.DBF')], None),
    ('descriptor_addresses', descriptor('TDEXPORT.DBF', 0, 12, b'\x01\x02\x03\x04'), None),
    ('assistant_and_other_tds', lambda f: (header_cell(f, 'H_ATD_ID', '90000001'),
                                           header_cell(f, 'H_OTHER_TD', '90000002,90000003')), None),
    ('event_ids', lambda f: (header_cell(f, 'H_EVENT_ID', 'E1'), section_cell(f, 'S_EVENT_ID', 'E1'),
                             section_cell(f, 'S_EVENT_ID', 'E1', row=1),
                             [detail_cell(f, 'D_EVENT_ID', 'E1', row=r) for r in range(28)]), None),
    ('canonical_time_control', lambda f: section_cell(f, 'S_TIMECTL', 'G/60;d5'), ('D', 'G/60;d5')),
    ('multi_period_time_control', lambda f: section_cell(f, 'S_TIMECTL', '40/90,SD/30;d5'), ('R', '40/90,SD/30;d5')),
    ('increment_time_control', lambda f: section_cell(f, 'S_TIMECTL', 'G/90;+30'), ('R', 'G/90;+30')),
    ('quick_time_control', lambda f: section_cell(f, 'S_TIMECTL', 'G/15;d0'), ('Q', 'G/15;d0')),
    ('round_robin', lambda f: section_cell(f, 'S_TRN_TYPE', 'R'), None),
    ('levels', lambda f: (section_cell(f, 'S_SCH_LVL', 'N'), section_cell(f, 'S_GP_PTS', '0')), None),
    ('blank_state', lambda f: detail_cell(f, 'D_STATE', ''), None),
    ('placeholder_member', lambda f: detail_cell(f, 'D_MEM_ID', '00000000'), None),
    ('blank_member', lambda f: detail_cell(f, 'D_MEM_ID', ''), None),
    ('matched_forfeit', matched_forfeit, None),
]


def accepted_test(mutate, expect):
    def test(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp)
            mutate(folder)
            result = import_package(folder)
            if expect:
                self.assertEqual((result['sections'][0]['ratingSystem'], result['sections'][0]['timeControl']), expect)
    return test


class LeniencyTests(unittest.TestCase):
    def test_missing_member_id_is_reported(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp)
            detail_cell(folder, 'D_MEM_ID', '')
            self.assertIn('section 1, player 1: no member ID (must be resolved in MUIR)',
                          import_package(folder)['warnings'])

    def test_matched_forfeit_scores(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = copy_base(temp)
            matched_forfeit(folder)
            players = import_package(folder)['sections'][0]['players']
            self.assertEqual((players[0]['legs'][0], players[0]['points']), ('X8', 3))
            self.assertEqual((players[7]['legs'][0], players[7]['points']), ('F1', 2.5))


for name, mutation, expect in ACCEPTED:
    setattr(LeniencyTests, f'test_accept_{name}', accepted_test(mutation, expect))


if __name__ == '__main__':
    unittest.main()
