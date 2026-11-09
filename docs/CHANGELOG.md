# Changelog

Downloads for each version are on
[Releases](https://github.com/Zinkelburger/Meow-Chess/releases); the browser
version at https://chessautoprep.com/meow-chess/ follows the latest release.

## Unreleased

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
