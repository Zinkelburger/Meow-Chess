# Requirements and acceptance criteria

Status: proposed specification, not implemented. **P0** = first usable TD release;
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
