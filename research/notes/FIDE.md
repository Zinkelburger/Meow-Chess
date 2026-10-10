# FIDE-rated events: ratings data, Swiss rules, tie-breaks, rating regs, endorsement, engines, TRF26

Research date: 2026-10-10. Everything below was read from primary sources saved under
`research/local/` (ids in `research/sources.json`; hashes in `research/local/manifest.json`).
"UNCERTAIN" marks an inference or a gap. This note complements the "FIDE later" section of
[ENGINEERING.md](ENGINEERING.md); it does not claim Meow-Chess is FIDE-compatible.

Headline facts:

- The only official bulk player data is the monthly **download list** (ZIP, TXT/XML). There is
  **no documented FIDE JSON API**. The `ratings.fide.com` AJAX endpoints work, but they are
  undocumented internals.
- New Swiss rules: C.04.1/C.04.2/C.04.3 have been **in force since 1 Feb 2026**. Tie-breaks follow C.07 (in force since **1 Mar 2026**).
- **Endorsement moved.** C.04.A was merged into **C.02.01/C.02.03/C.02.04** (in force since 1 Mar 2026).
  The 2026 framework is a "Technical Acceptance Process" (TAPC) with fees. As of the Sept 2026 Congress, its THP checklist
  (VCL) is **not final**, and new assessments will start under the next Commission. Every listed THP endorsement shows
  expiry **2026/02/01**, and a transition period of at least one year applies.
- **US Chess does not accept TRF files** for FIDE rating. It wants the native file of an endorsed pairing program, for example a SwissSys `.S#C` or `.sjson` file
  (`uscf-fide-events`). For a US Chess organiser, a TRF exporter alone does not make Meow-Chess usable for FIDE events.
- **bbpPairings v6.0.0** (2026-02-01, Apache-2.0) implements the 2025/2026 Dutch rules and reads TRF-2026.
  **Gacrux** (MIT, © FIDE, Python) is TEC's open reference pairing checker, tie-break calculator and tournament generator.

---

## 1. FIDE rating lists and "API"

