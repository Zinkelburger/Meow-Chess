# Meow-Chess

An offline-first Flutter desktop tournament director workspace.
US Chess first; Swiss events, easy quads, reliable identity/rating checks, and
usable printing. Inspired by SwissSys workflows and Chess Auto Prep V2's UI.

**Meow-Chess 1.2.1** provides an offline desktop workspace for Linux and Windows.
Download the installers and portable bundles from [Releases](https://github.com/Zinkelburger/Meow-Chess/releases).
This release adds complete quad schedules and pairing edits, improves US Chess
identity and rating review, and preserves reliable history and recovery. Shared
lookup and approval logic keeps late network responses from changing another
event, while smaller UI components make the desktop workflows easier to maintain.
The optional MCP launcher now works without Bash on Windows; report exports use
the native replacement mechanism on sandboxed macOS.
The 1.2.1 maintenance update protects database recovery files when saving copies,
rejects stale roster and pairing edits, preserves rating lookups after save
failures, and durably publishes complete report packages.
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
| [DBF compatibility tests](docs/DBF_COMPATIBILITY.md) | Fragile mock importer, mixed-round export, setup and remaining limits |
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
`build/linux/x64/release/bundle/meow_chess`. Start with **New tournament** to create an event, then add or import players.

Choose a section tab, then switch between **Players & standings** and
**Pairings & results**. Both views keep the selected section. Click a score cell in either view, then type **1/W** for a win, **0/L** for
a loss, or **D** for a draw. Results display as **1**, **0**, and **½**.
Typing saves and advances; mouse clicks only focus cells. Historical corrections
retain their review step.
**Create pairings** pairs every ready section with one click; sections waiting
for results are left alone. There is no separate start-round step.

Right-click a player or section tab for **Move**, **Swap**, and **Withdraw**.
Choose **Edit quad pairings** beside **New Section** to change opponents or flip
colors within a quad. Select players in each round, then **Save pairings**.
Everyone must meet once across the three rounds; changing opponents may require
adjusting another unplayed round. Rounds with results, start markers or pairing
assumptions stay locked. Saved edits update future rounds and printed sheets;
reprint any sheets already distributed. **Undo** restores the previous schedule.
The quad setup preview only displays the rating groups. **Print section sheets**
prints one plain result sheet per quad with all round-robin pairings, including
future rounds. Swiss sections print only the selected posted round. Sheets use
**Board | Result | White | Black | Result**, with blank result boxes for handwriting
and unused space left blank. Each section starts on a fresh page; large Swiss
sections continue onto additional pages as needed. The first print asks for a printer; later prints use the saved device.
Use **Print preview…** or **Export** to preview sheets and choose another printer.
Systems without direct printing support use the operating system's print dialog.

Use **Export** to wrap up the tournament. Review checks across all sections and
follow the repair links to resolve missing results or report inconsistencies.
**Generate DBF files** becomes available once blocking issues are resolved;
optional checks remain available for review. Final standings, crosstables,
printouts, backup status, and submission notes are also available here.
Expand **Optional checks** and choose **Fetch missing states from US Chess** to
fill missing player states from their USCF IDs. Rating and membership lookups
also fill missing states automatically; existing states are preserved.

On **Pairings & results**, choose a round number or **Show all rounds** to find an earlier
game. Choose **Correct a result**, or click a result cell in **Players & standings**, to review
a correction. The review shows score changes and later rounds: keep their pairings,
or reopen an unstarted round and all rounds after it. Recorded play and section
transfers prevent automatic reopening. Reopened rounds are paired again through
the normal pairing review. The previous version remains in **History**, where a
single-result transaction also offers **Undo this result** without reversing
unrelated edits. Restoring multiple transactions previews the whole-event changes
before confirmation.

**Import file…** opens a CSV/TSV/text file for review before adding players.
Choose the delimiter and header setting, then map your columns to name, rating,
and USCF ID (with optional split names, club/team, and state). The preview updates
as you change settings. Invalid rows must be fixed or explicitly skipped;
**Paste** uses the same review flow. Imports can be undone.

**Refresh from URL** accepts Boylston event or entry-list links. For other clubs,
paste a page containing a Name, Rating and USCF ID table, then review and confirm
the players. Clubs can contribute their own URL rules and parsers; see
[adding a club website](docs/CLUB_ROSTER_ADAPTERS.md).

**Find by name** beside a player's US Chess ID searches official member records.
**Check ID** warns about missing records or a different official name and offers
possible corrections. Choose a candidate, then Save (or Add for a new player).
Ratings stay unchanged. Event details offers the same name search for the chief
and assistant chief TD: enter a name, choose **Find by name**, then select the ID.
Search uses public access when available or the API key in Data sources; service
failures leave the identity unverified. Report city, state and ZIP refer to the
tournament site.

On **Players**, **Show unofficial rating estimates** is off by default. Enable
it to see approximate Regular ratings and changes as results are entered or
corrected between rounds. This just-for-fun preview assumes 50 prior rated games,
uses starting ratings and completed games in each section, and omits personal
floors and provisional formulas. It never changes pairing ratings or exports.
See [calculation details and limits](docs/RATING_PREVIEW.md).

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
portable zip, plus checksums, with no release description. A tag with a dash
(`v0.2.0-rc1`) is published as a pre-release. The Windows build alone can be tried
from Actions → Windows build → Run workflow.

Every package makes `.meow` files open in Meow Chess on double-click. The portable
zips do it on first launch instead: the app asks "Set up Meow Chess on this
computer?" and, on Linux, installs a menu entry, icon and the `.meow` file type under
`~/.local/share`; on Windows, it registers `.meow` for the current user. Nothing needs
administrator rights. Debug builds never ask. `MEOW_CHESS_DESKTOP_SETUP=1` sets up
without asking and `=0` never asks, for scripted installs. The icon is
[meow_chess_master.png](assets/icon/meow_chess_master.png); `tools/make_icons.sh` regenerates every
platform size from it.

The logo appears on the welcome screen and as the desktop app icon. The tournament
toolbar starts with the editable event title. Window controls, movement and
resizing use the operating system’s standard window decorations; whether an icon
appears in the title bar depends on the desktop environment.

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
