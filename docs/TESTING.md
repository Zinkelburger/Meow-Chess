# Release qualification and local tests

CI is the release gate, with independent jobs on Ubuntu 22.04, Windows Server
2022 and Windows Server 2025. Each runs analysis, architecture/link lint, all
unit/widget tests, independent DBF decoding, abrupt-termination recovery and the
native Flutter desktop integration tests. A failed job blocks the release build.
The workflow can also run manually from Actions → CI without publishing anything.
Pushing a commit to the opt-in `windows-check` branch runs the same matrix without
a release tag; this also works before the workflow reaches the default branch.
The separate Windows build workflow checks packaging and installation, then
launches the installed release and requires a native window and clean close.

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

On a standalone Windows development/CI host, after `flutter pub get --enforce-lockfile`:

```powershell
flutter analyze lib test integration_test tools
python scripts/lint.py
$env:MEOW_EXPORT_FIXTURES = '1'
$env:MEOW_CHESS_DESKTOP_SETUP = '0'
flutter test --concurrency=2
python -m pip install dbfread==2.0.7
python scripts/verify_dbf.py artifacts/dbf-contract
python scripts/verify_recovery.py
foreach ($target in Get-ChildItem integration_test/*_test.dart) {
    flutter test $target.FullName -d windows
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

## Coverage and boundaries

| Concern | Automated evidence | Remaining qualification |
|---|---|---|
| US Chess 2C exports | Independent dbfread schema/width/type/padding checks; every source result compared against exported values; two sections, 12 rounds, leading-zero IDs, leap-day date, wins/draws/losses/forfeits and full/half/zero byes; unsafe/unfinished/unsupported exports blocked; negative controls reject corrupt schemas, IDs and even reciprocal-but-wrong results | Current accepted files and authorized TD/provider draft validation. This is format regression coverage, not an acceptance certificate. |
| Swiss pairings | Seeded multi-round simulations, no duplicate assignment or played-opponent repeats, bye fairness, color handling, withdrawals, reproducibility, stale proposals and explicit impossible-constraint failure | Full US Chess priority/exception conformance remains a pilot limitation; experienced TD review is still required. |
| Teams and sibling requests | UI assignment and do-not-pair action, legal alternative opponent, four-round persistence, backup, invalid/stale mutations rejected; team names alone do not change pairings | Team names are roster labels for mixed-doubles partners. Fixed-board team tournaments and team scoring are not implemented. |
| Tournament day | Native app library create/close/reopen; roster paste, section creation, pairing, keyboard scoring, PDF, dark/light screenshots and independent backup | File-picker/print-driver UI, actual physical printers and OS double-click forwarding need separate native/manual qualification. |
| Data durability | Atomic rollback and auto-rollback injection, exclusive ownership, stale writes, exact backup/reopen, no-clobber publication, unknown/corrupt/future-file refusal, durable history, real process kill after acknowledged WAL commits | Tests cannot prove zero data loss under power failure, faulty storage, filesystem failure or every migration. Keep independent backups. |
| Safe APIs and boundaries | SQL-looking/Unicode text stored literally, parameterized repository operations, fixed HTTPS ratings host, credentials only in headers, redirects disabled, response identity checks, private data excluded from public reports; lint enforces domain/application boundaries | No live API credentials are used. macOS is not in this qualification matrix. |

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
