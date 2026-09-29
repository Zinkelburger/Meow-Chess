# Delivery plan and research gates

> Expanded scope: [full SwissSys feature map](FULL_FEATURE_MAP.md),
> [current TD experience](TD_EXPERIENCE.md), and [build handoff](BUILD_HANDOFF.md).
> The initial US Chess release below is a tranche of the larger product target.


Planning completed for the accessible public evidence; application implementation
has not begun. These are dependency-ordered milestones, not time estimates. Unanswered
product preferences use the documented defaults rather than invented approval.

## 0. Evidence and policy decisions

Obtain an authorized US Chess API key; accepted SwissSys/WinTD DBF samples; a redacted
Boylston registration export; and the TD's rating, bye, tie-break and prize policies.
Confirm first-release platforms and the inclusion of online/team-league workflows.

Resolve reporting codes for Blitz, double rounds and mixed round counts. Transcribe
the official 2C field schema and record unresolved contradictions. Arrange a
permitted test-validation route with a TD/US Chess. This is necessary evidence for
release, not a reason to stop all independent domain/UI work later.

Exit: agreed supported-format matrix and a precise list of still-unverified
integration claims. Owner: product lead + experienced TD; provider answers require
US Chess. No messages were sent by this planning task.

## 1. Pure Dart domain and report conformance

Implement typed entrants/sections/games, score outcomes, basic RR/quad policy and
US Chess report mapping. Build independent fixtures for played/unplayed outcomes,
mixed sections and field limits. Create a narrow DBF codec or select a maintained
compatible library after evaluating available options; package choice is not
settled by this plan. Validate writer output with an independent decoder.

Exit: a synthetic mixed-quad event can produce internally correct reports and
pass the agreed external validation route. If reporting evidence is unavailable,
label this milestone partially verified and keep release blocked.

## 2. Durable event lifecycle

SQLite schema/migrations, commands, audit records, backups, revision checks, undo
boundaries and event file/open flow. Implement error recovery before UI polish.

Exit: crash, disk-full, duplicate command, stale write and restore scenarios preserve
all acknowledged results. One event can be copied/opened independently. No credentials
travel with the event.

## 3. Registration and identity

CSV/TSV/paste preview, mapping, duplicate handling, check-in, exact-ID lookup, bounded
candidate search, membership findings, rating provenance and review/apply batch.
Use synthetic responses while access is missing, then verify against authenticated
production behavior. Latest-rating semantics are a named acceptance gate.

Exit: a deliberately messy roster imports without silent identity corrections;
re-import and API failure do not damage the event. The TD can explain which rating
was selected and why, including cases where latest is unavailable.

## 4. One complete quad day

Build the reusable dark workspace and section tabs, quad preview, current-round
results, crosstable, print/PDF/ASCII and export center. Run 22 entrants through four
quads plus a six-player Swiss using hand-verified or TD-approved pairings until the
Swiss engine milestone is complete. Do not call that a shipped automatic Swiss.

Exit: full scripted day including absent entrant, ID correction, late arrival,
forfeit, old-result correction, printer preview and restart. TD reviews usability
and report content.

## 5. US Chess Swiss and double-round blitz

Implement/pin the chosen Swiss engine only after the rule matrix is reviewed.
Exercise score brackets, color history, swaps, byes, requested exclusions and
unsatisfiable constraints. Add double-game results and validated Blitz reporting.
Manual edit paths must obey the same structural invariants as automatic pairing.

Exit: rule-linked fixtures and TD-reviewed event replays, bounded responsive search,
validity comparison with an established program, and accepted supported exports.
Accelerated pairing is a separate tested policy if included in this release.

## 6. Desktop pilot and release qualification

Run on Windows/macOS/Linux with real file pickers and print/PDF workflows, keyboard
navigation, scaling, Unicode/ASCII cases and recovery. Have a TD run shadow scoring
alongside their established program before using Meow-Chess as the primary tool.
Check Linux printing, Windows printer drivers and macOS permissions/signing rather
than inferring support from one successful Linux build.

Exit: all P0 scenarios in [Requirements](REQUIREMENTS.md), license notices and source
distribution, packaging, backup recovery documentation, and known limitations.
Publishing/releases need a later explicit request; this task only plans.

