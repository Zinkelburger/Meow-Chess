#!/usr/bin/env python3
"""Read-only Boylston archive inspection and real MCP tournament rehearsals.

Install xlrd and beautifulsoup4 in a venv. Private player data stays under the
ignored artifacts directory. No source sample is modified, no report submitted.
"""
import argparse
from collections import Counter
import configparser
import csv
import io
import json
from pathlib import Path
import re
import struct
import sys
import unicodedata

from bs4 import BeautifulSoup
import xlrd
from test_tournament_mcp import Client


def dbf(path):
    data = path.read_bytes()
    count, header, length = struct.unpack_from('<IHH', data, 4)
    fields, offset = [], 1
    for pos in range(32, header - 1, 32):
        name = data[pos:pos + 11].split(b'\0')[0].decode('ascii')
        width = data[pos + 16]
        fields.append((name, offset, width))
        offset += width
    return [{name: data[header + row * length + offset:header + row * length + offset + width]
             .decode('cp1252').strip() for name, offset, width in fields}
            for row in range(count)]


def sheet(book, name):
    table = book.sheet_by_name(name)
    return [dict(zip(table.row_values(0), table.row_values(i))) for i in range(1, table.nrows)]


def normalized(name):
    name = unicodedata.normalize('NFKD', name)
    return re.sub(r'[^a-z0-9]', '', re.sub(r'^(GM|IM|FM|NM|CM|WGM|WIM|WFM)\s+', '', name, flags=re.I).lower())


def display(name):
    if ',' in name:
        last, first = name.split(',', 1)
        return f'{first.strip()} {last.strip()}'
    return name.strip()


def html_tables(folder):
    result = []
    for path in sorted(folder.glob('*.html')):
        if not path.stat().st_size:
            continue
        soup = BeautifulSoup(path.read_text(errors='replace', encoding='utf-8'), 'html.parser')
        for table in soup.find_all('table'):
            heading = table.find_previous('h3').get_text(' ', strip=True)
            section_name = heading.split(': ', 1)[1].split(' (Standings', 1)[0].strip()
            rows = [[c.get_text(' ', strip=True) for c in tr.find_all('td')] for tr in table.find_all('tr')]
            if not rows or 'Name' not in rows[0]:
                continue  # Wallcharts are inventoried; score rows have different semantics.
            headers = rows[0]
            result.append({'path': path.name, 'section': section_name,
                           'rows': [dict(zip(headers, row)) for row in rows[1:]]})
    return result


def check_wallcharts(folder, exported):
    event = json.loads((exported / 'event.json').read_text(encoding='utf-8'))
    result = []
    values = {'whiteWin': (2, 0), 'draw': (1, 1), 'blackWin': (0, 2), 'whiteForfeit': (2, 0), 'blackForfeit': (0, 2)}
    for path in sorted(folder.glob('*.html')):
        if not path.stat().st_size:
            continue
        soup = BeautifulSoup(path.read_text(errors='replace', encoding='utf-8'), 'html.parser')
        for table in soup.find_all('table'):
            heading = table.find_previous('h3').get_text(' ', strip=True)
            if 'Wall Chart' not in heading:
                continue
            name = heading.split(': ', 1)[1].strip()
            section = next((s for s in event['sections'] if s['name'] == name), None)
            if section is None:
                continue
            rows = [[c.get_text(' ', strip=True) for c in tr.find_all('td')] for tr in table.find_all('tr')]
            members = {p['memberId']: p['id'] for p in event['players'] if p['id'] in section['players']}
            checks = {'file': path.name, 'section': name, 'checkpointScoresChecked': 0, 'differences': []}
            for i in range(1, len(rows)-1, 2):
                identity = re.search(r'\b(\d{8})\b', rows[i+1][1])
                if not identity or identity[1] not in members:
                    checks['differences'].append({'name': rows[i][1], 'issue': 'Missing member identity'})
                    continue
                pid = members[identity[1]]
                for col, label in enumerate(rows[0]):
                    if not label.startswith('Rd '):
                        continue
                    match = re.search(r'(\d+\.\d+)\s*$', rows[i+1][col])
                    if not match:
                        continue
                    checkpoint = int(label.split()[1])
                    total = 0
                    for r in section['rounds'][:checkpoint]:
                        total += sum(b['points'] for b in r['byes'] if b['player'] == pid)
                        for g in r['games']:
                            a,b = values.get(g['outcome'], (0,0))
                            total += a if g['white'] == pid else b if g['black'] == pid else 0
                    checks['checkpointScoresChecked'] += 1
                    if total / 2 != float(match[1]):
                        checks['differences'].append({'name': rows[i][1], 'round': checkpoint, 'html': float(match[1]), 'meow': total/2})
            result.append(checks)
    return result


