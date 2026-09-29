# Results entry: a first-class TD work surface

User requirement: type results into a large table and continue directly into the
next cell. This is an interaction contract, not an implemented interface.
US Chess's result collection/posting duty motivates the workflow (rules 15H/28O);
US Chess does not prescribe these keystrokes. See [duty evidence](../research/notes/TD_DUTIES.md).
This contract supersedes the earlier sketch's underspecified 1 / = / 0 shortcuts.

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
| 1 / 0 / 0.5 | Decimal result | Type value, Enter commits and advances down; Tab commits to next result cell |
| .5 / ½ / = | Draw aliases | `.5` uses numeric commit; single-character `½` or `=` saves and advances |
| Arrow keys | Navigate cells | No result created by moving focus |
| Enter on blank | Skip unknown game | Leave unreported and advance |
| Shift+Enter / Shift+Tab | Reverse traversal | Commit a valid edit, then move backward |
| Escape | Cancel current uncommitted edit | Restore old display; do not create a result |
| F2 or double-click existing result | Explicit correction | Edit directly; preserve history and review later-round dependencies when applicable |
| Delete on selected saved result | Clear result deliberately | Restore unreported state with history/undo; review dependencies if necessary |
| Undo | Revert latest applicable change | Restore both opponents and focus to that game; review historical dependencies |

There is a genuine parsing ambiguity: `0` is both a complete loss and the beginning
of `0.5`. Do not commit the first `0`, use a typing-speed timeout, or rely on how
fast the TD presses the decimal point. W/L/D supplies immediate one-key entry;
numeric input uses an explicit Enter/Tab terminator. The UI must explain this once
in the legend. This supports the requested numeric values safely while preserving
a fast one-keystroke path. A later optional numeric-keypad mode may map 1/0/5 to
win/loss/draw, but must be explicitly selected and cannot silently reinterpret 0.5.

A typed `0.` stays pending; `0.5` commits only on the numeric terminator. Invalid
values stay in the same cell with a concise message; no save or advance. Number-row
and numpad digits work. Reject incomplete decimals on commit. Decide locale decimal
separator support explicitly and test it; never treat a decimal separator as a
column delimiter in an individual cell.

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
| 1 Enter, 0 Enter, 0.5 Enter, .5 Tab | Win/loss/draw/draw; no premature loss while typing decimal |
| Pause after 0 or 0. for any duration | No timer-triggered commit or focus movement |
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
