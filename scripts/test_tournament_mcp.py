#!/usr/bin/env python3
"""Protocol and real controller/storage tests against the compiled MCP process."""
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

from toolchain import dart_executable

ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, root, log=None):
        self.process = subprocess.Popen(
            [dart_executable(), str(ROOT / 'scripts/tournament_mcp.dart'), str(root)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding='utf-8', bufsize=1, cwd=root)
        self.counter = 0
        self.revision = None
        self.log = log
        self.rpc('initialize', {'protocolVersion': '2025-06-18',
                               'capabilities': {}, 'clientInfo': {'name': 'rehearsal', 'version': '1'}})
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        self.definitions = {t['name']: t for t in self.rpc('tools/list')['tools']}

    def send(self, request):
        self.process.stdin.write(json.dumps(request) + '\n')
        self.process.stdin.flush()

    def rpc(self, method, params=None):
        self.counter += 1
        request = {'jsonrpc': '2.0', 'id': self.counter, 'method': method, 'params': params or {}}
        self.send(request)
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError('MCP exited: ' + self.process.stderr.read())
        response = json.loads(line)  # Deliberately reject stdout build logs.
        if response.get('id') != self.counter:
            raise RuntimeError(f'Response for another request: {response}')
        if self.log:
            self.log.write(json.dumps({'request': request, 'response': response}) + '\n')
        if 'error' in response:
            raise RuntimeError(response['error'])
        return response['result']

    def call(self, tool_name, **args):
        if 'expectedRevision' in self.definitions[tool_name]['inputSchema']['required']:
            args.setdefault('expectedRevision', self.revision)
        response = self.rpc('tools/call', {'name': tool_name, 'arguments': args})
        if response.get('isError'):
            raise RuntimeError(response['content'][0]['text'])
        value = response['structuredContent']
        self.revision = value.get('revision', self.revision)
        return value

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        error = self.process.stderr.read()
        self.process.stdout.close()
        self.process.stderr.close()
        if self.process.returncode != 0:
            raise RuntimeError(f'MCP exited with {self.process.returncode}: {error}')


def read_dbf(path):
    data = path.read_bytes()
    count, header, length = struct.unpack_from('<IHH', data, 4)
    fields, offset = [], 1
    for pos in range(32, header - 1, 32):
        fields.append((data[pos:pos + 11].split(b'\0')[0].decode('ascii'), offset, data[pos + 16]))
        offset += data[pos + 16]
    return [{name: data[header + row * length + at:header + row * length + at + width].decode('ascii').strip()
             for name, at, width in fields} for row in range(count)]


class TournamentMcpTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="meow chess café ")
        self.root = Path(self.temp.name)
        self.client = Client(self.root)

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def create(self, players=4, double=False):
        c = self.client
        c.call('create_event', path='sample.meow', name='Protocol rehearsal', date='2026-03-07')
        added = c.call('add_players', players=[{'name': f'Player {i}', 'rating': 1800 - i * 100} for i in range(players)])['added']
        s = c.call('create_section', name='Open', players=[p['id'] for p in added],
                   format='swiss' if players != 4 else 'quad', plannedRounds=3,
                   boardStart=1, doubleGames=double)['section']
        return s

    def test_play_reopen_export_and_history(self):
        s = self.create(players=7)
        c = self.client
        for _ in range(3):
            proposal = c.call('propose_pairings', sectionId=s['id'])
            self.assertFalse(proposal['issues'])
            c.call('post_pairings', proposalId=proposal['proposalId'])
            c.call('start_round', sectionId=s['id'])
            for g in proposal['rounds'][s['id']]['games']:
                c.call('record_result', gameId=g['id'], outcome='draw')
        event = c.call('get_event')
        self.assertEqual(len(list(g for r in event['sections'][0]['rounds'] for g in r['games'])), 9)
        self.assertEqual(sum(row['points'] for row in c.call('standings')['sections'][0]['rows']), 24)
        # A single-result undo is allowed by the GUI history policy.
        c.call('undo')
        c.call('redo')
        report = c.call('export_event', directory='report')
        self.assertIn('Practice copies cannot produce rating reports.', report['dbfIssues'])
        self.assertTrue((self.root / 'report/standings.csv').exists())
        c.call('backup_event', path='copy.meow')
        c.call('close_event')
        reopened = c.call('open_event', path='copy.meow')
        self.assertEqual(reopened['sections'], event['sections'])

    def test_stale_and_malformed_requests_are_atomic(self):
        s = self.create()
        c = self.client
        proposal = c.call('propose_pairings')
        c.call('update_event', notes='Changed after preview')
        before = c.call('get_event')
        with self.assertRaisesRegex(RuntimeError, 'changed while pairing'):
            c.call('post_pairings', proposalId=proposal['proposalId'])
        with self.assertRaisesRegex(RuntimeError, 'Stale revision'):
            c.call('update_event', name='Lost update', expectedRevision=1)
        with self.assertRaisesRegex(RuntimeError, 'unknown field'):
            c.call('update_event', surprise=True)
        with self.assertRaises(RuntimeError):
            c.call('post_manual_round', sectionId=s['id'], reason='Invalid omission', games=[], byes=[])
        with self.assertRaises(RuntimeError):
            c.call('add_players', players=[{'name': 'Valid'}, {'name': 'Invalid', 'rating': -1}])
        self.assertEqual(before, c.call('get_event'))

    def test_path_confinement_and_overwrites(self):
        c = self.client
        with self.assertRaisesRegex(RuntimeError, 'inside'):
            c.call('create_event', path='../escape.meow', name='Escape', date='2026-03-07')
        with tempfile.TemporaryDirectory() as outside:
            (self.root / 'link').symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, 'inside'):
                c.call('create_event', path='link/escape.meow', name='Escape', date='2026-03-07')
        self.create()
        c.call('export_event', directory='report')
        with self.assertRaisesRegex(RuntimeError, 'already exists'):
            c.call('export_event', directory='report')
        c.call('close_event')
        with self.assertRaisesRegex(RuntimeError, 'already exists'):
            c.call('create_event', path='sample.meow', name='Overwrite', date='2026-03-07')
        self.assertEqual(c.call('open_event', path='sample.meow')['name'], 'Protocol rehearsal')

    def test_forfeit_then_side_game_and_scoped_export(self):
        s = self.create()
        c = self.client
        q = c.call('propose_pairings')
        c.call('post_pairings', proposalId=q['proposalId'])
        game = q['rounds'][s['id']]['games'][0]
        before = c.call('get_event')
        with self.assertRaises(RuntimeError):
            c.call('pair_side_game', white=game['white'], black=game['black'])
        self.assertEqual(before, c.call('get_event'))
        c.call('record_result', gameId=game['id'], outcome='whiteForfeit')
        side_id = c.call('pair_side_game', white=game['white'], black=game['black'])['sectionId']
        event = c.call('get_event')
        side = next(s for s in event['sections'] if s['id'] == side_id)
        self.assertTrue(side['sideGames'])
        self.assertEqual(len(side['players']), 2)
        self.assertFalse(set(side['players']) & set(event['sections'][0]['players']))
        result = c.call('export_event', directory='side-only', sectionId=side_id)
        saved = json.loads((Path(result['directory']) / 'event.json').read_text(encoding='utf-8'))
        self.assertEqual([s['id'] for s in saved['sections']], [side_id])

    def test_double_games_and_manual_results(self):
        s = self.create(double=True)
        c = self.client
        proposal = c.call('propose_pairings')
        c.call('post_pairings', proposalId=proposal['proposalId'])
        games = proposal['rounds'][s['id']]['games']
        self.assertEqual(len(games), 4)
        for g in games:
            c.call('record_result', gameId=g['id'], outcome='whiteWin')
        self.assertEqual([r['points'] for r in c.call('standings')['sections'][0]['rows']], [2] * 4)
        self.assertFalse([i for i in c.call('rating_preflight')['issues'] if 'Double' in i])

    def test_rated_double_blitz_exports_each_game_and_credits_tds(self):
        c = self.client
        c.call('create_event', path='blitz.meow', name='Synthetic double blitz', date='2026-03-07',
               practice=False, timeControl='G/5;d0', tdId='90000001', assistantTdId='90000002',
               otherTdIds='90000003, 90000004', affiliateId='A9999999', city='Boston', state='MA',
               zip='02116', level='N')
        added = c.call('add_players', players=[
            {'name': f'Player {i}', 'rating': 1800 - i * 100, 'memberId': f'9100000{i}',
             'state': '' if i == 3 else 'MA'} for i in range(4)])['added']
        s = c.call('create_section', name='Open', players=[p['id'] for p in added], format='swiss',
                   plannedRounds=1, boardStart=1, doubleGames=True)['section']
        proposal = c.call('propose_pairings', sectionId=s['id'])
        c.call('post_pairings', proposalId=proposal['proposalId'])
        c.call('start_round', sectionId=s['id'])
        for g in proposal['rounds'][s['id']]['games']:
            c.call('record_result', gameId=g['id'], outcome='whiteWin')
        flight = c.call('rating_preflight')
        self.assertEqual(flight['issues'], [])
        self.assertTrue(any('State missing' in a for a in flight['advice']))
        result = c.call('export_event', directory='rated')
        folder = Path(result['directory'])
        self.assertEqual(result['dbfIssues'], [])
        self.assertEqual(sorted(p.name for p in self.root.iterdir() if 'partial' in p.name), [])
        manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['sections'][0]['reportedRounds'], 2)
        self.assertIn('UNVERIFIED', manifest['status'])
        header, = read_dbf(folder / 'THEXPORT.DBF')
        section, = read_dbf(folder / 'TSEXPORT.DBF')
        details = read_dbf(folder / 'TDEXPORT.DBF')
        self.assertEqual((header['H_EVENT_ID'], header['H_ATD_ID'], header['H_OTHER_TD']),
                         ('', '90000002', '90000003,90000004'))
        self.assertEqual((section['S_TOT_RNDS'], section['S_TIMECTL'], section['S_ATD_ID']),
                         ('2', 'G/5;d0', '90000002'))
        # Every player played both games of the double round, one per column.
        for row in details:
            self.assertRegex(row['D_RND01'], r'^[WL][1-4][WB]$')
            self.assertRegex(row['D_RND02'], r'^[WL][1-4][WB]$')
            self.assertNotEqual(row['D_RND01'][-1], row['D_RND02'][-1])

    def test_section_export_ignores_other_sections_moves(self):
        c = self.client
        c.call('create_event', path='moves.meow', name='Moves', date='2026-03-07')
        added = c.call('add_players', players=[{'name': f'Player {i}', 'rating': 1800 - i * 10} for i in range(8)])['added']
        ids = [p['id'] for p in added]
        a = c.call('create_section', name='A', players=ids[:4], format='swiss', plannedRounds=2, boardStart=1)['section']
        b = c.call('create_section', name='B', players=ids[4:], format='swiss', plannedRounds=2, boardStart=5)['section']
        for section in (a, b):
            proposal = c.call('propose_pairings', sectionId=section['id'])
            c.call('post_pairings', proposalId=proposal['proposalId'])
            c.call('start_round', sectionId=section['id'])
            for g in proposal['rounds'][section['id']]['games']:
                c.call('record_result', gameId=g['id'], outcome='draw')
        late = c.call('add_players', players=[{'name': 'Late entry', 'rating': 1500}])['added'][0]['id']
        c.call('move_players', players=[late], sectionId=a['id'], reason='Arrived for round two')
        moved = 'Players moved between sections after play started; this cannot be reported yet.'
        self.assertIn(moved, c.call('export_event', directory='a-only', sectionId=a['id'])['dbfIssues'])
        self.assertNotIn(moved, c.call('export_event', directory='b-only', sectionId=b['id'])['dbfIssues'])

    def test_metadata_is_validated_when_it_changes(self):
        s = self.create()
        c = self.client
        before = c.call('get_event')
        with self.assertRaisesRegex(RuntimeError, 'not in a form'):
            c.call('create_section', name='Bad', players=[], format='swiss', plannedRounds=1,
                   boardStart=1, timeControl='Game in 60')
        with self.assertRaisesRegex(RuntimeError, 'eight digits'):
            c.call('update_event', assistantTdId='123')
        with self.assertRaisesRegex(RuntimeError, 'Other TDs'):
            c.call('update_event', otherTdIds='12345678, 99')
        with self.assertRaisesRegex(RuntimeError, 'practice copy'):
            c.call('update_event', practice=False)
        with self.assertRaisesRegex(RuntimeError, 'No player has the ID'):
            c.call('update_player', playerId='nobody', name='Ghost')
        with self.assertRaisesRegex(RuntimeError, 'not in a form'):
            c.call('update_section', sectionId=s['id'], timeControl='sixty minutes')
        self.assertEqual(before, c.call('get_event'))
        # SwissSys's compact spelling is accepted and stored as entered.
        updated = c.call('update_section', sectionId=s['id'], timeControl='G90d5', name='Main')
        self.assertEqual((updated['section']['name'], updated['section']['timeControl']), ('Main', 'G90d5'))
        c.call('close_event')
        (self.root / 'dangling').symlink_to(self.root / 'missing-target')
        with self.assertRaisesRegex(RuntimeError, 'Broken symbolic link'):
            c.call('create_event', path='dangling/new.meow', name='Nope', date='2026-03-07')


