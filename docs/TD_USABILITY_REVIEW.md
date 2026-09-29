# TD usability review and rehearsal plan

Status: planning review, September 29, 2026 UTC. No application implementation or
observed TD usability study. This review tightens existing workflows; it does not
establish that the app, SwissSys parity, or federation integrations are complete.

## Conclusion

The plan covers many essential operations but underspecifies the work between
them. A TD should be able to interrupt result entry to handle a player, find the
right record without knowing its section, make the change, and return to the exact
game. Registration, round turnaround and recovery need equally explicit contracts.
The build must pass these end-to-end tasks, not merely expose menu items.

## Basis and limits

The [TD duty matrix](../research/notes/TD_DUTIES.md) links official sources to entry
processing, pairing, result collection/correction, byes, withdrawals, reporting and
delegation. Those duties establish *why* workflows matter. The user's examples
establish required interactions, including direct player editing, section combination
and immediate 1/0/5 result entry. Neither source mandates our proposed screen layout.

This is a document walkthrough using realistic tournament scenarios. General
[usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)
and their [application to complex software](https://www.nngroup.com/articles/usability-heuristics-complex-applications/)
support the review method: visible state, familiar terms, recoverable actions,
consistent interaction and efficient repeated work. The specific decisions below
are design proposals inferred from the tournament tasks. Actual TD observation is
still necessary. The two articles are saved in the private local reference cache;
[retrieval metadata](../research/td-usability-sources.json) records provenance.

## Findings and changes to the plan

All findings below refine first-release workflows, except where a later feature is
explicitly named. UX01–UX14 are acceptance IDs in [Requirements](REQUIREMENTS.md),
not additions to the 67-item competitor capability catalog.

| ID / urgency | Tournament situation and gap | Required improvement and source of need |
|---|---|---|
| UX01 / critical | “My son's ID is wrong.” The TD does not know his section. Per-section editing and a command palette do not specify event-wide person finding. | Persistent Find player searches event entries by name/ID and shows section, status and current board. Open the existing editable inspector; disambiguate same names/multiple entries. Close it to return to the original task. Basis: registration/identity duty; user's direct-edit requirement. |
| UX02 / critical | Three walk-ins arrive while the API is unavailable. Import is detailed, but manual registration is barely specified. | Add player requires a display name and destination (or unassigned pool); allow pending ID/rating with explicit findings. Save & add another retains suitable section defaults. Ask start round/past-round treatment for a late entry; no invented points or automatic repair of approved pairings. Basis: entries and late-entry duties. |
| UX03 / critical | An imported field has zero checked-in flags. The quad builder defaults to checked-in players and can appear empty or omit entrants. | Check-in enforcement is an explicit event policy. Without enforcement use active eligible entries; with it show outstanding arrivals. Before pairing/grouping, account for included entries and every exclusion. Import never asserts attendance/payment. Basis: check-in and correct pairing population. |
| UX04 / critical | Slips arrive rapidly; a TD is interrupted and resumes on the wrong board, or types faster than disk writes. | Preserve cursor by stable game ID; show event/section/round/players at focus; buffer rapid input safely and label pending writes. No lost, duplicated or retargeted keys. Historical rounds are read-only until an explicit correction action. Basis: result collection/correction; user's immediate-entry requirement. |
| UX05 / high | Quad 2 is ready while the bottom Swiss is missing results. A global status or disabled Next round creates confusion. | Event overview lists section-local missing results, unresolved games and next action. Jump to the precise game and return. Different sections advance independently. Final results and temporary pairing treatment remain distinct. Basis: collecting results and directing several sections. |
| UX06 / critical | A missing affiliate ID, failed lookup or unresolved export issue blocks unrelated scoring/pairing. | Issues name the action they block and why. Deferred report metadata blocks export, not local scoring. A real eligibility problem remains visible for the relevant pairing decision. Repair links return to the blocked task. Basis: offline operation and reporting duties. |
| UX07 / high | Routine edits require repeated confirmation, or the header says Saved while the inspector contains unsaved changes. Hidden selected rows receive a bulk withdrawal. | Save/Cancel only once for ordinary details; explicit dirty state. Bulk preview names the exact selected entries, including filtered-out selections. Confirmation is proportional to consequences. Basis: player editing and the user's flexibility requirement. |
| UX08 / high | Round turnaround requires reopening report setup for every section. A printer failure leaves the TD unsure whether to pair again. | Rounds offers Print pairings using a remembered preset, plus preview/settings. Approve & print is an optional shortcut. Approval and print delivery have separate status; retry the same revision without regenerating games. Show scope and round on every action. Basis: pairing/wallchart duty. |
| UX09 / high | “Publish” could mean save pairings, print them, or upload them. An empty result looks like a game has not started. | User actions say Approve pairings, Print and Post online. Keep draft/approved revision, play status and result completeness separate. No automatic next-round approval or inference that an unreported game is unstarted. Basis: posted pairings and safe correction. |
| UX10 / high | “Withdraw next round” is ambiguous during an unreported game or a weekly event. Moving an entrant loses their bye or board accommodation. | Display the exact effective round/date and existing game; explicitly resolve current participation. Show future byes, schedule mappings and reserved-board constraints in transfer/withdrawal reviews. Preserve other sections. Basis: bye, withdrawal, transfer and accessible venue operation. |
| UX11 / high | Live-rating review offers hundreds of unchanged rows, or accepting a spelling fix silently changes the seeding rating. | Filter to changes/problems; batch only selected fields. Separate identity, membership and rating changes. Show assigned/frozen pairing value and eligibility effects; stale API responses cannot overwrite edits. Basis: rating/identity validation duties and user's key feature. |
| UX12 / critical | After a crash or staff handover, the TD opens yesterday's copy or cannot tell what was saved. | Show event date, file location and latest saved activity; backup age/status separate from save status. Restore into a clearly named new copy by default. Handover summarizes current rounds, missing results and unresolved rulings from existing records. Basis: recovery, result integrity and TD delegation. |
| UX13 / high | Older UX and product documents specify different navigation; “planning complete” hides pending observation and evidence. | One authoritative navigation contract; current keyboard and operation specs linked first. Gate release on scenario performance as well as feature coverage. Validate narrow interaction prototypes before broad implementation; provider access is a separate evidence track. Basis: review consistency and build-agent handoff. |
| UX14 / high | A small pairing repair seems to require regenerating the round, or a player is assigned twice during a swap. | Eligible-opponent picker and explicit affected-board preview; preserve unaffected pairings and locks, protect started games. Basis: pairing duty and existing manual overrides. |

For UX14, **repair one pairing without restarting the round**.
The plan exposed manual controls but did not describe a usable repair. Selecting a
board should show both opponents, colors and board assignment; opponent selection
shows eligible unpaired entrants and explains conflicts. A player already assigned
elsewhere requires an explicit swap/rearrangement preview, never a duplicate
assignment. Preview only affected boards, preserve locks and unaffected pairings,
then approve a replacement revision and reprint those affected sections. An empty
result is not permission to change an already-started game. If no automatic pairing
is found, keep the last good proposal and offer the same repair surface with
specific constraints. Structural validity cannot be overridden. This refines the
existing pairing duty and manual-override requirement, not a new pairing system.

The architecture also needs relevant dependency checks: scoring an unrelated quad
must not invalidate the bottom Swiss's pairing proposal. Event revision provides
an audit sequence; proposal validity depends on its actual inputs, including shared
boards and membership constraints. This supports UX05 rather than introducing a
new feature.

## Minimum working surfaces

- **Event:** section status and attention items. Find the player or unresolved board
  immediately; no separate generic task-management dashboard.
- **Players:** add/import, editable details, team label, check-in when used, byes,
  withdraw/reinstate, move and Make quads. Show effective rating and its source.
- **Rounds:** review/approve, print, enter results, locate missing games, correct and
  manually repair pairings. Keep result entry central while play is in progress.
- **Standings:** standings/crosstable/prizes, with explanation of scores and ties.
- **Reports:** full output configuration and federation package validation. Frequent
  printing stays accessible from the screen where the TD is working.

A player inspector, contextual issue list and report preview are reusable surfaces.
Do not add a separate screen for every finding above. Dense tables, visible focus
and restrained styling should make this feel fast; decorative animation is not a
substitute for fast work.

## Rehearsal before committing to the UI

Use synthetic data: 22 entered players, four quads and a bottom six; duplicate
surnames, one missing ID, one name mismatch, a future bye, a withdrawn entrant,
a reserved board and a weekly-event date variant. Also use 100 entries to test
finding and bulk selection. Freeze expected identities, outcomes and counts in a
fixture so the observer can detect a wrong record independently of the UI.

Start with at least one experienced SwissSys TD and one newer TD. This is an initial
design check, not a statistically sufficient usability claim. Give goals and slips,
not instructions naming the buttons. Observe with permission; record assists,
wrong-record actions, abandoned paths, confusion and recovery. No interviews or
outreach have been performed by this planning task.

| Scenario | What the participant does | Required result |
|---|---|---|
| R1. Registration rush | Add three walk-ins offline; correct a duplicate name's ID; assign a team and round-two bye | No duplicate/lost entry, no lookup prerequisite; participant locates record unaided |
| R2. Account for the field | Import the 22-player field; use check-in both enabled and disabled; make quads | Included/excluded totals reconcile; absent/excluded entries never disappear silently |
| R3. Interrupted scoring | Enter 20 slips with 1/0/5, blanks and a typo; interrupt to edit someone in another section, then return | Zero wrong games/outcomes; mouse-free result entry; original cursor/context restored; target under 60 seconds for uninterrupted familiar entry |
| R4. Round turnaround and repair | Find missing results across sections; finish one section; repair an unstarted pairing with an explicit swap, approve and print | Other section and unaffected boards unchanged; no duplicate assignment; exact missing-game navigation; no repeated layout setup or automatic approval |
| R5. Player changes | Withdraw after the current game, cancel/retain future bye, reinstate, move an unpaired player | Exact rounds/dates understood; history, byes and totals agree; ordinary future bye target under 10 seconds once familiar |
| R6. Combine sections | Combine Quad 4 into bottom six before play, then inspect a separate post-play fixture | Ten-player Swiss; other quads unchanged; under 30 seconds for familiar pre-play case; post-play history/policy consequences understood |
| R7. Repair an old result | View round one after round two; deliberately correct a wrong score | No accidental shortcut edit while browsing; later played games retained; affected standings/printouts identified |
| R8. Output and printer failure | Print pairings, reprint a changed revision, export ASCII crosstables for all five sections; simulate failed print | Correct scope/round/revision; no stale report reused as current; retry preserves pairings; text and paper legible |
| R9. Restart and handover | Restart after saved scores; select a backup; brief a second TD on unresolved games/rulings | All acknowledged results present; older copy/date recognizable; restoration does not overwrite original; pending work identifiable |
| R10. Accessible operation | Repeat find/edit/result/print paths using keyboard and 200% text; inspect screen-reader announcements | No focus trap, hidden required action, clipped names preventing disambiguation, or color-only information |

Time targets are proposals, never substitutes for accuracy. Any wrong-player/game
write, lost acknowledged result, silent omission from pairing, or unintended
historical change fails the rehearsal. Record actual times and uncertainty; revise
before broadening the UI. Rehearse again after a relevant change, not as a ritual
for unrelated documentation edits.

Automated failure fixtures supplement the human exercise: rapid released keys under
slow local writes; held/duplicated key events; storage failure mid-sequence; stale
lookup; hidden bulk selection; unrelated section update during proposal review;
printer cancellation; read-only second instance. Automation does not establish
that a TD understands the interface.

## What still needs direct TD evidence

Confirm the actual check-in policy, board numbering/access needs, printer workflow,
late-entry and bye policies, ordinary prize workflow, input file shapes and staff
handover habits. Walk through an actual tournament day before adding speculative
screens. The official duties support these questions; they do not answer every
club's operating choices. Full SwissSys page-to-feature extraction, API validation,
report acceptance and actual desktop printing remain separate unfinished gates.