Sources: `fide-download-lists` (https://ratings.fide.com/download_lists.phtml), `fide-players-list-excerpt`,
`fide-ratings-endpoints-probe`, `fide-b02-rating-2024` §7.1.2.

### 1.1 Download URLs (current month; verified HTTP 200 on 2026-10-10, files dated 09 Oct 2026)

| List | TXT | XML | Zipped size | Member file |
|---|---|---|---|---|
| Combined STD+RPD+BLZ (with FOA column) | `https://ratings.fide.com/download/players_list.zip` | `https://ratings.fide.com/download/players_list_xml.zip` | 44.7 MB / 50.6 MB | `players_list_foa.txt` (317 MB, 1,932,868 lines) / `players_list_xml_foa.xml` (856 MB) |
| Combined "LEGACY" (no FOA column) | `https://ratings.fide.com/download/players_list_legacy.zip` | `https://ratings.fide.com/download/players_list_xml_legacy.zip` | 44.5 / 47.6 MB | `players_list.txt` |
| Standard | `https://ratings.fide.com/download/standard_rating_list.zip` | `https://ratings.fide.com/download/standard_rating_list_xml.zip` | 13.3 MB | `standard_rating_list.txt` (78.6 MB) |
| Rapid | `https://ratings.fide.com/download/rapid_rating_list.zip` | `https://ratings.fide.com/download/rapid_rating_list_xml.zip` | 11.2 MB | `rapid_rating_list.txt` |
| Blitz | `https://ratings.fide.com/download/blitz_rating_list.zip` | `https://ratings.fide.com/download/blitz_rating_list_xml.zip` | 7.6 MB | `blitz_rating_list.txt` |

- **Archives.** The page's period selector calls `GET /a_download.php?period=YYYY-MM-01`, which returns HTML links of the form
  `https://ratings.fide.com/download/{standard|rapid|blitz}_{mon}{yy}frl[_xml].zip`, for example `standard_sep26frl.zip`.
  The archive offers per-type lists only, not the combined list. This was verified for Sep 2026 only.
- `HEAD` returns `Content-Length` and `Last-Modified`. Use these to skip re-downloading an unchanged monthly list.

### 1.2 TXT layout (verified by parsing the whole Oct 2026 combined file)

The files are ASCII (no non-ASCII bytes in 1.93M lines) with CRLF line endings. There is no BOM. Each file has one header line, and every line is fixed width.
Combined `players_list_foa.txt` lines are **162 chars**. Three lines out of 1.93M are 163 chars because the OTit text overflows into FOA,
for example `SI,FI,LSI,SLI,NAAFM`. The parser must tolerate that, or use the XML.

Header (exact): `ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag`

| Field | 0-based [start,end) | 1-based cols | Notes |
|---|---|---|---|
| ID Number | 0–15 | 1–15 | FIDE ID, left-aligned |
| Name | 15–76 | 16–76 | "Last, First" (some single names) |
| Fed | 76–80 | 77–80 | 3-letter FIDE code |
| Sex | 80–84 | 81–84 | `M` / `F` |
| Tit | 84–89 | 85–89 | `GM IM FM CM WGM WIM WFM WCM` (women may carry the W-title here too) |
| WTit | 89–94 | 90–94 | `WGM WIM WFM WCM` |
| OTit | 94–109 | 95–109 | comma list: `IA FA NA IO FT FST DI NI SI FI LSI SLI AO …` |
| FOA | 109–113 | 110–113 | FIDE Online Arena title `AGM AIM AFM ACM` |
| SRtng / SGm / SK | 113–119 / 119–123 / 123–126 | 114–119 / 120–123 / 124–126 | standard rating, games in period, K |
| RRtng / RGm / Rk | 126–132 / 132–136 / 136–139 | 127–132 / 133–136 / 137–139 | rapid |
| BRtng / BGm / BK | 139–145 / 145–149 / 149–152 | 140–145 / 146–149 / 150–152 | blitz |
| B-day | 152–158 | 153–158 | birth **year** only (`0` for 33,734 players) |
| Flag | 158–162 | 159–162 | `i` inactive, `w` woman, `wi` woman inactive (lower-case in data) |

- **Unrated is `0`.** In the combined list, 1,140,225 of 1,932,867 players have 0 in all three ratings. The legend says "LEGACY = not rated included", but the FOA combined list also includes unrated players.
- **Single-type lists**, for example `standard_rating_list.txt`, have 136-char lines:
  `ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA OCT26 Gms K  B-day Flag`.
  Offsets are the same through FOA (109–113). After that: rating [113,119) (header = month code `OCT26`), Gms [119,123), K [123,126), B-day [126,132), Flag [132,136).
- **Legacy combined** (`players_list.txt`) has 158-char lines and no FOA column. After OTit [94,109): SRtng 109, SGm 115, SK 119, RRtng 122, RGm 128, Rk 132,
  BRtng 135, BGm 141, BK 145, B-day 148, Flag 154 (0-based starts).
- **Recommendation: compute offsets from the header line**, and look tokens up by name rather than hard-coding them. The month token changes and FIDE has changed layouts before (legacy vs FOA).

Sample lines (`fide-players-list-excerpt.txt` holds a ruler, the header and 6 lines):
```
1503014        Carlsen, Magnus                                              NOR M   GM                           2823  0   10 2801  12  10 2860  0   10 1990      
8603677        Ding, Liren                                                  CHN M   GM                           2723  11  10 2693  0   10 2736  0   10 1992      
2016192        Nakamura, Hikaru                                             USA M   GM                           2792  0   10 2738  0   10 2800  0   10 1987      
```

### 1.3 XML layout

The root is `<playerslist>`, with **no XML declaration**. It contains repeated `<player>` elements with these children, in this order:
`fideid, name, country, sex, title, w_title, o_title, foa_title, rating, games, k, rapid_rating, rapid_games, rapid_k,
blitz_rating, blitz_games, blitz_k, birthday, flag`. Here `birthday` is the year, and empty elements are written as `<title></title>`. The XML is 856 MB
uncompressed, so it needs a streaming parser.

### 1.4 Official vs unofficial access

- **Official:** the downloadable lists above. B.02 §7.1.2 lists the published fields: title, federation, rating, ID, games in period, birth year,
  gender and K. The page shows no licence or API terms, and `robots.txt` returns 404. Third parties (Lichess, Apify,
  fideratings.com) all build on this download.
- **No official JSON API** was found on ratings.fide.com, handbook.fide.com or tec.fide.com.
- **Unofficial (scraped/AJAX) endpoints**. These were probed once each without credentials. All return HTTP 200, and JSON bodies start with a UTF-8 BOM (`﻿`).
  - `GET /profile/<id>` returns 700 KB of HTML. Parseable fields by CSS class:
    - `profile-info-id`: the ID.
    - `profile-info-country`: the federation **name** (for example "Norway"), plus a flag `img src=/images/flags/no.svg`.
    - `profile-info-byear`: birth year.
    - `profile-info-sex`: "Male" or "Female".
    - `profile-info-title`: the **long** title (for example "Grandmaster").
    - Current std/rapid/blitz ratings appear in the top block.
    - A rating-history table shows Period / STD / GMS / RPD / BLZ.
  - `GET /incl_search_l.php?search=<name or id>&simple=1` returns an HTML table: FIDE ID, Name, Title, Tr.T., Fed (3-letter), Std., Rpd., Blz., B-Year, with links `/profile/<id>`.
  - `POST /a_chart_data.phtml?event=<id>&period=<n>` returns JSON (`application/json`) of monthly history:
    `{"date_2":"2026-Jan","id_number":"1503014","rating":"2840","period_games":"0","rapid_rtng":"2832","rapid_games":"13","blitz_rtng":"2869","blitz_games":"27","name":…,"country":"NOR"}`.
  - `GET /a_data_opponents.php?a=1&pl=<id>` returns a JSON list of `{id_number,name,country}` opponents, sent with content-type text/html.
  - `GET /a_profile_data.php?records=1|2|3&event=<id>` returns DataTables JSON `{sEcho,iTotalRecords,iTotalDisplayRecords,aaData}`.
  - `GET /a_calculations.phtml?event=<id>` returns an HTML fragment of per-period rating-change links.
- **Third party (not FIDE):** `https://lichess.org/api/fide/player/<id>` returns
  `{"id","name","federation","year","title","standard","rapid","blitz","gender"[,"inactive"]}`. `…/api/fide/player?q=` does a search.
- **Recommendation:** import the monthly ZIP, either the combined TXT or the per-type list. Treat AJAX/profile scraping as a fragile, optional single-player refresh, and never do bulk scraping.
  B.02 §7.1.2 lists the published fields. C.02.03 §7.1.1a requires a THP to "import FIDE rating lists via online updates, proprietary
  methods, or public files".

## 2. Swiss rules: C.04.1, C.04.2 and C.04.3 Dutch (approved 28/10/2025, applied from 1 Feb 2026)

Sources:
- `fide-c0401-basic-swiss-2026`: https://handbook.fide.com/chapter/C0401202507
- `fide-c0402-general-handling-2026`: https://handbook.fide.com/chapter/GeneralHandlingRulesForSwissTournaments202602
- `fide-c0403-dutch-2026`: https://handbook.fide.com/chapter/C0403202602
- `fide-c0407-accelerated-2026` (Baku)
- `fide-tec-annotated-dutch-2026` (TEC annotated text)

Older versions are at `…/C0401Till2026`, `…/C0403Till2026` and `…/GeneralHandlingRulesForSwissTournamentsTill2026` (not saved).

**C.04.1 Basic rules:**
1. The number of rounds is declared beforehand.
2. Two participants do not meet more than once.
3. With an odd number of participants, one gets a **pairing-allocated bye (PAB)**: no opponent, no colour, and a win's points unless the rules say otherwise. The value is the same for all PABs.
4. A participant who already had a PAB, **or** already scored a win's points in one round without playing (for example a full-point bye or a forfeit win), cannot get the PAB.
5. Participants are generally paired within the same score.
6. Colour difference stays within ±2.
7. No colour three times in a row. Systems may make exceptions to 6 and 7.
8. A participant generally gets the colour they had less often, otherwise alternation.

**C.04.2 General handling (implementation-relevant):**
- 1.1–1.3: The system must be a published FIDE Swiss system. Accelerations must be announced and FIDE-approved. Anything else needs prior QC authorisation.
  The CA declares the system and acceleration in the report. 1.4: systems without an approved THP and a **free pairing checker** are deprecated.
  1.5: Altering correct pairings to favour someone is an ethics matter.
- **2.2 Initial ranking:** (1) strength (rating), then (2) FIDE title in the order **GM, IM, WGM, FM, WIM, CM, WFM, WCM, no title** (individual events), then (3) **alphabetically**,
  unless replaced by another announced criterion. 2.1: Use one rating list for all players if available. If no reliable rating is known, **the CA estimates one**.
  FIDE has no "unrated last" rule; that is a US Chess convention.
- 2.3: TPNs come from this ranking. Data corrections may re-assign TPNs, but **not after round 4 has been paired**. 2.4–2.5: Late entries get 0 for missed rounds (unless the rules say otherwise) and are given a TPN.
  TPNs stay provisional until the list closes.
- 3.1: Adjourned games count as draws for pairing. 3.2: Withdrawn players are not paired. 3.3: Known absentees are not paired and score 0 (unless the rules say otherwise).
  **3.4: Only played games count for colour history.** Unplayed rounds are shifted to the front: `BWBuW` is treated as `uBWBW`. 3.5: Paired players who did not play may be paired again.
- **3.6 Board order:** (1) higher score of the higher-ranked player of the pair, (2) higher sum of both scores, (3) smaller TPN of the higher-ranked player.
- 4.3: Corrections notified in time are used for the next pairing. 4.4: Published pairings change only for the listed reasons: accidental rematch, competition rules,
  two unpaired players agreeing, a late entry with minimal change, or top-board emergencies in the final round.

**C.04.3 Dutch, key definitions and rules:**
- **Order (1.2):** score, then TPN ascending. Brackets are scoregroups plus moved-down players (MDPs).
- **Floats:** In a game between different scores, the higher-ranked player gets a downfloat and the lower-ranked an upfloat. The PAB receiver gets a downfloat, and so does anyone who scores more than a loss without playing.
- **Colour preference (1.7):**
  - *Absolute:* the colour difference is above +1 or below −1, or the same colour was played in the last two played rounds.
  - *Strong:* the colour difference is ±1.
  - *Mild:* the difference is 0, so alternate.
  - A player with no games has no preference.
- **Topscorers (1.8):** players above 50% of the maximum possible score when pairing the **final** round.
- **Absolute criteria:**
  - [C1] No rematches.
  - [C2] PAB eligibility per C.04.1 art 4.
  - [C3] Non-topscorers with the **same absolute colour preference** must not meet.
- **Completion:** [C4] the remaining players must be pairable. **PAB:** [C5] minimise the PAB assignee's score.
- **Quality criteria, in priority order:**
  - [C6] minimise downfloaters (maximise pairs)
  - [C7] minimise downfloater scores
  - [C8] the next bracket remains C1–C7 compliant
  - [C9] minimise the number of unplayed games of the PAB assignee
  - [C10] topscorers or their opponents with |colour diff| > 2
  - [C11] topscorers or their opponents with the same colour 3× in a row
  - [C12] colour preference not met
  - [C13] strong colour preference not met
  - [C14] resident downfloaters who downfloated in the previous round
  - [C15] MDP opponents who upfloated in the previous round
  - [C16] resident downfloaters who downfloated two rounds before
  - [C17] MDP opponents who upfloated two rounds before
  - [C18]–[C21] score differences of those same float repeats
- **Procedure (art. 3–4):**
  - Brackets are split into S1 and S2, with M0/M1/MaxPairs and a Limbo for MDPs that cannot be paired in the bracket.
  - Transpositions of S2 are ordered lexicographically by their first N1 BSNs.
  - Resident exchanges are ordered by:
    1. fewest exchanged players;
    2. smallest sum difference;
    3. largest differing BSN moved S1→S2;
    4. smallest differing BSN moved S2→S1.
  - Accept the first "perfect" candidate. Otherwise take the best candidate, comparing C5 then C6–C21, with earlier generation winning ties.
- **Colour allocation (5.2):**
  1. grant both preferences;
  2. grant the stronger preference (if both are absolute, as topscorers, grant the wider colour difference);
  3. alternate to the most recent round in which one player had White and the other Black;
  4. grant the higher-ranked player's preference;
  5. if the higher-ranked player has an odd TPN, they get the **initial-colour** (drawn by lot before round 1), otherwise the opposite colour.
- **Baku acceleration (C.04.7 §1):**
  - Applies only when a win equals two draws and a loss scores 0.
  - GA is the first half, rounded up to an even number (2·⌈N/4⌉).
  - Accelerated rounds are the first ⌈R/2⌉.
  - GA gets virtual points equal to a win in the first half (rounded up) of the accelerated rounds, then half a win in the rest.
  - Pairing score is standings points plus virtual points.

Implementation guidance: implementing the Dutch rules correctly is hard. Validate against bbpPairings or Gacrux and do not hand-roll trust. TRF 250 is the acceleration record.

## 3. Tie-breaks: C.07 (current version approved 02/02/2026, applied 1 Mar 2026)

Sources:
- `fide-c07-tiebreak-2026`: https://handbook.fide.com/chapter/TieBreakRegulations032026
- `fide-c07-tiebreak-2024` (1 Aug 2024 to 28 Feb 2026)
- `fide-c07-tiebreak-2023`
- `fide-c07-tiebreak-pre2023`
- `fide-mtb26`: https://handbook.fide.com/files/handbook/MTB26.pdf (codes for TRF 202/212)

**Acronyms** (Art. 5; type: A = subset of games, B = own record, C = opponents' final results, D = opponents' prior data):

| Code | Name | Art. | Type |
|---|---|---|---|
| DE | Direct Encounter | 6 | A |
| WIN | Number of Wins (incl. unplayed rounds scoring a win's points) | 7.1 | B |
| WON | Number of Games Won (OTB only) | 7.2 | B |
| BPG | Games Played with Black (OTB) | 7.3 | B |
| BWG | Games Won with Black (OTB) | 7.4 | B |
| PS | (Sum of) Progressive Scores | 7.5 | B |
| REP | Rounds one Elected to Play in = rounds − (HPB + ZPB + forfeit losses) | 7.6 | B |
| STD | Standard Points (new 2026) | 7.7 | B |
| TPN | Tournament Pairing Number (new 2026; `/R` reverses) | 7.8 | B |
| BH | Buchholz (not for round robins) | 8.1 | C |
| AOB | Average of Opponents' Buchholz (or FB), OTB opponents | 8.2 | CC |
| FB | Fore Buchholz (final round treated as all draws) | 8.3 | D |
| SB | Sonneborn-Berger | 9.1 | BC |
| KS | Koya (RR; points vs opponents with ≥50%) | 9.2 | BC |
| ARO | Average Rating of Opponents (OTB, round half up) | 10.1 | D |
| TPR | Tournament Performance Rating (ARO + dp(fractional OTB score)) | 10.2 | DB |
| PTP | Perfect Tournament Performance (lowest R with expected ≥ score; zero score → lowest opponent − 800; no ±400 cut) | 10.3 | DB |
| APRO | Average TPR of Opponents | 10.4 | DC |
| APPO | Average PTP of Opponents | 10.5 | DC |
| RTNG | Rating (new 2026; `/R` reverses) | 10.6 | B |
| Teams | BC, TBR, BBE (12.x); MPvGP, ESB as EMMSB/EMGSB/EGMSB/EGGSB, EDE (+EDEBT/EDEBB/EDET/EDEB), SSSC (13.x) | | |

- **Renamed code:** the 2024 regulations called art. 7.6 **GE** ("Games one Elected to Play"). From 2026 it is **REP**, and MTB26 uses REP. An importer should accept `GE` as an alias. That alias is my inference.
- **Modifiers** (art. 14) and the **MTB26 descriptor syntax** are `Name[:MP|:GP][/Variant…]`, case-insensitive:
  - `/C1` and `/C2` cut, and `/M1` and `/M2` median. Examples: `BH/C1` is "Buchholz Cut-1", `SB/C1`, `ARO/C1`, and `PS/C1` (drops the round-1 score).
  - `/Lx` sets the Koya limit ±x half-points.
  - `/Kx` sets the SSSC normaliser.
  - `/P` counts forfeits as played against the scheduled opponent.
  - `/F` uses Fore Buchholz (AOB, SSSC).
  - `/R` reverses the order (RTNG, TPN).
- Self-defined tie-breaks go in 202/212 as `OTHER_<code>`.
- **MTB26 individual codes** that an endorsed THP must implement:
  `DE DE/P BPG BWG REP STD SB SB/C1 SB/C2 SB/P SB/C1/P SB/C2/P ARO ARO/C1 ARO/C2 ARO/M1 ARO/M2 TPR PTP APRO APPO RTNG RTNG/R WIN WON PS PS/C1 PS/C2 TPN TPN/R BH BH/C1 BH/C2 BH/M1 BH/M2 BH/P BH/C1/P BH/C2/P BH/M1/P BH/M2/P FB FB/C1 FB/C2 FB/M1 FB/M2 FB/P FB/C1/P FB/C2/P FB/M1/P FB/M2/P AOB AOB/F KS KS/Lx`. The team codes are in the saved PDF.
  - UNCERTAIN: the `/P` text cites "C.07.16.5", but in the 2026 text 16.5 is the Cut-1 exception.
- **Rules affecting implementation:**
  - DE excludes forfeits unless the regulations say otherwise. Repeated meetings are averaged, and the Swiss "will be alone on top whatever the missing results" rule applies (6.3).
  - Rating-based tie-breaks (art. 10) are **dropped when unrated players are present**, unless handling was published beforehand.
  - A player with multiple ratings uses the first one.
  - Buchholz tie-breaks must not be used in round robins.
  - With pre-determined pairings (round robin), forfeits are regular games, except: all forfeits stay unplayed for rating-based tie-breaks, and forfeit losses stay unplayed for type-B tie-breaks (15.2).
- **Unplayed rounds in Swiss (Art. 16, replaced the old "virtual opponent"):**
  - *Requested bye* is an HPB or a ZPB; every round after withdrawal is a ZPB. *VUR* (voluntary unplayed round) is a requested bye or a forfeit loss.
  - Categories:
    - 16.2.1: PAB or FPB
    - 16.2.2: forfeit win
    - 16.2.3: requested bye followed by at least one non-VUR round
    - 16.2.4: forfeit loss
    - 16.2.5: requested bye followed only by VURs, or in the last round
  - **As an opponent (16.3):** categories 16.2.1–16.2.4 count with the result matching the points awarded. **Category 16.2.5 counts as a draw.**
  - **Own tie-break (16.4):** each unplayed round counts as a game against a **dummy** whose score is the participant's own score, capped at:
    - the scheduled opponent's adjusted score, for forfeits (16.2.2, 16.2.4);
    - draw points × number of rounds, otherwise.
  - **Cut-1 exception (16.5):** cut the lowest contribution that comes from a VUR, as long as it is not lower than the least significant value.
    For SB, cut the higher of the two candidates. Repeat for each further cut.
  - 16.6: competition rules may define alternatives.
  - **Historical** pre-2023 rule (do not use for current events): a virtual opponent with `Svon = SPR + (1 − SfPR) + 0.5·(n − R)`.
- **Recommended defaults: NONE in the current C.07.**
  - 2.1: if the regulations specify nothing, rank by tie-breaks and the CA completes and publishes the list (4.1.1). Any remaining tie goes to drawing of lots (4.2).
  - The 2023, 2024 and 2026 texts and the pre-2023 text contain no default list. The app's defaults are therefore *our* choice and must be shown and published before round 1.
  - A suggested starting point, labelled as such (UNCERTAIN, not FIDE-mandated):
    - **Swiss individual:** `BH/C1, BH, SB, DE, WIN` (none rating-based, so safe with unrateds).
    - **Round robin:** `DE, WIN, SB, KS`. Buchholz is forbidden in round robins.

## 4. Rating regulations

Sources:
- `fide-b02-rating-2024`: https://handbook.fide.com/chapter/B022024 (approved 15/12/2023, applied 1 Mar 2024, with a 1 Oct 2025 amendment)
- `fide-b02-rapid-blitz-2024`: https://handbook.fide.com/chapter/B02RBRegulations2024
- `uscf-fide-events` (US Chess process)

| Topic | Standard (B.02) | Rapid/Blitz |
|---|---|---|
| Registration | Pre-registered by the host federation: **30 days** before if any player > 2700 or a woman > 2500; otherwise **3 days** before (0.2) | **3 days** before (0.2) |
| Min time (assume 60 moves) | Either player ≥ 2400: ≥ **120 min** each; either player ≥ 1800: ≥ **90 min**; both < 1800: ≥ **60 min**. A first control with a move count must be ≥ 30 moves | Rapid: fixed time, or time + 60×increment, **>10 and <60 min**. Blitz: **>3 and ≤10 min**. Unequal times are **not rated** (so no Armageddon) |
| Daily limit | ≤ **12 h play/day** (60-move basis) | Rapid ≤ **15 rounds/day**; blitz ≤ **30 rounds/day** |
| Unplayed games | Forfeits and other unplayed games are **not rated**. Any game where **both players made ≥ 1 move is rated** (unless force majeure or fair-play rules apply) | same (4.1) |
| Matches | Not rated if one player is unrated; games after the match is decided are not rated (waivable) | same |
| New player | Published after ≥ **5 games vs rated opponents**, pooled over ≤ 26 months; rating ≥ 1400. A zero score in the first event is disregarded. Ru = Ra + dp, where Ra includes two hypothetical 1800 draws; max initial 2200 | Same. A standard rating, if the player has one, is used as the initial R/B rating |
| Rating difference cap | 400 cap for players < 2650; no cap at ≥ 2650 (from 1 Oct 2025) | 400 cap. Games with a gap ≥ 600 are **not rated** if either player is > 2600 (from 1 Dec 2024) |
| K | 40 new (< 30 games) or juniors to end of their 18th year while < 2300; 20 below 2400; 10 once reached 2400. K·n ≤ 700 | same |
| Reporting | The CA gives the **TRF** to the federation Rating Officer, who uploads it to the FIDE Rating Server in time for the list of the registration month (or the next list if ≤ 5 days remain in the month). **Not rated** if it misses the 3rd list after the event ends. Lists close 3 days before the list date. Events > 30 days report monthly | same (8.1) |

**Per-player data in the rating report (TRF 001, column R):**
- **Mandatory:** FIDE number (58–68), start rank, final rank, and every round's opponent, colour and result.
- **"Warning if wrong":** sex, title, name, FIDE rating, federation and birth date.
- **Mandatory tournament records (R):** 012 name, 022 city, 032 federation, 042 start date, 052 end date, 102 chief arbiter, 132 round dates, 222 encoded time control.
- **Mandatory for title events:** 182, 192 and 202/212.
- B.02 itself does not list player fields.
- **US Chess in practice:**
  - All players must have a FIDE ID before submission. US Chess issues USA IDs; foreign players use their own federation; a FIDE-flagged ID costs €60.
  - The pairing file must contain: name, US Chess ID, FIDE ID, federation, gender (M/F), birth year.
  - US Chess requires **14 days'** notice for non-norm events and **45 days** for norm events (from 1 Jan 2026), and each section is registered separately.
  - Reports are due 3 days before month end (for events ending ≥ 6 days before month end), else 7 days after the event.
  - The submission is the **endorsed program's native file, not TRF or DBF**.
  - Arbiters must be FIDE-licensed. The US Chess TD roles map to CA, deputy and arbiters.
  - Norms need PGN.

## 5. Endorsement of pairing programs (THPs)

Sources:
- `fide-c0201-equipment-general-2026`: https://handbook.fide.com/chapter/GeneralRulesAndRegulations032026
- `fide-c0203-electronic-equipment-software-2026`: https://handbook.fide.com/chapter/ChessEquipmentWithElectronicComponenets032026, §7 THPs
- `fide-c0204-certified-endorsed-2026` (register)
- `fide-tec-2026-congress-meeting`: https://tec.fide.com/wp-content/uploads/2026/09/TEC-2026-Congress-Meeting.pdf
- Superseded:
  - `fide-c04a-endorsement-appendix` (C.04.A, Wayback copy; spp.fide.com showed a "maintenance" page on 2026-10-10)
  - `fide-c04-annex1-fe1` (FE-1 form)
  - `fide-c04-annex4-vcl17` (VCL)
  - `fide-c04-annex3-fep22` (old list)
  - `fide-tec-endorsement`: https://tec.fide.com/endorsement/
  - `fide-swisssys-endorsement-report`: https://tec.fide.com/wp-content/uploads/2024/05/SwissSysReport.pdf

**Current rule (C.02.03 §7, in force since 1 Mar 2026).** A THP is a program on a commercial OS (web/online allowed by exception) that manages Swiss events. It must:
- (a) import FIDE rating lists;
- (b) pair with at least one FIDE Swiss system **and support all FIDE acceleration methods**;
- (c) produce final standings applying **all MTB26 tie-breaks**.

Compliance is declared per pairing system, in a **FIDE mode** that provides:
- an English UI and a full manual or online help;
- TRF import and export in the **latest** format (TRF26), backward compatible with TRF16 and TRF06;
- a **free PTC** (pairings *and tie-break* checker, embedded, CLI) and a **free RTG** (random tournament generator, CLI, with parameters), unless TEC exempts it;
- a controlled testing environment (for example a VM for web apps).

Extra features such as manual pairing or non-FIDE tie-breaks are allowed only if they do not compromise the declared system.

Acceptance cycle (§7.3):
- New-rules dates (NRD) are at least 4 years apart, and new rules are published at least 12 months before the NRD.
- An Acceptance Cycle of at least 3 years starts 6 months before the NRD.
- A TAPC is valid until the next cycle.
- A transition period of at least 1 year lets expired THPs keep running if pairing controllers inform the parties.

**Process (TEC 2026 report and C.02.01 §5):**
1. **Register** as a vendor through the TEC online form (`cognitoforms.com/FIDE/TECMenu`, as printed in the report).
2. The product enters an **Acceptance Cycle**.
3. The vendor self-assesses against the **VCL**.
4. The vendor files a **SDPC** (Self-Declaration of Product Compliance).
5. TEC runs **TAPC** (verification and testing).
6. FIDE endorsement follows as a separate *commercial* status.

Fees and timing:
- **Fees exist:** a one-time initiation fee plus a fee per product classification, with a higher tier for THPs. They are payable whether or not a TAPC is granted (C.02.01 §5.8).
  The amounts are in the TEC Manual (`fide-tec-manual-2026`, v1.24 of 7 March 2026), Annexure A: a **USD 300** one-time initiation fee plus **USD 900** per
  classification for equipment with electronic components (a THP), so **USD 1,200** for a THP; **USD 1,500** with optional preliminary testing (+300); USD 2,100
  for a THP plus Hybrid Tournament Management. Equipment without electronic components: 120 preliminary, 300 testing.
- Software must use major.minor semantic versioning (§5.9).
- Status at the Sept 2026 Congress: the THP VCL is not final, and new TAPC assessments will start under the incoming Commission. 44 vendor records are tracked, 30 of them THP-only.
  UTU Swiss and STOP are marked not operational.

**Register (C.02.04).** THPs: Vega 7.6.0 (JaVaFo), SwissSys 9.6 (**bbpPairings**), SwissMaster 5.7, Swiss-Manager 13, UTU Swiss, ChessManager,
STOP, TournamentService, Tornelo, Chess Online 7.7 (all JaVaFo), and Swiss-Chess 9.05 (internal engine). All are Dutch, and **all show expiry 2026/02/01**.

**TEC Manual 3.9 (THP TAPC process), `fide-tec-manual-2026`:**
- The first TAPC for a pairing system needs a four-person subcommittee reporting within 9 months; later THPs for the same system go through the
  Verification Process below.
- **External engine exemption (3.9.4.1):** a THP using a pairing and tie-break engine already integrated into another FIDE-accepted THP (as BBP
  Pairings is in SwissSys) can be exempted from providing its own PTC and RTG, provided TEC can see the input files given to the engine and preferably
  what the engine returns.
- **PTC (3.9.4.2c):** an embedded tool with a CLI (`yourprogram.exe -check FIDE_Report_File.fid`). It must read TRF26 and should read TRF16 and TRF06;
  for each round it rebuilds the tournament, pairs with the embedded engine, checks the standings by the listed tie-breaks, and reports what is not
  consistent.
- **RTG (3.9.4.2d):** freely available, preferably CLI, many parametrised tournaments (players, teams, rounds, unplayed games, acceleration methods,
  tie-breaks), a full TRF26 for each; results should follow the FIDE rating table's probabilities.
- **Large-scale test (3.9.4.4):** an external RTG generates **50,000** tournaments (C.04.A said 5,000), processed by the candidate's PTC. Up to 10
  discrepancies are each analysed; more than 10 means revocation. Discrepancies are classed as input-file errors (referred to the RTG's provider),
  candidate errors (must be fixed), or rule-interpretation divergences (TEC issues a clarification). With its own RTG, the candidate's 50,000 tournaments go
  through one or more existing PTCs.
- Major versions follow semantic versioning; a major version restarts the TAPC, and hiding one under a minor number breaches the agreement (3.5).

**Old procedure (C.04.A, merged into C.02.03 and useful as a test recipe):**
- File the FE-1 form. Self-test with ≤ **1 discrepancy per 500** test tournaments to apply.
- TEC/SPPC generates **5000 RTG tournaments** with an existing endorsed RTG and runs them through the candidate's checker, collecting at most 10 discrepancies. If the candidate has its own RTG, its 5000 tournaments go through the existing checkers.
- Apply ≥ 4 months before the Congress. The first endorsement of a new system needs a four-person subcommittee.
- Major bugs must be fixed within 2 weeks and minor bugs within 2 months, or the endorsement is suspended.
- **The checker's CLI contract:** `yourprogram.exe -check FIDE_Report_File.fid` reads TRF, rebuilds every round, re-pairs it and reports matches or mismatches.

**VCL items (2017 version, also used in the SwissSys report):**
1. FIDE mode is the default.
2. FIDE mode is reachable by a standard install.
3. The default pairing system is the endorsed one.
4. Pairing services behave correctly.
5. Prohibited features are disabled.
6. The word "FIDE" appears only on endorsed services.
7. Pairings strictly follow the rules.
8. Pairing uses pairing numbers, not ratings.
9. **TPNs are frozen after round 4 is paired.**
10. The handbook acceleration (Baku) is implemented.
11. TRF import works.
12. TRF export is checker-readable even with non-standard scoring; UTF-8 recommended.
13. Unusual results (½-0, 0-½, unforfeited 0-0) are allowed; inconsistent ones (1-½) are refused.
14. Forfeits are only 1F-0F, 0F-1F and 0F-0F.
15. Adjourned games are handled.
16. The PAB value is configurable.
17. HPB is supported. Assigning an FPB must **warn that it is deprecated**.
18. The FIDE rating list is easy to use.

**VCL.19 (added by 2023, from the COPP report):** every tie-break included in the program is tested and must follow the Handbook. The 2023 report
deferred it to 2025 because tie-break checkers were not ready.

**Practices the six endorsement reports record (Vega, Swiss Master, Swiss-Manager, Swiss-Chess, SwissSys, COPP; `fide-*-endorsement-report`):**
- Baku is offered (several only from 9 rounds, with standard scoring); other accelerations may exist beside it in FIDE mode.
- The PAB may be a win, a draw or a loss; Swiss-Manager fixes it once a PAB has been given.
- TRF16 import rebuilds the cross-table from all letter codes and infers the PAB value (and, where it can, the scoring system).
- "Quick" (unrated) results, TRF W/D/L, are entered from a list of allowed scores (Swiss-Chess maps them to normal results, noted as a limitation).
- Adjourned games pair as draws. Swiss-Chess blocks pairing while an adjourned game from an earlier round than the previous one remains; COPP requires the
  result before pairing the second round after; reports and final standings warn while adjourned games remain.
- Full-point byes are allowed with a warning that FIDE deprecates them.
- Forbidden pairings and club/federation avoidance are tolerated; Swiss-Manager warns after two rounds, SwissSys at round 3.
- Pairing numbers cannot change after round 4 is paired (Vega only warns); Swiss-Manager warns when pairing numbers do not follow the ratings.
- COPP's report criticises a TRF export made before the end of the tournament without saying it is not a full rating report.

**What SwissSys testing involved (2017):**
- FE-1 sent in June 2017. A private build (9.583) was tested and released as 9.6, and an interim certificate was granted on 2017-11-23 pending the Board.
- FPC and RTG were "provided through bbpPairings". The verification focused mainly on whether the engine was **interfaced properly**.
- A FIDE-only licence key gives a FIDE-only mode. TRF16 import and export were checked, including all letter codes and PAB-value inference. UTF-8 is used.
- Club and federation avoidance restrictions were tolerated, with a warning at round 3.
- An auto-renumber-on-rating-edit option was flagged as risky.
- FPB entry warns, and adjourned games count as draws. The FIDE report is blocked while adjourned games remain.

**Contact.** The FIDE Technical Commission (TEC) is the single point of contact, through tec.fide.com and the registration form.
The 2024 Q1 TEC report names Roberto Ricca as SPP head and Hendrik du Toit as secretary, but the Commission changes after the 2026 Congress (UNCERTAIN).

## 6. Pairing engines

Sources:
- `pairing-bbp-readme`, `pairing-bbp-releases`, `bbp-LICENSE.txt`
- `pairing-javafo`, `pairing-javafo-aum`
- `pairing-gacrux-tiebreakserver-readme`

**bbpPairings** (https://github.com/BieremaBoyzProgramming/bbpPairings):
- **Latest release `v6.0.0`, published 2026-02-01.** Release notes:
  - "Switch to 2025 Dutch rules (effective date in 2026)."
  - "Add initial support for TRF-2026 (free points and adjustable point values for adjourned games are not currently supported)."
  - The README says it implements the **2025 Dutch rules, which are the rules in force from 1 Feb 2026**. It also has a flawed, unendorsed Burstein implementation.
- **Unreleased changes on master:**
  - 2026-05-20: accept the `192` values `FIDE_DUTCH_2026` and `FIDE_DUTCH_2026_BAKU`.
  - 2026-06: TRF26 `162` parsing fixes (last push 2026-07-31).
- **v6.0.0 accepts only these `192` values:** `FIDE_DUTCH_2025`, `FIDE_DUTCH`, `FIDE_DUTCH_2025_BAKU`, `FIDE_DUTCH_BAKU`, `FIDE_BURSTEIN`, `FIDE_BURSTEIN_BAKU`. Any other value is an error.
  It rejects `299` (abnormal points) records. **For portability, emit `192 FIDE_DUTCH`** (ETT26 defines it as the 2026 rules after 2026-01-31).
- **Binaries:**
  - `bbpPairings-v6.0.0-x86_64-pc-linux.tar.gz`
  - `bbpPairings-v6.0.0-i386-pc-linux.tar.gz`
  - `bbpPairings-v6.0.0-x86_64-pc-windows.zip`
  - `bbpPairings-v6.0.0-i686-pc-windows.zip`

  There is **no macOS binary**, so it must be built from source (C++). The tarball contains `bbpPairings.exe`, `README.txt`, `LICENSE.txt` and `Apache-2.0.txt`.
- **Licence:** source under **Apache-2.0**, © 2016-2026 Jeremy Bierema. "Official builds" may add terms, and v6.0.0's LICENSE lists none.
  The repo has a MinGW runtime COPYING patch for Windows packaging. UNCERTAIN whether runtime notices must ship with Windows builds.
- **CLI (exact, from the README):**
  ```
  bbpPairings.exe [-r]
  bbpPairings.exe [-r] (--burstein | --dutch) input-file -c [-l [check-list-file]]
  bbpPairings.exe [-r] (--burstein | --dutch) input-file -p [output-file] [-l [check-list-file]]
  bbpPairings.exe [-r] (--burstein | --dutch) (model-file -g | -g [config-file]) -o trf_file [-s random_seed] [-l [check-list-file]]
  ```
  - `-r` prints the version.
  - `-c` checks the whole tournament, so it is the FPC.
  - `-p` pairs the next round; the output goes to stdout if no file is given.
  - `-g` is the RTG, from a model TRF (positional, before `-g`) or a config file. It writes a TRF with `-o`, and `-s` sets the seed (the first line of the output records the seed).
  - `-l` writes a checklist.
  - There is **no `--model` flag**; the model file is positional.
  - JaVaFo's `-w`/`-q` are not supported, and `-b` (Baku) is replaced by TRF records.
- **Pairing output (`-p`), JaVaFo format:** line 1 is the number of pairs P, then P lines of `whiteId blackId`. The PAB appears as `id 0`.
  Example from the bbp test `dutch_2025_C9`: `3`, `2 1`, `3 5`, `4 0`.
- **Exit codes:**
  - 0: OK
  - 1: no valid pairing
  - 2: unexpected error
  - 3: invalid request or file
  - 4: size limits
  - 5: file access error
- **Input:**
  - TRF-2026 is preferred; it also reads TRF(bx), meaning JaVaFo `XX*` plus `BBW/BBD/BBL/BBZ/BBF/BBU` point-value codes (format `BBW  3.0`).
  - Recognised records: `001 013 310 240 250 260 142 152 162 192` and `XXA XXP XXR XXC(rank|white1|black1)`.
  - It **does not randomise the initial colour.** Give it with `152` or `XXC white1|black1` for round 1, otherwise it is inferred from the earliest round with colours.
  - It checks that every 001 score is consistent with the point system, and refuses to run otherwise.
- **RTG config keys:** follows JaVaFo 1.4, plus `PointsForLoss`, `PointsForForfeitLoss` and `PointsForPAB`. UNCERTAIN: exact JaVaFo 1.4 key names; the 2.x names are below.
- SwissSys's FIDE endorsement relies on bbpPairings as its engine, FPC and RTG.

**JaVaFo** (http://www.rrweb.org/javafo/JaVaFo.htm):
- Roberto Ricca's Java (≥ 7) Dutch engine. The current version stated is **2.2 (2018-09-15)**. The page does not mention 2026 rules (UNCERTAIN whether a newer build exists).
- **Licence:** "free of charge" if you pronounce and spell the name properly. In a commercial product you must mention `rrweb.org/javafo` and notify the author.
  It is distributed only as `javafo.jar`; **no source or OSS licence** is offered, so it is freeware, not open source.
- **CLI (AUM, where `javafo` = `java -ea -jar javafo.jar`):**
  - `javafo [-r]`
  - `javafo [-r] input-file -c [round-number]`
  - `javafo [-r] input-file [-b] -p [output-file] [-l [check-list-file]]`
  - `javafo [-r] [model-file] -g [-b] -o trf-file`
  - `javafo [-r] -g config-file [-b] -o trf-file`

  If config-file is an integer, it is used as the seed.
- **TRF(x) extensions:**
  - `XXR n`: total rounds.
  - `XXC rank|white1|black1`: cumulative configuration.
  - `XXA NNNN pp.p pp.p …`: id at col 5, the round-r points at col 10+5(r−1).
  - `XXP id id …`: no two listed players may meet.
  - `XXS CODE=VALUE …`: codes WW BW WD BD WL BL ZPB HPB FPB PAB FW FL, plus the shortcuts W (=WW, BW, FW, FPB) and D (=WD, BD, HPB).
- **RTG properties:** PlayersNumber, RoundsNumber, ForfeitRate, QuickgameRate, ZPBRate, HPBRate, FPBRate, HighestRating, LowestRating, Groups, Separator,
  and WWPoints…FLPoints.

**Gacrux** (https://github.com/OttoMilvang/TieBreakServer):
- **MIT, © 2024 FIDE.** The code was donated by Otto Milvang. If embedded, add a link to www.gacrux.no.
- Python ≥ 3.11. It provides `pairingchecker.py` (`-m dutch|berger|fideteam`, `-p` pair, `-c` check, `-a` analyse), `tiebreakchecker.py` (`-t` rank-order list, `-s` Swiss, `-p` predetermined) and `tournamentgenerator.py`.
  It reads TRF16, TRF-25 and TRF-26, Chess-JSON and Tournament Service files.
- TEC calls it the open reference platform ("not itself FIDE approved"). ChessRoster's FIDE engine is built on it.
- Its TRF writer is a useful alignment reference (see §7).

## 7. TRF26 essentials for an exporter

Sources:
- `fide-trf26-spec`: https://handbook.fide.com/files/handbook/TRF26.pdf (C.02.03 Annexure A; approved 12/05/2025, applied 01/09/2025)
- `fide-ett26`: https://handbook.fide.com/files/handbook/ETT26.pdf (192 codes)
- `fide-mtb26` (202/212 codes)
- TEC copies: `fide-trf26-tec-draft` (same content, different layout), `fide-trf26-tournament-type-codes`, `fide-trf26-mandatory-tiebreaks` (Apr 2025, superseded by ETT26 and MTB26)

General rules:
- Every line ends with CR. `###` starts a comment line.
- All positions are **1-based, inclusive**. The record code is in cols 1–3, and data starts at col 5.
- "Format 11.5" means a 4-char decimal such as ` 4.5` or `17.0`.
- Use UTF-8; VCL.12 recommends it.

**Tournament records** (data from col 5; R = required for rating, P = required for pairing; ◙ = required for title events):

| Code | Content | Notes |
|---|---|---|
| 012 | Tournament name | R■ P■ |
| 022 | City | R■ |
| 032 | Federation | R■ |
| 042 / 052 | Start / end date `YYYY/MM/DD` | R■ |
| 062 / 072 / 082 | Number of players / rated players / teams | |
| 092 | Type of tournament (free text) | |
| 102 | Chief Arbiter | R■ |
| 112 | Deputy CA (one line each) | |
| 122 | Allotted times per moves/game (free text) | |
| 132 | Round dates `YY/MM/DD`: round 1 at cols **92–99**, round 2 at **102–109**, round 3 at 112–119, … (10-col stride) | R■ |
| **142** | **Number of rounds** | mandatory only for ITDX (equivalent to `XXR`) |
| **152** | **Initial-colour** `W`/`B` | mandatory only if it differs from the colour of the highest-ranked player paired in round 1, or for ITDX before round 1 (equivalent to `XXC white1/black1`) |
| 162 | Individual scoring | col 6 is a symbol in `W D L A P X`, cols 7–10 its points (11.5). Optional further pairs at col 15 / 16–19, col 24 / 25–28, and so on every 9 cols (33, 42, 51). Defaults: W (win OTB, forfeit win or FPB) 1.0; D (draw or HPB) 0.5; L (loss OTB) 0.0; A (ZPB or forfeit loss) 0.0; P (PAB) = W; X (unknown or adjourned) = D. Write it only when a value differs from the default (equivalent to `XXS`/`BB*`) |
| 172 | Encoded starting-rank method, only if NRS records exist | cols 5–7 federation; cols 9–13 one of `FIDE` `NRO` `FIDON` `NIDOF` `HBFN` `LBFN` `OTHER` |
| 182 | Pairing controller identifier (program or user) | R◙ |
| **192** | Encoded type of tournament (table below) | R◙ P■ |
| 202 | Tie-break list (comma-separated MTB26 codes) | R◙ P■ |
| 212 | Alternative to 202: same, plus `PTS` (`212 PTS,…` ≡ `202 …`) | |
| 222 | Encoded time control: `d[:d]` or `Wd[:d]-Bd[:d]` with d = `M/S` or `M/S+I` or `S` or `S+I` (seconds). Examples: 90'+30" = `5400+30`; 100'/40+15'+30" = `40/6000+30:900+30`; Armageddon = `W300-B240` | R■ |
| 352 / 362 | Team board colour sequence (`WBWB…`) / team match-point scoring (TW/TD/TL) | teams |

**Player record 001:**

| Cols | Field | Content | R | P |
|---|---|---|---|---|
| 1–3 | id | `001` | ■ | ■ |
| 5–8 | Starting rank (TPN) | 1–9999, right-aligned | ■ | ■ |
| 10 | Sex | `m` / `w` (note: rating lists use M/F) | □ | |
| 11–13 | Title | `GM IM WGM FM WIM CM WFM WCM` (Gacrux writes right-aligned in 3) | □ | |
| 15–47 | Name | `Lastname, Firstname` (33 chars) | □ | |
| 49–52 | FIDE rating | 4 digits; blank or 0 if unrated | □ | |
| 54–56 | FIDE federation | 3 letters | □ | |
| 58–68 | FIDE number | 11 chars "including 3 digits reserve", right-aligned | ■ | |
| 70–79 | Birth date | `YYYY/MM/DD` (UNCERTAIN how to write a year-only date; the field is "warning only") | □ | |
| 81–84 | Points | standings points with the actual scoring and PAB value, 11.5 (3/1/0 example: `17.0`) | | ■ |
| 86–89 | Rank | final or current rank, ties allowed | ■ | ■ |
| per round r | opponent `92+10(r−1)`–`95+10(r−1)`; colour `97+10(r−1)`; result `99+10(r−1)` | ■ | ■ |

Round fields:
- **Opponent:** the opponent's starting rank, or `0000` (or 4 blanks) for any bye or not-paired round.
- **Colour:** `w`, `b`, or `-` (or blank) for a bye or not-paired round.
- **Result codes** (case-insensitive):
  - `+` forfeit win; `-` forfeit loss
  - `W` / `D` / `L`: win / draw / loss **in a game that lasted less than one move (not rated)**
  - `1` / `=` / `0`: regular win / draw / loss
  - `H` half-point bye; `F` full-point bye (not rated)
  - `U` **pairing-allocated bye** (at most one per round, "U for player unpaired by the system")
  - `Z` zero-point bye or known absence; blank = `Z`
- Round 2 is at cols 102–105, 107 and 109; round 3 at 112–115, 117 and 119; and so on.
- Gacrux writes each round as two spaces, then the opponent right-aligned in 4, a space, the colour, a space and the result. A round with no entry is written as 10 spaces.

Verified line (bbp test input):
```
001    1      Test0001 Player0001               2720                             1.0    1     3 w 1
```
Its fields:
- start = `   1`
- rating = `2720` (cols 49–52)
- points = ` 1.0` (81–84)
- rank = `   1` (86–89)
- opponent = `   3` (92–95)
- colour = `w` (97)
- result = `1` (99)

**National Rating Support (NRS)** has the same static layout as 001, but cols 1–3 hold the **federation code**, for example `USA`. A 172 record must also exist.

| Cols | Field | Notes |
|---|---|---|
| 5–8 | Starting rank | links to 001; P■ |
| 10 | National sex | optional |
| 11–13 | National classification | |
| 15–47 | National name | optional |
| 49–52 | National rating | P■ |
| 54–56 | National origin | state, region, etc. |
| 58–68 | National number | |
| 70–79 | Birth date | optional |

**ITDX and extension records** (individual-relevant):
- **250 Acceleration** (overrides any acceleration named in 192, for ITDX). Example (team Baku): `250 00.0 02.0 001 003 0001 0090`.

  | Cols | Field | Notes |
  |---|---|---|
  | 5–8 | Fictitious match points | teams; empty for individuals |
  | 10–13 | Fictitious game points | 11.5; must be ≠ 0.0 for individuals |
  | 15–17 | First round | |
  | 19–21 | Last round | |
  | 23–26 | First player id | |
  | 28–31 | Last player id | the record covers a range of player ids |

- **260 Prohibited pairings.** Cols 5–7 first round, 9–11 last round, then player ids at 13–16, 18–21, 23–26, … (5-col stride). No two listed players may meet in those rounds.
  Example: `260 001 002 125 180 184 216`. JaVaFo's `XXP` has no round range.
- **240 Bye.** At most one record per type per round, listing players or teams:

  | Cols | Field |
  |---|---|
  | 5 | Type `F` / `H` / `Z` |
  | 7–9 | Round |
  | 11–14, 16–19, 21–24, … | Ids |

  For individuals it is optional, because it duplicates 001. **For ITDX it is mandatory for rounds not yet paired**, which is how pre-requested byes reach the engine.
  Example: `240 H 003 026 047`.
- **299 Abnormal points.**

  | Cols | Field | Notes |
  |---|---|---|
  | 5 | Type | `W D L F H Z + -` or blank (blank = penalty or bonus) |
  | 8–11 | Match points | teams |
  | 14–17 | Game points or individual points | `[-]11.5` |
  | 20–22 | Round | `000` = all |
  | 24–27, 29–32, … | Ids | |

  **bbp rejects 299.**
- Team-only records: 013 (old), 310 (team roster), 320 (team PAB), 330 (team forfeits), 300 (out of default order), 801/802 (informative).
- **JaVaFo/bbp equivalents:**
  - 142 ↔ `XXR`
  - 152 ↔ `XXC white1|black1`
  - 250 ↔ `XXA`
  - 260 ↔ `XXP`
  - 162 ↔ `XXS` (JaVaFo) or `BBW/BBD/BBL/BBZ/BBF/BBU` (bbp)
  - `XXC rank` has no TRF26 equivalent; I found none.

**192 tournament-type codes (ETT26):**
- **Individual Swiss:**
  - `FIDE_DUTCH_2017`: rules before 1 Feb 2026.
  - `FIDE_DUTCH_2026`: rules after 31 Jan 2026.
  - `FIDE_DUTCH`: resolves by date.
  - `FIDE_DUBOV`, `FIDE_BURSTEIN`.
  - `_BAKU` variants of each (`FIDE_DUTCH_2017_BAKU`, `FIDE_DUTCH_2026_BAKU`, `FIDE_DUTCH_BAKU`, `FIDE_DUBOV_BAKU`, `FIDE_BURSTEIN_BAKU`).
  - `CUSTOM_SWISS`, `FIDE_DOUBLESWISS`, `FIDE_DOUBLESWISS_BAKU`, `CUSTOM_DOUBLESWISS`.
  - The Apr 2025 TEC draft used `FIDE_DUTCH_2025` with a 1 Jul 2025 cutover. bbp v6.0.0 accepts that spelling, not `_2026`.
- **Individual predetermined:**
  - `BERGER_ROUNDROBIN_Gn` (games repeated n times); `BERGER_ROUNDROBIN` = G1; `BERGER_DOUBLEROUNDROBIN` = G2.
  - `FIDE_ROUNDROBIN` = BERGER_ROUNDROBIN.
  - `FIDE_DOUBLEROUNDROBIN`: G1 with the last two rounds reversed, followed by G1.
  - `CUSTOM_ROUNDROBIN`.
  - `FIDE_SCHILLER_TxP`, `FIDE_SCHILLER` (=4x3), `CUSTOM_SCHILLER` (rules not yet defined).
  - `FIDE_SCHEVENINGEN_Gn`, `FIDE_SCHEVENINGEN`, `FIDE_DOUBLESCHEVENINGEN`, `CUSTOM_SCHEVENINGEN` (not yet defined).
  - `CUSTOM_KNOCKOUT`.
- **Team:**
  - `FIDE_TEAM_{TYPEA|TYPEB|}_{MP_GP|GP_MP|MP|GP}[_BAKU]` (BAKU only with MP-primary).
  - `FIDE_TEAM` = TYPEA_MP_GP; `FIDE_TEAM_BAKU`.
  - `CUSTOM_TEAM_SWISS[_MP|_GP]`, `BERGER_TEAM_ROUNDROBIN[_Gn]`, `BERGER_TEAM_DOUBLEROUNDROBIN`, `FIDE_TEAM_ROUNDROBIN`, `FIDE_TEAM_DOUBLEROUNDROBIN`, `CUSTOM_TEAM_ROUNDROBIN`, `CUSTOM_TEAM_KNOCKOUT`.

**Title codes** (TRF 001 cols 11–13 and rating lists): `GM IM WGM FM WIM CM WFM WCM`. Order for initial ranking: GM > IM > WGM > FM > WIM > CM > WFM > WCM > none.
Readers should also accept the legacy single-letter forms `g m f c wg wm wf wc`, which Gacrux maps. Arbiter titles (IA/FA/NA) live in rating-list OTit, not in TRF 001.

**Minimal exporter checklist (individual Swiss):**
- Records 012, 022, 032, 042, 052, 062, 072, 102, (112), 122, 132, **142**, (152), (162 only if non-default), **182**, **192 `FIDE_DUTCH[_BAKU]`**, **202/212**, **222**.
- One 001 per player.
- 240 for future requested byes when used for ITDX.
- 260 for restrictions, and 250 for acceleration.
- Verify the export by round-tripping it through `bbpPairings --dutch file -c` and Gacrux `pairingchecker.py -c`.

## What I could not find or verify

- **No official FIDE API**, and no licence or terms statement for the rating-list downloads.
- The **final 2026 THP VCL** is not published yet (the fees now are: TEC Manual Annexure A, above). The live SPP site (spp.fide.com) was in maintenance, so a Wayback copy of C.04.A was used.
- **No FIDE-recommended default tie-break lists** exist in the current C.07. The defaults above are a suggestion, not a FIDE rule.
- How to write a year-only birth date in TRF 001 cols 70–79. Exact TRF alignment conventions are taken from Gacrux and bbp files, not from the spec text.
- Whether JaVaFo has a 2026-rules build (its page still says 2.2 from 2018). bbp's 2026 `192` spelling is only on unreleased master.
- I did not run any downloaded binary. The bbp v6.0.0 linux tarball was fetched into the scratchpad only to read its LICENSE.
