# Documentation

Start with the guides, then the rules and formats, then the engineering notes.
The research folder holds the sources everything else cites.

## Running a tournament

| Document | What it covers |
|---|---|
| [A tournament day, in order](TD_DAY.md) | Registration, pairing, results, prizes and the rating report, in the order a TD does them |
| [Workspace guide](USING.md) | Results entry, quad edits, printing, export, corrections, import, website rosters, ID checks and rating estimates |
| [Keyboard results entry](RESULT_ENTRY.md) | The results-entry contract: keys, focus, saving |
| [Roster import and Help](ROSTER_AND_HELP.md) | The import window, field inference and the in-app Help |
| [Adding a club website](CLUB_ROSTER_ADAPTERS.md) | URL rules and parsers for a club's registration pages |
| [Rating estimates](RATING_PREVIEW.md) | The just-for-fun rating preview and its limits |
| [The browser version](WEB.md) | What differs in the browser and how the website copy is updated |
| [History and recovery](HISTORY_AND_RECOVERY.md) | Back up to round X, persistent Undo/Redo, version comparison, saved alternatives |
| [Diagnostics](DIAGNOSTICS.md) | The diagnostic log and what to send with a bug report |

## Rules and formats

| Document | What it covers |
|---|---|
| [Tournament formats](TOURNAMENT_FORMATS.md) | Swiss, quads, round robin, Scheveningen, Holland, knockout, ladder, bughouse |
| [Pairing](PAIRING.md) | US Chess pairing, quads, team distinctions, bughouse |
| [US Chess TD rules map](USCF_TD_RULES_MAP.md) | Which rule each behaviour follows |
| [FIDE](FIDE.md) | FIDE-rated sections, Dutch pairings, tie-breaks, TRF26, the rating list, and what is verified |
| [DBF compatibility](DBF_COMPATIBILITY.md) | The US Chess rating report files and how they are checked |
| [Tournament automation](TOURNAMENT_AUTOMATION.md) | The MCP server for driving an event from an assistant |

## Engineering

| Document | What it covers |
|---|---|
| [Changelog](CHANGELOG.md) | What each release added |
| [Developing](DEVELOPING.md) | Building, the CI gate, releases, the browser build, desktop integration |
| [Implementation status](IMPLEMENTATION.md) | What is built and verified, and what remains |
| [Release qualification](TESTING.md) | The CI gate, local test commands and manual checks |
| [Architecture](ARCHITECTURE.md) | Dart domain, SQLite transactions, commands, adapters, recovery |
| [Requirements](REQUIREMENTS.md) | Acceptance criteria |
| [Full feature map](FULL_FEATURE_MAP.md) | Every capability, by ID |
| [TD experience](TD_EXPERIENCE.md), [TD operations](TD_OPERATIONS.md), [TD usability review](TD_USABILITY_REVIEW.md) | Interaction specifications and rehearsal scenarios |
| [UX](UX.md) | Design references and report layout |
| [Boylston rehearsal](BOYLSTON_REHEARSAL.md) | Replaying a club's real events through the app |
| [Product plan](PRODUCT_PLAN.md), [Delivery](DELIVERY.md), [Build handoff](BUILD_HANDOFF.md), [Fable review](FABLE_REVIEW.md) | Planning documents; they keep the full target, and implementation status records what was built |

## Research

| Document | What it covers |
|---|---|
| [Reference library](../research/README.md) | Source catalog, local snapshots, provenance and limits |
| [The TD's duties](../research/notes/TD_DUTIES.md) | What a TD actually does, with sources |
| [Boylston event survey](../research/notes/BOYLSTON.md) | Real event formats and import evidence |
| [SwissSys and ChessRoster](../research/notes/SWISSSYS.md) | Feature map, interoperability, quad setup |
| [SwissSys archive](../research/SWISSSYS_ARCHIVE.md), [topic ledger](../research/SWISSSYS_TOPIC_LEDGER.md) | Saved pages versus reviewed requirements and tested parity |
| [US Chess reporting](../research/notes/US_CHESS_REPORTING.md) | The three DBF files and the specification's contradictions |
| [US Chess ratings API](../research/notes/US_CHESS_API.md) | The public API, live probes and identity review |
| [Engineering reading](../research/notes/ENGINEERING.md) | Books, patterns, libraries and licensing |

Sources were checked September 28–29, 2026. Statements labelled **observed**,
**documented**, **proposed** and **unverified** intentionally differ in strength.
No US Chess upload, payment, registration, email or tournament modification was
performed in research.
