# Workspace guide

How the main screens work, in the order a TD meets them. For the day as a
whole, see [a tournament day, in order](TD_DAY.md).

## Start

Start with **New tournament** to create an event, then add or import players.
Choose a section tab, then switch between **Players** and **Pairings**. Both
views keep the selected section.

## Results

On **Pairings**, click a score box on a board, or a round cell in the
crosstable beside the boards, then type **1**/**W** for a win, **0**/**L** for a
loss, or **D** for a draw. Results display as **1**, **0** and **½**. Typing
saves and advances; mouse clicks only focus cells. A key that replaces a result
already recorded still applies at once, and a notice at the bottom of the window
names the board and the change ("Board 7 was 1–0, now ½–½") with **Undo**.
Historical corrections retain their review step. The full contract is in
[keyboard results entry](RESULT_ENTRY.md).

**Create pairings** names what it will pair. With a section tab selected it
pairs that section only ("Create pairings · Open · Round 2"); with **All
sections** selected it pairs every ready section with one click. Sections
waiting for results are left alone. There is no separate start-round step.

After a withdrawal once pairings are up, **Re-pair unstarted boards** (beside
**Edit pairings** on a section's Pairings page) keeps the boards that have a
result and pairs the rest again without the withdrawn players. It asks for the
reason; reprint the sheets afterwards.

## Player cards and section settings

Changes typed into a player's card or a section's settings are saved when the
panel closes or another player or section is opened, as one step that **Undo**
takes back. A change that cannot be saved keeps the panel open on the problem;
**Discard draft** throws the change away. The **Add player** form is different:
a half-typed new player is kept as a draft and never registered by closing.

## Moving, swapping and withdrawing

Right-click a player for **Move**, **Byes** and **Withdraw** (or press
Shift+F10 on the focused row). The selected section tab has a **Section
actions** button for printing, **Rename / section settings**, **Combine
sections** and **Delete section**; right-clicking any tab opens the same menu.

Choose **Edit quad pairings** beside **New section** to change opponents or flip
colors within a quad. Select players in each round, then **Save pairings**.
Everyone must meet once across the three rounds; changing opponents may require
adjusting another unplayed round. Rounds with results, start markers or pairing
assumptions stay locked. Saved edits update future rounds and printed sheets;
reprint any sheets already distributed. **Undo** restores the previous schedule.
The quad setup preview only displays the rating groups.

## Printing

**Print player list** (Players view, or right-click a section tab) prints each
section's players by pairing number with rating and US Chess ID; it never
depends on pairings.

**Print wall chart** (right-click a section tab, or choose Wall chart in any
Standings print) prints the chart to post on the wall (rule 28O): players in
pairing-number order with rating, and a column for every planned round showing
the result, opponent number and color with the score so far underneath. Swiss
rounds not yet paired are blank, so results can be pencilled in between prints;
a round robin's coming rounds already show the opponent and color. Withdrawn
players are greyed. The **Crosstable** print has the same cells in
standings order, for played rounds only.

Pairing sheets print from the Pairings view: a quad prints its plain result
sheet with all round-robin pairings, including future rounds. A larger round
robin prints the same grid on its own page to post, then every round's board
table. Swiss sections print only the selected posted round. Pairing sheets use
**Board | Result | White | Black | Result**, with blank result boxes for
handwriting and unused space left blank. Each section starts on a fresh page;
large Swiss sections continue onto additional pages as needed.

The first print asks for a printer; later prints use the saved device, with the
paper, tray and two-sided settings it has in your computer's printer settings.
Use **Choose printer…** beside **Print** to pick another printer. **Copies and
options…** opens your computer's own print window for copies, two-sided printing
and trays, for that one print. **Save PDF** keeps the sheet as a file, to print
from another computer. Each sheet is laid out for the paper the printer reports,
or the paper chosen in the print window, so a Letter tray never cuts off an A4
sheet; the panel says when a print went out on other paper than the preview.
**Paper** chooses Letter or A4 for the preview and for printers that do not
report their paper. Printers come from your computer: one that is not listed needs adding in
its printer settings, and **Refresh list** then finds it without starting over.

## Export and the rating report

Use **Export** to wrap up the tournament. Review checks across all sections and
follow the repair links to resolve missing results or report inconsistencies.
**Generate DBF files** becomes available once blocking issues are resolved;
optional checks remain available for review. Final standings, crosstables,
printouts, backup status and submission notes are also available here.

Expand **Optional** and choose **Fetch missing states from US Chess** to fill
missing player states from their US Chess IDs. Rating and membership lookups
also fill missing states automatically; existing states are preserved.

## Correcting a result

On **Pairings**, choose a round number or **All rounds** to find an earlier
game. Choose **Correct a result**, or type in that round's cell of the crosstable, and the
correction opens beside the table. Pick who won, see each player's score change,
and decide what happens to later rounds: keep their pairings, or unpair an
unstarted round and all rounds after it. Recorded play and section transfers
prevent unpairing. A note is optional. Unpaired rounds are paired again through
the normal pairing review.

The previous version remains in **History**, where a single-result change also
offers **Fix this result** without reversing unrelated edits. Selecting any
change lists what going back to it would undo, and any recorded play it would
remove, above the button that does it. See
[history and recovery](HISTORY_AND_RECOVERY.md).

## Importing players

**Import file…** opens the file in an import window before adding players. The
separator is detected; as in a spreadsheet's text import you can tick Comma,
Tab, Semicolon or Space, type any other separator characters, choose the quote
character, merge repeated separators and say whether the first row holds column
names. Every row is shown in a grid with a field picker above each column
(Name, First/Last name, Rating, US Chess ID, State, Team, Club, Section,
Registration note, or Don't import), and a status for each row: new, already in
the event, or the problem to fix. Invalid rows must be fixed or explicitly left
out; **Paste** uses the same window. Imports can be undone. Sample files are in
[samples/](../samples/README.md).

**Refresh from URL** accepts Boylston event or entry-list links. For other
clubs, paste a page containing a Name, Rating and US Chess ID table, then review
and confirm the players. Clubs can contribute their own URL rules and parsers;
see [adding a club website](CLUB_ROSTER_ADAPTERS.md).

## US Chess identity checks

**Find by name** beside a player's US Chess ID searches official member
records. **Check ID** warns about missing records or a different official name
and offers possible corrections. Choose a candidate, then Save (or Add for a new
player). Ratings stay unchanged.

Event details offers the same name search for the chief and assistant chief TD:
enter a name, choose **Find by name**, then select the ID. Search uses public
access when available or the API key in Data sources; service failures leave
the identity unverified. Report city, state and ZIP refer to the tournament
site.

## Rating estimates

On **Players**, **Show rating estimates** (under **Player tools**) is off by
default. Enable it to see approximate Regular ratings and changes as results are
entered or corrected between rounds. This just-for-fun preview assumes 50 prior
rated games, uses starting ratings and completed games in each section, and
omits personal floors and provisional formulas. It never changes pairing ratings
or exports. See [calculation details and limits](RATING_PREVIEW.md).
