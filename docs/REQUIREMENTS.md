# Requirements and acceptance criteria

Status: target specification. See IMPLEMENTATION.md for the tested implementation and outstanding release gates. **P0** = first usable TD release;
**P1** = next extension; **Research** = capability whose contract is unresolved.
Every P0 must pass its acceptance scenario before that release is called complete.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| E01 | P0 | Create, duplicate template, open, save and recover an event | Restart after recording a result and recover the last acknowledged revision |
| E02 | P0 | Multiple sections, independent format/round/settings, stable IDs | Four quads and a six-player Swiss coexist without sharing round state |
| E03 | P0 | Event and section dates, time controls, venue, affiliate and TD metadata | Export preflight identifies a missing/invalid value at its owning field |
| E04 | P0 | Copy template settings into the new event | Editing a club default cannot mutate an event already in progress |
| I01 | P0 | CSV/TSV and pasted-table mapping with preview | Reordered columns, quoted commas/newlines, BOM and leading-zero IDs import correctly |
| I02 | P0 | Keep raw import rows, source and corrections | Re-import does not duplicate confirmed entries or erase TD corrections |
| I03 | P0 | Name/ID conflict and duplicate review | A valid ID for a different name remains unresolved until TD selection |
| I04 | P0 | Check-in, inactive, withdrawn, late entry and reserved byes | An absent player is not paired; late entry preserves earlier-round history |
| I05 | P1 | Narrow Boylston table adapter | Entries are selected separately from results and extraction is previewed |
| I06 | Research | SwissSys SJSON import/export | Versioned real fixtures round-trip without dropping sections/results/byes |
| R01 | P0 | Exact-ID API lookup and bounded name search | 401, 404, 429, timeout and partial batches are distinguishable |
| R02 | P0 | Separate published/live/imported/assigned ratings | “Latest unavailable” stays visible; monthly data is never silently labelled live |
| R03 | P0 | Bulk validate/update with before/after review | Confirmed IDs and selected fields change atomically, with original values retained |
| R04 | P0 | Membership findings and offline cache | Expiration on the event date is checked; offline findings show age/source |
| R05 | P0 | Freeze pairing and eligibility ratings | A later API refresh leaves published pairings and section assignments unchanged |
| Q01 | P0 | Preview rating-sorted quad partition | 20→5 quads; 21→4 quads+5 Swiss; 22→4+6; 23→4+7; 24→6 quads |
| Q02 | P0 | Tie/unrated placement and manual group edits | TD can move a player before pairing; duplicates and lost players are rejected |
| Q03 | P0 | Explicit tiny/odd field handling | Under four requires a choice; a 5/7-player Swiss warns about sitting rounds |
| Q04 | P0 | Approved quad schedule and locked assignment | All six unordered pairs occur once; each round covers every player once |
| P01 | P0 | Versioned US Chess Swiss policy | Rule-linked fixtures cover score groups, transpositions, byes, colors and exceptions |
| P02 | P0 | Pairing proposal, review, publish and manual overrides | Stale proposals fail; override records reason and re-runs integrity checks |
| P03 | P0 | Double-round games | Six pairing rounds produce 12 games/player; both colors and results are preserved |
| P04 | P0 | No unexplained fallback | Unsatisfiable constraints identify conflicts rather than inventing illegal pairings |
| G01 | P0 | Large keyboard results grid with automatic advancement | 1/0/5 and W/L/D save and advance without Enter; 5 means a half-point draw; held keys never fill multiple games; see RESULT_ENTRY.md |
| G02 | P0 | Distinct played result, forfeit, bye, absence | Equal scores from a win and a bye remain different for rating and tie-breaks |
| G03 | P0 | Revisioned corrections | Earlier result correction marks dependent standings/pairing proposals stale |
| G04 | P0 | RR withdrawal semantics | Completed games remain in rating history even when excluded from prize standings |
| S01 | P0 | Crosstable, standings, configured tie-break order | Recalculation from game records matches independent expected examples |
| S02 | P0 | Tie-break/prize policies fixed for the event | A late policy change requires a visible revision; no quiet reordering |
| T01 | P0 | Assign a team/club label to a player | Labels import, edit and appear in chosen reports without implying team matches |
| T02 | P1 | Individual-team score aggregation | Best-N/all-player scoring is explicit and separate from individual standings |
| T03 | P1 | Fixed-roster multi-board team matches | Board and match points differ; lineups are retained per round |
| B01 | P1 | Permanent two-player bughouse teams | Four distinct people per match, partner colors opposite, one match outcome |
| B02 | Research | Rotating partners / adaptive balance | Simulation demonstrates fair sit-outs, partner variety and calibrated uncertainty |
| O01 | P0 | Print current/all sections | Legible Letter/A4 preview with repeated headers and no clipped player/round columns |
| O02 | P0 | ASCII crosstable export/print | Output uses only ASCII; names needing transliteration are previewed; width is stable |
| O03 | P0 | PDF and CSV reports from one snapshot | Same revision produces consistent scores/sections in every renderer |
| U01 | P0 | Three-file US Chess DBF export | Independent reader validates structure and cross-record integrity |
| U02 | P0 | Tested portal compatibility | Authorized TD/test workflow accepts representative supported event exports |
| U03 | P0 | Export package and history | Crash cannot mix revisions across the three files; report package is traceable |
| N01 | P0 | Offline event operation | Disconnect after import: pair, score, print, save and reopen all work |
| N02 | P0 | Crash-safe storage and backup | Kill between transaction stages: old or new state survives, never half a result |
| N03 | P0 | Safe schema migration | Backup before upgrade; failed migration preserves recoverable original |
| N04 | P0 | Three-desktop-platform qualification | File chooser, fonts, printing/PDF, keyboard, secure key storage and recovery tested on each |
| N05 | P0 | Accessible dense UI | Keyboard-only use, screen-reader labels, non-color status and 200% text verified |
| N06 | P0 | Data minimization and export boundaries | Public reports omit contact/birth/private notes and credentials |
| F01 | Future | Federation-independent IDs/rating categories | FIDE ID/rating can coexist without changing US Chess entry identity |
| F02 | Future | FIDE Dutch/TRF26 | Current rules, exact engine version and official validation path documented |

