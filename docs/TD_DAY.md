# A tournament day, in order

What to do in Meow-Chess from an empty event to the rating report, in the order
the day happens. The example is a one-day club Swiss with one TD, one laptop
and one printer; quads differ only where noted. The [workspace guide](USING.md)
describes each screen in more detail, and [keyboard results entry](RESULT_ENTRY.md)
has the full key list.

Everything saves as you go. **Undo** (Ctrl+Z) takes back the last step and
**History** (Ctrl+H) lists every step of the day.

## Before players arrive

1. **New tournament**, type the event's name and choose where to keep its file.
2. Click the event's name at the top left to open **Event details**: date, time
   control, venue, city, state and ZIP, the chief TD's US Chess ID and the
   affiliate ID. The rating report needs all of these, so enter them now rather
   than at 11 pm.
3. Click **No backup folder** at the bottom of the window and pick a folder on
   another drive (a USB stick is fine). A copy is written there after every
   round.
4. On **Players**, bring in the advance entries: **Add from URL** for a club
   registration page, **Import file…** for a CSV, or **Paste** for rows copied
   from a spreadsheet. The import window shows every row. Each row that names
   someone comes in; if a rating, ID or state could not be read, the row says so
   and the player comes in without that field.
5. **Refresh from US Chess** checks IDs and brings in current ratings and
   membership expiry dates, when the network allows.
6. **New section**: choose who goes in, the format (Quads, Swiss, Round robin,
   or another under **Other format…**), the number of rounds and, if it differs
   from the event's, the time control. Byes, pairing rules and prizes can be
   set here or later from the section's **Section actions** button.

## At the door

There is no check-in step: everyone entered is paired, and a player who never
arrives is forfeited when the round is under way.

- A walk-up: **Add player**, type the name, the US Chess ID (or **Find by
  name**), the rating and the section.
- A bye request: right-click the player, **Byes…**, and tick the round in the
  ½ pt row. The section's bye rules are shown beside the choice.
- Someone in the wrong section: right-click, **Move…**.

## Round 1

1. Go to **Pairings**. **Create pairings** names what it will pair: the selected
   section, or every ready section when **All sections** is selected.
2. The round appears at once. Any note the pairing needs, such as who has the
   bye and why, is listed with the round.
3. Print the pairing sheet with the printer button above the boards. The first
   print asks for a printer; later prints go straight to it.

Quads show their whole schedule as soon as the section exists, so there is
nothing to create: print the sheet and start.

## During a round

- **Where am I playing?** Ctrl+L finds a player and shows their board, color and
  opponent.
- **A late entry.** **Add player** and choose the section. They get a bye for
  each round already paired (a half point where the section's bye rules allow
  it, otherwise zero; you can change it on their card) and are paired from the
  next round.
- **A no-show.** Click the absent player's score box and press **F**. The
  opponent wins by forfeit, and **Withdraw from future rounds** appears on the
  board for the absent player.
- **A player has to leave.** Right-click, **Withdraw after round N**.
- **A withdrawal after pairings are up but before play.** **Re-pair unstarted
  boards** keeps the boards that have results and pairs the rest again.
- **Two players paired wrongly.** **Edit pairings** swaps players on boards
  that have no result yet.

## Results

Click a score box and type: **1** or **W** for a win, **0** or **L** for a
loss, **D** for a draw, **F** for a no-show. The opponent's box fills in and the
cursor moves to the next board. **Delete** clears a result. **Missing only**
hides the boards that are done.

Typing over a result that is already there changes it at once and says so at
the bottom of the window, with **Undo**. For a result from an earlier round,
choose the round and **Correct a result**: the panel shows each player's new
score and asks what should happen to later rounds.

## Between rounds

When the last result is in, **Create pairings** offers the next round. Print the
new pairing sheet, and standings or the wall chart from the printer button
above the crosstable.

## End of the day

Open **Export**.

1. **Awards** lists each prize, who won it and what decided a tie. Print the
   prize report from the same page.
2. The **US Chess rating report** lists anything that would stop the report,
   each with a link that opens the place to fix it: a missing result, a player
   who played but has no US Chess ID, a missing TD or affiliate ID.
3. **Generate DBF files** writes the three files US Chess asks for into a new
   folder. Upload them from the TD/Affiliate area of the US Chess site, then
   record the confirmation under **Submission notes**.
4. Check the status bar for the time of the last backup before closing the
   laptop.

Meow-Chess checks its rating reports against reports US Chess has accepted from
other software, but no report made by this app has been uploaded yet; see
[DBF compatibility](DBF_COMPATIBILITY.md). Read the file list US Chess shows
after the upload before you confirm it.
