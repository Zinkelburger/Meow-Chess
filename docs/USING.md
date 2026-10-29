# Workspace guide

How the main screens work, in the order a TD meets them. For the day as a
whole, see [a tournament day, in order](TD_DAY.md).

## Start

Start with **New tournament** to create an event, then add or import players.
Choose a section tab, then switch between **Players** and **Pairings**. Both
views keep the selected section.

## Results

Click a score cell in either view, then type **1**/**W** for a win, **0**/**L**
for a loss, or **D** for a draw. Results display as **1**, **0** and **½**.
Typing saves and advances; mouse clicks only focus cells. Historical corrections
retain their review step. The full contract is in
[keyboard results entry](RESULT_ENTRY.md).

**Create pairings** pairs every ready section with one click; sections waiting
for results are left alone. There is no separate start-round step.

## Moving, swapping and withdrawing

Right-click a player or section tab for **Move**, **Swap** and **Withdraw**.

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

Pairing sheets print from the Pairings view: a quad prints its plain result
sheet with all round-robin pairings, including future rounds, and Swiss sections
print only the selected posted round. Pairing sheets use
**Board | Result | White | Black | Result**, with blank result boxes for
handwriting and unused space left blank. Each section starts on a fresh page;
large Swiss sections continue onto additional pages as needed.

The first print asks for a printer; later prints use the saved device. Use
**Choose printer…** beside **Print** to pick another printer. Systems without
direct printing support use the operating system's print dialog.

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
game. Choose **Correct a result**, or click a result cell in **Players**, and the
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
