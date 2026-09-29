# Meow-Chess

Planning for an offline-first, cross-platform Flutter tournament director's app.
US Chess first; Swiss events, easy quads, reliable identity/rating checks, and
usable printing. Inspired by SwissSys workflows and Chess Auto Prep V2's UI.

**Research phase only. No application has been implemented.** The existing
AGPLv3 [LICENSE](LICENSE) is retained. Platform and release boundaries below
are recommendations awaiting product decisions, not promises of shipped features.

Start with [the TD usability review and realistic rehearsal scenarios](docs/TD_USABILITY_REVIEW.md),
[the TD’s actual duties and supporting sources](research/notes/TD_DUTIES.md)
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
| [Design references and report layout](docs/UX.md) | V2 source provenance and print/ASCII details; current interaction contracts linked above |
| [Delivery and validation](docs/DELIVERY.md) | Ordered milestones, release gates, research questions, POCs |
| [Engineering reading / reuse](research/notes/ENGINEERING.md) | Books, patterns, library findings, licensing and future FIDE |
| [Reference library](research/README.md) | Source catalog, local snapshots, provenance and research limits |

Sources were checked September 28–29, 2026 (Eastern / UTC boundary). Statements
labelled **observed**, **documented**, **proposed**, and **unverified** intentionally
have different strength. No US Chess upload, payment, registration, email, or
tournament modification was performed.