## Core TD flexibility — explicit first-release gates

See [TD operations](TD_OPERATIONS.md). These supplement the earlier requirements;
UI access and safe historical behavior are both required, not optional polish.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| D01 | P0 | Double-click/Enter opens editable player with visible Byes/Move/Withdraw | Same record/actions from roster, pairings and standings; editing US Chess ID preserves provenance |
| D02 | P0 | Round-specific bye editor and cancellation | Requested/allocated/forfeit outcomes distinct; current game conflicts resolved explicitly |
| D03 | P0 | Withdraw/reinstate effective from a selected round | Preserve played games; unresolved pairing never silently becomes a loss |
| D04 | P0 | Individual/bulk section transfer before and after play | Retain entry lineage, reviewed scoring/byes and export attribution; no overlapping pairing |
| D05 | P0 | Combine sections directly, including quads into Swiss | Quad 4 + bottom six becomes ten-player Swiss; other sections unchanged; pre-play undo exact |
| D06 | P0 | Reviewed transitions after publication/play | Confirm whether games started; retain played games; same-progress merge has tested score/prize/reporting mapping |
| D07 | P0 | Dependency-aware undo and actionable conflict resolution | No silent partial batch, historical deletion, fabricated game or approximation of unsupported export |

## Duty-based workflow gaps

Basis and scope are recorded in [TD duties](../research/notes/TD_DUTIES.md).
The UI mechanisms below are proposals, not keystrokes mandated by US Chess.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| J01 | P0 | Separate unfinished/unreported/disputed result from temporary pairing treatment | TD can use supported next-round procedure without inventing a final draw or rating result |
| J02 | P0 | Effective announced event conditions and changes | TD can see the published bye/prize/eligibility policy at the point of decision |
| J03 | P0 | Lightweight private ruling/appeal record and handover | Game-linked decision, responsible TD and unresolved status survive restart; excluded from public reports |
| J04 | P0 | House-player role and reviewed manual extra-game handling | Distinguish house player from ordinary entrant, membership exception and prize eligibility; preserve actual opponent |
| J05 | P0 | Submission/correction follow-through | Export, portal submission and acceptance are different; correction identifies original event and changed records |
| J06 | P0 | Results-entry usability rehearsal | Enter 20 outcomes with blanks/correction keyboard-only; stable perspective/focus; no wrong reciprocal result |

## Tournament-day usability gates