## Later milestones

Individual-team scoring → permanent bughouse teams → online events/double quads →
fixed-roster leagues → experimental rotating-partner pairing → FIDE conformance.
Reorder according to TD feedback. Hosted registration/payments and collaborative
editing are independent later projects, not hidden prerequisites.

## Test strategy

| Layer | Meaningful evidence |
|---|---|
| Domain | Exact outcome/tie-break examples; invariants; rule-number fixtures |
| Quad grouping | Boundary counts, conservation, no duplicate entrants, deterministic sorting |
| Swiss | Hand-reviewed adversarial cases; metamorphic invariance to input container order; allowed exceptions |
| Storage | Transaction rollback/crash, backup/restore, migration and multi-instance lock checks |
| API | Nullable fields, unknown enums, missing/expired key, pagination, throttling, out-of-order completion |
| Import | Quoting/BOM/encoding, ambiguous headers, provisional ratings, duplicate IDs, re-import |
| Reports | Independent DBF parser, known accepted files, source-revision consistency, strict ASCII and page layout |
| UI | Keyboard TD tasks, retained tabs, 200% scaling, screen-reader labels, visible errors |
| System | Complete quad/Swiss/blitz days, disconnect/restart/correction during play |

Do not test only a writer against its own reader or an algorithm against itself.
Do not equate valid serialization with portal acceptance. No fake tournament is
submitted to the real rating system as a test.

## Small experiment included now

`poc/quad_partition.dart` is a standalone Dart experiment, not app scaffolding. It
checks the proposed field partition from 4–500 entrants, rejects counts below four,
and checks all four last-round color toss combinations for the preferred quad
schedule. It proves group arithmetic, participant conservation, pair uniqueness
and color counts only. It does not prove Swiss pairing, ranking fairness, ID
validation, printing, federation conformance or an application's correctness.

Run: `dart run poc/quad_partition.dart`. Results are recorded in
`../research/VALIDATION.md` after this planning pass.

Potential later spikes, each with an explicit question: DBF codec against current
accepted files; actual US Chess live-rating semantics; printer/PDF behavior on each
desktop OS; cancellable worst-case Swiss search; and Bayesian bughouse simulation.
Avoid building a throwaway UI until those risks have clear answers.

## Remaining interview / evidence checklist

| Priority | Question / evidence | Default or consequence |
|---|---|---|
| Before implementation scope freeze | Windows/macOS/Linux only initially? Tablet needed at a venue? | Desktop first recommended |
| Before first import adapter freeze | Actual Boylston/admin export, SwissSys version and sample files | Generic CSV/paste works independently; native compatibility remains unverified |
| Before rating feature sign-off | Key and provider confirmation of latest/unofficial behavior | Preserve unavailable state; no unsupported “live” claim |
| Before pairing policy freeze | Published/live/assigned seeding and eligibility; ties/unrated placement | Explicit event policy with TD review, no global guess |
| Before first pilot | Bye deadlines, withdrawals, tie-break order, shared prizes, check-in rules | Template choices recorded per event |
| Before coverage claim | Online double quads, accelerated rapid, league and series required at launch? | Stage after core OTB formats |
| Before bughouse implementation | Permanent/rotating teams, repeat games, sit-outs, scoring and goal | Permanent teams, conventional standings recommended |
| Before distribution | AGPLv3-only or later, app signing, target OS minimums | Preserve existing license; settle headers and packaging explicitly |
| Before compliance claim | Current accepted DBF fixtures and authorized portal validation | Hard release gate |

A research question is not automatically an implementation blocker. Continue
independent work when authorized later, while maintaining truthful capability
status for contracts that cannot yet be tested.

## Core TD flexibility gate

The first usable release also requires all [TD operations](TD_OPERATIONS.md): direct
player editing, round-specific byes, withdraw/reinstate, individual/bulk transfers,
and combining quad/Swiss sections. Exercise the 4+6→10 example before play, after
publication and through a supported same-progress post-play transition. These are
early vertical-slice requirements, not part of a later specialist-parity backlog.
