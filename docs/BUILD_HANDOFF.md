# Build-agent handoff

Application implementation is authorized by the user’s September 28, 2026 request.
This document describes the target; IMPLEMENTATION.md records what exists and what
has been tested. DELIVERY.md owns the sequence.

## Read first

Start with [actual TD duties and their evidence](../research/notes/TD_DUTIES.md)
and [a tournament day, in order](TD_DAY.md). For every core workflow, trace duty →
moment on the clock → interaction → acceptance test. A competitor menu item alone does not establish priority or usability.
Read [Results entry](RESULT_ENTRY.md) before implementing any results table.


1. [Full capability map](FULL_FEATURE_MAP.md) — expanded scope and stable IDs.
2. [TD experience](TD_EXPERIENCE.md) and [first-class TD operations](TD_OPERATIONS.md) — current navigation, editable player inspector, byes, withdrawals, transfers and section combination.
3. [Architecture](ARCHITECTURE.md) and [pairing](PAIRING.md).
4. [US Chess report specification findings](../research/notes/US_CHESS_REPORTING.md)
   and [API findings](../research/notes/US_CHESS_API.md).
5. [SwissSys page checklist](../research/SWISSSYS_TOPIC_LEDGER.md) and
   [archive coverage](../research/SWISSSYS_ARCHIVE.md).
6. [Requirements](REQUIREMENTS.md), [delivery](DELIVERY.md) and research limitations.

Full parity is the target, not an instruction to implement everything in one pass.
The task navigation names in TD_EXPERIENCE.md supersede the earlier UX sketch.
The original release scope is a first tranche of this larger product.

## Resolve before coding affected features

- Choose exact reference SwissSys stable version; keep upcoming/preview docs marked
  separately. Read current downloads/release notes, not only the legacy history.
- Obtain legitimate reference event files and accepted rating-report packages.
  Specify native interchange support by extension/version and known loss behavior.
- Settle exact pairing/tiebreak/prize rule variants with a qualified TD and fixtures.
- Establish US Chess validation access. Tokenless API experiments are not proof of
  authenticated v2 behavior or reliable latest-rating semantics.
- Decide FIDE engine/licensing/approval when that tranche starts; do not label a
  home-grown Swiss engine FIDE-compliant without the applicable validation.
- Choose AGPL-3.0-only versus AGPL-3.0-or-later for original code explicitly; retain
  upstream license notices. Archived third-party docs keep their own rights.
- Product decisions still open: exact OS priority, accessibility devices, first
  printer targets, native SwissSys import priority, first team format, and whether
  a later hosted service is desired. Proceed with desktop Windows/macOS/Linux,
  local ownership, US Chess-first and no required account unless redirected.

## Build in vertical slices

| Slice | Result the TD can exercise | Gate |
|---|---|---|
| 0. Evidence and UX | TD walkthrough of roster → quad preview → round → correction → print | Reconcile source gaps; observe novice/experienced TDs; record revisions |
| 1. Event, safety and export feasibility | Create, edit, close, reopen, undo, recover a synthetic event | Transaction/crash/backup/migration checks; stable identity model; early independent DBF codec verification |
| 2. Registration | Import, edit player details, assign byes, withdraw/reinstate and transfer entries | Reimport diff; no data loss; ratings provider fakes and cache behavior |
| 3. Quads and scoring | Make and combine quad/Swiss groups, review/publish, enter/correct games | Pure domain invariants, seeded schedule fixtures, keyboard walkthrough |
| 4. Swiss and external reporting qualification | Run a complete US Chess event, print and export DBFs | TD-reviewed pairing cases, accepted DBF comparison, authorized portal test |
| 5. Full club operation | Double games, prizes, team totals, recurring templates and extended print suite | Scoring/report consistency and documented edge cases |
| 6. Specialist parity | Fixed-board teams, Scheveningen, ladder, merged schedules, side games, databases | Feature-by-feature documented and reference-app comparisons; basic section combination/transfer must already work in earlier slices |
| 7. International and integrations | Verified federation policies, native interchange, hosting and collaboration | Format/version compatibility matrix; OS and integration validation |
| Separate experimental slice | Bughouse fixed teams then optional rotating matchmaking | Rules agreed; simulation/calibration; no effect on US Chess behavior |

Parallel modules can be built only after their data/command contracts are settled.
Do not build 50 empty screens and call it progress. Each slice must use actual
persisted data through the same commands and reports as the eventual application.
No need for microservices, full event sourcing, a generic plugin framework, or a
custom widget toolkit to get the first event running.

