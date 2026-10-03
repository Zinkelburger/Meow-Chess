# Results entry: a first-class TD work surface

User requirement: type results into a large table and continue directly into the
next cell. Result entry is typing only: **1 or W = win, 0 or L = loss, D = draw**.
The sheet displays 1, 0, or ½. D is the only draw shortcut; 5, =, decimal,
and fraction aliases are not accepted. Clicking a cell focuses it without choosing a result.
This applies to both Players & standings and Pairings & results.
US Chess's result collection/posting duty motivates the workflow (rules 15H/28O);
US Chess does not prescribe these keystrokes. See [duty evidence](../research/notes/TD_DUTIES.md).
This contract supersedes the earlier proposal requiring Enter/Tab for numeric input.

## The table

Two grids share one contract: the section grid and the **event-wide grid** in
global board order (K07). Boards are numbered across the room, not per section,
and the TD collects results by walking the room or reading the wall sheet in
board order. During play the event-wide grid is the default; switching to a section
grid is a filter, not a different editor. The round number is the largest text on
the surface, because entering into the wrong round is the mistake this layout
exists to prevent.

Default: board-ordered rows for the selected round. Columns: Board, White, white
pre-round score, **White result**, Black, black pre-round score. Label the perspective
in both the column heading and focused-cell accessible name. A white loss sets the
black win automatically in one transaction. The TD enters a game once.

Offer an all-round player matrix as an alternate view, with persistent player names,
round headings and opponent/color context. Its cells mean the row player's result.
Editing one updates the reciprocal opponent cell; traversal skips that already-set
counterpart unless the TD deliberately navigates to correct it. Never change
perspective just because the table is sorted or the player currently has Black.

Use a clearly visible active-cell border, readable row height, sticky names/headings
where needed and a persistent context line: “Round 2 · Board 10 · Morgan vs Sam ·
entering White's result.” Do not force a pop-up or mouse interaction for ordinary
win/loss/draw entry. A compact visible keyboard legend makes the interaction discoverable.

## Input and commitment

| Input | Meaning | Commit / focus behavior |
|---|---|---|
| W or w | Win for labelled player | Save and advance immediately |
| L or l | Loss for labelled player | Save and advance immediately |
| D or d | Draw | Save and advance immediately |
| 1 | Win for labelled player | Save and advance immediately; no Enter needed |
| 0 | Loss for labelled player | Save and advance immediately; no Enter needed |
| F then 1/W or 0/L | Forfeit win / forfeit loss for labelled player | Save as an unplayed forfeit and advance; legend shows the pending modifier; Escape cancels it |
| X | Double forfeit | Save both sides unplayed and advance |
| Arrow keys | Navigate cells | No result created by moving focus |
| Enter on blank | Skip unknown game | Leave unreported and advance |
| Shift+Enter | Previous result cell | Move backward; an explicit text editor commits only a valid complete value |
| Tab / Shift+Tab in grid navigation | Leave grid forward/backward | Normal focus traversal; not a trap cycling through every result |
| Escape | Cancel current uncommitted edit | Restore old display; do not create a result |
| F2 or double-click existing result | Explicit correction | Edit directly; preserve history and review later-round dependencies when applicable |
| Delete on selected saved result | Clear result deliberately | Restore unreported state with history/undo; review dependencies if necessary |
| Undo | Revert latest applicable change | Restore both opponents and focus to that game; review historical dependencies |

Show a persistent compact legend: **1 / W win · 0 / L loss · D draw**.
Support both the number row and numpad. These keys are commands, not decimal text
entry: D stores/displays a draw (½). There is no Enter/Tab
requirement, typing-speed timeout or automatic mode inference for these shortcuts.
The focused-cell context always states whose result is being entered.

Decimal strings such as 0.5 belong to an explicit text-edit/import/paste path, if
provided, with a complete-value parser and explicit commit. They are not accepted
as a multi-keystroke sequence in the default immediate-entry grid. Do not advertise
both decimal typing and instant 0 commitment in the same input mode. Invalid command
keys do not save or advance; show the short legend instead of interpreting them as
an outcome. Keep bulk paste separate from individual keyboard events.

