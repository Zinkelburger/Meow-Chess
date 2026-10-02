# Meow-Chess

An offline-first Flutter desktop tournament director workspace.
US Chess first; Swiss events, easy quads, reliable identity/rating checks, and
usable printing. Inspired by SwissSys workflows and Chess Auto Prep V2's UI.

**Meow-Chess 1.1.0** provides an offline desktop workspace for Linux and Windows.
Download the installers and portable bundles from [Releases](https://github.com/Zinkelburger/Meow-Chess/releases).
This release adds recoverable form drafts, restored result-entry position,
round-specific print previews with revision warnings, direct report-repair links,
and an updated workspace with improved large-text support.
Federation acceptance and full Swiss priority conformance remain unverified; see
[implementation status](docs/IMPLEMENTATION.md) and [release qualification](docs/TESTING.md).
The existing
AGPLv3 [LICENSE](LICENSE) is retained. The planning documents retain the full target; implementation status records the
subset actually built and tested.

Start with [the TD usability review and realistic rehearsal scenarios](docs/TD_USABILITY_REVIEW.md),
[the TD’s actual duties and supporting sources](research/notes/TD_DUTIES.md),
[a tournament day, in order](docs/TD_DAY.md)
and [the keyboard results-entry contract](docs/RESULT_ENTRY.md). Then read the expanded [full feature map](docs/FULL_FEATURE_MAP.md),
[TD experience specification](docs/TD_EXPERIENCE.md),
[first-class TD operations](docs/TD_OPERATIONS.md), and
[build-agent handoff](docs/BUILD_HANDOFF.md). The original
[product plan](docs/PRODUCT_PLAN.md) defines the first delivery tranche.

The [SwissSys archive coverage](research/SWISSSYS_ARCHIVE.md) and
[page checklist](research/SWISSSYS_TOPIC_LEDGER.md) distinguish saved pages from
reviewed requirements and tested parity.

The [review of Fable’s tournament-day additions](docs/FABLE_REVIEW.md) records
what to keep, corrections needed, and how the two proposals fit together. Those
main-checkout edits are reviewed but not yet merged into this branch.

The [history and recovery contract](docs/HISTORY_AND_RECOVERY.md) specifies safe
“back up to round X,” persistent Undo/Redo, version comparison and saved alternatives.

Supporting plans:

| Document | Purpose |
|---|---|
| [Requirements and acceptance criteria](docs/REQUIREMENTS.md) | What the app must do and how we will know it works |
| [Boylston event survey](research/notes/BOYLSTON.md) | Actual event formats, import evidence, scope implications |
| [SwissSys / ChessRoster](research/notes/SWISSSYS.md) | Feature map, interoperability, and a practical quad setup guide |
| [US Chess reporting](research/notes/US_CHESS_REPORTING.md) | The three DBF files, authoritative specification, unresolved contradictions |
| [US Chess ratings API](research/notes/US_CHESS_API.md) | Public OpenAPI, live probes, identity review, latest-rating limitations |
| [Pairing and bughouse](docs/PAIRING.md) | US Chess pairing, quads, team distinctions, experimental skill estimates |
| [Architecture](docs/ARCHITECTURE.md) | Dart domain, SQLite transactions, commands, adapters, recovery |
| [Design references and report layout](docs/UX.md) | V2 source provenance and print/ASCII details; current interaction contracts linked above |
| [Delivery and validation](docs/DELIVERY.md) | Ordered milestones, release gates, research questions, POCs |
| [Engineering reading / reuse](research/notes/ENGINEERING.md) | Books, patterns, library findings, licensing and future FIDE |
| [Reference library](research/README.md) | Source catalog, local snapshots, provenance and research limits |

Sources were checked September 28–29, 2026 (Eastern / UTC boundary). Statements
labelled **observed**, **documented**, **proposed**, and **unverified** intentionally
have different strength. No US Chess upload, payment, registration, email, or
tournament modification was performed.

## Run and develop

With Flutter installed, run `flutter pub get`, then `flutter run -d linux`
(or `-d windows` / `-d macos` on the corresponding host). On this workstation,
use `scripts/ci.sh build` for a bounded Linux release build; the executable is
`build/linux/x64/release/bundle/meow_chess`. Start with **Try a practice event**
for 22 synthetic entrants in four quads and a six-player Swiss.

Linux build prerequisites include GTK 3, CMake, Ninja, C++ tooling and libsecret
development headers (`libsecret-1-dev` on Debian/Ubuntu, `libsecret-devel` on Fedora).
The workstation wrapper discovers the local dependency prefix if present.

Events are `.meow` files; use the app’s Save independent copy or backup actions
to transfer an open event safely. `MEOW_DATA_DIR` overrides the recent-event library
location for isolated testing. A filename argument opens that event; in release
builds a second launch hands its file to the window already open.

## Install and release

Pushing a `v*` tag (`git tag v0.2.0 && git push origin v0.2.0`) runs
[release.yml](.github/workflows/release.yml): the CI gate, then a GitHub Release with
a Windows setup `.exe` and portable zip, and Linux `.deb`, `.rpm`, `.flatpak` and
portable zip. A tag with a dash (`v0.2.0-rc1`) is published as a pre-release. The
Windows build alone can be tried from Actions → Windows build → Run workflow.

Every package makes `.meow` files open in Meow Chess on double-click. The portable
zips do it on first launch instead: the app asks "Set up Meow Chess on this
computer?" and, on Linux, installs a menu entry, icon and the `.meow` file type under
`~/.local/share`; on Windows, it registers `.meow` for the current user. Nothing needs
administrator rights. Debug builds never ask. `MEOW_CHESS_DESKTOP_SETUP=1` sets up
without asking and `=0` never asks, for scripted installs. The icon is
[meow_chess_master.png](assets/icon/meow_chess_master.png); `tools/make_icons.sh` regenerates every
platform size from it.

The logo appears in the welcome screen and tournament toolbar. Window controls,
movement and resizing use the operating system’s standard window decorations.

For a local checkout on KDE/Wayland, build the app and run
`python3 tools/install_linux_launcher.py`. This installs the menu entry and icon
whose name matches the Wayland app ID, without changing default file handlers.
Use `--bundle build/linux/x64/debug/bundle` to point the launcher at a debug build.
Rerun after changing the logo or moving the checkout; reopen the app if Plasma
still shows a cached icon. Packaged installations already include this entry.

Run `scripts/ci.sh analyze`, `scripts/ci.sh lint`, `scripts/ci.sh test`, and
`scripts/ci.sh integration` here. On another machine, configure `MEOW_JOB_RUNNER`
or run the corresponding standard Flutter commands in your own resource limits.

See [release qualification and the test matrix](docs/TESTING.md) for Linux/Windows
commands, tested guarantees and remaining acceptance checks.

No real tournament submissions, account changes or player communications are made
by the app. US Chess validation packages remain explicitly unverified.
