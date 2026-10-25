# Implementation and verification

This file owns implementation status. The other planning documents describe the
product target; a requirement in those documents is not evidence that it shipped.

The repository now contains a Flutter desktop application, with Windows, macOS and
Linux runners. The tested scope and remaining gates below must accompany any demo.

## Architecture

- `lib/domain`: immutable event values, structural invariants, exact half-point
  scoring, quad/circle schedules, and bounded score-Swiss proposals. No Flutter,
  database, filesystem or HTTP imports.
- `lib/application`: command owner and event repository contract. Mutations commit
  before notifying UI; pairing runs in an isolate against an immutable revision.
- `lib/infrastructure`: relational SQLite persistence, import parser, PDF/CSV/text
  renderers, strict 2C DBF encoder and injectable authenticated ratings adapter.
- `lib/ui`: event library/workspace, player roster by section with standings
  and read-only round results, Rounds page score boxes, reports, event side panel, identity review and reusable form/confirmation controls.

Each event is a `.meow` SQLite database. Event metadata, entrants, membership,
sections, rounds, games and byes have separate tables. One writer holds the file;
foreign keys, FULL synchronous WAL transactions and revision checks protect saves.
The audit remains in the file and also logs every move through history. Each
command also saves a compressed full snapshot as a node in a history tree
(`node` table, schema version 4): Back/Forward (Ctrl+Z, Ctrl+Shift+Z/Ctrl+Y)
walk the current line, and the History panel (Ctrl+H) draws the tree, describes
each step and restores any node. Going back and then changing something starts a
branch; the old line stays restorable. Moving still advances the revision, so
proposals made against the left state stay stale. A move that removes a played
round, clears a round start or reverts more than one result asks first; single
result undo does not. Version 1 files start their graph at their current state.
This is not an event-sourced architecture. Newer schemas are refused unchanged.

Backups use SQLite `VACUUM INTO` followed by an integrity check. A secondary copy
recovers its explicitly recorded revision, not later edits saved only on the first
laptop. Copying a live main database file without its WAL is unsupported. Use Save
independent copy, Back up now, or close the app before ordinary file copying.
API keys use the OS credential store and never enter event files or reports.

## Available workflows

