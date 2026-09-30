# Review of Fable's tournament-day additions

Reviewed September 29, 2026 UTC against the uncommitted main-checkout edits based
on `396fc34`, including the new `TD_DAY.md`. [Snapshot metadata](../research/fable-review-snapshot.json)
identifies exactly which versions were reviewed; copies are in the ignored local
reference cache. This is a review and reconciliation proposal, not an implementation
or an assertion that the two branches have been merged. Fable's source edits remain
untouched. Our complementary baseline is [TD usability review](TD_USABILITY_REVIEW.md).

## Assessment

The direction is good: registration at the door, physical paper, interruptions and
round turnaround are better organizing principles than a competitor's menu tree.
Keep the tournament-day narrative. Several added contracts, however, infer facts
that the application does not know or promise guarantees the proposed mechanism
cannot deliver. Correct those before giving both documents to a build agent.

## Keep these additions

- Fast check-in with walk-up registration and a printable not-yet-here list.
- One round packet containing board-order pairings, alphabetical pairings and
  optionally standings; writeable result space matching the results grid.
- Event-wide results as an optional saved view of the same game records/editor.
- Read-only player lookup that is safe to show a player, separate from editing.
- Actionable preflight and closing checklists; every issue opens its resolution.
- Private operational notes, clearly separate from public reports.
- A consistent secondary backup and a rehearsed second-laptop handoff.
- A clearly marked practice copy and later read-only external display, with scope
  matched to the release rather than automatically promoting every idea to P0.

## Corrections before implementation

Locations below refer to the captured main-checkout version, not the different
line positions in the usability worktree.

| Finding | Location / trigger | Correction and acceptance consequence |
|---|---|---|
| F01 — high: posting is not starting | `TD_EXPERIENCE.md:182`, K06: posting starts the clock | Keep planned start, optional actual start, approved pairings, print status and result completeness independent. Pairings prepared ten minutes early must not claim games started. Replace automatic switching to today's round with an offer; preserve an unfinished earlier round and the TD's current work. |
| F02 — high: missing results are not live game telemetry | `TD_EXPERIENCE.md:26`, K06: “boards still playing” | Use “results missing” unless the TD explicitly records a playing state. A finished game with an unreturned slip is still unreported; an empty cell does not authorize a re-pair. Do not require continuous per-board start/finish tracking to use the app. |
| F03 — high: a secondary snapshot is not zero-loss replication | K15; `TD_EXPERIENCE.md:247` | Posting/export-only snapshots omit results recorded between those moments. Show copied revision/time and edits since that copy. A planned handoff must make and verify a fresh consistent copy containing the latest acknowledged edits; loss of the source laptop can recover only the last successfully copied revision. Missing USB/sync completion remains visible; avoid claiming a file written to a sync folder reached another device. |
| F04 — high: event-wide entry needs per-row round identity | `RESULT_ENTRY.md:12`, K07 | Quad 1 can be in round 3 while the bottom Swiss is in round 2. Show section, round, leg where relevant, board and players on every row/group. Freeze the selected game set during entry; approval of another round must not insert new targets. Board numbering can be event-wide by default, but section/room scope and stable game IDs remain explicit. |
| F05 — high: no automatic two-game undo for 0 then 5 | `RESULT_ENTRY.md:141` | Those keys can legitimately mean loss on board A and draw on board B. The app cannot infer that the user meant decimal 0.5. Keep one named command per Undo; offer an explicit reviewed selection of recent entries for multi-game correction. Do not guess from typing speed. Preserve the user's immediate 1/0/5 contract. |
| F06 — high: cash winners do not follow from filtering | K17; `TD_DAY.md:149` | Keep prize-class filters, but label them eligible standings until supported allocation rules are applied. Overlapping overall/class prizes and tied cash splits require policy-aware allocation or an explicit manual worksheet. A class's first row is not automatically its cash winner; pending results/rulings must stay visible. |
| F07 — high: generic exceptions do not establish federation eligibility | K02; `TD_EXPERIENCE.md:126` | Distinguish reported renewal/pending verification, a documented permitted exception, and an unresolved finding. A typed reason cannot turn unknown membership into verified status or guarantee acceptance. Preserve real played games while resolving reporting issues. Store the specific authority/evidence when an exception applies. |
| F08 — high: forfeit shortcuts need narrower semantics | `RESULT_ENTRY.md:47–49,109–113,142`, K08 | Define F-prefix outcomes explicitly as unplayed/no-show outcomes if that is their purpose; a loss on time in a played game is not the same thing. Offer withdrawal only for an identified absent entrant, whichever color lost, and never steal focus from the next result. Double forfeits can involve two separate absence decisions. Reset the F modifier on cancel/focus or target change; it cannot leak onto another board. |
| F09 — high: batch approval needs an exact visible scope | K05; `TD_EXPERIENCE.md:170` | Keep a fast Approve selected ready sections action with a compact section/round/player-count summary and optional detail expansion. Validate all selected inputs at commit and specify all-or-none behavior for that reviewed set. Other sections can stay unresolved; never silently omit a failing selected section or include one that became ready after the TD clicked. A warning-free state does not replace input validation or player-pool accounting. |
| F10 — medium: drafts are not committed outcomes | K14; `TD_EXPERIENCE.md:282` | Resume form/import drafts separately from official event records and label their recovery state. Never execute buffered result commands or an F modifier automatically on restart. Only durably committed results count as saved; partially typed forms can be recovered as drafts with Save/Discard. “Every half-done action survives” needs bounded, testable semantics. |

