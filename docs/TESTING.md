# Release qualification and local tests

CI is the release gate, with independent jobs on Ubuntu 22.04, Windows Server
2022 and Windows Server 2025. Each runs analysis, architecture/link lint, all
unit/widget tests, independent DBF decoding, abrupt-termination recovery and the
native Flutter desktop integration tests. A failed job blocks the release build.
The Linux and Windows jobs also compile and exercise the MCP server through its
portable Dart launcher, using a different working directory and Unicode paths.
A separate macOS job compiles the app and exercises Foundation staging,
exclusive publication, replacement, bookmark restoration and the Dart event-save
boundary. Its test host is built unsigned, so the App Sandbox is off there:
GitHub's macOS runners cannot launch the ad hoc signed, sandboxed host. Running
the Runner scheme's tests from Xcode covers the sandboxed paths. That job does
not qualify the full macOS tournament workflow
or replace a manual save-dialog sandbox test outside the app container.
That manual test must create an event outside the container, save a copy, choose
an external backup folder, restart the app, reopen from Recent events and verify
a new automatic backup without selecting either path again. Also verify that a
disconnected backup volume reports a backup failure without preventing event
editing, and that reconnecting and restarting restores its grant.
The workflow runs on every push to `main`, and can also run manually from
Actions → CI without publishing anything. All work is committed directly to
`main`; the project does not use feature branches.
The separate Windows build workflow checks packaging, then runs
`scripts/test_windows_installer.ps1`: it upgrades over the latest published
release's setup, checks that files from the old bundle are gone and that `.meow`
is associated, launches the installed release and requires a native window and
clean close, confirms the uninstaller refuses while the app is open, and then
uninstalls and checks that the app, shortcut and registry entries are gone while
the tournament library stays.