## Required architectural boundaries

- Pure Dart domain with explicit Person, Entry, Section, Round, Game, Team,
  RatingObservation and PublishedRevision identities. Multiple entries can share
  one person; multiple games can share one pairing round.
- Pairing input snapshot → deterministic proposal → validated publication. Preserve
  policy/version, seed/tie resolution and manual exception reasons.
- Separate tournament score, prize score, pairing adjustment and rated result.
  Avoid encoding “bye” as a missing opponent plus arbitrary numeric score.
- Local SQLite transaction for command + audit + state; persist before claiming
  success. Single-writer ownership initially. Backups must handle WAL safely.
- One report projection from one revision, rendered to table/text/PDF/export.
  Federation adapters own encoding/spec versions, not widgets.
- Network services are adapters with cache, rate limiting, cancellation and revision
  guards. In-flight lookup cannot overwrite a TD correction made afterward.
- Reusable shell/table/inspector/review controls, with feature state scoped to event
  and section. Domain validation shared across menus, keyboard and imports.
- Record dependency licenses and native packaging constraints before adopting code.

## Verification matrix

Test Swiss odd/even fields, unfinished/unreported games with separately recorded temporary pairing treatment, unrated ties, odd score groups, repeat avoidance, colors,
multiple byes, late entries, withdrawals, no-show forfeits, correction after later
round, and no legal automatic pairing. Quads: sizes 4–500, equal ratings, leftover
5–7, fewer than four, entry arrival after partition and RR withdrawal rules.
Double games: individual results, two draws versus split wins, and export round
counts. Teams: substitute, missing board, match/game totals, team withdrawal and
historical membership. Prizes: cash splits, trophy priorities, overlapping classes,
unrated caps, no eligible recipient, pending/clinched state and manual overrides.

Use golden accepted export fixtures where rights/privacy allow; synthetic fixtures
for everyday tests. Never fabricate a passing federation upload result. Cross-check
printed totals, player histories and export games. Exercise save interruption and
restore with a disposable database. Test actual OS printing and package installation,
including non-ASCII paths and long names. Performance targets are measured on a
specified machine; aim for immediate local feedback and virtualized large rosters,
then record real latency rather than invent benchmark results.

## Evidence status must stay explicit

For each topic/feature track: discovered → archived → reviewed → specified →
implemented → tested → compared with reference. These are separate fields, not
one checkbox. “Archived” must never automatically mark “reviewed.” A completed
feature has a requirement ID, source links, exact supported variants, tests and
known gaps. A source topic may map to several IDs; a feature can span many pages.

Suggested first future-agent prompt:

> Read docs/BUILD_HANDOFF.md and its linked planning documents. First reconcile
> the SwissSys page checklist against the full capability map and identify any
> unsupported assumptions. Then propose the smallest first vertical slice with
> concrete acceptance fixtures. Preserve US Chess-first delivery and full-parity
> traceability. Do not silently approximate export formats or pairing rules. Build
> only the slice explicitly authorized in this task, and report its tested scope.

## Priority correction: the tournament day is the spec

Build the screens the timeline names: Check-in, Event preflight and end-of-day
lists, Post all ready sections with Print packet, the round clock, the event-wide
results grid and Lookup. Batch post is the default path; per-section review is
the exception. Use TD vocabulary in every visible label (Post, not Publish). The
K01–K22 gates in [Requirements](REQUIREMENTS.md) are release gates for the first
usable TD release, alongside D01–D07 and J01–J06.

## Priority correction: TD flexibility is core

Do not postpone basic section moves/combination to slice 6. Include direct editing
from every player name, byes, withdrawal/reinstatement, individual/bulk transfers,
and Quad 4 + Bottom Swiss combination in early slices. Historical changes require
explicit transition records, impact review and preserved played games. Complete the
acceptance cases in TD_OPERATIONS.md before calling the first TD release usable.

The earlier inline dropdown concept does not satisfy the user’s results-entry
requirement. The first results slice must exercise 1/0/5 and W/L/D immediate advance, correct half-point draw storage, reciprocal result updates, stable focus and fast correction.
Duty review also requires lightweight ruling/appeal handover, announced policy
visibility, house-player handling and submission-correction tracking at the scope
defined in the duty matrix. Do not replace those workflows with decorative dashboards.
