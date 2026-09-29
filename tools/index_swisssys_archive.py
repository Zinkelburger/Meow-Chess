#!/usr/bin/env python3
"""Generate coverage and a conservative, title-routed research checklist.

Routing is a triage suggestion, not a claim that a page is fully understood.
No page is automatically marked reviewed, specified, implemented or tested.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ROUTES = [
    (r'switch state and federation', 'R04', 'Player inspector'),
    (r'changing game results', 'P05 P07', 'Rounds / History'),
    (r'rules for pairing', 'F01 F05', 'Section rules'),
    (r'scholastic rating|ratings - overview', 'R06 R07', 'Ratings / section settings'),
    (r'^validate -', 'P02 R05', 'Validation (determine exact checks)'),
    (r'setting up the tournament|tournament setup and tools', 'E02 E03', 'Event / section settings'),
    (r'wrapping up', 'O01 O06', 'Reports / completion'),
    (r'^players menu$', 'R01 R04 R08', 'Players (menu index)'),
    (r'^reports menu$|^reporting$', 'O01 O06 O07', 'Reports (index)'),
    (r'^file menu$', 'E01 U03', 'Event menu (index)'),
    (r'^edit menu$|^edit commands$', 'R10 P07 U03', 'Editing (index)'),
    (r'^setup menu$|some options', 'E03 E04', 'Settings (index)'),
    (r'^view menu$|^options menu$|pairchart frequently', 'U02 P04', 'View / preferences (index)'),
    (r'error messages', 'U01 U03', 'Help / diagnostics'),
    (r'license|activation|register swisssys|unlocking|purchas|upgrade|install|requirements|version|home page|about|technical help', 'U04', 'Help / installation'),
    (r'quad', 'F02 X01', 'Players → Make quads'),
    (r'prize|rating range restrictions', 'S04 S06', 'Standings → Prizes'),
    (r'tiebreak', 'S02', 'Standings / section rules'),
    (r'fees', 'R13', 'Players / Reports → Fees'),
    (r'network', 'R12', 'Registration staging'),
    (r'merged|^merge -', 'E06 R09', 'Manage sections → Combine'),
    (r'side game', 'E07', 'Sections / Rounds'),
    (r'double.round', 'F04', 'Rounds / format'),
    (r'ladder', 'F06', 'Standings / format'),
    (r'round robin|crenshaw|lot numbers', 'F03', 'Rounds / format'),
    (r'accelerat|rating range', 'F05', 'Section rules'),
    (r'rollins|subtotal|small teams|number on a team', 'F09 S03', 'Teams / Standings'),
    (r'scheveningen|team match', 'F10', 'Teams / format'),
    (r'fixed.roster|board order|active team|game wins', 'F08', 'Teams / Rounds'),
    (r'team', 'F08 F09 F10 O04', 'Teams (classify exact model)'),
    (r'rating.*report|ratings reports|trf|uscf database file', 'O06 O07', 'Reports → Rating submission'),
    (r'fide norms', 'O07', 'Reports → Rating submission'),
    (r'bbp|fide.*mode|fide.only', 'F11', 'Section policy'),
    (r'backup|save|reopen|^open -|exit|undo|logging', 'E01 U03', 'Event / History'),
    (r'profile|link settings', 'E04 U05', 'Templates / settings'),
    (r'board.*number|board conflict|reserved board', 'E05', 'Event → Boards'),
    (r'board history', 'P08', 'Player inspector'),
    (r'pairing logic|integrity|problem summary', 'P02', 'Pairing review'),
    (r'adjusting pair|pairings setup|replacement player|vanilla', 'P03', 'Pairing review'),
    (r'previous round|correcting results|results editor', 'P07', 'Rounds → History'),
    (r'entering results|results entry|import results|clear selected results', 'P05 P06', 'Rounds'),
    (r'pair next|all sections|make pairings', 'P01', 'Rounds / Event'),
    (r'pair number|resort|name format|classes|unflag|tinker', 'R10', 'Players'),
    (r'withdraw|bye|inactive|late registration', 'R08 P06', 'Player inspector / Rounds'),
    (r'move player', 'R09', 'Players → Move'),
    (r'eligibility|expired memberships|membership', 'R05 O03', 'Players / Reports'),
    (r'import.*player|delimited|dtf|drag and drop', 'R01 R02', 'Players → Import'),
    (r'switch ratings|ratings.overview|estimated|provisional|post.event rating', 'R06 R07 S05', 'Ratings / Analysis'),
    (r'database|player search|fide player list|update players', 'R03 R06 R11', 'Club / Data sources'),
    (r'club', 'E08', 'Club directory'),
    (r'email|player messages', 'O09', 'Share / messages'),
    (r'internet|sync|chessroster|hosted|events page|online tournament', 'O08', 'Event → Share'),
    (r'print|preview|fonts|format|columns|page setup|wall chart|chart appearance', 'O01 O02 U02', 'Reports / view preferences'),
    (r'pgn|export|clipboard|^copy', 'O05', 'Reports → Export'),
    (r'certificate|board signs|label', 'O03', 'Reports'),
    (r'upsets|win stats', 'S05', 'Standings → Analysis'),
    (r'standings|scoring point', 'S01', 'Standings'),
    (r'section.*menu|section panels|section box|multi.section|tournament.at.a.glance', 'E02', 'Event / sections'),
    (r'tournament types|unrated', 'F01 F02 F03 F07 F08 F09 F10', 'Section format'),
    (r'register|registration|player roster|find player', 'R01 R04 R08', 'Players'),
    (r'pair chart|pairing list|view pairings|pairings', 'P01 P04', 'Rounds'),
    (r'language|display|environment|toolbar|multi.view|section panels', 'U02', 'Preferences'),
    (r'scratch pad', 'U01', 'Event notes'),
]


def route(title):
    for pattern, ids, home in ROUTES:
        if re.search(pattern, title, re.I):
            return [f'CAP-{value}' for value in ids.split()], home
    return ['CAP-U01'], 'Orientation / index / tutorial (check linked feature topics)'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--cache', type=Path, default=ROOT / 'research/local/swisssys-site')
    args = p.parse_args()
    coverage = json.loads((args.cache / 'coverage.json').read_text())
    nav = json.loads((ROOT / 'research/swisssys-navigation.json').read_text())
    pages = coverage['pages']
    rows = []
    for n in nav:
        r = pages[n['url']]
        assert r['status'] == 200, n['url']
        for field, hashfield in [('raw','sha256'),('text','text_sha256')]:
            assert hashlib.sha256((args.cache / r[field]).read_bytes()).hexdigest() == r[hashfield]
        ids, home = route(n['title'])
        rows.append(dict(source_id='SS-'+hashlib.sha256(n['url'].encode()).hexdigest()[:8],
            title=n['title'],url=n['url'],archive_status=200,sha256=r['sha256'],
            local_text='research/local/swisssys-site/'+r['text'],candidate_feature_ids=ids,
            proposed_home=home,exhaustive_extraction='pending',reference_app_test='not run'))
    public = {k:v for k,v in coverage.items() if k != 'pages'}
    public['pages'] = [{**r} for r in rows]
    (ROOT / 'research/swisssys-coverage.json').write_text(json.dumps(public,indent=2)+'\n')
    lines = ['# SwissSys page-by-page research checklist', '',
        'All 296 navigation/sitemap pages were archived with raw HTML, article text and hashes.',
        'This table is **research triage**, not an atomic feature inventory or a parity claim.',
        'Candidate IDs are title-based suggestions; open the article and map every behavior before marking extraction complete.',
        'Every row currently needs exhaustive feature extraction and reference-application verification.',
        'Focused reads and cross-cutting findings are recorded in the planning notes; that does not close an entire page.', '',
        'See [archive scope and exclusions](SWISSSYS_ARCHIVE.md) and [capability IDs](../docs/FULL_FEATURE_MAP.md).', '',
        '| Source ID | Page | Candidate IDs | Proposed home | Extraction |',
        '|---|---|---|---|---|']
    for r in rows:
        lines.append(f'| {r["source_id"]} | [{r["title"]}]({r["url"]}) | {", ".join(r["candidate_feature_ids"]) or "Unclassified"} | {r["proposed_home"]} | Pending |')
    lines += ['', '## Completing a row', '',
        'Read the entire cached article, follow relevant cross-references, and identify each independent behavior,',
        'option, exception, limit, file field and release-version caveat. Add acceptance cases to the feature',
        'specification, including counterexamples. Record explicit omissions and why they are out of scope.',
        'Mark only that review status complete; implementation and reference comparison stay separate.',
        'Release-note bug fixes should become regression fixtures even when no new menu item exists.', '']
    (ROOT / 'research/SWISSSYS_TOPIC_LEDGER.md').write_text('\n'.join(lines))
    print(f'Indexed {len(rows)} pages; verified {len(rows)*2} raw/text hashes; {sum(not r["candidate_feature_ids"] for r in rows)} need initial classification.')


if __name__ == '__main__':
    main()
