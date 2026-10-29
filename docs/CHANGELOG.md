# Changelog

Downloads for each version are on
[Releases](https://github.com/Zinkelburger/Meow-Chess/releases); the browser
version at https://chessautoprep.com/meow-chess/ follows the latest release.

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
