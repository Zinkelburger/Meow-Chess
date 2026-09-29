# Meow-Chess

An offline-first Flutter desktop tournament director workspace.
US Chess first; Swiss events, easy quads, reliable identity/rating checks, and
usable printing. Inspired by SwissSys workflows and Chess Auto Prep V2's UI.

**Development pilot: an application now exists; federation and platform release
qualification is still pending.** See [implementation status](docs/IMPLEMENTATION.md).
The existing
AGPLv3 [LICENSE](LICENSE) is retained. The planning documents retain the full target; implementation status records the
subset actually built and tested.

Start with [the TD’s actual duties and supporting sources](research/notes/TD_DUTIES.md),
[a tournament day, in order](docs/TD_DAY.md)
and [the keyboard results-entry contract](docs/RESULT_ENTRY.md). Then read the expanded [full feature map](docs/FULL_FEATURE_MAP.md),
[TD experience specification](docs/TD_EXPERIENCE.md),
[first-class TD operations](docs/TD_OPERATIONS.md), and
[build-agent handoff](docs/BUILD_HANDOFF.md). The original
[product plan](docs/PRODUCT_PLAN.md) defines the first delivery tranche.

The [SwissSys archive coverage](research/SWISSSYS_ARCHIVE.md) and
[page checklist](research/SWISSSYS_TOPIC_LEDGER.md) distinguish saved pages from
reviewed requirements and tested parity.

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
| [UX specification](docs/UX.md) | Reusable workspace, section tabs, results entry, printing |
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
`build/linux/x64/release/bundle/meow_chess`. Start with **Explore a practice event**
for 22 synthetic entrants in four quads and a six-player Swiss.

Linux build prerequisites include GTK 3, CMake, Ninja, C++ tooling and libsecret
development headers (`libsecret-1-dev` on Debian/Ubuntu, `libsecret-devel` on Fedora).
The workstation wrapper discovers the local dependency prefix if present.

Events are `.meow` files; use the app’s Save independent copy or backup actions
to transfer an open event safely. `MEOW_DATA_DIR` overrides the recent-event library
location for isolated testing. A filename argument opens that event.

Run `scripts/ci.sh analyze`, `scripts/ci.sh lint`, `scripts/ci.sh test`, and
`scripts/ci.sh integration` here. On another machine, configure `MEOW_JOB_RUNNER`
or run the corresponding standard Flutter commands in your own resource limits.

No real tournament submissions, account changes or player communications are made
by the app. US Chess validation packages remain explicitly unverified.