GitHub has no Windows 10 runners; both Windows Server images stand in for it. To
check a real Windows 10 PC, run the same script there in a Windows account
where Meow Chess is not installed (the script refuses to run otherwise). Run
it from a checkout, because it needs `smoke_windows.ps1` beside it:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test_windows_installer.ps1 -Setup meow-chess-v1.3.1-windows-setup.exe
```

The pinned Flutter SDK and committed pubspec.lock are shared across the matrix.
Tests use synthetic players, temporary event files and an isolated event library;
no federation credentials, real tournament files or live submissions are needed.
JSON test reports, screenshots, a PDF and DBF fixtures are retained as `test-evidence-<OS>` artifacts,
including on failure. Test artifacts are excluded from public release downloads.

## Run on this Linux workstation

```sh
scripts/ci.sh analyze
scripts/ci.sh lint
scripts/ci.sh test
scripts/ci.sh integration
scripts/ci.sh recovery
# One-time independent reader setup (outside the repository):
python3 -m venv "$HOME/.local/share/meow-test-tools"
"$HOME/.local/share/meow-test-tools/bin/python" -m pip install dbfread==2.0.7
MEOW_PYTHON="$HOME/.local/share/meow-test-tools/bin/python" scripts/ci.sh exports
```

The wrapper uses the shared bounded runner. Each integration test file runs in a
separate Flutter invocation and private Xvfb display/session, so native app and
debug-connection state cannot leak into the next test executable. If the runner is occupied, inspect `scripts/ci.sh status` and wait for a
slot; do not run heavy commands outside containment. `MEOW_JOB_RUNNER` may select
another configured runner. No Python runtime is needed by the distributed app.

The shared runner keeps build scratch files and disposable app profiles on disk
under `~/.cache/chess-prep-jobs`, with private per-job temporary directories that
are removed on exit. `CHESS_PREP_JOB_CACHE` can select another disk-backed path.
It refuses memory-backed checkouts and cache directories: this workstation's
`/tmp` is RAM-backed, so compiling there reduces memory available to every app.
Only small coordination locks remain in `/tmp`; do not remove those locks while
the runner is installed or jobs may stop sharing the same admission limits.
Use a checkout under the project directory and the wrapper above for local work.

On a standalone Windows development/CI host, after `flutter pub get --enforce-lockfile`:

```powershell
flutter analyze lib test integration_test tools scripts
python scripts/lint.py
$env:MEOW_EXPORT_FIXTURES = '1'
$env:MEOW_CHESS_DESKTOP_SETUP = '0'
flutter test --concurrency=2
python -m pip install dbfread==2.0.7
python scripts/check_exports.py --validate-only
python scripts/verify_recovery.py
foreach ($target in Get-ChildItem integration_test/*_test.dart) {
    flutter test $target.FullName -d windows
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Linux and Windows CI build and test the MCP server. Linux additionally replays
real club reports:

```bash
dart build cli --target=tools/tournament_mcp.dart --output=build/tournament-cli
python3 scripts/test_tournament_mcp.py
python3 scripts/test_boylston_replay.py
```

The checked-in `.mcp.json` uses `dart scripts/tournament_mcp.dart`. Build the CLI
bundle first using the command above. The launcher selects `.exe` on Windows,
does not require Bash, resolves the bundle relative to its own file, and keeps
stdout reserved for the protocol. Native clients must run the configuration
from the repository root, or use an absolute launcher path. The Bash script is
retained only as a compatibility entry point.

New regression coverage lives in `member_lookup_batch_test.dart`,
`rating_approval_test.dart`, `ratings_failure_test.dart` and
`artifact_save_test.dart`. These cover late-response rejection, duplicate IDs,
provider failures independent of wording, atomic approval, newer evidence,
native staging outside the selected directory and publication failure. The
macOS XCTest target tests native creation/replacement and preservation of the
old report when the staged source is missing.

`test_boylston_replay.py` rebuilds each anonymized report in
`test/fixtures/boylston/` through the MCP tools, exports it, and fails on any
difference from the accepted SwissSys report that has no stated reason, or any
result that disagrees with what US Chess rated where SwissSys's own report did
not.

## Controller fuzzer

`test/fuzz/` drives the real `TournamentController` and SQLite event file
through random tournament days. It registers and imports players, makes
sections and quads, reserves byes, pairs, scores, corrects results, withdraws
after posting and re-pairs (29G3), replaces pairings, moves back, forward and
to any point in history, applies stale proposals and reviews, and reopens the
file. Steps are drawn from phase-weighted tables (setup, play, repairs), so a
run spends its time in deep tournament states rather than on refusals.

After every controller command:

- A `TournamentException` is a refusal and must leave the event untouched. Any
  other error is a crash.
- An accepted command commits at most one revision, never changes the event
  without one, and never spends one on nothing.
- A stale proposal or result review must be refused.
- The saved rows (`load()`) and the current history node equal the event in
  memory. Reopening the file changes nothing.

After every step:

- `validateEvent` passes.
- The history summary, wall chart, crosstable, standings CSV, prize report,
  rating-report issues, standings and rating previews refuse plainly or
  succeed. If the rating preflight passes, the rating report must be produced.
- In each simple section, every player's score equals their game scores plus
  their byes, and ranks never decrease.
- A newly posted or re-paired Swiss round holds every active player once. It
  pairs no withdrawn player and no player with a reserved bye, repeats no
  played pairing without 27A1, and gives no second full-point bye without 28L3.

History moves are checked as a model:

- Undo, Redo and Restore land exactly on the saved state they target.
- The losses History shows equal the play the move removes. A move that loses play
  is refused unless accepted, and one that loses none is never refused.
- Undo then Redo returns to the same version and node.
- Every 25 steps and at the end: every state ever committed is still in the history,
  and every saved state is valid.
- Every recovery point is true: "Before round N pairings" has N - 1 rounds, and the
  next step paired round N. Every posted round has such a point, and a limited walk
  is a prefix of the full one.

Each history oracle was checked by mutation. With `recoveryMarks` off by one round,
the first seeds fail at once, naming the false point.

Steps name players, sections and games by stable identity. Every ID minted during
a step derives from the step's permanent tag, and a choice among candidates is a
rendezvous hash of the step's argument and each candidate's identity. Deleting
another step or candidate therefore never changes what a step picks, and faults that
need one particular player still shrink, typically to 4–9 steps.
`MEOW_FUZZ_VERBOSE=1` prints the most common refusal of each command, which shows
where a campaign wastes its steps.

The suite also counts every event a command built that `validateEvent`
refuses. The repository refuses those, so no data is at risk, but the TD
then sees a generic message instead of one naming the player.
`MEOW_FUZZ_STRICT=1` turns each into a failure.

A failure is shrunk by delta debugging: first steps, then arguments. Each step
names its choices as indices into the live event, so any subsequence still
runs. The minimal trace is printed and written to `build/fuzz/seed-N.json`.
To make it a permanent test, copy it into `test/fuzz/regressions/` with a
`why`, and `"strict": true` if it was a refused invalid event. Every pinned
trace is replayed on each run.

```sh
flutter test test/fuzz                                         # 12 seeds × 120 steps, as in CI
MEOW_FUZZ_SEEDS=0-999 MEOW_FUZZ_STEPS=400 flutter test test/fuzz # a campaign
MEOW_FUZZ_STRICT=1 MEOW_FUZZ_SEEDS=0-199 flutter test test/fuzz  # also fail on refused invalid events
MEOW_FUZZ_REPLAY=build/fuzz/seed-17.json flutter test test/fuzz  # replay one trace
```

The first campaigns (November 5, 2026) ran a few hundred thousand commands, with
sections up to ten rounds deep. They found six faults, each now pinned and covered
by a focused test. Each pin was checked both ways: it fails with its fix reverted
and passes with it.

| Trace | Fault | Fix |
|---|---|---|
| `side-game-blocks-next-round` | A player with a bye began a side game, and the next round was posted while it was still being played. Only the repository's validation refused it, without naming anyone. | `post` names the player and board. |
| `reopen-result-during-side-game` | A finished game was set back to unreported after its player began a side game, again refused only by validation. | `recordResult` and `correctResult` name the side game. |
| `move-second-entry-of-person` | Moving a side-game entry into the section holding the same person's main entry was refused only by validation. | `movePlayers` names the existing entry. |
| `repair-keeps-withdrawn-board` | A 29G3 re-pairing (MCP `repair_round`) could keep the unstarted board of a player who had withdrawn, leaving the opponent waiting. | `repairUnstartedRound` refuses. |
| `repair-keeps-second-meeting` | A 29G3 re-pairing kept a board that 27A1 allowed as a second meeting, but dropped the round's explanation, so nothing said the two players were meeting again. | The repaired round names the kept repeat. |
| `bughouse-partner-moved-away` | Moving or removing a partnered bughouse player left the partnership naming them. | Before play the partner is left unpartnered; after play the move is refused with both names. |

One oracle was found too weak this way. To allow a kept board whose withdrawn
player had already been scored, the repaired-round check had exempted every kept
board, including the waiting one it was written to catch. Hunting for the bug on
code without its fix showed nothing, which exposed the gap. Kept boards are now
exempt only once they have a result.

Knockout, ladder, bughouse and Scheveningen sections are generated too, with
their own steps: partners, home team, ladder games and reorders, and knockout
decisions. Play weights follow the hall: results while boards are open, pairing
once a section is ready, and new sections once every section has finished. Not
yet covered: team awards, ratings and membership, and FIDE sections.

## UI fuzzer

`test/fuzz/ui_fuzz_test.dart` mounts the real workspace on an event the
controller fuzzer built part way through a tournament day. It then taps, types,
presses keys and scrolls, choosing among what the semantics tree says can be done
on screen. Choices use the same stable hashing on each control's label. Each run
uses one window: desktop (1400 × 900), the app's minimum window (960 × 540), or
200% text. Each seed runs as Linux, Windows or macOS, because widget tests default
to Android, whose scrolling and keys differ. A keyboard-only mode drives the
workspace from Tab, Enter, Escape, the arrows, digits, `=`, Space and F2 alone.
Printing goes to a stand-in printer that still lays out every PDF the app asks for.
Pairing runs on the test's thread through `runProposal`, because a fake clock
cannot wait for an isolate.

After every step: nothing threw or overflowed, with the error's widget and source
line in the report; the event is valid; and memory, the saved rows and the current
history node agree. Every tenth step and at the end, the run checks that every
tappable control has a label and that text has legible contrast. Failures shrink
like controller traces and are written to `build/fuzz/ui-*.json`.

```sh
flutter test test/fuzz/ui_fuzz_test.dart                                        # 2 seeds per window, as in CI
MEOW_UI_FUZZ_SEEDS=0-49 MEOW_UI_FUZZ_STEPS=120 flutter test test/fuzz/ui_fuzz_test.dart
```

What it found, each fixed with a test:

- **History's header tripped Flutter's selection container.** Recovery points
  fill in over a few frames, so the header changed on its own after a tap or
  scroll, and `SelectionArea` threw `ConcurrentModificationError` while replaying
  its selection over the changed children (large text, seeds 0 and 1). The header
  is now `SelectionContainer.disabled`; the saved traces pass and HEAD never did
  fail, so the fuzzer caught it before it shipped.

- **Up and Down did nothing in every text field.** Flutter 3.47 throws when a
  `TextField` inside a `SelectionArea` receives them, on Linux, Windows and macOS.
  The workspace is one selection area, so names can be dragged and copied. The
  error was logged and the key dropped. `TextFieldKeysInSelection` works around it.
  `test/ui/selection_keys_test.dart` shows Flutter still needs the workaround,
  checks that the caret moves, and checks that keyboard selection outside fields
  still extends.
- **Section tabs were unnamed controls.** The tab's right-click menu detector
  wrapped each tab in its own tappable, unlabeled semantics node, so a screen reader
  heard an unnamed "selected" control before each tab. The workspace's shortcut
  focus also formed a window-sized, unnamed tappable node.
- **The empty state overflowed at the minimum window.** Searching the players for
  something nothing matched showed an empty state 27 pixels taller than the space
  left. It now scrolls when short.
- **The Board heading vanished at 200% text.** The board column had a fixed width
  while the score columns grew. It now grows with the text.
- The status line's `·` separators no longer read aloud.

Two early reports were artifacts of the test environment rather than app faults:
the Android default's scroll behaviour and a missing print plugin. Both are now
modelled correctly.

## Printed reports

`test/infrastructure/pdf_bounds_test.dart` prints every report on Letter and A4,
in Inter as the app prints them and in the built-in Helvetica. The rosters are
built to break layouts: long and unbreakable names, accented names, long section,
club and event names, nine rounds, unrated players and 180 entrants across pages.
`test/pdf_geometry.dart` reads where every word lands from the PDF's own drawing
commands (`cm` transforms, `re W n` cell clips, and font widths from `/Widths`,
`/W` and `/ToUnicode`). The test requires that every word lies on the page and
inside its cell, that no two words on a line overlap, and that names print whole,
not broken mid-word. The checker shows it can fail: a word in a too-narrow clipped
box and two words stacked are both reported, and a PDF it reads no text from fails.
Every report passed.

## Scale

`test/ui/scale_test.dart` counts rows built rather than timing frames, because
times vary by machine and mean little in debug mode. A roster of 2,000 builds
about 20 rows, before and after typing a search. With boards beside standings
(a window about 1,500 pixels or wider), a round of 500 boards builds about 60
score boxes. Before this change it built all 1,000, and entering one result took
7–11 seconds in debug mode with 1,000 players; it now takes about 0.4 seconds at
any size. Committing a result costs about 85 ms at 1,000 players in debug mode.

**Known limit:** narrower windows stack the boards above the standings in one
scroll view, and both are still built in full. With 1,000 players that costs
seconds per result in debug mode, growing faster than the field. The fix is to
make the stacked page a `CustomScrollView` with the board rows and standings rows
as slivers, which means splitting each bordered table into per-row pieces.

The board list is a `ListView.builder` over row builders, so a keystroke rebuilds
only the rows on screen. A focus node keeps the context of a row the list has
dropped, so `focusBox` treats only a mounted context as built, and it reaches an
unbuilt board by measuring the rows on screen (headings, score groups and byes
included) rather than assuming even spacing. The scale test enters a result on
board 181 of 200 and checks that the cursor returns to skipped board 2 and that
the next key records there.

A pinned trace means something only to the step semantics that produced it. When
steps change, re-derive each pin: run a strict campaign on code with only its fix
reverted, check that the new trace fails there and passes on the fixed code, then
replace the pin.

## 1.2.1 maintenance regressions

The maintenance suite checks that replacing pairings invalidates old game IDs,
that an outstanding pairing assumption prevents replacement, and that roster
reviews cannot cross event boundaries even when revisions match. Simulated
storage failures verify that completed membership lookups remain retryable and
cannot silently proceed to rating approval. Storage tests protect live database
recovery files and aliases from Save Copy, and verify that report-package
publication preserves a concurrently created destination.

The tag-triggered release repeats the platform matrix before building packages.
The shared local runner separately tests disk-backed scratch storage, isolation,
abandoned-job cleanup, and rejection of memory-backed build directories.

## 1.2.0 pre-release verification — October 4, 2026

[CI run 37179195816](https://github.com/Zinkelburger/Meow-Chess/actions/runs/37179195816)
passed on Ubuntu 22.04, Windows Server 2022 and Windows Server 2025, with the
separate macOS artifact-publication job also passing. Linux ran all 447
unit/widget tests; Windows ran 444 and skipped three POSIX-specific file tests.
Each desktop job passed 13 native scenarios across 11 test targets, 89
mock-importer tests, eight MCP protocol tests and abrupt-termination recovery.
Linux also passed seven archived club-report replays. The reports and screenshots
are attached to that run, including rating review and draft editing at 200% text.

[Windows installer preflight](https://github.com/Zinkelburger/Meow-Chess/actions/runs/37178886735)
installed the 1.2.0 build, verified file associations and bundled runtime DLLs,
and launched and closed its native window. Local Linux release and RPM builds
passed; the release executable also opened and closed its native window using
an isolated Unicode data directory. A fresh MCP build reported version 1.2.0
and completed synthetic quad, Swiss and double-game export rehearsals.

The pre-release runs exposed and corrected platform-dependent test paths,
implicit Python text encodings and outdated native rehearsal assumptions.
Analysis and architecture/version checks passed after the final import and
documentation cleanup. The tag-triggered release workflow repeats the full gate
on the published commit before producing the downloads.

## Coverage and boundaries

See [DBF compatibility setup and fragile importer](DBF_COMPATIBILITY.md) for the
eight-package export matrix, independent byte reader and corruption tests.

| Concern | Automated evidence | Remaining qualification |
|---|---|---|
| US Chess 2C exports | Independent dbfread and fixed-offset mock readers; source-event oracle; eight synthetic packages covering 1–32 rounds, mixed counts, side games, quads, 1,000 players, leading-zero IDs, text limits and every supported outcome; 89 mock-importer tests plus source/schema corruption controls; seven club-report replays compare exports with rated records, including blitz and double-game expansion. | Live MUIR acceptance remains unverified. Local format and semantic checks, including comparisons with previously accepted reports, do not certify portal acceptance. |
| Swiss pairings | Seeded multi-round simulations, no duplicate assignment or played-opponent repeats, bye fairness, color handling, withdrawals, reproducibility, stale proposals and explicit impossible-constraint failure | Full US Chess priority/exception conformance remains a pilot limitation; experienced TD review is still required. |
| Teams and do-not-pair requests | UI assignment and do-not-pair action, legal alternative opponent, four-round persistence, backup, invalid/stale mutations rejected; team names alone do not change pairings | Team names are organizer labels (for example mixed-doubles partners). Fixed-board team tournaments and team scoring are not implemented. |
| Tournament day | Native app library create/close/reopen; roster paste, section creation, pairing, keyboard scoring, PDF, dark/light screenshots and independent backup | File-picker/print-driver UI, actual physical printers and OS double-click forwarding need separate native/manual qualification. |
| Data durability | Atomic rollback and auto-rollback injection, exclusive ownership, stale writes, exact backup/reopen, no-clobber publication, unknown/corrupt/future-file refusal, durable history, real process kill after acknowledged WAL commits | Tests cannot prove zero data loss under power failure, faulty storage, filesystem failure or every migration. Keep independent backups. |
| Safe APIs and boundaries | SQL-looking/Unicode text stored literally, parameterized repository operations, fixed HTTPS ratings host, credentials only in headers, redirects disabled, response identity checks, private data excluded from public reports; lint enforces domain/application boundaries | No live API credentials are used. macOS coverage is limited to compilation and native artifact publication. |

Windows runs exercise real SQLite and `MoveFileExW` backup publication rather than
mocking platform file operations. The dangling-symlink test is skipped on Windows
because it requires privileges/developer mode not guaranteed on the runner; normal
files, directories and no-replacement races are still checked there.

The recovery harness uses a pipe-reading thread (Windows pipes cannot be polled
with Unix selectors), an explicit commit handshake, and a nonzero termination
status on either OS. It checks the last acknowledged revision, all 120 players,
audit/history counts, SQLite integrity and foreign keys. It closes Python SQLite
handles before cleanup, which is required on Windows.

## Verification record — September 30, 2026

[GitHub qualification run 36740268856](https://github.com/Zinkelburger/Meow-Chess/actions/runs/36740268856)
passed on Ubuntu 22.04, Windows Server 2022 and Windows Server 2025. It includes
analysis, lint, unit/widget tests, independent DBF validation and negative controls,
actual writer termination/WAL recovery, and all three native desktop scenarios.
The tested code is commit `55b77d6`; the subsequent native-test change only formats
the same assertions. Local Linux also passed 129 unit/widget tests and three
native scenarios. The Windows-only symlink skip is described above.

The first Windows runs caught and prompted fixes for Python's default text
encoding, uppercase `.EXE` launcher handling in Dart native hooks, and an E2E
navigation target clipped by the smaller Windows viewport. These are fixed in
the passing run. This run tests desktop debug builds; installer launch checks
remain part of the release packaging workflow and were not executed by this run.

## UI recovery and output verification — October 2, 2026

The Impeccable follow-up implementation passed `scripts/ci.sh analyze`,
`scripts/ci.sh lint`, and the full 189-test unit/widget suite. All five native Linux
integration targets passed (seven test cases). The new workflow target was rerun
after the large-text score-column correction; subsequent player-draft fixes passed
the full unit/widget suite and the focused player/workspace tests.

New regression coverage includes actual form input across Escape and event-file
reopen, pending section-move target/reason recovery, injected preference-write
failure and retry, current-record merging when restoring drafts, result board-side
restoration, historical rounds reopening read-only, explicit print round scope,
stale preview acknowledgment and refresh, PDF retry, invalidated print scope,
prize-class ranking, structured report repair destinations, panel replacement,
and the full workspace at 1280×720 with 200% text.

`integration_test/workflow_accessibility_test.dart` exercises native draft editing,
keyboard scoring, lookup by pairing number, historical PDF preview, stale/refresh
states and dark/light Reports. Inspected captures are in ignored
`artifacts/workflow-*.png`; the revised capture confirms the 200% Score headings
stay on one line. The native tournament-day suite also regenerates the PDF packet
and checks event-file/backup recovery.

These checks do not establish physical-printer behavior, Windows/macOS native
qualification, human screen-reader usability, federation acceptance or measured
performance with working TDs. Those remain the qualification boundaries above.

## UI stability verification — October 2, 2026

The 1.1.1 UI fixes passed analysis, repository lint, and all 212 unit/widget tests.
Regression coverage checks table geometry while opening, replacing and closing
panels, navigation at 960×600 and at 1280×720 with 200% text, draft actions,
lookup focus, Escape handling, and visible desktop file-open failures.

All five native Linux integration targets have passing runs (seven test cases).
The workflow target was rerun after the final keyboard-focus correction and
passed. Inspected light/dark captures include large-text player drafts, event
drafts, History and Reports. Windows qualification and installer checks run
separately in the tag-triggered release workflow.

## Website roster, ratings and Help checks (2026-10-03)

The full 225-test unit/widget suite passed. A further regression test verified
that an unchanged website source preserves manual corrections and that manually
changing a verified rating clears its old supplement attribution. Analysis and
architecture/whitespace lint passed. Native Linux rehearsal
`integration_test/roster_help_test.dart` passed with light/dark captures at 1280×720,
200% text, and a 960×600 update panel. The existing responsive suite also exercises
history, section management, forms and navigation at large text.

Live read-only smoke check: the new web adapter parsed all 24 entrants from
Boylston entry list 1563, and the new public-rating adapter returned a dated
2026-10-01 supplement for the first ID. No real event file was imported or altered.
Fixtures use synthetic players. Authenticated v2 access, guaranteed future public
access, and live/unofficial rating freshness remain unverified.

Artifacts: `artifacts/roster-horizontal-tabs.png`, `roster-quad-help.png`,
`roster-help-dark-200.png`, and `roster-update-small.png`.