Derived from [a tournament day, in order](TD_DAY.md). These exist because the plan
was strong on correctness and weak on the clock-driven physical flow: the door, the
wall, the walk around the room, the next-round deadline. All are proposed
interactions to rehearse with TDs, not federation mandates.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| K01 | P0 | Check-in mode: keyboard mark-present, inline walk-up registration, “not yet here” filter/print, once-per-round policy for unchecked pre-registrations | 40 check-ins and 3 walk-ups in under five minutes keyboard-only; 3 absentees resolved with one choice, not three dialogs |
| K02 | P0 | Door-side resolution of validation findings: renewed on site, TD exception with note, leave open | Resolution and reason visible in round-one preflight and export preflight; flag never silently disappears |
| K03 | P0 | Section eligibility check at import, check-in and transfer: rating ceiling/floor, age or grade where configured | A 1520 entered in U1500 is flagged at each entry point with a move-up option; override records a reason |
| K04 | P0 | Round-one preflight and end-of-day checklists on the Event tab; each row opens the resolving action | Every blocker in the example lists in TD_DAY.md is reachable in one click; no row is a dead checkbox |
| K05 | P0 | Post all ready sections in one action with a combined print job; per-section review only when a warning exists | Quads day: make quads → post → print in three actions; 15 warning-free quad rounds open zero review screens |
| K06 | P0 | Round clock: scheduled start, estimated finish from the actual start, time control and an explicit move-count assumption, boards still playing; multi-day events open on today's round | Tuesday Swiss opened on week 3 shows round 3 without navigation; posting pairings does not start the clock; G/65 d10 shows an estimate with its move-count assumption, never an “ends by” guarantee |
| K07 | P0 | Event-wide results grid in global board order with the same keystrokes as the section grid | 20 results across five sections entered without changing tabs; section standings update correctly |
| K08 | P0 | Forfeit keystrokes and a post-forfeit offer to withdraw the absent player | F then 1/0 records a forfeit win/loss, X a double forfeit; the withdraw offer can be declined without side effects |
| K09 | P0 | Printed pairing sheet is the result-collection instrument: identical board order to the entry grid, writable result column, time control and round start in the header, reprint one section | Results transcribed from the sheet in board order with no reordering; a one-section reprint changes no other page |
| K10 | P0 | Pairing sheets: one quad per page with its complete round-robin draw; Swiss prints the selected posted round. Plain grid columns: Board, Result, White, Black, Result; both result cells blank for handwriting | Each section starts on a new page; a quad fits on one sheet with unused space blank. No roster, alphabetical list or standings appended; large Swiss fields may continue on another page |
| K11 | P0 | Player lookup by name or pairing number: board, color, opponent, score, next bye, in a large panel that can face the player; never enters a result | Lookup in under five seconds; typing W or 1 in lookup changes nothing |
| K12 | P0 | Pairing numbers visible and searchable everywhere a player appears | “Number 14” finds the same player from Players, Rounds, Standings and lookup |
| K13 | P0 | Global shortcut table (find, print, undo, next/previous section, next missing result, zoom) and Undo that names its action | Undo control reads “Undo result, board 9”; workspace zoom does not clip actions |
| K14 | P0 | Interruption survival: any half-completed form, draft or entry sequence persists across navigation and restart | Abandon a half-filled walk-up form, restart the app, resume it |
| K15 | P0 | Secondary backup folder receives a consistent copy at every posted round and at export; continue on another laptop is a rehearsed scenario | Open the secondary copy on a second machine and recover exactly the last verified backup revision; edits saved locally after that copy are explicitly outside the secondary recovery guarantee. A handoff first makes and verifies a fresh copy |
| K16 | P0 | Practice copy of any event: one action, clearly marked, cannot export a rating report | A newer TD rehearses a round on the copy; the real event is untouched |
| K17 | P0 | Standings filtered and grouped by prize class, on screen and in print | U1900 prize winners readable from the class view without a calculator |
| K18 | P0 | Private notes on a player or event, shown at check-in, in the inspector and in the pairing draft | “Must leave by 3” is visible when posting round 3; never printed on public reports |
| K19 | P0 | Late add asks about missed rounds inline | Adding a player after round 1 records the round-1 treatment in the same flow; no separate trip to the bye editor |
| K20 | P0 | Bye recipient and reason at the top of every draft and posted round | The odd section's bye is the first line, with the rule-linked reason |
| K21 | P0 | Merge suggestion from the announced section minimum before round one | A six-player section under an announced minimum of eight proposes Combine with the adjacent section; declining is one action |
| K22 | P0 | TD vocabulary in the UI: Post/Posted for the local revision, Share online for the network action, wall sheet, pairing number, house player | Terminology reviewed with two TDs before the first pilot; “Publish” does not appear as a visible verb |
| K23 | P1 | Second-screen read-only pairings/standings display for a TV or projector, no network required | Display follows the last posted revision and never shows private fields |

## Usability contracts across workflows

