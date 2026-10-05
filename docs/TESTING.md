# Release qualification and local tests

CI is the release gate, with independent jobs on Ubuntu 22.04, Windows Server
2022 and Windows Server 2025. Each runs analysis, architecture/link lint, all
unit/widget tests, independent DBF decoding, abrupt-termination recovery and the
native Flutter desktop integration tests. A failed job blocks the release build.
The Linux and Windows jobs also compile and exercise the MCP server through its
portable Dart launcher, using a different working directory and Unicode paths.
A separate macOS job compiles the app and exercises Foundation staging,
exclusive publication, replacement, bookmark restoration and the Dart event-save
boundary. That job does not qualify the full macOS tournament workflow
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
powershell -ExecutionPolicy Bypass -File scripts\test_windows_installer.ps1 -Setup meow-chess-v1.2.2-windows-setup.exe
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