class ProtocolErrorTest(unittest.TestCase):
    """Malformed input is answered and skipped; the session keeps serving."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='meow chess protocol ')
        self.process = subprocess.Popen(
            [dart_executable(), str(ROOT / 'scripts/tournament_mcp.dart'), self.temp.name],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=self.temp.name)

    def tearDown(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        error = self.process.stderr.read().decode('utf-8', 'replace')
        self.process.stdout.close()
        self.process.stderr.close()
        self.temp.cleanup()
        if self.process.returncode != 0:
            self.fail(f'MCP exited with {self.process.returncode}: {error}')

    def raw(self, data):
        self.process.stdin.write(data)
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            self.fail('MCP exited: ' + self.process.stderr.read().decode('utf-8', 'replace'))
        return json.loads(line)

    def request(self, request):
        return self.raw(json.dumps(request).encode('utf-8') + b'\n')

    def assertError(self, response, code, request_id=None):
        self.assertEqual(response.get('id'), request_id, response)
        self.assertEqual(response.get('error', {}).get('code'), code, response)

    def test_errors_are_answered_and_the_session_continues(self):
        rpc = {'jsonrpc': '2.0'}
        response = self.request({**rpc, 'id': 1, 'method': 'tools/list'})
        self.assertError(response, -32000, 1)
        self.assertEqual(response['error']['message'], 'Initialize first')
        self.assertError(self.request({**rpc, 'id': 2, 'method': 'tools/call',
                                       'params': {'name': 'get_event'}}), -32000, 2)
        self.assertIn('result', self.request({
            **rpc, 'id': 3, 'method': 'initialize',
            'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                       'clientInfo': {'name': 'protocol test', 'version': '1'}}}))
        # Invalid UTF-8 and invalid JSON are parse errors, not a dead server.
        self.assertError(self.raw(b'\xff\n'), -32700)
        self.assertError(self.raw(b'{"jsonrpc": "2.0", "id": 4, "method": "ping"\xff}\n'), -32700)
        self.assertError(self.raw(b'{not json\n'), -32700)
        # Valid JSON that is not a request object is an invalid request.
        self.assertError(self.raw(b'[1, 2]\n'), -32600)
        self.assertError(self.raw(b'42\n'), -32600)
        self.assertError(self.request({'id': 5, 'method': 'ping'}), -32600, 5)
        # An id that is neither a string nor a number is answered with null.
        self.assertError(self.request({**rpc, 'id': {'n': 6}, 'method': 'ping'}), -32600)
        self.assertError(self.request({**rpc, 'id': [7], 'method': 'ping'}), -32600)
        self.assertError(self.request({**rpc, 'id': 8, 'method': 'no/such/method'}), -32601, 8)
        self.assertError(self.request({**rpc, 'id': 9, 'method': 'tools/call', 'params': [1]}), -32602, 9)
        self.assertError(self.request({**rpc, 'id': 10, 'method': 'tools/call',
                                       'params': {'name': 7}}), -32602, 10)
        self.assertError(self.request({**rpc, 'id': 11, 'method': 'tools/call',
                                       'params': {'name': 'get_event', 'arguments': [1]}}), -32602, 11)
        # Blank lines get no response: the next answer belongs to the ping.
        self.assertEqual(self.raw(b'\n  \r\n\t\n' + json.dumps({**rpc, 'id': 12, 'method': 'ping'}).encode()
                                  + b'\r\n'), {'jsonrpc': '2.0', 'id': 12, 'result': {}})
        self.assertIn('tools', self.request({**rpc, 'id': 13, 'method': 'tools/list'})['result'])


if __name__ == '__main__':
    unittest.main()
