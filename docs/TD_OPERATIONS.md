# First-class TD operations

This specification records the user's explicit priority: running the tournament
means handling changes easily, throughout the event. Editing players, assigning or
changing byes, withdrawing/reinstating players, moving players and combining sections
are **first-release requirements**, not specialist utilities or later polish.
Planning only: no application implementation is authorized by this document.

## The everyday interaction contract

| Intent | Direct entry point | Behavior |
|---|---|---|
| Edit a player | Double-click their name/row, or select and press Enter | Open the same editable player inspector from Players, pairings or standings |
| Give/change/cancel a bye | Inspector → Byes; also row context menu → Assign bye | Select round(s), type and effective score; show existing participation conflicts |
| Withdraw | Inspector → Withdraw; also row context menu | Choose effective round; show current pairing and outstanding games |
| Reinstate | Same inspector → Reinstate | Choose return round; keep prior withdrawals/results in history |
| Move sections | Inspector → Move section; selected players → Move to section | Destination selector and concise before/after preview |
| Combine Quad 4 with bottom Swiss | Quad 4 tab context menu → Combine with… | Choose Bottom Swiss and preview the resulting playing pool |
| Change grouping before play | Quad builder / Manage sections | Move players between groups or combine entire groups without restarting setup |
| Repair pairing/result | Rounds → select pairing → Edit / Correct | Manual opponent/color/board/outcome controls and dependency review |

Every context-menu action also has a visible button/menu entry. Right-click and
double-click are accelerators, not the only way to find essential features.
Single-click selects; double-click edits. Double-clicking a result cell edits that
result, not the player. In a pairing row with two names, the clicked name determines
which player opens. Keyboard users can reach each name and invoke Open player.
On touch, tap a name/Open player; do not require a double tap.

## Player inspector: useful immediately

Header: **Name · current section · participation status**. Keep these actions
visible together: **Byes · Move section · Withdraw/Reinstate**. Withdraw is clearly
labelled and visually separated from Save; it is not disguised as Delete.

The initial Details view is editable immediately: name, US Chess ID, pairing rating
(with source), team/club, and section summary. Do not require a second Edit button.
Keep additional identity/membership fields, rating observations, schedule and
history in labelled disclosures/tabs. Show round-by-round availability near Byes.
Contact/private fields never appear on public reports by default.

Use Save / Cancel for an ordinary multi-field edit. Validate fields inline, preserve
IDs as strings, distinguish unknown from invalid, and retain imported/original values.
A saved manual US Chess ID correction triggers a new validation status; it does not
claim federation verification. Never overwrite the name/rating automatically just
because the ID changed. If editing changes identity to another existing person,
show the duplicate/conflict and a separate reviewed reconciliation workflow.

Do not silently change all historical events when editing an event entry. A club
profile update is a separate explicit choice. Changing the person attached to a
played game is more than fixing spelling; preserve the previous attribution and
require the appropriate correction review.

The inspector remains open after Save with clear saved feedback. If the TD invokes
Byes/Move/Withdraw while details are dirty, offer Save and continue / Discard edits /
Keep editing. Never lose typed changes or silently include them in another action.
Ordinary valid edits save without a second confirmation dialog. History and Undo
are reachable without leaving the workspace.

## Byes and withdrawal are participation operations

The bye editor presents a round grid with existing games, results and reservations.
Show the event's allowed requested bye types and points in plain language. Requested
half-point/zero-point byes, pairing-allocated byes, unpaired absences and forfeits are
different domain outcomes. The TD can record a policy exception with a reason where
permitted; a numeric score alone never changes one outcome into another.

Before pairing, a bye changes eligibility for the specified round(s) and future
pairing drafts. After a pairing is published but unplayed, show the opponent and
options to revise pairings or record the appropriate unplayed outcome. After a game
has been played, changing it requires the result-correction workflow, not replacing
it invisibly with a bye. If a deadline or policy prevents the default action, explain
why and expose the applicable TD resolution path.

Withdrawal defaults to the next unpaired round. If a current game has no result,
ask whether withdrawal begins now or after that game, and show the unresolved game.
Do not assume a loss, award the opponent a point, or erase a pairing automatically.
Offer to retain or cancel future requested byes and show the effect explicitly.
Preserve completed games for rating history and apply the event's separate standings
policy, including round-robin withdrawal rules. Reinstatement restores future
availability without inventing results for missed rounds.

Bulk bye, withdrawal and move actions show all selected names, shared changes and
per-player conflicts. An operation must not partially apply silently: either one
transaction commits the reviewed set, or a documented partial selection is reviewed
before committing. Participation and scoring remain editable after export through
a new revision; an exported file is not a lock on correcting the tournament.

## Combine Quad 4 into Bottom Swiss

For the motivating example, the preview reads:

```
Combine Quad 4 → Bottom Swiss
4 + 6 = 10 players
Format: Swiss             Planned rounds: 3
Destination: Bottom Swiss [rename if desired]
Source: Quad 4 retained in history; hidden from active tabs when empty
```

This is a dedicated command, not “export a club list, delete sections, reimport.”
Also offer multi-select sections → Combine. Default to the destination's rules and
show differences in time control, round schedule, rating basis, eligibility, prizes,
tiebreaks, board ranges and federation reporting. No silent inheritance of an
incompatible rule. Allow preserving separate prize groups within a combined playing
pool, or explicitly adopting the destination prize policy. Never silently discard
an advertised prize category. Number of rounds remains a visible TD decision.