Keyboard shortcuts apply only when a result cell owns focus. Typing in names,
search, notes or another window must never enter a result. Ignore key-repeat events
for instant-entry keys until released; a held W must not fill the next five boards.
Prevent duplicate event delivery from committing twice. Do not treat unconfirmed
IME/composition text as a shortcut.

## Traversal stays predictable

Default advance goes down the current round's result column, skipping byes,
non-editable structural cells and already completed games. Provide a visible
“Missing only” filter. Manual navigation can reach completed cells for correction.
The all-round grid offers Down this round / Across this player, with the current
mode labelled. Automatic result advancement is over result cells, not names or
ratings. The grid is one Tab stop: arrows move inside; Tab/Shift+Tab leave forward/
backward. Returning restores the active cell. In an explicit text editor, Tab
commits a valid complete edit and exits; invalid input explains the error and
Escape always cancels it. Document/announce this convention; do not require a
hidden exit shortcut. Player-name actions remain keyboard-accessible through a
labelled game/player details control without making every name a Tab stop.

Freeze row order during an entry sequence. Updating scores must not re-sort rows
under the TD's fingers. When a missing-only row disappears, focus advances using
the previous ordered game IDs; never skip an extra row. Virtualization must preserve
focus and scroll the next cell into view. At the last editable cell, show completion
without silently switching sections, creating a new round or publishing pairings.

Allow jumping by board number or player search and returning to the entry cursor.
Out-of-order slips should not require scrolling through the whole tournament.
Paste TSV/newline result blocks through a preview that names target games and flags
conflicts, missing opponents and existing values. Do not mutate thousands of cells
on paste without reviewing the mapping. Batch result paste is later than basic
keyboard entry; it shares the same command/validation path.

## Correctness and recovery

Commit both opponents and the audit record atomically; acknowledge saved state and
advance only after durable local success. Keep focus and pending input on failure.
If the next released shortcut arrives before that write finishes, buffer it in order
against the captured next eligible game IDs, show a pending count, and drain in
sequence. Do not apply it twice to the still-focused game, drop it, or guess a new
target after a filter/sort change. Pending input is not labelled saved. Pause on
write failure or stale target and show exactly which outcomes remain uncommitted.
Navigation/correction/undo during a pending sequence must resolve it explicitly
(first finish saving, or cancel uncommitted queued input); never carry keys into a
new section. An in-flight commit's outcome must be known before claiming it cancelled.
After a crash only durably acknowledged outcomes are guaranteed; never imply queued
keys were saved. Bound the buffer and visibly stop accepting further commands if
full, with feedback; no silently discarded keystrokes.

Local writes must feel immediate; measure latency rather than inserting a modal
after every result. Network posting cannot block entry. Undo is discoverable and
names the action/game/section it will reverse; it must not ambiguously undo an
unrelated player edit made during an interruption. Result history offers correction
of that specific game. A simple same-round typo needs no multi-screen wizard.

Past rounds open in browse mode. Choose Correct results for the displayed historical
round, or Correct this result, to deliberately enable edits with a visible banner;
leaving that round exits the mode. Impact review appears only for actual dependencies,
not for every navigation key. Restoring an interrupted current-round cursor shows
both names, section, round and perspective again before result shortcuts resume.

[History and recovery](HISTORY_AND_RECOVERY.md) specifies persistent Undo/Redo and
saved alternatives. A different edit after Undo cannot destroy the previous state.
Use one command per outcome; no typing-speed heuristic groups 0 then 5 into a
single guessed decimal mistake. Historical previews never accept result shortcuts.

A win/loss key records a played result by default. Forfeits have their own
keystrokes because a no-show is the second most common outcome after a played
game. After a forfeit loss, offer once to withdraw the absent player from the
remaining rounds (K08); declining has no side effect, and the app never withdraws
on its own. Requested/allocated byes, disputed and unfinished games use labelled
outcomes in an adjacent menu with a keyboard-accessible command. `0` is not “absent,” “no result,”
or “withdrawn.” A disputed result has an unresolved status; any TD-authorized
pairing assumption is stored separately from the actual result and rating record.

Double-game rounds have distinct result cells for each game, with unmistakable
player/color labels. Do not infer two individual outcomes from a 1–1 aggregate.
Match and team totals recalculate from their defined rules; users edit the underlying
outcome through an explicit action, not overwrite a derived total accidentally.