The timeline's pairing-swap example (`TD_DAY.md:101`) also needs the explicit
not-started check from [TD operations](TD_OPERATIONS.md): retain games already
underway and use the appropriate participation/correction path. Speed targets do
not authorize rewriting played pairings.

## Source-backed checks

The current [US Chess rules](https://new.uschess.org/sites/default/files/media/documents/us-chess-rule-book-online-2026.pdf)
distinguish clock provisions, game-loss circumstances and prize allocation. Their
clock provisions support an estimate with disclosed move assumptions, not an exact
finish inferred from a G/65 d10 label. Rules 32B/34C require attention to cash-prize
pooling and tied awards. Rule 13I covers losses imposed for rule violations, so
“forfeit” cannot universally mean an absent player or an unplayed game. These are
reasons to retain explicit outcome and policy distinctions.

The [US Chess TD FAQ](https://new.uschess.org/tournament-director-and-affiliate-frequently-asked-questions)
describes membership validation and specific exceptions; a local note is not
provider confirmation. It also defines X as a **forfeit win** in its result-entry/
reporting vocabulary. Our keys need not match report codes, but choosing bare X for
a double forfeit is an avoidable mismatch for experienced users. Prefer a clearly
labelled outcome-menu command or an explicit forfeit-prefix selection. Keep UI
shortcuts and federation serialization separately specified.

Remove the unsupported claim that no-shows are the second most common outcome.
Neither reviewing the rulebook nor reading a competitor manual establishes that
frequency. These sources are already in the local research library; this pass
rechecked the current pages. No TD interview or product usage measurement occurred.

## Reconcile these design choices

1. **Terminology:** our proposed Approve pairings / Print / Post online is clearer
   about three separate facts. Fable's Post / Share online could work if tested,
   but “posted” can also imply paper is on the wall. Use the explicit three-action
   wording as the working contract until TD testing establishes a better label.
   Do not claim all TDs interpret “publish” in one particular way.
2. **Navigation:** Check-in can be a focused mode of Players; Lookup can be a
   read-only variant of event-wide Find; the all-section results grid belongs in
   Event. These need direct access, not necessarily three more permanent tabs.
   Keep section views and remember the TD's choice rather than forcing a universal
   event-wide default or automatically changing screens at the end of the day.
3. **Identity:** pairing numbers are scoped to an event/section and revision where
   renumbering is possible; they are not federation IDs or stable person IDs.
   Search must disambiguate “number 14” across sections. Keep section/board labels
   in a player-facing lookup, and suppress private notes there.
4. **Attendance:** use the explicit check-in policy in the usability review.
   Bulk resolution names the selected entries and round; it cannot silently turn
   every unchecked player into an identical scored bye. A fuzzy search with no
   match offers Add player, never creates an entry from a typo automatically.
5. **Shortcuts:** suppress result commands in text fields while preserving native
   text editing, including field-local Undo. The blanket “shortcuts never fire”
   statement needs that distinction. Resolve OS-reserved bindings per platform;
   do not let an unmodified Shift+Z become global redo accidentally.
6. **Timings and scope:** three top-level actions is a useful familiar-user target,
   not permission to eliminate quad review, eligibility decisions or printer UI.
   Hardware/network speed is not a product guarantee. Keep core lookup, print and
   participation flows early; basic schedule display can precede forecasting,
   and practice-copy UX need not delay a usable core release. The timeline is a
   walkthrough, not the only test of scope: weekly events, post-submission fixes,
   recovery and accessibility also matter.

## Three additional ideas worth testing

These refine existing work surfaces rather than expanding the menu tree.

- **A short recent-results strip:** show the last few saved outcomes with section,
  round, board and a direct correction action. It makes a shifted run of paper slips
  visible without scrolling back. Duplicate matching slips can show Already recorded;
  a conflicting slip opens correction rather than silently overwriting. Read this
  from command history, with pending writes visually distinct.
- **Changes since the last wall sheet:** after a withdrawal, board move or pairing
  repair, list affected players/boards and offer reprint of the affected section.
  Keep generated/sent-to-printer status separate from a TD's optional marked-posted
  status. This closes the gap between correct software and outdated paper.
- **Turn an operational note into an explicit action:** beside “needs round-3 bye,”
  offer Open bye editor prefilled with that player/round only after TD selection.
  Free text alone must never reserve a bye, withdraw someone or change their score.
  Keep the note and structured reservation linked so the TD sees whether it was handled.

## Focused combined rehearsal

Use two sections on different rounds; enter a legitimate 0 then 5; register a
player with an offline renewal claim; post pairings early; cancel printing; enter
three more results after the last secondary copy; repair one unstarted board; then
complete a fresh handoff and award a tied overlapping class prize. The TD must be
able to explain what is saved, approved, printed, backed up and still unresolved.
No component or click-count demo alone proves this workflow works.
