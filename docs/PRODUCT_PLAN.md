# Product plan

> Expanded scope: [full SwissSys feature map](FULL_FEATURE_MAP.md),
> [current TD experience](TD_EXPERIENCE.md), and [build handoff](BUILD_HANDOFF.md).
> The initial US Chess release below is a tranche of the larger product target.


Build a calm, dependable tool for the person running the tournament. The important
moment is not creating an impressive dashboard: it is checking in the last player,
making sensible sections, posting round one, correcting a result, and leaving with
a report US Chess can accept. [A tournament day, in order](TD_DAY.md) puts those
moments on the clock with targets; the usability gates K01–K23 in
[Requirements](REQUIREMENTS.md) make them release criteria.

## Decisions proposed now

1. Flutter on Windows, macOS, and Linux desktop first. Mobile/tablet layouts and a
   web viewer can follow. Shared Dart logic makes this possible; it does not make
   printing, file access, secure storage, and native pairing executables identical
   across platforms.
2. One locally owned event document; no account or network needed to run rounds.
   Network access enriches registrations and ratings. A failed lookup never stops
   result entry or printing.
3. US Chess individual Swiss and quads are the core. Include double-round blitz
   before claiming coverage of Boylston's common OTB calendar. Quads need a real
   guided workflow, not a hidden combination of generic section operations.
4. Keep US Chess reporting, SwissSys interchange, and human-readable reports as
   independent capabilities. “SwissSys-compatible” must always name the format
   and tested version.
5. Use the existing AGPLv3 license. Preserve upstream notices if code is reused.
   A third-party reference archive does not become AGPL because it is nearby.

## First usable release

Create/open/recover an event; import or paste a roster; review identity problems;
fetch ratings where available; freeze the event's chosen rating policy; divide
quads; run individual Swiss/RR sections; enter and correct results; show standings;
print pairings and ASCII crosstables; export a validated US Chess DBF package.

The release must handle mixed quad/Swiss events, normal and double-game rounds,
late registrations, byes, withdrawals, missing results, manual pairing overrides,
and interrupted writes. A beautiful roster with unverified exports is not a usable
tournament program.

US Chess reporting is a release gate, not an end-of-project afterthought. Establish
the schema and a TD-assisted validation route early. Independently rehearse the
core TD interactions before broad UI implementation; missing API credentials must
not postpone finding basic usability problems. See [usability review](TD_USABILITY_REVIEW.md).

## Subsequent scope, explicitly retained

| Capability | Proposed phase | Reason |
|---|---|---|
| Team/club labels | First release | Editable/importable labels are a core player operation |
| Individual team standings | First extension | Explicit aggregation policy, distinct from matching teams |
| Fixed two-person bughouse teams | First extension | Separate, unrated match model; user explicitly wants this |
| Rotating-partner bughouse / adaptive matchmaking | Experimental extension | Requires a fairness policy and evaluation, not just Elo arithmetic |
| US Chess online events / six-week double quads | Next calendar-coverage phase | Separate online rating systems and reporting rules |
| Multi-board fixed-roster team leagues | Next calendar-coverage phase | Board order, reserves, match points, season schedule, playoffs |
| Accelerated pairings, advanced prizes and series | Explicitly validated extensions | Some Boylston events use these; ordinary Swiss is not full parity |
| Native SwissSys SJSON round trip | After real fixtures and schema/version checks | No public formal contract established in this pass |
| FIDE Dutch and TRF26 | Future federation adapter | Different pairing/rating/reporting requirements and endorsement work |
| Cloud registration, payments, SMS, multi-TD editing | Deferred | Independent products and distributed-state complexity |

“All Boylston events” is a larger target than an initial Swiss/quad application.
The [survey](../research/notes/BOYLSTON.md) makes that gap explicit.

## Product principles

- Preserve original input. Name/ID corrections are reviewed, attributed decisions.
- Explain a pairing or a validation problem at the board/player where it matters.
- Treat posted pairings as a published revision. Corrections produce a new revision.
- Never silently reshuffle sections or reinterpret a completed game.
- Separate competition scores, prize standings, and ratable games.
- Save durably before displaying “Saved.” Make recovery understandable.
- Prefer a small complete workflow over a menu of unfinished features.
- Put time on screen. The TD should never need a separate clock to answer “when?”
- The default path is the batch path. Review is for warnings, not for every round.
- Speak TD: post, wall sheet, pairing number, house player. Never “publish” as a verb.
- Survive interruption. Nothing half-done is lost when the TD walks away.

## Main view

An event workspace with persistent **Event + one top tab per section**.
Within a section: Players, Rounds, Standings, Reports, conditional Teams, and Section
settings. Crosstable and prize views live within Standings. New sections open
Players; existing sections resume the last view, round, selection and scroll.
Event-wide Find player opens editable details and returns to the interrupted task.
The authoritative interaction contract is [TD experience](TD_EXPERIENCE.md), with
[TD operations](TD_OPERATIONS.md) and [results entry](RESULT_ENTRY.md) for details.

Use compact dark surfaces, Inter and Source Code Pro, strong keyboard navigation,
and restrained accents informed by Chess Auto Prep V2. Printing has its own white
paper layout. See [UX](UX.md).

## Decisions still needing the TD's input

The current recommendations stand for planning until answered: desktop first;
OTB Swiss/quads/double blitz before online and leagues; permanent bughouse teams
before rotating partners. We also need actual sample exports and a chosen rating
policy. A prioritized interview and evidence checklist lives in
[Delivery](DELIVERY.md). The user subsequently authorized implementation. See IMPLEMENTATION.md for delivered scope and evidence.