### Before any published pairing or played game

One review page names the affected players and rules. Confirming atomically moves
the entries, changes the source quad's active grouping, allocates non-conflicting
boards and invalidates only affected drafts. Future bye reservations carry by the
reviewed round mapping. Destination round robin, if chosen instead of Swiss, needs
a new schedule preview; do not silently infer it from player count. Undo restores
both sections exactly. Other quads remain untouched.

### Pairings published, no affected game started

Show affected rounds/boards and their publication revisions. Offer a reviewed
replacement pairing for the affected sections. Mark old pairings/printouts stale;
publication of replacement revision is explicit. The app cannot infer from an empty
result cell that a game has not started: require the TD to establish that before
replacing a published pairing. Other sections continue operating normally.

### Games started or finished

Keep the operation available, but switch to an **effective-from-round** transition
review. Do not pretend merging two tables also resolves tournament rules.

- Retain every played/started game, original entry/section, opponent, color and result.
- Show how source and destination rounds align, including differing time controls or
  unequal progress. Resolve in-progress games before changing their assignments.
- Propose eligible future pairings from the combined pool, with applicable opponent,
  color, bye and score history. Distinguish carried score from any TD-assigned pairing
  adjustment; never create a fictional ratable game to balance the standings.
- Preview standings/prize treatment and reporting groups separately. Combining the
  playing pool need not erase original reporting or prize group identities.
- Show the exact supported US Chess export representation. If that transition's
  reporting is not yet supported/validated, identify the incompatible records and
  offer a supported alternative that retains history. Do not label it export-ready
  or approximate a report format. Unsupported export is a specific unresolved issue,
  not a reason to disable unrelated TD operations.
- Store an auditable transition, publish new pairings explicitly, and supersede
  affected reports. Undo must review dependent later games rather than deleting them.

The first release must support the clean before-play combination and a tested,
TD-reviewed same-progress transition with preserved games. More exotic combinations
of unequal schedules/rating categories can have a dedicated resolution workflow;
full multi-schedule re-entry remains a specialist tranche. The builder must define
and test the supported transition contract before implementing the command.

## Move one player, or several

Use the same transition machinery with a smaller selection. Show source and target,
effective round, eligibility findings, available boards, reserved byes, current
game and rating/prize differences. Moving an unpaired entry before play is immediate
after the short preview; it does not require exporting or rebuilding the event.
A source quad reduced to three players produces an actionable format/schedule issue
with choices to continue under an allowed format, replace the entrant or combine
with another section. Do not auto-fill it with an unrelated player.

Once games exist, keep historical entry attribution and link any successor entry to
the same person. Explicitly distinguish a section transfer from re-entry with a new
score. Preserve original games for reporting, and use the reviewed destination
scoring policy. Never duplicate a person into overlapping pairings. Late arrival is
an ordinary registration + participation workflow with explicit past-round handling.

## Shared safeguards that support flexibility

All entry points invoke the same domain commands and validations. Each command has
an input revision, affected-record preview when needed, atomic commit, history and
dependency-aware undo. Short forms handle routine cases; impact review appears only
when there are actual conflicts, published material or historical dependencies.

Model section membership with effective transitions rather than overwriting the
historical section on a player record. Separate active playing pool, entry lineage,
prize eligibility and federation reporting groups. Keep policy/rating snapshots and
score adjustments explicit. Source sections can leave active navigation while
remaining discoverable in History. Never erase an entry with played games as a
shortcut to withdrawing or moving them.

## First-release acceptance scenarios

| Scenario | Required proof |
|---|---|
| Double-click a name from Players, Pairings or Standings | Same editable record and actions; Enter and touch alternatives work |
| Correct US Chess ID while a lookup is in flight | Manual correction survives; stale response cannot overwrite it |
| Reserve/cancel a round-two half-point bye | Round participation updates; no opponent/result is invented |
| Withdraw after round one; later reinstate | Prior game retained; no future pairing while withdrawn; return round honored |
| Withdraw a player with an unresolved current game | Explicit current-game resolution; no automatic forfeit |
| Move an unpaired player between sections | No duplicate/lost entry; source/target counts and bye schedule agree |
| Combine 4 + 6 before play | Ten-player Swiss, original metadata review, other quads unchanged, exact undo |
| Combine after publishing unplayed pairings | TD confirms games not started; old publication stale; replacement reviewed |
| Same-progress sections combine after completed games | History retained, repeat constraints honored, defined score/prize policies, validated export mapping |
| Attempt unequal/incompatible schedule merge | Specific conflict and supported choices; no silent rule approximation |
| Bulk change with one conflicting player | Reviewed subset or atomic rejection; never an unnoticed partial application |
| Undo a transfer after subsequent play | Dependency review preserves every played game |

Suggested usability targets, to measure: open an editable player in one gesture;
assign a straightforward future bye in under ten seconds; combine the unplayed
four-plus-six example in under thirty seconds once the TD knows the destination.
These are design targets, not measured claims. Essential TD operations are release
gates even if the visual styling and specialist reports are otherwise complete.
