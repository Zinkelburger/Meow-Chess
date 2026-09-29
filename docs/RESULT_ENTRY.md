# Results entry: a first-class TD work surface

User requirement: type results into a large table and continue directly into the
next cell. Default numeric shortcuts are **1 = win, 0 = loss, 5 = draw**, as
explicitly selected by the user; W/L/D are equivalent shortcuts. This is an interaction contract, not an implemented interface.
US Chess's result collection/posting duty motivates the workflow (rules 15H/28O);
US Chess does not prescribe these keystrokes. See [duty evidence](../research/notes/TD_DUTIES.md).
This contract supersedes the earlier proposal requiring Enter/Tab for numeric input.

## The table

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
| 5 | Draw | Save a half-point draw and advance immediately; never store five points |
| ½ / = | Additional draw aliases | Save and advance immediately |
| Arrow keys | Navigate cells | No result created by moving focus |
| Enter on blank | Skip unknown game | Leave unreported and advance |
| Shift+Enter / Shift+Tab | Reverse traversal | Commit a valid edit, then move backward |
| Escape | Cancel current uncommitted edit | Restore old display; do not create a result |
| F2 or double-click existing result | Explicit correction | Edit directly; preserve history and review later-round dependencies when applicable |
| Delete on selected saved result | Clear result deliberately | Restore unreported state with history/undo; review dependencies if necessary |
| Undo | Revert latest applicable change | Restore both opponents and focus to that game; review historical dependencies |

Show a persistent compact legend: **1 Win · 0 Loss · 5 Draw · W/L/D also work**.
Support both the number row and numpad. These keys are commands, not decimal text
entry: 5 stores/displays a draw (½ or 0.5), not five points. There is no Enter/Tab
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
mode labelled. Traversal is over result cells, not names/ratings/IDs or arbitrary
DOM tab order. When leaving the grid, normal Tab navigation remains possible via
an explicit exit/standard grid keyboard convention explained to assistive users.

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
advance only after durable local success. Keep focus and the pending text on failure.
Local writes must feel immediate; measure latency rather than inserting a spinner
or confirmation modal after every result. Network publishing cannot block entry.
Undo is always discoverable; a simple same-round typo needs no multi-screen wizard.
Historical changes only open impact review when dependencies actually exist.

A win/loss key records a played result by default. Forfeits, double forfeits,
requested/allocated byes, disputed and unfinished games use labelled outcomes in
an adjacent menu with a keyboard-accessible command. `0` is not “absent,” “no result,”
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
| 1, 0, 5 sequence without Enter | Win/loss/draw on three games; reciprocal results correct; one advancement each |
| Numpad 1, 0, 5 and number-row equivalents | Identical behavior; draw stores half a point, never five |
| Decimal 0.5 through explicit text/paste path, if offered | Parse full value before commit; do not dispatch individual shortcut events |
| Hold W; deliver duplicate event | At most one game entered for one physical key press |
| Enter on blank, invalid value, Escape | No invented loss; invalid input stays; cancel restores |
| Black player's all-round cell receives W | Black wins; reciprocal white cell becomes loss |
| Missing-only filter and virtualized rows | Exactly next eligible game receives focus |
| Score changes would alter standings sort | Entry order stays fixed until deliberate resort |
| Change a completed game after later round | Explicit impact review; historical games preserved |
| Storage error or app crash at commit boundary | No one-sided score; no false saved acknowledgement |
| Type W/0.5 into player-name/search fields | No results changed |
| Double-game match with split wins | Two actual games retained; not converted to draws |
| Keyboard/screen reader at 200% text | Names/perspective announced, focus visible, grid escapable |

Rehearsal target: 20 mixed results, two intentional blanks and one corrected typo,
without mouse use or incorrect records. Measure time and error rate with working
TDs. No prototype speed or usability result is being claimed yet.