## Acceptance fixtures

| Fixture | Must hold |
|---|---|
| W, L, D sequence across three missing games | Correct reciprocal outcomes; one advancement per released key |
| 1, 0, D sequence without Enter | Win/loss/draw on three games; reciprocal results correct; one advancement each |
| Numpad 1, 0 and W/L/D | Identical behavior; draw stores half a point, never five |
| Decimal 0.5 through explicit text/paste path, if offered | Parse full value before commit; do not dispatch individual shortcut events |
| Hold W; deliver duplicate event | At most one game entered for one physical key press |
| Enter on blank, invalid value, Escape | No invented loss; invalid input stays; cancel restores |
| Black player's all-round cell receives W | Black wins; reciprocal white cell becomes loss |
| Missing-only filter and virtualized rows | Exactly next eligible game receives focus |
| Score changes would alter standings sort | Entry order stays fixed until deliberate resort |
| Change a completed game after later round | Explicit impact review; historical games preserved |
| Storage error or app crash at commit boundary | No one-sided score; no false saved acknowledgement |
| Five released keys 1, 0, D, W, D at 100 ms intervals with 300 ms writes | Five intended stable game IDs receive exactly those results in order; pending/saved status truthful |
| Fail the third write in that sequence; change filter or request navigation | First two durable; remaining inputs identifiable and not silently applied elsewhere |
| Open historical round and type 1/0/D before enabling correction | No result changed; visible browse/correction distinction |
| Interrupt for event-wide player edit, then return | Same result cursor/context; Undo clearly identifies its target |
| Tab/Shift+Tab from grid and invalid text editor | Grid can be left; Escape cancels invalid edit without trapping focus |
| Type W/0.5 into player-name/search fields | No results changed |
| Double-game match with split wins | Two actual games retained; not converted to draws |
| Keyboard/screen reader at 200% text | Names/perspective announced, focus visible, grid escapable |
| TD reads “0.5” in the score column and types 0 then 5 | Named typo fixture: the legend and perspective line are tested against it; 0 records a loss and advances; 5 does nothing. One Undo restores both opponents of the changed game. Never infer a grouped mistake from valid keystrokes |
| F then 1, then X on the next board | Forfeit win and double forfeit recorded as unplayed; rating export excludes both; withdraw offer shown once |
| Event-wide grid across five sections | Global board order; each section's standings update; no cross-section reciprocal error |
| Entry abandoned mid-sequence, app restarted | Cursor position and Missing-only filter restored; no result invented (K14) |

Rehearsal target: 20 mixed results, two intentional blanks and one corrected typo,
without mouse use or incorrect records. Measure time and error rate with working
TDs. No prototype speed or usability result is being claimed yet.


## Implemented correction review (October 3, 2026)

Rounds offers individual numbered rounds and **Show all rounds**, grouped by
round and section. Earlier rounds remain read-only until **Correct a result** is
selected. Entry result cells open the same review directly; a double-game cell
first asks which game to correct. Ordinary latest-round keyboard entry remains
immediate.

The review identifies the section, round, board, colors and game leg, and shows
old/new outcomes and each player's score contribution. Later rounds default to
**Keep pairings and results**. **Reopen from round N** selects the entire suffix;
changing that boundary updates the preview. Reopening requires both no recorded
play in that suffix and an explicit check that no games have actually started.
Later section transfers disable automatic reopening and disclose linked sections.
The correction reason and reopening choice commit in one revision. New pairings
are generated and reviewed separately; a stale review cannot commit.

History transaction details show before/after values. A transaction that changed
only one game's result offers **Undo this result** if that exact game still has
the recorded outcome. This creates a reviewed correction against current data,
preserving later roster edits and other results. Compound transactions remain
atomic. Whole-event restores across multiple transactions or recorded-play losses
show an impact review first; cancelling changes nothing. Prior versions stay in
the persistent graph. Printed and exported files need replacement after a change.

Covered by `test/application/result_correction_test.dart`,
`test/ui/result_correction_test.dart`, and the native rehearsal in
`integration_test/result_correction_test.dart`.