def select_snapshot(folder, section, expected_count, rounds):
    candidates = []
    rejected = []
    for path in folder.glob(section + '.S*'):
        if not (path.suffix.upper() == '.SRR' or re.fullmatch(r'\.S\d+C', path.suffix, re.I)):
            continue
        book = xlrd.open_workbook(str(path), logfile=io.StringIO())
        settings = sheet(book, 'Settings')[0]
        players = sheet(book, 'Players')
        if expected_count and len(players) != expected_count:
            rejected.append(path.name)
            continue
        results = sheet(book, 'Results')
        completed = sum(1 for r in range(1, rounds + 1)
                        if any(str(row.get(f'RES_CH{r}', '')).strip('\0 ') for row in results))
        rank = (completed, int(path.suffix[2:-1]) if path.suffix != '.SRR' else 100)
        candidates.append((rank, path, settings, players, results))
    if not candidates:
        raise ValueError(f'No suitable snapshot: {section}')
    _, path, settings, players, results = max(candidates, key=lambda x: x[0])
    return path, settings, players, results, rejected


def outcome(points, code):
    if code in ('X', 'F'):
        return 'whiteForfeit' if points == 2 else 'blackForfeit'
    return {0: 'blackWin', 1: 'draw', 2: 'whiteWin'}[points]


def compare_dbfs(folder, exported, section_name=None):
    if not (exported / 'TDEXPORT.DBF').exists():
        return {'status': 'blocked by preflight'}
    expected = dbf(folder / 'tdexport.dbf')
    actual = dbf(exported / 'TDEXPORT.DBF')
    source_section_number = None
    if section_name:
        source_section_number = next(s['S_SEC_NUM'] for s in dbf(folder / 'tsexport.dbf') if s['S_SEC_NAME'] == section_name)
        expected = [dict(r, D_SEC_NUM='1') for r in expected if r['D_SEC_NUM'] == source_section_number]
    key = lambda row: (row['D_SEC_NUM'], row['D_MEM_ID'])
    left, right = {key(r): r for r in expected}, {key(r): r for r in actual}
    differences = []
    for k in sorted(left.keys() | right.keys()):
        if k not in left or k not in right:
            differences.append({'player': k, 'difference': 'missing row'})
            continue
        a, b = left[k], right[k]
        for field in sorted(a.keys() & b.keys()):
            if field in ('D_EVENT_ID', 'D_NAME'):
                continue
            av, bv = a[field], b[field]
            # Ignore padding inside opponent references, but retain result codes.
            if field.startswith('D_RND'):
                av, bv = re.sub(r'\s+', '', av), re.sub(r'\s+', '', bv)
            if av != bv:
                differences.append({'player': k, 'field': field, 'boylston': av, 'meow': bv})
    metadata = []
    for filename in ('thexport.dbf', 'tsexport.dbf'):
        source_rows = dbf(folder / filename)
        if section_name:
            if filename == 'tsexport.dbf':
                source_rows = [dict(r, S_SEC_NUM='1') for r in source_rows if r['S_SEC_NUM'] == source_section_number]
            else:
                source_rows = [dict(r, H_TOT_SECT='1') for r in source_rows]
        for i, (a, b) in enumerate(zip(source_rows, dbf(exported / filename.upper()))):
            for field in a.keys() & b.keys():
                if a[field] != b[field]:
                    metadata.append({'file': filename, 'row': i + 1, 'field': field,
                                     'boylston': a[field], 'meow': b[field]})
    return {'status': 'compared', 'referencePlayers': len(expected), 'exportPlayers': len(actual),
            'detailDifferences': differences, 'metadataDifferences': metadata,
            'normalization': 'Whitespace in round cells; event IDs and player name formatting excluded. Pair numbers preserved from native roster.'}


