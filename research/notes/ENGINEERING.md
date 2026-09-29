# Engineering reading, reuse and future federation support

## Reading honestly scoped

The user asked for design-pattern and DDIA-informed planning. This pass consulted
the [DDIA author's site](https://dataintensive.net/) and
[publisher contents/preview](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781491903063/ch01.html),
plus the [GoF publisher page](https://www.pearson.com/en-us/subject-catalog/p/design-patterns-elements-of-reusable-object-oriented-software/P200000009480).
Full paid books were not accessible, so this is not a claim of reading them in
full. An accessible alternative for applied patterns was Robert Nystrom's
[*Game Programming Patterns*](https://gameprogrammingpatterns.com/contents.html),
especially [Command](https://gameprogrammingpatterns.com/command.html),
[State](https://gameprogrammingpatterns.com/state.html) and
[Observer](https://gameprogrammingpatterns.com/observer.html).

DDIA's relevant framing is reliability, maintainability and choosing storage/data
tradeoffs deliberately. The concrete design decisions below are our application
of that framing, supported by the database/framework documentation; they are not
quotations or claims that a book prescribes this architecture.

| Idea | Concrete application | Complexity to avoid |
|---|---|---|
| Reliability over happy-path demos | Transactional results, independently validated exports, restore tests | Optimistic “Saved” before durable commit |
| Derived data has provenance | Rating source/time, frozen seeds, versioned standings/report projections | One mutable rating number used for everything |
| Schema evolution | Explicit versions, backups and migration fixtures | Persisting widget state as unversioned domain JSON |
| Command | Typed operations with invariant checks and audit records | A huge command framework for trivial local UI state |
| State | Legal draft/published/in-progress/complete transitions per round | Overlapping booleans allowing impossible combinations |
| Observer | Flutter listens to committed view state; subscriptions disposed | Hidden event-bus chains controlling core domain mutations |
| Strategy | Pairing/tie-break/report policies with known contracts | One class hierarchy for every future sport/federation |
| Adapter | US Chess, DBF, CSV and future TRF at boundaries | Leaking legacy DBF widths into the person model |
| Composition | Small explicit owners, injected clock/client/storage | Global service locators and mutable singletons |

The [Flutter architecture guidance](https://docs.flutter.dev/app-architecture/guide),
[Effective Dart design guidance](https://dart.dev/effective-dart/design),
[Drift transaction docs](https://drift.simonbinder.eu/dart_api/transactions/), and
[SQLite backup docs](https://sqlite.org/backup.html) were reviewed for the relevant
boundaries. Prefer immutable values, narrow APIs, explicit ownership, typed errors,
and pure calculations. Detailed implementation choices still need measurement.

## Upstream projects: useful, with different strengths

| Project | Observed state | Useful inspiration | Why not simply adopt it |
|---|---|---|---|
| [ToMaChess](https://github.com/Moritz72/ToMaChess) | Python library describes itself as early-stage; inspected source has individual/team RR structures and Berger pairing; MIT | Pure tournament model, state separation, RR examples | Not a verified US Chess Swiss/reporting solution; old GUI is a separate project |
| [Gambit Pairing](https://github.com/gambit-devs/gambit-pairing) | Python/PyQt6 desktop app; README says alpha, GPL-3.0-or-later | Results/standings/history, manual pairings, print preview, importer ideas | README's USCF-style claim is not a conformance proof; inspected Dutch engine has FIDE-oriented criteria and a placeholder; no reporting certification established |
| [BBP Pairings](https://github.com/BieremaBoyzProgramming/bbpPairings) | Current README describes Dutch rules effective in 2026, TRF26 support, and warns its old Burstein implementation is flawed/not endorsed; source license says Apache-2.0 | Future FIDE adapter; independently testable process contract | FIDE rules do not implement US Chess Swiss; pin the release/capabilities and inspect any additional binary-build terms |
| Chess Auto Prep V2 | Existing Flutter AGPLv3 app; source inspected read-only | Typography, semantic UI, compact tabs, keyboard workflow, owner lifecycles | Chess analysis/repertoire/engine architecture is unrelated to TD administration |

Pinned ToMaChess and Gambit commits are listed in the reference index. Inspection
was static; neither application nor its suite was run. Do not characterize a
competitor as incorrect based on a quick read: treat the observed placeholder and
scope mismatches as reasons to demand evidence before dependency selection.

ToMaChess's engine handles cyclic Berger pairings and color reversal for later
cycles. The quad-specific US Chess 30G schedule is a separate requirement.
Gambit's current documentation and source layout differ, reinforcing the need to
inspect pinned code rather than rely on README feature lists alone.

## Licensing posture

Meow-Chess already contains the GNU AGPL version 3 license. Retain it. Decide
`AGPL-3.0-only` versus `AGPL-3.0-or-later` explicitly before adding source headers;
the license text alone does not settle that grant. Recommendation: AGPL-3.0-only
unless the owner prefers “or later.” No source license was silently changed here.

ToMaChess's MIT notice must accompany any copied substantial code. Gambit identifies
GPL-3.0-or-later; [GNU's GPL/AGPL compatibility explanation](https://www.gnu.org/licenses/gpl-faq.html#v3Compatibility)
allows a combined work under the relevant provisions, but this does not permit
erasing GPL notices or pretending upstream files were originally AGPL. Track
attribution, source availability and build instructions for actual reuse.

Visual/workflow inspiration does not authorize copying SwissSys proprietary code,
icons, branded screens or documentation into our distribution. Reference snapshots
are local reading material, not application assets. Audit font licenses and every
dependency at the pinned version. Check the terms of any TrueSkill implementation
before shipping it; an independently licensed alternative also needs review.

## FIDE later: leave boundaries now, earn compatibility later

FIDE's [updated Swiss rules](https://www.fide.com/fide-reminds-organizers-and-arbiters-of-updated-swiss-rules-effective-from-february-1-2026/)
took effect February 1, 2026. Its official [TRF26 specification](https://handbook.fide.com/files/handbook/TRF26.pdf)
has separate requirements for rating and pairing/data interchange; the header
states approval in May 2025 and application from September 2025. Do not use the
2006 FIDE example embedded in the old US Chess page as the new target.

Keep federation identities/rating categories separate; preserve colors, unplayed
game types, game eligibility, dates, board/lineup data, arbiter metadata and policy
versions. Add a federation-specific eligibility/report adapter and an exact-version
pairing engine. TRF serialization is not equivalent to correct Dutch pairing,
correct rating eligibility, or FIDE endorsement of a tournament program.

[ChessRoster's FIDE page](https://docs.chessroster.com/chessroster/about/fide-pairing/)
names Gacrux / FIDE TieBreakServer as its basis and explicitly limits the engine to
testing pending approval. This is another research lead, not a basis for claiming
Meow-Chess approval. Future work must inspect pinned upstream code/licenses,
current approved-engine lists and conformance/endorsement procedures.

US Chess + FIDE dual rating also requires organizer/arbiter prerequisites and
pre-registration, described by the [US Chess FIDE event guidance](https://new.uschess.org/tournament-directors/fide-rated-events).
Preserve the needed fields now, but expose no “FIDE compatible” switch until the
whole workflow, not just a text file, is verified.
