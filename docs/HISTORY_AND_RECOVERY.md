# History, undo and reopening an earlier round

Status: target contract, originally September 29, 2026 UTC. The implementation now
has durable version history, reviewed whole-event restores, and direct earlier-result
corrections with a choice to retain later pairings or reopen a confirmed unstarted
suffix. History can selectively undo single-result transactions. General selected-change
recovery, planning continuations and promotion checks below remain target behavior;
see [implementation status](IMPLEMENTATION.md) and the
[implemented correction review](RESULT_ENTRY.md#implemented-correction-review-october-3-2026).

This makes capability-map P07/P08/U03 concrete. It strengthens the earlier bounded
undo proposal: a short in-memory undo stack or audit descriptions alone cannot
satisfy the user's requirement to go back without losing subsequent work.

## The product decision

Use **a readable history timeline, automatic recovery points and preserved alternative
versions**. A version tree is useful internally and as optional advanced navigation;
it should not be the primary screen a busy TD must understand. The TD sees actions
and rounds, with Preview, Compare, Continue from here and Return to current version.

Every acknowledged tournament change remains recoverable within the retained event
history. Viewing the past changes nothing. Continuing from an earlier state preserves
the current version first. Editing after Undo does not make the abandoned work
unrecoverable. Returning after a restart works too. This is a required behavior,
not a claim about software that has already been built.

History protects against mistakes in the app; a verified copy on another device
protects against loss of the laptop. Do not equate the two or promise recovery of
uncommitted input or data that never reached the secondary backup.

## What SwissSys documents

SwissSys's [Back to a Previous Round](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/pairings-menu/back-to-a-previous-round-do/)
returns to before the selected round's pairing. It keeps subsequent player-data
changes but removes pairings/results from that round onward, with confirmation
when results exist. Its [backup page](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/file-menu/backups/)
also cautions that restoring an earlier backup removes later rounds. Its
[Undo documentation](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/edit-menu/undo-last-command/)
states that some commands cannot be undone. These are documented behaviors, not
results of running the licensed desktop application. The three pages already exist
in the local SwissSys archive; their relevant content was reviewed for this contract.

Meow-Chess should cover the same TD need while preserving the superseded work.
Do not copy destructive rollback semantics merely to claim feature parity.

## Four actions, four different intentions

| TD intent | Action | Effect |
|---|---|---|
| “That last result was a typo.” | Undo result — section, round, board | Reverse that command atomically; show the next Redo action. Review only actual dependencies. |
| “What did we have before I changed this?” | History → select revision → Preview / Compare | Read-only historical state with explicit timestamp/version; current event is untouched. |
| “I paired round 3 incorrectly; let me do it again.” | Rounds → Reopen before pairing round 3 | Review affected section/rounds, preserve current version, supersede permitted unstarted pairings and create a replacement draft using reviewed current data. |
| “I want to try the older version, or undo my rollback.” | History → Saved versions → Continue from here / Return to saved version | Preserve the version being left, open a continuation, then explicitly choose whether it is eligible to become the live event version. |

Correcting an earlier result normally uses the existing Correct result command.
Do not force a whole-round rollback to repair one score. Likewise, changing a
spelling, bye or withdrawal should use the direct player workflow.

## History panel

Open History from the event menu or the named Undo control. Default is a chronological
list grouped by round and meaningful operation, with newest activity easy to find.
Examples: “Recorded draw — Bottom Swiss, round 2, board 9,” “Moved Jamie to Open,”
“Approved Quad 4 round 3,” “Reopened Bottom Swiss before round 3.” Show time, actor
label if configured, affected section/players, and before/after values. A local
actor label is attribution supplied by the operator, not authenticated identity.

Filter by section, player, game or action. Expand a results-entry run into individual
games; visual grouping must not turn several independent keystrokes into one guessed
undo unit. An import or section combination is one atomic command with expandable
changes. Reading the history cannot trigger result shortcuts.

Selecting a row opens a read-only preview and concise comparison against current
state: changed results, entries/byes, settings, pairings and affected reports. Historical
standings use their original policy/rating inputs. Use a conspicuous “Viewing history
— live event unchanged” banner and Return to current version. Never make ordinary
navigation between old rounds equivalent to changing the active version.

Offer named recovery points, but create automatic points before pairing approval,
reopening rounds, roster replacement, section combination/transfer, migration and
final report generation. Name them in TD terms, including section, round and time.
The underlying per-command history preserves edits between these larger milestones.
A checkpoint is not a claim that an external backup was made.

Saved alternatives normally appear as a compact list: Current live version,
Before reopening round 3, Round 3 repair in progress. Optional ancestry disclosure
can show where an alternative began; no Git terminology or giant per-keystroke graph.
Only one version is the live writable event. Historical previews are read-only;
planning continuations are conspicuously marked and cannot silently become official.

## Reopen before pairing round X

Use the exact phrase **Reopen before pairing round 3**, with the section and date
visible. “Back to round 3” is ambiguous about whether round 3 stays or goes.
The default scope is the current section; event-wide/multiple-section scope is an
explicit selection listing each section and its own round. A section-filtered history
view does not imply that a whole-event restore is scoped to that section.

For a simple unstarted round, one concise review should say:

```text
Bottom Swiss — reopen before pairing round 3
Keep rounds 1–2 and current player details, withdrawals and bye reservations.
Replace round-3 pairings on boards 9–11. Other sections stay unchanged.
Save the current version as “Before round-3 restart · 14:12”.
Previous printed round-3 pairings will need replacing.
[Cancel]                         [Save current version and reopen]
```

Preflight lists all affected subsequent rounds and results, not just the selected
round. Ask whether any affected games actually started; a blank outcome is not
proof that a game is unstarted. Flush or explicitly cancel pending input and resolve
dirty forms before the command; never let a pending key land in a restored round.

Preserve current identity corrections, registrations, withdrawals and requested
byes by default, with their effective-round semantics visible. Keep unaffected
sections and earlier played games. Show current versus historical pairing settings,
ratings and schedule: the TD chooses any necessary change explicitly. Later section
transfers/combined pools or cross-section games require their dependency review;
do not splice an old section snapshot into today's membership graph blindly.

In the same durable operation, retain the pre-reopen version, record the selected
scope and source milestone, update the current working state and audit the command.
Old pairings remain inspectable as superseded; they are not deleted. New pairings
start as a draft requiring explicit approval. A failed history write means no
successful reopen: retain the original state and a recoverable error message.

Afterward show “Round 3 reopened. Previous version saved — View / Return.” Keep
that version available in History permanently under the event retention policy;
it cannot be accessible only from a disappearing toast.

### If later games have started or been played

Preserving bytes in an archive is not enough: real games must also stay in the
live event's competition/reporting model. A normal reopen cannot discard them.
Offer the appropriate choice: correct an outcome, repair only unstarted boards,
make an explicit effective-round transition, or explore the historical state in a
planning continuation. Explain which games prevent simple re-pairing.

A planning continuation can omit later games for exploration, but cannot produce a
submission-ready rating package or ordinary official pairings until promotion is
reviewed. Promotion compares against retained evidence of actual games from live
versions, checks all known ratable games are properly represented, and resolves
current participant/board/round constraints. A mistaken game record can be corrected
through an explicit auditable correction; it cannot simply disappear by switching
versions. Simulation-only games never become evidence that a real game occurred.

Actual printouts, online posts and federation submissions also survive a local
restore as external facts. Show which need a replacement or submitted-report
correction. Going back cannot retract paper from the wall or unsend a rating report.
Historical exports remain archived; label them as historical rather than current.

## Return, redo and recover selected work

After a safe unstarted restart, Return to saved version offers the exact preserved
state. If the TD has already edited the replacement, preserve that continuation
first as well. Apply the same dependency and actual-game checks when returning;
never overwrite unrelated section progress just because it happened later in time.
A whole-event return explicitly lists its whole-event scope. For one-section work,
use a scoped reviewed recovery command against the current event.

Normal Undo/Redo is a named, durable command with preconditions. Undo appends a
compensating change to history; it does not erase the original action. Redo reapplies
the intended change only if still valid, never reruns an API request or submits a
report. If a new edit makes the shortcut Redo invalid, explain that, but keep the
old state available in Saved versions/history. Filtered or game-specific history
shows which action will change; it cannot silently undo a different section.

To recover just a few things from an alternative, Compare offers **Recover selected
changes** for supported commands (for example, a name correction or missing result
for the same actual game). Preview changes against current data, validate identities
and dependencies, then apply new ordinary commands with source-version provenance.
Never copy a result by row position, board number alone or a coincidentally matching
opponent pair. Different game identity/color/round/leg requires explicit resolution.
Support the defined common recovery paths in the first release; general automatic
branch merging and conflict-free concurrent TD editing are not implied.

## Storage design: versioned state, not only a log

Keep SQLite and one writer. Add a versioned history layer to the existing transaction
model; no cloud service, Git repository inside the app, or replay of business commands
is required. A useful division is:

- Current relational event state for ordinary queries and validation.
- Immutable committed revisions: parent, originating revision/continuation where
  applicable, command ID/type, exact before/after row data (including deletion),
  actor/time/reason and schema version. All competition-relevant state must be covered.
- Consistent full checkpoints plus complete intervening state changes, sufficient
  to reconstruct **every retained committed revision** without the old pairing
  engine, current API responses or guessing missing fields. Preserve original
  computed outputs, policy/rating snapshots and print/export provenance.
- References for named recovery points and saved alternative heads, plus an active
  live-version reference. Scope-specific recovery creates a new version of the
  current whole event; it is not an unsafe independent section database rewind.
- Retained evidence of actual play and external publications from live versions for
  promotion/recovery validation. An old preview must not erase that evidence; a
  later explicit correction records why an earlier observation was wrong.

Store current mutation, complete recovery material and audit/version references in
one transaction. Materializing a restore and activating it must be all-or-nothing;
keep the source material intact. Validate snapshot checksums, schema compatibility,
referential integrity and reconstruction before activating a recovered version.
Large imports may use full checkpoints instead of huge inverse command payloads,
but cannot bypass durable history or acknowledged-save guarantees.

Fast Undo caches may be bounded; the retained event history must not silently prune
versions because a new action occurred or the cache filled. Retain history and all
alternative heads by default for the active event and full-fidelity event copies.
Ordinary backups, Save copy and handoff include this history. A future explicit
history-stripping export must be clearly labelled and cannot replace the working
file or silently reduce its recovery capability. Retention/pruning, if added, needs
an explicit scope/impact review; backups cannot be described as unlimited storage.

Reconstruction tests must cover every mutation type, branches and schema migration.
A human-readable audit log without restorable state does not pass. This is stronger
than the earlier architecture's bounded command snapshots, while still avoiding
full business-event replay as the source of truth.

## Required acceptance scenarios

These are specifications to build and test, not completed experiments.

| ID | Scenario | Required result |
|---|---|---|
| H01 | Preview round 1 and move back/forward through history | Current event/revision unchanged; Return restores workspace context; no result shortcut writes |
| H02 | Undo a result, redo it, restart; undo then make a different edit | Reciprocal outcomes/history correct; former state remains recoverable even if direct Redo is invalid |
| H03 | Reopen before unstarted round 3 after a late entry and ID fix | Preserve current player changes/rounds 1–2; save old round-3 revision; other sections unchanged |
| H04 | Edit the replacement, restart, then return to pre-reopen work | Both continuations survive with exact states and clear labels; new work is preserved before returning |
| H05 | Reopen across played games or a later section transfer | No silent game loss or inconsistent membership; correct/transition/plan alternatives; promotion checks real-game evidence |
| H06 | Recover a name fix/result from an alternative | Explicit diff, stable identity, domain validation and source provenance; no row/board-based misattribution |
| H07 | Disk failure during reopen; damaged checkpoint; migration | Original or complete new state; no success without durable history; failed recovery does not overwrite original |
| H08 | Copy event to second laptop and inspect alternatives | Full acknowledged state as of copy plus history/heads preserved; backup timestamp/revision honest |
| H09 | Restore after printing/posting/export/submission | External actions remain recorded; stale-output/correction work visible; no automatic retransmission |
| H10 | Dense 500-entry event with bulk import and many results | Every retained revision reconstructs and compares correctly; history opens responsively on the specified reference machine |

Usability rehearsal: ask a TD to “go back before round 3, try a correction, then
recover both the original work and one useful edit from the attempt” without explaining
storage or branching terminology. They must identify the live version, show where
both alternatives are saved, and explain which paper copies are stale. No data-loss
or wrong-live-version error is acceptable. Measure the actual interaction costs
before choosing an advanced tree visualization.