Create/open/reopen local events; synthetic practice events and independent practice
copies; CSV/TSV file import or paste with preview and rejected-row repair;
walk-up editing and checkbox moves between sections; private notes, byes, withdrawal/reinstatement; deterministic quad
partition and individual Swiss/RR sections; score-Swiss proposals in a background
isolate; batch posting with revision guards; separate actual round start with
explicitly assumed finish estimates; manual unstarted pairing edits; Swiss-Sys style per-player score boxes on the Rounds page (1/0/5, W/L/D aliases,
+/− forfeits; the opponent's box fills in) with repeat suppression and advance after commit; forfeit shortcuts and optional withdrawal; historical
corrections with reasons; separate TD-authorized temporary pairing assumptions;
undo/history; current rounds across sections; class-filtered standings, early RR
withdrawal prize projection and crosstable; PDF packet preview/printing, CSV and
strict ASCII export;
independent backup/reopen; same-progress section combination with preserved history;
exact-ID authenticated provider review with stale-response rejection.

### Clearer tournament-day workspace

Players and Rounds have a permanent section sidebar. Search names without needing
spaces (`quad12`), or use the section's ordinal (`section2`). Ctrl+J focuses this
search; Enter opens the first match. The sidebar shows player counts before play
and current-round missing-result counts during play. Reports have their own
**Include sections** selector for print, CSV and text output; the rating package
always covers the entire event and is labelled accordingly.

Players is a read-only crosstable with opponent references (`W37`, `D10`, `L5`),
using stable event roster numbers shown in the # column, independent of sort and
search. Byes use `B` plus their points; `F` suffixes mark forfeits. Edit requested
byes in player details, where **None** removes a request. IDs and tiebreaks are
optional under **View**, alongside the advanced standings filters. Imports and
spreadsheet paste live in the menu beside **+ Add player**. Bulk actions only
appear when players are selected.

Rounds opens a single section by default. Its full-width table has larger names
and score boxes, without ratings. Search by player or exact board number. The
row menu provides mouse entry and **Still playing / clear result**, which returns
both boxes to blank. Keyboard 1/0/5 entry and Delete continue to work. The player
details header and close button stay visible while its contents scroll.

Select partners and choose **Assign team** to record a shared mixed-doubles team
name, or edit a player's team in their details. Reports → Team standings totals
individual competition scores per section, with
a selectable number of scorers (default best four, or all). Equal totals share
places. The report lists counted and uncounted entries and its full policy.
It does not implement team-match pairings or establish prize eligibility.
Select two players and choose **Do not pair together** for sibling/other requests;
player details also add and remove these requests. Swiss proposals respect them,
and impossible requests report a conflict. Quads/round robins check the remaining schedule before posting and report a conflict
when it requires that meeting, so the TD can separate the
players or remove the request. Requests preserve posted games and are checked
when posting new or replacing unstarted pairings. Teams and requests persist in
player JSON and participate in undo, redo and backups; older records default to
no team and no requests.

A Swiss proposal is labelled `score-swiss-pilot-v2`. Its priorities include score
proximity, upper/lower-half preference, non-repeat opponents, float history,
color allocation and eligible byes. Same-score color improvements use disjoint
transpositions within 80/200 rating-point limits. Repeated colors or exceptional
byes produce explicit warnings before posting. It is **not a qualified US Chess Swiss engine**.
Never promote the pilot to that claim without the rule-linked fixtures in DELIVERY.

Section settings include exact half-point win/draw/played-loss/allocated-bye
scoring, four standings tiebreak orders, a recorded first-board top-seed color,
and explicit per-player/per-round pairing-only acceleration. Scoring and pairing
setup are fixed after posting; history can return to before round one. Reports
identify the selected scoring and tiebreak order. Actual game outcomes remain
independent of competition points. Files use schema 4 so older builds cannot
silently drop these policies; versions 1/2 load with standard defaults.

Reports → Pairing checklist and replay check shows saved Swiss inputs, color
history, due colors, floats, bye eligibility, exclusions and assignments. Replay
checks compare with the original inputs, including double-game legs, and identify
manual deviations. They do not certify rules or rewrite earlier inputs after a
correction. Older rounds explicitly have no replay evidence. Current next-round
inputs and pairing failures can also be inspected. The welcome screen's Generate
a practice tournament accepts a seed, field size, rounds, draw/forfeit rates and
withdrawal rate; generation runs outside the UI thread, retains a partial event
with a reason if pairing becomes impossible, and always marks it as practice.

These features were implemented independently in Dart. BBP is neither a dependency
nor an embedded/copied engine. FIDE Dutch/Burstein and TRF interchange remain outside
this US Chess-focused implementation.

The DBF writer follows the archived 2C field layout and 2025 character-field
correction. Packages are explicitly **unverified validation packages**, not accepted
rating reports. Only completed, same-round-count, single-game sections without
post-play transitions are enabled. All three files publish as a new directory with
a manifest; unsupported encodings fail rather than fabricate data. Practice events
cannot export rating packages, including after undo.

The rating system is derived from the event time control under rule 5C (total
= every control's minutes + delay/increment seconds; Regular > 65, Dual 30–65,
Quick 11–29, Blitz 5–10), not chosen by hand. 2C has no Blitz code, so Blitz is
blocked. `S_TIMECTL` is written as `Game/60 d/5` or `40/90, SD/30 inc/30`.
Names go out as `LAST, FIRST` in capitals with accents folded to ASCII; a
per-player "Name on rating report" overrides the derivation, and a US Chess
lookup can fill it and the player's state. City, state, ZIP and event type
(`S_SCH_LVL`) are saved with the event on the Reports page; multi-day events
have a last day. Affiliate IDs must be `A` + seven digits. `H_OTHER_TD` uses the
published 255-character width and is always empty. The preflight in
`dbf_export.dart` lists every problem before any file
is written; see `research/notes/US_CHESS_REPORTING.md` for sources.

Export publication now decodes the actual written bytes with a separate reader,
checking the 2C schema, padding, record counts, references and each source result
before renaming the staging directory. The package includes `validation.json`
and SHA-256 hashes in its manifest. The Reports page can run the same local
inspection without saving files. Missing player-round assignments, stray game
legs and byes over one point are refused instead of becoming misleading results.
The independent Python/dbfread verifier remains a separate test implementation.
BBP outputs TRF, not US Chess DBF; it provides no US Chess acceptance reference.
Passing either local reader is not evidence of MUIR acceptance.

## Still required before the planned first release

- Qualified US Chess pairing policy and adversarial TD-reviewed event replays.
- Accepted current DBF fixtures, external portal validation, Blitz/double-game and
  mixed-round-count mappings, and post-play transfer reporting attribution.
- Authenticated provider success/expiry/latest-rating evidence; batch rating review,
  name search and explicit per-category frozen rating observations.
- Broader rule-specific withdrawal and transfer prize policies, comprehensive
  eligibility rules and automated prize allocation. Eligibility overrides,
  templates, structured ruling/appeal records, explicit
  effective-round withdrawal and late-entry scoring also remain release work.
- Full per-section workspace/draft restoration, all-round reciprocal player matrix,
  advanced accessibility and large-field performance qualification. Import has
  header inference, not a custom column-mapping editor. Class filters currently
  apply to the Players page standings view, not printable prize-allocation reports.
- Windows/macOS native build, printing, signing and recovery qualification; real
  printer testing on each OS and working-TD usability rehearsal.
- Later tranches: team matches, bughouse, native SwissSys interchange, FIDE and hosted
  services. They remain in the product plan and are not represented by empty screens.

The application is a development pilot. It must not be described as having passed
all P0 requirements or full SwissSys parity.

## Checks

Run `scripts/ci.sh analyze`, `scripts/ci.sh lint`, `scripts/ci.sh test`, and
`scripts/ci.sh integration` on this workstation. The wrapper uses the shared bounded
runner. Native integration uses a private Xvfb display, session bus and temporary
synthetic event files. It writes screenshots and a PDF to ignored `artifacts/`.

Unit tests cover complete quad and mixed Swiss/quad days, round-robin coverage,
score conservation, double games, byes, stale proposals, corrections, transitions,
board collisions, database reopening, independent backup recovery, writer exclusion,
failed backups, newer-schema refusal, CSV/TSV edge cases, privacy boundaries, DBF
bytes and API failures. Widget tests exercise instant result entry, held keys,
missing-only traversal and typing in non-result fields.


## Backend review — September 29, 2026

A review of domain, application and storage code found and fixed these defects,
each now covered by a test that fails without the fix:

- Moving some players out of a started round robin recomputed its schedule from
  the new roster and re-paired earlier opponents. Such partial moves are refused.
- Import silently skipped a second member with the same name but a different ID.
  A member ID is now identity; `importPlayers` returns the skipped count.
- Marking a game unfinished or disputed discarded its TD pairing assumption.
- Undoing “Start round” committed a revision that changed nothing; it is refused.
  A practice copy can no longer undo into the original event's history, which
  restored the original backup folder.
- A failed command in a transaction SQLite had already rolled back reported
  “no transaction is active” instead of its cause.
- Backups are built and verified under a temporary name, synced, then renamed.
- Event dates are validated by the domain, not only the settings dialog.
- Repeated identical commands create no revision or audit row.
- Locked and non-database files report plain messages, not SQLite codes.

Swiss colors now equalize, then alternate. The pilot still chooses opponents
before colors: a 64-player simulation had repeated three-same-color runs.

Verified: analysis and lint clean, 70 unit/widget tests (41 before), both native
Linux integration tests, and `scripts/verify_recovery.py`. New tests include
seeded property simulations of 40 Swiss events with withdrawals, bye requests
and forfeits; per-command close/reopen of a 22-player day; and injected
automatic rollback.

## Verified on this workstation — September 28, 2026

- Flutter analysis: no issues. Architecture/documentation lint: passed.
- All 41 unit/widget tests passed across domain, storage, imports, reports, API
  and UI, including refusal to modify an unrelated SQLite file.
- Two native Linux integration tests passed: practice creation from the event
  library, close/reopen, and a tournament-day rehearsal with 22 synthetic entrants, four quads plus a
  six-player Swiss, three posted rounds and 33 keyboard-entered results; five-page
  PDF, closed-file reopen and independent-backup recovery passed.
- Large-text widget check: overview and results at 200%, 1280×900, no overflow.
- Independent `dbfread 2.0.7` decoded all three 2C files and checked event references,
  entrant identities, reciprocal results and colors. This is format evidence only.
- Abrupt termination: killed a synthetic writer after acknowledgment of revision 5;
  SQLite recovered complete revision 5, all 120 players, matching audit and valid
  foreign keys. A separate injected mid-transaction failure test verified rollback.
- `flutter build linux --release`: passed. Release bundle is generated under
  `build/linux/x64/release/bundle/`; it depends on the host's native libraries.
- Inspected native overview/results/standings screenshots and the rendered PDF.
  Generated evidence is local in ignored `artifacts/`, containing synthetic data.

Reproduce the independent checks with:

```sh
scripts/ci.sh with -- python3 scripts/verify_recovery.py
MEOW_EXPORT_FIXTURES=1 scripts/ci.sh test test/infrastructure/import_reports_test.dart
python3 -m venv artifacts/validation-env
artifacts/validation-env/bin/pip install dbfread==2.0.7
artifacts/validation-env/bin/python scripts/verify_dbf.py artifacts/dbf
```

Initial checks exposed and led to fixes for immediate-key focus loss, next-round
scroll position, large-text overflow, native build dependencies and an initial
crash-test fixture compilation error. No failing check was treated as a pass.
Windows/macOS, authenticated production API behavior, portal acceptance, physical
printing, actual power loss/disk failure and large-field performance were **not**
qualified by these Linux checks.


## Tournament setup and registration additions

Section settings → Swiss acceleration offers top-half presets: +1 virtual
pairing point for round one, or rounds one and two, then zero. These require
standard scoring, single games, at least four active players, and a later
unaccelerated round. A preview lists the selected players before the schedule is
saved. Rating, name, and entry ID determine order; the top half is rounded down.
Withdrawn entries are excluded; requested byes do not change initial ranking.
The stored player-specific schedule is frozen, not automatically regenerated
when ratings or the roster change. Review it before round one after late entries.
Custom schedules remain available. Neither preset claims FIDE Baku or complete
US Chess accelerated-pairing conformance.

Player details → More player details edits club, school, grade, chess title,
FIDE ID, reference FIDE rating, federation, and private birth date. These optional
values survive save/reopen and history; old files default them to blank/unrated.
The main Rating field still controls pairings and US Chess reports. Federation
validation checks three-letter syntax only, not federation membership. Titles
are recorded text, not verified credentials. Birth dates are not printed or
included in public standings/team reports or US Chess DBF files.

CSV/TSV registration accepts Club and Team as separate columns, plus School,
Grade, Title, FIDE ID, FIDE Rating, Federation, and Birth Date (YYYY-MM-DD).
Malformed optional IDs, ratings, federations, and dates are rejected in the import
preview. Team is now imported as membership, instead of being mistaken for Club.

Team standings uses the current team labels, matched case-insensitively after
trimming spaces. It includes earned points of withdrawn members, awarded byes,
and forfeits; excludes house players; counts a re-entered person only once at
their best score; and gives missing scorers zero. It operates separately for each
section and exports text/CSV with the chosen policy and event revision. Changing
the report's scorer limit does not alter the tournament. It is a report option,
not a saved prize rule. Editing membership can change historical totals.

See [the BBP feature comparison](BBP_COMPARISON.md) for remaining gaps.
