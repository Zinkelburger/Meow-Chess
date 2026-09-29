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
- `lib/ui`: event library/workspace, registration/check-in, keyboard results,
  standings, reports, identity review and reusable form/confirmation controls.

Each event is a `.meow` SQLite database. Event metadata, entrants, membership,
sections, rounds, games and byes have separate tables. One writer holds the file;
foreign keys, FULL synchronous WAL transactions and revision checks protect saves.
The audit remains in the file. Up to 100 prior command snapshots support undo;
this is not an event-sourced architecture. Newer schemas are refused unchanged.

Backups use SQLite `VACUUM INTO` followed by an integrity check. A secondary copy
recovers its explicitly recorded revision, not later edits saved only on the first
laptop. Copying a live main database file without its WAL is unsupported. Use Save
independent copy, Back up now, or close the app before ordinary file copying.
API keys use the OS credential store and never enter event files or reports.

## Available workflows

Create/open/reopen local events; synthetic practice events and independent practice
copies; CSV/TSV paste preview with raw rows and rejected-row repair; check-in and
walk-up editing; private notes, byes, withdrawal/reinstatement; deterministic quad
partition and individual Swiss/RR sections; score-Swiss proposals in a background
isolate; batch posting with revision guards; separate actual round start with
explicitly assumed finish estimates; manual unstarted pairing edits; 1/0/5 and W/L/D result entry with repeat suppression and
advance after commit; forfeit shortcuts and optional withdrawal; historical
corrections with reasons; separate TD-authorized temporary pairing assumptions;
undo/history; current rounds across sections; class-filtered standings, early RR
withdrawal prize projection and crosstable; PDF packet preview/printing, CSV and
strict ASCII export;
independent backup/reopen; same-progress section combination with preserved history;
exact-ID authenticated provider review with stale-response rejection.

A Swiss proposal is labelled `score-swiss-pilot-v1`. Its priorities are score
proximity, upper/lower-half preference, non-repeat opponents, color balance and
lowest eligible non-repeat bye. It is **not a qualified US Chess Swiss engine**.
Never promote the pilot to that claim without the rule-linked fixtures in DELIVERY.

The DBF writer follows the archived 2C field layout and 2025 character-field
correction. Packages are explicitly **unverified validation packages**, not accepted
rating reports. Only completed, same-round-count, single-game R/D/Q sections without
post-play transitions are enabled. All three files publish as a new directory with
a manifest; unsupported encodings fail rather than fabricate data. Practice events
cannot export rating packages, including after undo.

## Still required before the planned first release

- Qualified US Chess pairing policy and adversarial TD-reviewed event replays.
- Accepted current DBF fixtures, external portal validation, Blitz/double-game and
  mixed-round-count mappings, and post-play transfer reporting attribution.
- Authenticated provider success/expiry/latest-rating evidence; batch rating review,
  name search and explicit per-category frozen rating observations.
- Broader rule-specific withdrawal and transfer prize policies, comprehensive
  eligibility rules and automated prize allocation. Configurable tie-break orders,
  eligibility overrides, templates, structured ruling/appeal records, explicit
  effective-round withdrawal and late-entry scoring also remain release work.
- Full per-section workspace/draft restoration, all-round reciprocal player matrix,
  advanced accessibility and large-field performance qualification. Import has
  header inference, not a custom column-mapping editor. Class filters currently
  apply to the standings screen, not printable prize-allocation reports.
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