[TD usability review](TD_USABILITY_REVIEW.md) explains the original gap and evidence
for each contract. These tighten existing capabilities; they do not assert that a
prototype or TD study has passed. R1–R10 refer to that document's rehearsal scripts.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| UX01 | P0 | Event-wide find and return to task | Find duplicate surnames by name/ID with section/board context; edit correct entry and restore original cursor; R1/R3 |
| UX02 | P0 | Fast offline walk-in registration | Save name + destination with missing ID/rating flagged; Save & add another; explicit late-entry treatment; R1 |
| UX03 | P0 | Explicit attendance policy and complete pool accounting | Check-in on/off cases account for every entry/exclusion; import never asserts presence; R2 |
| UX04 | P0 | Safe rapid results and interruption recovery | Ordered stable-ID buffering under delayed writes; historical browse guard; zero wrong-game edits; RESULT_ENTRY.md fixtures and R3/R7 |
| UX05 | P0 | Section-local progress and exact missing-game navigation | One section advances while another remains unfinished; unrelated result does not invalidate proposal; R4 |
| UX06 | P0 | Validation blocks the relevant action only | Missing export metadata or API outage does not stop unrelated scoring/printing; real eligibility issue remains actionable; R1/R4 |
| UX07 | P0 | Clear save and bulk-selection scope | Dirty inspector never looks saved; hidden selected rows counted/named; routine edit needs no second confirmation; R1/R5 |
| UX08 | P0 | Fast repeat printing with independent delivery status | Remembered preset, visible scope/revision, retry without new pairing; R8 |
| UX09 | P0 | Distinct approval, play, printing and online status | Approve does not imply posted/printed/started; empty result not proof game unstarted; R4/R6/R8 |
| UX10 | P0 | Exact effective rounds and preserved constraints | Withdrawal/transfer shows date/round/current game, byes and reserved boards; R5/R6 |
| UX11 | P0 | Focused field-specific identity/rating review | Changes/problems first; accepting spelling does not change seeding; stale lookup cannot overwrite edit; R1 |
| UX12 | P0 | Understandable restore and handover | Active event/date/file clear; backup state separate; restore new copy; unresolved games/rulings visible; R9 |
| UX13 | P0 | Canonical interaction contracts and observed rehearsals | R1–R10 completed in relevant supported flows, errors/assists recorded; serious data/targeting faults block release; accessible paths included |
| UX14 | P0 | Local pairing repair without whole-round regeneration | Eligible-opponent picker, explicit swap/rearrangement preview, preserved unaffected/locked boards; started games protected; R4 |

## History and recovery — preserved progress

[History and recovery](HISTORY_AND_RECOVERY.md) strengthens the earlier audit/undo
requirements. These are first-release requirements, not implemented behavior.

| ID | Priority | Requirement | Acceptance scenario |
|---|---|---|---|
| H01 | P0 | Read-only timeline, historical preview and comparison | Browse past revisions without changing live state; Return restores workspace context |
| H02 | P0 | Persistent named Undo/Redo with preserved former states | Undo then a different edit or restart never makes former committed work unrecoverable |
| H03 | P0 | Scoped Reopen before pairing round X | Save pre-operation version; retain current reviewed player data, earlier games and unaffected sections |
| H04 | P0 | Retain and return between continuations | Edit after reopening, restart, then recover both alternatives with clear live/planning status |
| H05 | P0 | Dependency and actual-game checks when reopening/promoting | No real game lost from official state/reporting; transfers and external actions reconciled |
| H06 | P0 | Recover selected supported changes | Preview/diff and domain commands preserve stable identity; no implicit general merge |
| H07 | P0 | Atomic history/state changes and validated recovery | History-write failure cannot acknowledge mutation; bad checkpoints/migration preserve original |
| H08 | P0 | Full history in event copies and backups | Second machine opens saved revision plus all retained version heads; copy age explicit |
| H09 | P0 | Preserve external publication/submission facts | Restoring cannot erase submission status or resend automatically; stale output is actionable |
| H10 | P0 | Complete, responsive history reconstruction | All mutation types and retained revisions verified in 500-entry stress fixture; no invented benchmark claim |

## Core invariants

- Stable person, entry, section, round and game IDs. A row sort never changes them.
- Entry is event-specific; a person can have multiple authorized entries.
- No player is scheduled into two overlapping games. Double-round legs are
  sequential, not simultaneous. Future team/bughouse matches reserve all participants.
- A played game has exactly two distinct entrants and complementary results,
  except a specifically modelled, reviewed federation exception.
- A bye has no opponent; an unplayed paired game can still retain one internally.
- Use exact score units (e.g. half-points as integers); never use floating point
  equality to establish competition standings.
- Registration pool → sections is a partition: no missing or duplicated entrants.
- Published pairings retain their input revision, policy version and random seed
  or actual color-lot decisions.
- Competition result, prize contribution and rating eligibility are independent.
- Finalization is not irreversible deletion. Corrections produce a new revision
  and clearly invalidate older export packages.

## Proposed operational targets

Qualify at 100 entrants for Boylston, with a 500-entrant synthetic stress case;
these are design targets, not measured performance. Normal result edits should
acknowledge durable save within 250 ms on the agreed reference laptop; opening a
100-player event should take under 2 seconds. Pairing search must be cancellable
and must not block input; a bounded search can report “needs TD resolution.”

Durability and correct results take precedence over a target timing. Measure p95
interaction latency and restoration correctness before assigning hard marketing
claims. No benchmarks have been run on a product that does not yet exist.
