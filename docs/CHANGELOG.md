# Changelog

Downloads for each version are on
[Releases](https://github.com/Zinkelburger/Meow-Chess/releases); the browser
version at https://chessautoprep.com/meow-chess/ follows the latest release.

## Unreleased

- **Entered or US Chess rating, one click.** After **Refresh from US
  Chess**, the Players table keeps both numbers for everyone it found:
  **Entered** (the rating from registration, an import or typed by hand) and
  **US Chess** with the supplement date. A tick box beside the US Chess
  rating shows which one the player is paired with; click it to switch, and
  click again to switch back. The box in the column heading switches everyone
  listed. Nothing is looked up again, and **Undo** takes any of it back. This
  covers players you left unticked in the review and reviews closed with
  **Keep current ratings**. The column goes away once a section is paired,
  when its pairing ratings are fixed. A player's card lists the rating not in
  use under **US Chess**.

- **The crosstable is in rating order.** It used to list a section in the
  order the players were entered until round 1, then by score with ties in
  name order. Now it lists the highest rated first, before and after play
  starts, so a row stays put as results come in; **Rank** still gives the
  place. A menu beside the search box switches to **Standings order**,
  **Pairing number order** or **Name order** for the whole event. Equal
  ratings go by pairing number and unrated players come last; a FIDE-rated
  section uses its FIDE ranking. Printed standings and crosstables are
  unchanged.

- **The Pairings page keeps still.** Creating pairings, typing results and
  dismissing notes no longer move the page under you:
  - **Create pairings** keeps its label and size while it works; a spinner
    takes the arrow's place.
  - **Edit pairings**, **Re-pair round**, **Flip pairing** and **Re-pair
    unstarted boards** are now in one **Change pairings** menu. The toolbar no
    longer loses a line when the first result goes in; what the round no
    longer allows is greyed in the menu.
  - **Website results** stays on the toolbar before the round is paired,
    greyed.
  - Section tabs keep their width as "Round 1 · 8 missing" counts down to
    "Complete", and choosing a tab no longer shifts the tabs after it.
  - The notes on new pairings show in the empty column at the right instead
    of pushing the page down.
  - A no-show's **Withdraw** button sits on the player's line, so the row
    keeps its height.
  - The key hints under the boards always keep room for their longest
    wording, so a wrong key or a forfeit board doesn't make the sheet jump.
  - The round chips stay at the right of the heading, so picking a round or
    **All** never moves the chip you are clicking.

  Elsewhere:
  - "Draft saved · not applied" now appears with **Save** (or under the
    buttons) instead of above the form, so the first keystroke no longer
    pushes the fields down.
  - The US Chess ID check waits until you leave the field before calling an
    unfinished ID wrong, and **Check ID** is always shown.
  - A wrong key in the crosstable is answered in a hint that floats over the
    table instead of pushing it down.
  - **Print** keeps its label while printing.
  - Times and counts in the status bar use even-width digits. Print and
    History messages now appear after **Backup**, so the bar no longer
    shifts sideways.
  - Ticked players in the selection panel take a fixed two lines.
  - A recorded ladder game no longer drops the table.

- **1, 0 and D always mean a played game.** On a board that holds a forfeit,
  **1** and **0** used to choose who won the forfeit and **D** was refused.
  Now they enter a played result there as on any other board, with the usual
  notice and **Undo**. **F** alone handles forfeits and switches a player's
  no-show on and off: **F** on one player is a forfeit, **F** on both a double
  forfeit, and **F** again on a player takes their no-show back.

- **Combine either way.** **Combine sections** no longer assumes the tab you
  opened it from is the one that goes. The panel offers each way round as a
  whole outcome ("U1800 into Open", "Open into U1800"), with the settings
  everyone would then play under and how many players would fall outside the
  rating range. The way that fits everyone's rating is offered first. With
  three or more sections you tick the ones to combine, and any number can
  become one in a single step with one **Undo**.
  Set up no longer puts **Combine…** on every section's row: one **Combine
  sections…** under the table opens the panel for any of them. The section
  tab's menu has **Combine sections** too.

- **Too few players.** Set up no longer marks a section as under the event
  page's merge size. Instead, before round 1, a caution triangle beside
  **Create pairings** names a section with too few players: one player
  alone, a Swiss with more rounds than its players can play without meeting
  twice ("U1800 has 4 players for 5 rounds, so some will meet twice."), or
  fewer players than the event page says may be merged. It never holds
  pairings back.

- **Clearer marks on the player list.** A player outside their section's
  rating range now carries one icon at the end of the name, where a long name
  can no longer hide it and no words are cut off; hovering it gives the reason
  at once. Until the section is paired those players are listed last, under a
  bar that states the rule ("Playing up into Open takes 1600 or more. Unrated
  players may enter.") and ticks them all for a single Move. Unrated players
  the rule admits stay above it. In a US Chess rating review, a change of more
  than 50 points or a first rating is marked beside the number instead of
  shaded, and the panel lists them under **Large rating changes** with the
  rule in words.

- **Re-pair round.** Until a Swiss round has its first result, **Re-pair
  round** on the Pairings toolbar pairs the whole round again from the
  entries as they are now, in one click with **Undo**: a walk-up entered
  after the pairings went up is paired instead of taking a late-entry bye,
  and withdrawals, bye requests and corrected ratings are taken into
  account. It works in FIDE sections too. With nothing changed the pairings
  stay exactly as they are and the notice says so; nothing is added to the
  history, so **Undo** never has to take back a step that changed nothing.
  On round 1, **Flip pairing** beside it pairs the round again with the
  coin toss reversed, so board 1's other player has white, for matching
  another program's round-1 colors. Every section's round 1 shares the one
  toss, so the other sections are flipped in the same step.

- **Mac download.** Releases now include a Mac app (macOS 12 or later). It is
  not signed by an Apple developer account, so the Mac asks once before opening
  it; [the workspace guide](USING.md#on-a-mac) shows how. It runs without the
  App Sandbox, which only the Mac App Store requires. CI now runs every test on
  a Mac, including a tournament day in the real app, and opens the download
  before each release.

- **Results from the club website.** **Website results**, on the Pairings
  toolbar, reads the Boylston Chess Foundation's live results page
  (`beta.boylstonchess.org/results`) every ten seconds and enters each result
  players report there, as its own step with **Undo**. The button is there
  only for an event imported from a Boylston address, where it is the one
  tinted button on the toolbar, with a cloud; one click starts it. Other
  events do not show it. Results are taken only
  when the website shows this round's own pairings, board for board, and a
  result typed here is never replaced: differences are listed with one button
  to take the website's. Once a section's next round is paired, the website
  no longer changes the earlier round; a difference there is listed for you
  to enter. Results wait while pairings are being made or remade. See
  [Results from the club website](USING.md#results-from-the-club-website).
  Checked against the live page's layout and with the app's tests; not yet
  run through a round at the club.

- **A folder for each tournament.** A new event gets a folder named after it
  inside `Documents/Meow-Chess` (or a place you pick), holding the `.meow`
  file, and PDFs, standings, DBF files and SwissSys files are saved straight
  into it. Events kept elsewhere still ask where to save. No folder window opens for the first event. See
  [Start](USING.md#start).

- **SwissSys files for a pairings screen.** Each section's SwissSys 9 file is
  kept current in the event's folder (`Open.S0C`, `Open.S1A`, `Open.S1C`,
  `Open.S2A`…), so a display that reads those files can show Meow-Chess
  pairings and board numbers. Only files the event wrote are replaced or
  removed, so another event's files in the same folder are safe. Withdrawn
  players are flagged. See [Printing](USING.md#printing). Checked
  against SwissSys 9.14's own files before and after pairing round 1; not yet
  tried with a display program or with files from later rounds.

- **Import, then set up.** Adding players from a URL or a file no longer asks
  for rounds or lists every player with a checkbox: it says how many players
  and which sections it found, and one button adds them. **Set up**, beside
  **New section**, then holds the whole tournament in one panel: time control,
  each section's format and rounds, and the play-up limit. A Boylston event
  page fills in what it announces (4SS, G/60 d5, play up within 200 points).
  See [Setting up the tournament](USING.md#setting-up-the-tournament).
- **Play-up check.** With a play-up limit, a player rated too low for the
  section above is listed with **Move to U1800** and **Keep in Open**. Sections
  named like U1800 take that rating cap. Unrated players may enter any section.
- **Registration notes.** Notes from the website ("Bye rd 1") are worked
  through in one list, each with the bye grid, and marked **Dealt with**.
- **Combine after pairing.** Combining two sections whose round is paired but
  not played discards those pairings and pairs the combined section again.
  Combining an unpaired section is now one step to undo, not two.
- **Check event.** A button in the top bar lists likely mistakes before the
  next round (repeat pairings, a third game with one color, a player with no
  game or bye, byes past the limit, one person entered twice, a prize nobody
  can win and more), says what every check looked at, and gives each Swiss
  round's pairing quality as counts. It changes nothing and never blocks a
  round. See [Checking the event](USING.md#checking-the-event). Automation has
  it as `check_event`.
- **Scoreboard.** The desktop app serves a page that cycles through pairings
  and standings for a projector, a TV or phones on the same Wi-Fi, with a QR
  code. It follows the event as rounds are posted and results come in, and
  shows only what is on the wall. See [The scoreboard](USING.md#the-scoreboard).
  Checked in Chrome at TV and phone sizes; not yet tried on a smart TV's own
  browser or at a venue.
- **Save PGN headers** on the pairing sheets: the round's games as PGN with no
  moves, for entering scoresheets afterwards.
- **Prizes.** Each prize in the prize table says how many entrants can win it
  and warns when nobody can. The Awards board names each section's biggest
  upset.

Fixes from an October review that never reached a release:

- **Prizes:** when a tied player takes a larger points prize, they leave the
  tie and the others divide the place prizes; what they can't take passes down.
  Those place prizes used to go unawarded.
- **Swiss colors:** the due color is right when one player sat out the latest
  round the two differ in, and the alternating-color variation restarts in each
  score group. A double-game pairing counts as one meeting, scores in double-game
  sections are measured as such, and bughouse partnerships get no invented
  color history.
- **Printed reports:** Swiss sections no longer print round-robin prize
  standings; "Under X" classes use the prize rating; a double-game full-point
  bye prints B, not U; bughouse partners appear on board 2 with their
  partnership's result; wall-chart totals include a re-entry's carried score;
  conditions sheets print open classes and points prizes plainly; Scheveningen
  sheets show the match score; knockouts export as ASCII crosstables.
- **On screen:** the knockout bracket draws again on Pairings, and each bracket
  keeps its own advance reasons when searching. Bughouse partners get a score
  box, Swiss score groups include re-entry scores, the Prize standings print
  matches the screen, and Fetch missing states keeps going after leaving
  Reports.
- **Corrections** warn about a player moved into a section that had played
  fewer rounds.
- **Names** with accents (José Núñez) match US Chess's NUNEZ without a
  wrong-ID warning.
- **Sections and byes:** adding a section is checked like creating one;
  moving players who are already in the target records nothing; a bye is
  cancelled with its own command, and bye values outside 0–2 are refused.
- **Automation:** create_section refuses withdrawn players, duplicates and
  more than 32 rounds, and errors say what is allowed.
- **Files:** reopening an event no longer leaves a -shm file beside it; the
  Linux save dialog no longer blocks the app.

## 1.5.1 — November 12, 2026

- Ticking players and then creating a section or moving them no longer leaves
  an old Move-to or swap waiting to be applied.
- Crosstable headings stay over their columns in every layout, and tables in
  FIDE-only events are sized to the columns they show.
- Tab into the crosstable lands on the cell you were on, or else the first one
  still missing a result.
- An event whose prize table or variation setting cannot be read is refused
  when it opens rather than failing later.
- More unexpected problems (keychain, damaged drafts, US Chess replies, browser
  storage) are written to the diagnostic log instead of passing silently.

## 1.5.0 — November 10, 2026

- **Events saved by this version cannot be opened by 1.4.0 or earlier**, which
  now say the event is from a newer version. An older copy that opened a newer
  file used to drop whatever it did not know about at its first save. Update
  every computer that shares event files; events from older versions open as
  before.
- Copying a backup over an event file after a crash is safe: nothing is left
  beside the event file between saves for SQLite to replay over the copy.
- If the open event file is moved, renamed, deleted or replaced, or its drive
  is unplugged, the status bar stops saying "Event saved", a banner says what
  happened, and **Save a copy…** carries on in a new file with nothing lost.
- The backup folder belongs to the computer: Undo and going back in History no
  longer change or switch it off, an event opened on another computer says it
  has no backup folder there, and a folder from another system is never written
  to. Backup copies are named for the event.
- Entering a result on a 300-player event saves in about two thirds of the time.
- "New event like…" only reads the event it copies from. It no longer rewrites
  it, or creates an empty file where a recent event had been deleted.
- `meow_chess -check file.trf` and the other FIDE tools run even while the app
  is open, instead of handing the file to the open window.
- On Windows the first window fits a small or scaled screen.
- In the browser, deleting an event asks in its row; saves are finished when the
  page is hidden or left.

- **Save PDF** in every print panel, and **Copies and options…** for the
  computer's own print window: copies, two-sided printing and trays.
- Each sheet is laid out for the paper it prints on: the printer's tray on
  Windows, or the paper chosen in the print window, so an A4 sheet on a Letter
  tray no longer loses its bottom. The macOS print window now offers paper size.
  **Paper** chooses Letter or A4 for the preview and for printers that do not
  say. Direct prints use the printer's own settings instead of forcing a custom
  page size.
- A round robin of any size prints a one-page pairing grid to post, ahead of its
  board tables, and its wall chart shows the coming rounds' opponents and colors.
- The Flatpak can reach printers; it had no access to CUPS. The macOS app has
  the print entitlement its sandbox requires.
- Linux no longer offers GTK's "Print to File" and "Print to LPR" as printers,
  so a computer with no printers says so, and sheets cannot silently go to a file.
- A printer that fails or has gone away gets a plain message rather than the
  print plugin's raw error, or none at all. A print service that stops
  responding ends in a message, and never leaves Print stuck on "Printing…".

## 1.4.0 — November 6, 2026

- A Wall chart print (rule 28O): the crosstable in pairing-number order with a
  column for every planned round, blank until paired, and withdrawn players
  greyed. Right-click a section tab, or pick Wall chart in a Standings print.
  Exports include `wall_chart.txt`.
- History lists recovery points: before each round was paired or unpaired,
  each import and each move of players. When the event is on an earlier
  version, Return to latest comes back, and asks first when that would remove
  play or change a result later rounds were paired on.
- Pairing several sections at once refuses to put one person on two boards
  and names who and where.
- After a result far down a long round, the cursor reaches a board skipped
  near the top, and the next key lands there.
- Bughouse partners moved together into another section stay partners.
- The backup folder also gets a copy when a round's last result is entered,
  not only when the next round is paired.
- Re-pairing an unstarted round refuses a player still in a side game, and
  replacing a pairing refuses a game with the same player on both sides; each
  names the player and board.
- A print preview with nothing to print no longer leaves a stray error behind.

## 1.3.1 — October 29, 2026

- The browser version: the same workspace at chessautoprep.com/meow-chess/.
  Events stay in the browser, with download and upload of `.meow` files the
  desktop app opens. FIDE-rated pairing and the FIDE rating list still need the
  desktop app.
- An Awards board in Reports: every section's prizes with the winner, the award,
  the tie-break that settled a tie, and a Handed out tick kept in the event.
  Indivisible awards now follow the tie-breaks instead of alphabetical order.
- A lowest rating beside each section's cap. Players outside the range are
  flagged wherever they can land, and the TD can allow one in with a recorded
  reason.
- Imported players land in the section their registration names.
- Sample rosters and a sample-event generator for trying the app.
- The note under New event like this names what the template copies.
- CI is green again (sample line endings, a screenshot folder, the macOS test
  host). The 1.3.0 downloads were never published because of those failures,
  so this is the first release carrying the 1.3.0 work.

## 1.3.0 — October 10, 2026 (not published)

- FIDE-rated sections, dual-rated or FIDE only, paired with the FIDE Dutch
  system through BBP Pairings; FIDE tie-breaks; TRF26 export; a FIDE rating list.
- Scheveningen, Holland, knockout, ladder and bughouse formats, with one
  section panel for every format.
- Scholastic team awards and the remaining US Chess Swiss rules.
- Swiss pairings validated against the Boylston archive.

## 1.2.3 — October 6, 2026

- One New section panel replaces Create sections and New Section, previewing
  every player in each section it will create.
- CSV and TSV imports open in a spreadsheet-style window: separators, quotes,
  a field per column, and rows already in the event or repeated in the file.
- Blue buttons quieted to one commit action per region; every menu opens
  instantly.
- Saving and opening events under the macOS App Sandbox fixed.

## 1.2.2 — October 5, 2026

- F is a one-key no-show; US Chess result letters print (X/F forfeits,
  B---/H---/U--- byes).
- The player card redesigned with a compact bye table and one Move action that
  keeps quads at four.
- The full US Chess record shows from Check ID; the crosstable and round
  headings stay level; any on-screen text can be selected and copied.

## 1.2.1 — October 4, 2026

- Database recovery files protected when saving copies; stale roster and
  pairing edits rejected; rating lookups preserved after save failures;
  complete report packages published durably.

## 1.2.0 — October 4, 2026

- Complete quad schedules and pairing edits.
- US Chess identity and rating review improved; reliable history and recovery.
- Shared lookup and approval logic keeps late network responses from changing
  another event.
- The optional MCP launcher works without Bash on Windows; report exports use
  the native replacement mechanism on sandboxed macOS.

## 1.1.1 — October 3, 2026

- Stable panels and UI fixes.

## 1.1.0 — October 2, 2026

- Recoverable workflows and scoped printing.

## 1.0.0 — September 30, 2026

- First release: Swiss and quad events, keyboard results entry, US Chess ID
  checks, printing and the US Chess rating report.
