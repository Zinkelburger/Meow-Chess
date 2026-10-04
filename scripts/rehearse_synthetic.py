#!/usr/bin/env python3
"""Run generated quad, Swiss and double-game events through the stdio MCP server."""
import json
from pathlib import Path
import sys
from test_tournament_mcp import Client


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=False)
    summaries = []
    with (root / 'mcp-transcript.jsonl').open('w', encoding='utf-8') as log:
        c = Client(root, log)
        try:
            for label, count, double in [('quad', 4, False), ('swiss', 7, False), ('double', 5, True)]:
                c.call('create_event', path=f'{label}.meow', name=f'Synthetic {label} validation',
                       date='2026-03-07', timeControl='G/65 d10', practice=False,
                       tdId='99000000', affiliateId='A9900000', city='Test City', state='MA', zip='02111',
                       notes='SYNTHETIC TEST DATA ONLY. IDs and locations are invented test fixtures. DO NOT SUBMIT.')
                people = c.call('add_players', players=[{
                    'name': f'Synthetic Player {i+1}', 'memberId': str(99000001+i),
                    'rating': 2000-i*100, 'state': 'MA', 'checkedIn': True,
                } for i in range(count)])['added']
                if label == 'quad':
                    section = c.call('make_quads')['sections'][0]
                else:
                    section = c.call('create_section', name='Open', players=[p['id'] for p in people],
                                     format='swiss', plannedRounds=3, boardStart=1, doubleGames=double)['section']
                for r in range(1, 4):
                    q = c.call('propose_pairings', sectionId=section['id'])
                    assert not q['issues'], q
                    c.call('post_pairings', proposalId=q['proposalId'])
                    c.call('start_round', sectionId=section['id'])
                    for i, g in enumerate(q['rounds'][section['id']]['games']):
                        c.call('record_result', gameId=g['id'], outcome=['whiteWin', 'draw', 'blackWin'][(r+i)%3])
                e = c.call('get_event')
                summaries.append({'event': label, 'players': count,
                                  'rounds': len(e['sections'][0]['rounds']),
                                  'games': sum(len(r['games']) for r in e['sections'][0]['rounds']),
                                  'export': c.call('export_event', directory=f'{label}-export')})
                c.call('close_event')
        finally:
            c.close()
    (root / 'summary.json').write_text(json.dumps(summaries, indent=2), encoding='utf-8')
    print(json.dumps(summaries, indent=2))


if __name__ == '__main__':
    main()
