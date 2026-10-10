# FIDE-rated sections

Meow-Chess runs FIDE-rated sections beside US Chess ones: dual-rated (US Chess and
FIDE) or FIDE only. This page says what is built, where it lives, what was checked,
and what is not claimed. The sources are summarized in
[research/notes/FIDE.md](../research/notes/FIDE.md) and saved under `research/local/`.

## What is not claimed

- **Meow-Chess is not a FIDE-endorsed pairing program, and is not applying.**
  FIDE's acceptance (TAPC, C.02.01/C.02.03; TEC Manual v1.24) costs USD 1,200 for
  a tournament program and its 2026 checklist is not final. Meow-Chess instead
  implements what the process tests (see [the checklist](#fides-checklist)) and
  verifies it the way TEC does. The Dutch pairings come from BBP Pairings, the
  engine inside SwissSys's endorsement, but endorsement belongs to the program.
- **US Chess does not process TRF files.** For a US event it takes FIDE-rated
  sections only as the file of an endorsed program (SwissSys `.S#C`/`.sjson`,
  `research/local/uscf-fide-events.txt`). The TRF26 files suit a federation rating
  officer elsewhere, or another program: SwissSys documents opening TRF files.
- The TRF26 export has not been uploaded to FIDE's rating server.

## How a section is rated

`Section.unrated` (left out of the US Chess report) and `Section.fideRated` combine
into `RatedBy` (`lib/domain/fide.dart`): US Chess, US Chess and FIDE, FIDE only, or
Not rated. The section settings panel shows it as **Rated by**, under the time
control. FIDE rates Swiss, round-robin and quad sections; each section is its own
FIDE tournament. A FIDE-rated Swiss changes pairing system, so that choice is made
before round 1.

`fideCategory` maps a time control to FIDE's list by each player's time for 60
moves, with delay counted as increment: standard at 60 minutes or more, rapid
above 10 and under 60, blitz above 3 up to 10 (B.02 and the rapid and blitz
regulations).

## Player identity

`Player` carries `fideId`, `fideStandard`, `fideRapid`, `fideBlitz`, `title`,
`federation`, `birthDate` (`YYYY` or `YYYY-MM-DD`), `sex` (`m`/`w`, as TRF writes
it) and `fideEvidence` (which FIDE list filled them). They are validated by
`fideFieldsProblem`. The player panel shows them in a **FIDE** group once any
section is FIDE rated, and the roster gains FIDE ID and FIDE rating columns
wherever a listed section is FIDE rated; the group opens itself for a FIDE-section player with no ID.
FIDE ratings are fixed once their FIDE section is paired, like the US Chess rating.

Where the data comes from:

- **US Chess member lookups** return `fideId`, `fideTitle` (one letter, mapped by
  `fideTitleFromCode`), `fideCountry` and `gender`. Membership checks fill blank
  FIDE fields; the player panel offers "Use FIDE ID …".
- **FIDE's monthly rating list** (`lib/infrastructure/fide_rating_list.dart`). FIDE
  has no API, so the official list is the only source. Player tools → **FIDE
  ratings** downloads `players_list.zip` (45 MB) or imports a list ZIP the TD
  already has; a download can be cancelled. The ZIP becomes a 32 MB gzipped index in the app data folder
  (`fide/players.tsv.gz`). Columns are read from the header line, and fields after
  "other titles" from the line's end, because that column overflows on a few
  lines. On the October 2026 list (1,932,867 players), import took 18 s on a
  background isolate, an ID lookup 0.5 s and a name search 3.4 s. The panel
  compares every player who has a FIDE ID, lists the differences ticked, and
  applies them as one undoable change. A player's FIDE group searches the list by
  name, or refreshes them by ID, from what is typed.

FIDE has no membership that expires, so nothing matches US Chess's expiry date.
Instead, the panel checks four things against the list:
- whether the installed list is older than the event's month;
- whether the chief arbiter's and deputies' FIDE IDs carry an arbiter title (IA, FA
  or NA); licence payment is not in the list, so FIDE's arbiter site is the final
  word;
- which players FIDE lists as inactive (still rated, no rated game for a year);
- who in a FIDE-rated section still has no FIDE ID, each a link to their FIDE ID
  field.

## FIDE-only events

Where no section is US Chess rated, US Chess clutter steps aside:
- the roster drops the USCF ID, rating and expiry columns;
- "Refresh from USCF" becomes "Update FIDE ratings";
- Event details hides the US Chess TD and affiliate fields;
- Report details keeps only the event, dates, chief arbiter and city.

## Pairing: FIDE Dutch

`pairFideDutch` (`lib/domain/fide_pairing.dart`) writes the section as an
in-tournament TRF26 file. `bbpPairDutch` (`lib/engine/bbp_pairings.dart`) pairs it
with BBP Pairings, which implements the Dutch rules in force since 1 February 2026.
The engine is vendored in `third_party/bbpPairings` (Apache-2.0, pinned commit in
`VENDORED.md`). `hook/build.dart` compiles it into a dynamic library on every
platform, so there is no helper program or temporary file. The licence ships in
the app's licence page.

- Pairing numbers are fixed when round 1 is posted (`Section.fideOrder`), so later
  rating, title or name edits never renumber a section. A late entry is placed
  before the first player it outranks.
- Pairing numbers follow C.04.2: rating, then title (GM > IM > WGM > FM > WIM > CM >
  WFM > WCM), then name. The rating is chosen by TRF record 172's method. A
  dual-rated section defaults to `FIDON` (FIDE rating, else US Chess); a FIDE-only
  section defaults to `FIDE`.
- Requested byes, withdrawals and house players are marked unavailable for the
  round: `fideEngineInput` passes the byes `roundAvailability` settled, so the
  engine's file and the round agree.
- Do-not-pair requests become record 260. From round 3 the pairing explanation
  notes that they are not part of the Dutch rules (as Swiss-Manager and SwissSys
  warn).
- Pairing assumptions for unreported games are used as results; in a FIDE section
  an assumption can only be a draw (C.04.2 3.1).
- An adjourned game (`Outcome.unfinished`) counts as a draw for the next pairing
  only (C.04.2 3.1); pairing the round after waits for its result
  (`pairsWithoutResult`, `readyToPair`).
- **The pairing-allocated bye's value** (`Section.pabPoints`, C.04.1 3, VCL.16):
  a win (default), a draw or nothing, chosen in Pairing rules and written as TRF
  record 162 `P` when it is not a win.
- **Baku acceleration** (`Section.accelerated = 'baku'`, C.04.7, VCL.10). Group A
  is the first 2 × ⌈n/4⌉ players; its last player is fixed when round 1 is posted
  (`Section.bakuLast`), so late entries above them join the group and those below
  do not (1.3.2). Group A gets a win's points before the first half (rounded up)
  of the accelerated rounds and half that before the rest; the accelerated rounds
  are the first half (rounded up). `bakuAccelerations` writes them as explicit
  TRF records 250, which BBP Pairings applies. (BBP's own `FIDE_DUTCH_BAKU` uses a
  group of ⌈n/2⌉ and no late-entry rule, so Meow-Chess does not rely on it.) US
  Chess accelerations (28R) and two games per round are refused for FIDE Swiss
  sections.
- Acceleration, the bye's value and FIDE rating itself are announced before
  round 1 and fixed once a section is paired (`fideSettingsChangeProblem`, used by
  the section panel and the MCP tools).
- Forfeited games may be paired again (C.04.1).
- Rounds record the policy `fide-dutch-2026-bbp-6`.
- A house player is never paired; they get a 0-point bye, since FIDE uses the
  pairing-allocated bye.
- US Chess selective re-pairing (29G3) is refused in FIDE sections.

## Results and byes

- **Unusual results** (VCL.13): `Outcome.whiteHalf` (½–0), `blackHalf` (0–½) and
  `bothLose` (a played 0–0). US Chess cannot report them, so `validateEvent`
  allows them only in a section US Chess does not rate; Correct a result offers
  them there. TRF writes each player's own result (`=` and `0`).
- **Games of less than one move** (`Game.shortGame`): the result stands and FIDE
  does not rate it; TRF writes `W`, `D`, `L`. Correct a result marks it in any
  FIDE-rated section; US Chess still sees the ordinary result.
- Forfeits are only 1F–0F, 0F–1F and 0F–0F (VCL.14).
- **Full-point byes** (VCL.17) stay allowed; in a FIDE section the player panel
  says FIDE deprecates them as soon as one is chosen, the MCP `reserve_bye` tool
  returns the same warning, and the FIDE report lists them as advice.

## Tie-breaks: C.07 (2026)

`lib/domain/fide_tiebreaks.dart` computes every individual tie-break of MTB26
(C.02.03 Annexure B), 59 codes:

- `DE`, `DE/P`, `WIN`, `WON`, `BPG`, `BWG`, `REP` (`GE` is read as `REP`), `STD`
- `PS`, `PS/C1`, `PS/C2`; `KS` and `KS/L±1`…`KS/L±3`
- `BH`, `FB` and `SB`, each with `/C1`, `/C2` (and `BH`/`FB` with `/M1`, `/M2`),
  and `/P` with any of them
- `AOB`, `AOB/F`
- `ARO` with `/C1`, `/C2`, `/M1`, `/M2`; `TPR`, `PTP`, `APRO`, `APPO` (B.02
  tables 8.1.1 and 8.1.2, no 400-point cut for `PTP`)
- `RTNG`, `RTNG/R`, `TPN`, `TPN/R`

They are `TiebreakMethod` values flagged `fide`, so standings, printing and the
MCP tools handle them like the US Chess methods. `FideTiebreakCode.parse` reads a
code's modifiers (`/Cn`, `/Mn`, `/P`, `/R`, `/F`, `/L±n`), so one calculation
serves every variant. The team tie-breaks of MTB26 are not implemented: Meow-Chess
has no FIDE team Swiss.

Where C.07 leaves a detail open, the values follow Gacrux, TEC's open reference
implementation:
- `STD` counts each round's points against a draw's (the text's "scheduled
  opponent" reading differs only for ½–0, 0–½ and double forfeits);
- `KS` counts every paired round, forfeits included, and in a round robin with an
  odd field measures 50% over the games each player can play;
- `APRO` and `APPO` leave out opponents with no rated game;
- `AOB` rounds to two decimals before round 9 and three from then on.

- Swiss unplayed rounds follow Article 16. A last-round requested bye counts as a
  draw for opponents. Each of a player's own unplayed rounds is a game against a
  dummy, scored at the player's own score but capped by the forfeit opponent or by
  ½ × rounds. Cut-1 removes the lowest voluntary unplayed round first.
- Round robins treat forfeits as games (Article 15.2) and never use Buchholz
  (Article 8).
- C.07 has no default order. Meow-Chess starts from `BH/C1, BH, SB, DE, WIN` for a
  Swiss and `DE, WIN, SB, KS` for a round robin; none is rating-based. Event
  details → Standings → Tie-breaks sets the order (`Event.fideTiebreaks`).
- That group is closed by default; its one-line summary gives the current order.
  Opened, the order is a short numbered list: move a method up or down, remove it,
  or add one from a single picker. "Use the suggested order" (or "Use the US Chess
  default") restores the default. The US Chess order sits behind its own switch,
  "Break ties", and stays hidden while that switch is off.
- FIDE sections always rank ties by tie-breaks (C.07 2.1).
- `DE` follows Article 6 in full. When every tied player has met every other (or
  in a round robin), the separate standings rank them (6.2). In a Swiss where some
  never met, players are placed from the top of the separate standings for as long
  as each stays alone on top whatever the missing games bring (6.3). Article 6 is
  then applied again to each set still tied. The value is the place among the tied
  players (1 = first), which is what prints.
- The order editor lists each FIDE method once; a row whose method has variants
  (Cut-1, Median-2, forfeits as played, a Koya limit…) chooses among them in
  place.

## The FIDE report: TRF26

`writeTrf` (`lib/domain/trf.dart`) writes the records the rating report needs
(TRF26, C.02 Appendix A):

- event details: 012, 022, 032, 042, 052, 062, 072, 092
- officials: 102 and 112 (from `Event.fide`)
- 122 and 222 (time control: in words, then encoded, e.g. `5400+30`)
- 132 round dates, 142 rounds, 172 ranking method, 182 pairing controller
- 162 scoring, only when the pairing-allocated bye is not a win
- 192 tournament type (`FIDE_DUTCH`, `FIDE_DUTCH_BAKU`, or `CUSTOM_ROUNDROBIN`)
- 202 tie-break order
- 250 accelerated rounds (Baku)
- one 001 record per player; its rank is the standings place among the players
  reported, so an entry left out of the report holds no place
- in a dual-rated section, `USA` National Rating Support records with the US
  Chess rating, state and ID

Two-game rounds become two TRF rounds. A year-only birth date is written
`YYYY/00/00` (TRF26 does not say; this matches files seen from other programs).

Export → **FIDE rating report** lists what blocks the files. Each problem has a
fix link.

**Blocking:**
- the chief arbiter and FIDE ID
- the city
- unfinished rounds
- a time control FIDE rates no game at
- missing or duplicate FIDE IDs

**Advice (does not block):**
- standard time controls below B.02's minimum for the field's ratings
- birth year, sex or federation missing for FIDE-unrated players
- rating-based tie-breaks with unrated players (C.07 Art. 10)
- full-point byes given (deprecated by FIDE)

Unfinished rounds, adjourned games included, block the files: a TRF is only ever a
full rating report, never a partial export (the COPP report's concern).

## Importing a TRF

Import FIDE report, on the start screen, reads a TRF26, TRF16 or TRF06 file (and
the `XX*`/`BB*` records of JaVaFo and BBP Pairings files) with `TrfFile.parse` and
`trfToEvent` (`lib/domain/trf_read.dart`), and saves it as a new event. Starting
ranks become the fixed pairing numbers; every round keeps its games, forfeits,
byes, unusual results and short games, ordered on boards by C.04.2 3.6. The PAB's
value is read from record 162 (or `BBU`/`XXS`) or inferred from the players'
points (VCL.11). Absences announced for rounds still to play (the ITDX column or
record 240) become requested byes, so a tournament begun elsewhere can be paired
on. National Rating Support records for `USA` make the section dual rated. Team
files and other scoring systems are refused; prohibited pairings limited to some
rounds, acceleration other than Baku and unknown tie-breaks are left out and
listed in the event's notes.

## Checker and generator

`lib/domain/fide_checker.dart` is the Pairings and Tie-Breaks Checker the TEC
Manual describes (3.9.4.2c): it imports a TRF, pairs each round again through the
app's own path (`proposeRound`, so `pairFideDutch` and BBP Pairings), ranks the
final standings by the file's tie-breaks and reports every difference. Round 1
pairs from the file's starting ranks. `lib/domain/fide_generator.dart` is the
Random Tournament Generator (3.9.4.2d): it simulates FIDE Swiss tournaments
through the same path, drawing results from the B.02 rating table, with byes,
forfeits, withdrawals, late entries, unusual and short games, Baku and the bye's
value as options. `lib/infrastructure/fide_cli.dart` puts both on a command line:

```
meow_chess -check FILE.trf [--round N] [--inputs DIR]
meow_chess -generate --output FILE [--count K] [--players N] [--rounds R] …
meow_chess -pair FILE.trf
meow_chess -values FILE.trf [--tiebreaks BH,SB,…]
```

The desktop app runs them before opening a window. For development and CI,
`dart build cli --target=tools/meow_fide.dart --output=build/fide-cli` builds the
same tools as `meow_fide`. `--inputs DIR` saves the exact file BBP Pairings read
for each round, the access the TEC Manual asks for when a program uses an outside
engine.

## FIDE's checklist

The 2017 verification checklist (VCL, `fide-c04-annex4-vcl17`), as the six
endorsement reports applied it, and C.02.03 7:

| Item | Where Meow-Chess meets it |
|---|---|
| FIDE mode default (VCL.01–03) | US Chess stays the default; `fideModeDefault` in `fide.dart` makes new sections FIDE only. A FIDE Swiss always pairs by the Dutch system. |
| Correct pairing services, nothing prohibited (VCL.04–07) | BBP Pairings; checked both ways against BBP's checker and generator. |
| Pairing numbers, frozen (VCL.08–09) | Fixed at round 1, stricter than C.04.2 2.3's round 4. |
| Acceleration (VCL.10, C.02.03 7.1.1b) | Baku, the only FIDE method. |
| TRF import and export (VCL.11–12, C.02.03 7.1.3b) | TRF26 out; TRF26, TRF16, TRF06 in; UTF-8, Latin-1 read. |
| Unusual results, forfeits, adjourned games (VCL.13–15) | Above, under Results and byes. |
| PAB value, half- and full-point byes (VCL.16–17) | Above. |
| FIDE rating list (VCL.18, C.02.03 7.1.1a) | Player tools → FIDE ratings. |
| Tie-breaks (VCL.19, C.02.03 7.1.1c) | All 59 individual MTB26 codes. |
| PTC and RTG (C.02.03 7.1.3c, TEC Manual 3.9.4) | `-check` and `-generate`. |
| English interface and help (C.02.03 7.1.3a) | Help → FIDE-rated sections. |


**Generate TRF files** writes one `.trf` per section into a new folder. The US
Chess report sets `S_FIDE` to `Y` for dual-rated sections. The MCP
`export_event` tool writes the TRF files too, and its section and player tools
accept the FIDE fields.

## Verification

- `scripts/check_fide_rtg.py` runs the TEC Manual's test in both directions:
  Meow-Chess's generator checked by Meow-Chess's checker and BBP Pairings' (`-c`),
  and BBP Pairings' generator (`-g`) checked by Meow-Chess's. With `--gacrux DIR`
  it also compares every MTB26 tie-break value with Gacrux. On 10 October 2026,
  5,000 tournaments each way (8–120 players, 3–13 rounds, every option above):
  all 5,000 of BBP's matched Meow-Chess's checker, and 4,996 of Meow-Chess's
  matched Meow-Chess's checker, BBP's checker and Gacrux on every tie-break; the
  other 4 could not be generated (a small field over many rounds runs out of
  legal pairings). CI runs 300 each way.
- `test/domain/fide_tools_test.dart` round-trips generated tournaments through
  TRF and the checker, and shows the checker catching a changed pairing and a
  wrong place. `test/domain/fide_checklist_test.dart` covers Baku (the rules'
  161-player example), the bye's value, unusual and short results, adjourned games
  and draw-only assumptions.
- `test/domain/fide_test.dart` covers:
  - time-control categories and C.04.2 ranking
  - a full 11-player Swiss without repeats, with one pairing-allocated bye each
  - round 1 pairing top half against bottom half
  - byes and withdrawals left out of pairing
  - fixed TRF columns
- `test/domain/fide_random_test.dart` pairs 40 random events (12–41 players, 5–9
  rounds, with forfeits, draws, requested byes and FIDE-unrated players) to the
  end.
- `scripts/check_fide_trf.py` builds BBP Pairings' own checker from the vendored
  source and replays every one of those events from the TRF Meow-Chess writes. The
  checker re-pairs each round and reports any difference. All 40 match. CI runs
  it on Linux.
- `test/domain/fide_tiebreaks_test.dart` is a hand-worked C.07 example covering
  each Article 16 case.
- `test/infrastructure/fide_rating_list_test.dart` uses real lines from the
  October 2026 list, including the overflow line.
- `test/ui/fide_ui_test.dart` and `test/ui/fide_list_panel_test.dart` drive the
  panels.
- `integration_test/fide_screens_test.dart` pairs a round through the bundled
  engine in the desktop app and captures the panels (`artifacts/fide-*.png`).