def rehearse(folder, output):
    h = dbf(folder / 'thexport.dbf')[0]
    sections = dbf(folder / 'tsexport.dbf')
    html = html_tables(folder)
    report = {'event': folder.name, 'sources': [], 'warnings': [], 'sections': [], 'htmlComparisons': []}
    slug = re.sub(r'[^a-z0-9]+', '-', folder.name.lower()).strip('-')
    log_path = output / f'{slug}-mcp.jsonl'
    with log_path.open('w', encoding='utf-8') as log:
        client = Client(output, log)
        try:
            date = h['H_BEG_DATE']
            metadata = dict(name=h['H_NAME'], date=f'{date[:4]}-{date[4:6]}-{date[6:]}',
                            timeControl=sections[0]['S_TIMECTL'], tdId=h['H_CTD_ID'],
                            assistantTdId=h.get('H_ATD_ID', ''), otherTdIds=h.get('H_OTHER_TD', ''),
                            affiliateId=h['H_AFF_ID'], city=h['H_CITY'], state=h['H_STATE'], zip=h['H_ZIPCODE'],
                            practice=False, notes='LOCAL ARCHIVE REHEARSAL ONLY. Not submitted. Metadata copied from the supplied DBF header.')
            client.call('create_event', path=f'{slug}.meow', **metadata)
            seen_members = {}
            for source_section in sections:
                name = source_section['S_SEC_NAME']
                rounds = int(source_section['S_TOT_RNDS'])
                path, settings, players, results, rejected = select_snapshot(
                    folder, name, int(source_section['S_LST_PAIR']), rounds)
                report['sources'].append(path.name)
                if rejected:
                    report['warnings'].append(f'{name}: rejected snapshots with a different roster size: {", ".join(rejected)}')
                double = bool(settings['BLITZ'])
                section_report = {'name': name, 'players': len(players), 'plannedRounds': rounds,
                                  'doubleGames': double, 'timeControl': source_section['S_TIMECTL'], 'completedRounds': 0}
                report['sections'].append(section_report)
                registration = [{'name': display(p['NAME']), 'memberId': str(p['ID']).strip(),
                                 'rating': int(p['RATING']), 'state': p['STATE'].strip(), 'reportName': p['NAME'].strip(),
                                 'checkedIn': True} for p in players]
                # Only a real US Chess ID identifies a person across rows and
                # sections; blank IDs are always separate people.
                known = lambda p: p['memberId'] and p['memberId'] in seen_members
                fresh = [p for p in registration if not known(p)]
                new_entries = client.call('add_players', players=fresh)['added'] if fresh else []
                assert len(new_entries) == len(fresh)
                fresh_entries = iter(new_entries)
                section = client.call('create_section', name=name, players=[],
                                      format='quad' if bool(settings['R_ROBIN']) and len(players) == 4 else 'swiss',
                                      plannedRounds=rounds, boardStart=max(1, int(settings['1ST_BD'])),
                                      doubleGames=double, timeControl=source_section['S_TIMECTL'],
                                      sideGames='side game' in name.lower())['section']
                ids = {}
                for i, p in enumerate(registration, 1):
                    member = p['memberId']
                    if known(p):
                        entry = client.call('add_section_entry', playerId=seen_members[member], sectionId=section['id'])['entry']
                        client.call('update_player', playerId=entry['id'], **p)
                    else:
                        entry = next(fresh_entries)
                        client.call('move_players', players=[entry['id']], sectionId=section['id'])
                        if member:
                            seen_members[member] = entry['id']
                    ids[i] = entry['id']
                rows = {int(row['PLAYER']): row for row in results}
                source_to_name = {i: display(p['NAME']) for i, p in enumerate(players, 1)}
                expected_scores = {ids[i]: int(float(players[i - 1]['SCORE'])) for i in ids}
                if double:
                    report['warnings'].append(f'{name}: double-game snapshots store aggregate match scores. Per-leg results are an explicitly inferred realization; totals/opponents are verifiable, chronology is not.')
                for r in range(1, rounds + 1):
                    games, byes, scores, used = [], [], [], set()
                    issue = None
                    for i, row in rows.items():
                        if i in used:
                            continue
                        opponent = int(row.get(f'OP{r}', 0))
                        code = str(row.get(f'RES_CH{r}', '')).strip('\0 ')
                        points = int(row.get(f'RES{r}', 0))
                        if opponent <= 0:
                            byes.append({'player': ids[i], 'points': points,
                                         'reason': f'SwissSys {code or "unplayed"}; {path.name} round {r}', 'allocated': code == 'B'})
                            used.add(i)
                            continue
                        other = rows[opponent]
                        reciprocal = int(other.get(f'OP{r}', 0))
                        other_points = int(other.get(f'RES{r}', 0))
                        if reciprocal != i or points + other_points != (4 if double else 2):
                            issue = f'Round {r}: nonreciprocal or noncomplementary source results for {source_to_name[i]} / {source_to_name[opponent]} ({code}, {points}, opponent back-reference {reciprocal}, {other_points}). No result invented.'
                            break
                        color = int(row.get(f'CLR{r}', 0))
                        white, black = (i, opponent) if color >= 0 else (opponent, i)
                        if color not in (-1, 1):
                            report['warnings'].append(f'{name} round {r}: unplayed forfeit has no color; assigned a display orientation only.')
                        white_points = int(rows[white][f'RES{r}'])
                        white_code = str(rows[white][f'RES_CH{r}'])
                        # Board history is unreliable in SRR files; use a stable section board range.
                        board = section['boardStart'] + len(games) // (2 if double else 1)
                        games.append({'white': ids[white], 'black': ids[black], 'board': board, 'leg': 1})
                        if double:
                            first, second = {0: (0, 0), 1: (1, 0), 2: (2, 0), 3: (2, 1), 4: (2, 2)}[white_points]
                            # Keep forfeits as forfeits in both legs, never as played games.
                            forfeit = white_code if white_code in ('X', 'F') else ''
                            scores.append(outcome(first, forfeit))
                            games.append({'white': ids[black], 'black': ids[white], 'board': board, 'leg': 2})
                            scores.append(outcome(2 - second, forfeit))
                        else:
                            scores.append(outcome(white_points, white_code))
                        used.update([i, opponent])
                    if issue:
                        section_report['blocked'] = issue
                        break
                    try:
                        client.call('post_manual_round', sectionId=section['id'], games=games, byes=byes,
                                    reason=f'Archive replay from {path.name}; ' + ('aggregate double-game realization, per-leg chronology unknown' if double else 'opponents/colors/results preserved'))
                        current = next(s for s in client.call('get_event')['sections'] if s['id'] == section['id'])
                        if current['rounds'][-1]['games']:
                            client.call('start_round', sectionId=section['id'])
                        for game, score in zip(current['rounds'][-1]['games'], scores):
                            client.call('record_result', gameId=game['id'], outcome=score, reason=f'Source {path.name}, round {r}')
                        section_report['completedRounds'] = r
                    except RuntimeError as error:
                        section_report['blocked'] = str(error)
                        break
                actual_section = next(s for s in client.call('standings')['sections'] if s['id'] == section['id'])
                actual = {r['playerId']: r for r in actual_section['rows']}
                section_report['nativeScoreMatches'] = sum(actual[pid]['points'] == score for pid, score in expected_scores.items())
                section_report['nativeScoreDifferences'] = [
                    {'name': actual[pid]['name'], 'expected': score / 2, 'actual': actual[pid]['points'] / 2}
                    for pid, score in expected_scores.items() if actual[pid]['points'] != score]
                by_name = {normalized(display(p['NAME'])): i for i, p in enumerate(players, 1)}
                actual_event_section = next(s for s in client.call('get_event')['sections'] if s['id'] == section['id'])
                for table in [t for t in html if t['section'].lower() == name.lower()]:
                    checks = {'file': table['path'], 'section': name, 'matched': 0, 'differences': [], 'roundCellsChecked': 0}
                    for row in table['rows']:
                        native_i = by_name.get(normalized(row.get('Name', '')))
                        if native_i is None:
                            checks['differences'].append({'name': row.get('Name'), 'issue': 'No unique native identity match'})
                            continue
                        nr = rows[native_i]
                        columns = [k for k in row if k.startswith('Rd ')]
                        # Compare the same checkpoint, not an early HTML total with the final total.
                        expected_html = float(row['Tot'])
                        native_total = sum(float(nr.get(f'RES{int(k.split()[1])}', 0)) for k in columns) / 2
                        checkpoint = max(int(k.split()[1]) for k in columns)
                        pid = ids[native_i]
                        replay_halves = 0
                        values = {'whiteWin': (2, 0), 'draw': (1, 1), 'blackWin': (0, 2), 'whiteForfeit': (2, 0), 'blackForfeit': (0, 2)}
                        for actual_round in actual_event_section['rounds'][:checkpoint]:
                            replay_halves += sum(b['points'] for b in actual_round['byes'] if b['player'] == pid)
                            for game in actual_round['games']:
                                ws, bs = values.get(game['outcome'], (0, 0))
                                replay_halves += ws if game['white'] == pid else bs if game['black'] == pid else 0
                        if expected_html != replay_halves / 2 or checkpoint > section_report['completedRounds']:
                            checks['differences'].append({'name': row['Name'], 'html': expected_html, 'meowCheckpoint': replay_halves / 2,
                                'nativeCheckpoint': native_total, 'incompleteReplay': checkpoint > section_report['completedRounds']})
                        else:
                            checks['matched'] += 1
                        for col in columns:
                            cell = row[col]
                            match = re.fullmatch(r'([WDLFX]+)(\d+)', cell)
                            if not match:
                                continue
                            round_no = int(col.split()[1])
                            other_html = next((p for p in table['rows'] if p.get('#') == match[2]), None)
                            op = int(nr.get(f'OP{round_no}', 0))
                            checks['roundCellsChecked'] += 1
                            if other_html is None or op <= 0 or normalized(other_html['Name']) != normalized(source_to_name[op]):
                                checks['differences'].append({'name': row['Name'], 'round': round_no, 'htmlCell': cell, 'issue': 'Opponent mismatch'})
                    report['htmlComparisons'].append(checks)
            report['completeReplay'] = all(s['completedRounds'] == s['plannedRounds'] for s in report['sections'])
            if not report['completeReplay']:
                client.call('update_event', notes=metadata['notes'] + ' INCOMPLETE REPLAY; inspect comparison.json before using any output.')
            report['export'] = client.call('export_event', directory=f'{slug}-export')
            report['wallchartComparisons'] = check_wallcharts(folder, Path(report['export']['directory']))
            report['dbfComparison'] = compare_dbfs(folder, Path(report['export']['directory']))
            # A separate section package is an explicit scope, never a preflight bypass.
            report['sectionExports'] = []
            state = client.call('get_event')
            for section_report in report['sections']:
                if section_report['completedRounds'] != section_report['plannedRounds']:
                    continue
                section = next(s for s in state['sections'] if s['name'] == section_report['name'])
                subslug = re.sub(r'[^a-z0-9]+', '-', section['name'].lower()).strip('-')
                exported = client.call('export_event', directory=f'{slug}-section-{subslug}', sectionId=section['id'])
                report['sectionExports'].append({'section': section['name'], 'export': exported,
                    'comparison': compare_dbfs(folder, Path(exported['directory']), section['name'])})
            client.call('close_event')
            reopened = client.call('open_event', path=f'{slug}.meow')
            report['reopenedRevision'] = reopened['revision']
        finally:
            client.close()
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'source': str(args.source), 'events': [],
              'emptyHtml': [str(p.relative_to(args.source)) for p in args.source.rglob('*.html') if not p.stat().st_size],
              'unrehearsedWithoutDbf': [p.name for p in args.source.iterdir() if p.is_dir() and not (p / 'thexport.dbf').exists()]}
    for folder in sorted(args.source.iterdir()):
        if not (folder / 'thexport.dbf').exists():
            continue
        print('Rehearsing', folder.name, flush=True)
        try:
            result = rehearse(folder, args.output)
            report['events'].append(result)
            print(' ', [(s['name'], s['completedRounds'], s.get('blocked')) for s in result['sections']], flush=True)
        except Exception as error:
            report['events'].append({'event': folder.name, 'failed': str(error)})
            print(' FAILED', error, flush=True)
        (args.output / 'comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(args.output / 'comparison.json')
    failed = [e['event'] for e in report['events'] if 'failed' in e]
    if failed:
        sys.exit(f'FAILED: {len(failed)} of {len(report["events"])} events: {", ".join(failed)}')


if __name__ == '__main__':
    main()
