# Workspace guide

How the main screens work, in the order a TD meets them. For the day as a
whole, see [a tournament day, in order](TD_DAY.md).

## On a Mac

Download `meow-chess-…-macos.zip` from
[Releases](https://github.com/Zinkelburger/Meow-Chess/releases) (macOS 12 or
later, Apple Silicon or Intel). Open the zip if the browser has not already, and
drag **Meow Chess** into Applications.

Meow Chess is not signed by an Apple developer account, so the first time, the
Mac will not open it:

1. Double-click Meow Chess. The Mac says it could not verify the app. Click
   **Done**, not Move to Trash.
2. Open **System Settings → Privacy & Security**, scroll down to the line about
   Meow Chess and click **Open Anyway**, within an hour of step 1.
3. Click **Open Anyway** again in the window that appears, and enter your Mac
   password if asked.

From then on it opens like any other app, and double-clicking a `.meow` file
opens it in Meow Chess. Each new version asks once more.

If there is no Open Anyway button, or the Mac says the app is damaged, open
Terminal and run this, then double-click the app again:

```
xattr -dr com.apple.quarantine "/Applications/Meow Chess.app"
```

The [browser version](https://chessautoprep.com/meow-chess/) needs no install.
On a Mac, use it in Chrome or Firefox: Safari can delete its events after
seven days without a visit.

## Start

Start with **New tournament** to create an event, then add or import players.
Choose a section tab, then switch between **Players** and **Pairings**. Both
views keep the selected section.

Each new event gets a folder of its own, named after it, inside
`Documents/Meow-Chess`. The line under the event name shows where it will be
saved; **Change…** beside it keeps events somewhere else from then on.
The folder holds the event's `.meow` file and everything saved from it: PDFs,
standings, the rating report's DBF files and the SwissSys files below. While
the event is open, those saves go straight into its folder without asking.
An event file that shares its folder with other `.meow` files, or that is in
a folder Meow-Chess did not make for it (an older event saved alone on the
Desktop, or a copy saved elsewhere), keeps asking where to save, as before. **Import FIDE report** makes a folder the same way.

## Results

On **Pairings**, click a score box on a board, or a round cell in the
crosstable beside the boards, then type **1**/**W** for a win, **0**/**L** for a
loss, or **D** for a draw. Results display as **1**, **0** and **½**. Typing
saves and advances; mouse clicks only focus cells. A key that replaces a result
already recorded still applies at once, and a notice at the bottom of the window
names the board and the change ("Board 7 was 1–0, now ½–½") with **Undo**.
Historical corrections retain their review step. The full contract is in
[keyboard results entry](RESULT_ENTRY.md).

The crosstable lists each section in rating order, highest first, before round
1 and after: a row stays where it is as results come in, and **Rank** gives the
place. The menu beside the search box lists it instead in **Standings order**,
**Pairing number order** or **Name order**. The choice applies to every section
of the event and is remembered with it; a new event starts in rating order.

**Create pairings** names what it will pair. With a section tab selected it
pairs that section only ("Create pairings · Open · Round 2"); with **All
sections** selected it pairs every ready section with one click. Sections
waiting for results are left alone. There is no separate start-round step.

The **Change pairings** menu on the Pairings toolbar holds every way to
change a round once it is paired. Until a round has its first result,
**Re-pair round** (beside **Edit pairings** in that menu, on a Swiss
section's Pairings page) pairs the whole round again
from the entries as they are now, in one click with **Undo**: someone entered
since is paired instead of taking a late-entry bye, and a withdrawal, a bye
request or a corrected rating is taken into account. Pairing is not random,
so with nothing changed the pairings stay exactly as they are: the notice
says so, and nothing is added to the history. On round 1, **Flip pairing** in the same menu pairs the round again with the coin
toss reversed, so the other player on board 1 has white: use it to match
another program's round-1 colors. One coin toss decides board 1 in every
section, so every other section with round 1 paired is flipped with it in the
same step, and the notice names them; once another section's round 1 has
started, the colors can no longer be flipped. The notice names who now has
white on board 1, and **Undo** flips it back.

After a withdrawal once games are under way, **Re-pair unstarted boards**
(also in **Change pairings**) keeps the boards that have a result and pairs the rest
again without the withdrawn players. It asks for the reason; reprint the
sheets afterwards.

### Results from the club website

Where players enter their own results on the club's website, **Website
results** enters them here as they come in. The button is on the Pairings
toolbar only for an event whose players came from a Boylston Chess Foundation
address; an event typed in or imported from a file has no website to take
results from, so it has no button. It is the one tinted button on the toolbar,
with a cloud, so it is hard to miss on the days it matters. One click turns it
on: the club's results page, `https://beta.boylstonchess.org/results`, is read
straight away, the button changes to a ticked cloud, and a strip above the
boards says what is being followed. Meow-Chess reads the page about every ten
seconds while boards are waiting, on whichever page of the workspace you are
on, and carries on after the event is closed and reopened. **Stop** (or the
button again) turns it off, **Website results** turns the same page back on,
and **Change page** asks for another address, such as another club's results
page.
Nothing is ever sent to the website.

A result is taken only from a round the website is plainly showing: the same
section and round number, and every board it lists has the same two players
with the same colors as a board here. If one board differs (the website still
shows last week's event, or pairings changed here after they were sent), the
strip above the boards says which, and nothing is taken from that round until
the website has this round's pairings. Send them again with
[**Save SwissSys files**](#printing).

The website shows only the round being played now. Once it moves on to the
next round, the earlier round's results are no longer there to read, so a
result still missing from an earlier round has to be typed in here.

Each result that comes in is a step in History like one typed at the board,
labelled "Result from beta.boylstonchess.org, …", and a notice names the board
with **Undo**. A result you take back is not entered again; it is listed with
**Use 1–0** in case you change your mind. A result you typed yourself is never
replaced: where the website disagrees, the strip shows both ("the website says
0–1, entered here as ½–½") with **Use 0–1**. If the players correct a result on
the website that came from the website, the correction follows by itself, but
only until the section's next round is paired. From then on the website
changes nothing in that round, neither a missing result nor a correction,
because the pairings were made from the results as they stood: a result it
shows differently is listed for you to type in yourself if it is right.
Forfeits entered on the website come in as forfeits. Also left for you to
enter: a "forfeit draw", which has no equivalent here, and a game marked
disputed. When the page cannot be read, the strip says so and keeps trying;
enter results here meanwhile. A Boylston page with no round posted yet reads
as "not on the website yet", not as an error.

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

**SwissSys files** are kept in the event's folder as SwissSys 9 keeps them in
its own, for a screen or website that shows pairings and board numbers from
those files: `Open.S0C` for the Open section before round 1, `Open.S1A` once
round 1 is paired (rewritten as results come in), `Open.S1C` when its results
are all in, then `Open.S2A`, and so on. Earlier rounds' files stay; undoing a
round's pairings removes its file. Only files this event wrote are ever
replaced or removed: another event's SwissSys files in the same folder are left
as they are, and a file of the same name is not written over. Files are
written a moment after the last change, not on every result. **Save SwissSys files**, on the pairing
sheets, writes the files again on demand; for an event without a folder of its
own it asks which folder to use and offers that folder again next time. The file names the
players as `LAST,FIRST` and lists the boards, colors, byes, scores and earlier
results. Quads, round robins, Swiss and Scheveningen sections have one; ladders,
knockouts and bughouse do not. The round 1 file matches SwissSys's own cell for
cell; later rounds follow the same layout but have not yet been compared with
one.

**Save PGN headers**, on the pairing sheets, writes the round's games as a PGN
file with no moves: one game per board with the event, round, board, players,
ratings, titles, FIDE IDs and time control, for whoever enters the scoresheets
afterwards. A game without a result carries `*`, so the file can be made as soon
as the round is posted. Byes and forfeits are left out, as no game was played.
A quad or round robin, which prints its whole schedule, saves its whole
schedule.

## Checking the event

**Check event**, in the top bar, lists likely mistakes before the next round:
two players paired a second time, the same color three games in a row, an
active player with no game and no bye, a withdrawn player still on a board, a
second full-point bye, byes past the announced limit, a do-not-pair request
that was paired, a rating outside its section's range, a prize nobody entered
can win, an earlier round still missing results, and one person entered in two
sections. Check the whole event or one section. It reads the event as it is,
changes nothing and never stops a round from being paired.

Under **Checked**, every check says what it looked at ("Clear: 24 pairings
checked"), and a check that did not apply says why ("Not checked: no section
limits half-point byes"). Each Swiss section also gets its **pairing quality**
round by round, as counts out of what they could have been: boards inside one
score group, players who got the color they were due, third games in a row with
one color, and repeat pairings. **Copy report** puts all of it on the clipboard.

In the prize table, each prize says how many entrants can win it, and warns
when nobody can, which usually means a mistyped rating range. The **Awards**
board names each section's biggest upset (the largest rating gap in a played
win by the lower-rated player), for an upset prize you announced.

## The scoreboard

**Scoreboard**, in the top bar of the desktop app, serves a page that cycles
through each section's pairings and standings, for a projector, a TV or phones.
Choose **Start scoreboard**, then **Open in browser**, drag the window to the
projector and press F11. The page follows the event: a posted round or a result
appears within a few seconds, and a round still under review does not appear
until it is posted. It keeps running while the panel is closed and stops when
the event closes.

Tick **Let TVs and phones on this network open it** for an address and a QR
code that work on the same Wi-Fi. Anyone on that network can read the board;
nobody can change anything through it. If a phone cannot open it, the venue
Wi-Fi may keep devices apart, and a phone hotspot shared by the laptop and the
TV works without it. The computer's firewall may ask once whether to allow
Meow Chess on the network.

Choose pairings, standings or both, which sections, and the seconds each screen
stays up; the choices are kept with the event. A long section is split across
screens rather than shrunk. A Swiss shows its latest round; quads and round
robins show the first round still being played. Standings appear once a round
is complete. The page shows a clock and the time of the last change, says so if
it loses contact with the director's computer, and takes Space to pause, the
arrow keys or a swipe to step, and **A−**/**A+** for text size. It shows what
is posted on the wall (names, boards, results, ratings and scores) and never an
ID, a note or a contact detail.

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

**Add from URL** (later **Refresh from URL**) accepts Boylston event or
entry-list links. For other clubs, paste a page containing a Name, Rating and
US Chess ID table. After **Fetch players** the panel says how many players it
found and which sections the list names, and one button adds them: **Add 16
players**. Only what needs a decision is listed: a row that cannot come in, or
a local player the website now shows differently (ticked by you, never by
default). **All new entries** opens the full list. Clubs can contribute their
own URL rules and parsers; see [adding a club website](CLUB_ROSTER_ADAPTERS.md).

An import never asks for rounds. Sections the list names are started with the
rating cap in their name (U1800 is under 1800), and from a Boylston event page
the announced rounds, time control and play-up rule are filled in. A section
whose rounds are still unknown is not paired until they are set.

## Setting up the tournament

**Set up**, beside **New section**, is the whole tournament in one panel, and
opens by itself after an import. At the top are the three things every
section shares: **Time control**, **Rounds** and **Play up within**. Typing a
number in **Rounds** fills every section at once; it reads **Varies** when
the sections differ. Under them the panel says **Matches the event page**, or
names what the page announced with **Use these**.

**Sections** is a table: each section's name against its **Format** and
**Rounds**, with its size and rating range beneath. **Combine sections…**
under the table opens Combine for any of them.

A section with too few players is not marked here. Before round 1, a caution
triangle beside **Create pairings** names it: a single player, a Swiss with
more rounds than its players can play without meeting twice, or fewer
players than the event page says may be merged. You can still pair; Combine
or fewer rounds is the usual answer.

With a play-up limit of 200 and a U1800 section, the Open takes players rated
1600 and over; unrated players may enter any section. **Players to check**,
under the table, lists everyone the rule or a rating cap puts elsewhere, each
with **Move to U1800** and **Keep in Open**; the section's row counts them
("1 to check"). Pairing is never held back for it.

**Review registration notes** follows: each entrant's note from the website
("Bye rd 1") with the bye grid under it. Give the bye, then **Dealt with**.
Nothing is read out of a note for you. The list is also under **Player
tools**.

**Combine** makes one section of two or more. Open it from a section tab's
menu, or from **Combine…** on a section marked for merging in Set up. With two
sections the panel asks only **Which way**: "U1800 into Open" or "Open into
U1800". The section the players go into keeps its name,
format and rounds; under each choice are those settings and how many players
would be outside its rating range, and the way that fits everyone's rating is
chosen to start with. With three or more sections, tick the ones to combine
first; any number can become one. The button names the outcome ("Combine into
Open · 18 players"). If the round is already paired but no result is in,
those pairings are discarded and the combined section is paired again with
everyone; **Undo** takes back the pairings, and again the combine.

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

## Entered rating or US Chess rating

**Refresh from US Chess** on **Players** looks up each US Chess ID and shows
the supplement rating beside the rating you entered; tick the ones to use and
choose **Confirm**. Afterwards the table keeps both for everyone found:
**Entered**, and **US Chess** with the supplement date and the difference. The
tick box beside the US Chess rating says which one the player is paired with.
Click it to switch that player, in either direction; the box in the column
heading switches everyone listed (search or pick a section first to narrow
that). Each switch is saved at once and **Undo** takes it back. Typing a rating
in a player's card makes that the entered rating and keeps the US Chess one to
switch back to.

The choice is open until the section is paired. After that the pairing rating
stays, and the column is no longer shown.

## Rating estimates

On **Players**, **Show rating estimates** (under **Player tools**) is off by
default. Enable it to see approximate Regular ratings and changes as results are
entered or corrected between rounds. This just-for-fun preview assumes 50 prior
rated games, uses starting ratings and completed games in each section, and
omits personal floors and provisional formulas. It never changes pairing ratings
or exports. See [calculation details and limits](RATING_PREVIEW.md).
