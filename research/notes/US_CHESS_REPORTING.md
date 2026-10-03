# US Chess rating report interoperability

**Implementation follow-up, October 3:** Mixed-round export is now implemented
using maximum physical round columns, section-local counts and `U0` padding.
The full Fall Equinox reconstruction passes both independent readers and matches
all 19 entries / 70 active result cells. See [current compatibility checks and
remaining limits](../../docs/DBF_COMPATIBILITY.md). Mixed-round blockers described
in the dated investigations below are historical, not current behavior.

Latest evidence: the [Fall Equinox Swiss comparison](#fall-equinox-swiss--real-file-comparison-october-3-2026)
checks user-provided SwissSys files against our exporter and the published US Chess
results. The event is confirmed rated; our generated packages have not been uploaded.

## The missing developer reference exists

The [official file-format page](https://secure2.uschess.org/TD_Affil/fileformat.php)
is titled draft **2C**, dated August 3, 2006, but explicitly says the format is
supported. Its September 2025 correction changes several fields to left-justified,
space-filled **character** fields to match pairing programs and MUIR testing.
The March 2026 [staff discussion](https://forum.uschess.org/t/up-to-date-dbf-file-format-reference/60661)
corroborates that correction. Both were saved locally.

The [current FAQ](https://new.uschess.org/tournament-director-and-affiliate-frequently-asked-questions#Format)
is useful for TD workflow but describes some **older-format** mechanics, including
record pointers and extra detail records beyond ten rounds. In 2C those pointer
and sequence fields were removed and round fields are variable. Do not combine
both descriptions into an invented hybrid schema.

The same FAQ says a separate developer guide is pending. We found a usable legacy
specification and a real API contract; we did not establish a newer complete
reporting specification that supersedes 2C.

## Three files, three responsibilities

| File | Records | Important fields / constraints |
|---|---|---|
| `THEXPORT.DBF` | Event headers | `H_FORMAT=C(5)` containing `2C`; `H_PROGRAM=C(10)`; `H_EVENT_ID=C(12)`; `H_NAME=C(35)`; `H_TOT_SECT=C(2)`; dates `D(8)`; affiliate and TD IDs |
| `TSEXPORT.DBF` | Sections | Event/section IDs, name `C(30)`, rating system, time control `C(40)`, tournament type, round/player counts, dates, TDs and event classification |
| `TDEXPORT.DBF` | Player entries | Event/section/pairing IDs, member ID `C(8)`, name `C(30)`, state, rating `C(4)`, `D_RND01…D_RNDnn` result fields `C(7)` |

The full source is the authority for field order/types/widths; this table is not
a substitute schema. We should transcribe and review a versioned schema before
implementing the encoder. The draft's 255-byte `H_OTHER_TD` and variable round
columns warrant explicit DBF-reader compatibility checks.

`H_EVENT_ID` is not an arbitrary database UUID. The spec reserves 12-character
assigned IDs and allows a shorter internal tracking value when unassigned.
Internal application identities therefore require a separate export mapping.
Section and pairing numbers are also export-local identities, not UI row indices.

## Format-sensitive interpretation

For Swiss-style chronological reporting, a result links to an opponent's **export
pairing number**, not their US Chess ID. Ordinary result codes include W/D/L;
forfeits, byes and unplayed games are different. In the 2C encoding, X/Z/F/B/H/U
have opponent zero. Internally retain the actual paired opponent for a forfeit
even if that export representation omits it. Unusual inconsistent-but-ratable
codes require explicit TD/office handling; never use them to hide invalid data.

For round-robin reporting, columns refer to opponents and the diagonal is unplayed.
A four-person quad has four opponent columns although it has three chronological
rounds. The alternative documented by US Chess is reporting those three rounds
chronologically as Swiss. This is an **encoding choice**, not a change to the
competition's pairing method.

Proposed initial quad export: chronological three-round Swiss representation, with
the actual quad/RR preserved in Meow-Chess. Validate with a current accepted
SwissSys/WinTD example and a TD before making this the release default.

A double-game round is not one ordinary game. Keep two game records and confirm
the `2` double-Swiss representation versus expanded chronological games against
current accepted samples. Never export a combined 1–1 match score as one draw.

## Remaining specification ambiguities are release gates

| Issue | Evidence / required resolution |
|---|---|
| Rating-system codes | The old 2C prose enumerates R/D/Q and old time thresholds; current rules include Blitz and online categories. Obtain accepted current encodings rather than guessing. |
| Match game limit | Old 2C text says 20, current FAQ says 32. Versioned rules must resolve the difference; matches are not initial scope. |
| Mixed section round counts | DBF has one physical schema per file. Confirm unused round-column padding and the applicable maximum-column convention with real mixed-section exports. |
| Encoding | Confirm DBF dialect, code page, non-ASCII handling, date bytes, numeric-looking character padding, and field limits with actual accepted files. |
| Event participant coding | Current TD workflow requires classification; determine which data can be exported and which still needs portal entry. |
| Report completeness | A generated file is not an accepted report. Portal validation/TD review is still required. |
| Legacy vs 2C | Test only explicitly supported versions. Do not silently fall back to old pointer-based layouts. |

Blitz matters in the first release, so an unknown Blitz encoding cannot be pushed
into a distant backlog. If unresolved, show that capability as unavailable and do
not claim the initial release scope has passed.

Current time-control rules must come from the current rules/FAQ, not the 2006
examples. Preserve base time, increment/delay kind, seconds, move stages, online/OTB
and per-round schedule. For example G/60 d5 cannot be classified by “60” alone.
Use the current federation calculation and test category boundaries explicitly.

## Proposed export pipeline

`Event revision → federation report model → preflight → encode in staging folder
→ independent decode/validation → publish immutable export package`.

Preflight covers selected sections, event/section date consistency, TD/affiliate
metadata, unresolved identities, required member IDs, membership findings,
all results present, reciprocal opponents/results, pairing-number references,
rating categories, field overflow, nonrepresentable text and duplicate entries.
Only supported exceptions can be acknowledged; integrity errors stay blocking.

Do not truncate names or section titles silently. Present a separate export alias
and retain the full internal text. Do not label invented local IDs as US Chess
IDs. Keep genuinely different entries for an authorized reentry rather than
blindly deduplicating all member IDs within an event.

Publish the three files together in a new folder, plus a manifest identifying
event revision, schema and app version, selected sections, checks and hashes.
Never leave one newly written file alongside two old ones after a crash.
The TD uploads through MUIR, reviews its validation, and handles submission/payment.
Meow-Chess initially records export history and the eventual report ID/status
manually; it does not imply automated submission.

## Acceptance evidence needed

Known accepted fixtures: single Swiss; quad; four quads plus six-player Swiss;
mixed round counts; half/full/zero byes; forfeits; provisional/unrated players;
long/non-ASCII names; double blitz; >10 chronological rounds. Decode with a reader
independent of our writer. Compare semantic content with a current pairing program;
binary equality is not required when timestamps/metadata legitimately differ.

Arrange an authorized test/draft validation with US Chess or a TD. Do not submit
a fictional event as a real rated tournament. This phase performed no uploads.

## Implementation decisions — September 30, 2026

Each rule below is enforced by `ratingPreflight` before any file is written and
re-checked by `scripts/verify_dbf.py`.

| Field / topic | Decision | Source |
|---|---|---|
| `S_R_SYSTEM` | Derived, never chosen: total = sum of control minutes + delay/increment seconds; > 65 `R`, 30–65 `D`, 11–29 `Q`; first control ≥ 5 min. Blitz (5–10, first control ≥ 3) has no 2C code; **since Oct 3** it is written as the `D` SwissSys sent and US Chess rated as blitz from the time control (event 202604280273). | Rules 5C and its TD TIP table (`uscf-rules-2026.txt`) |
| `S_TIMECTL` | **Since Oct 3:** US Chess's own stored spelling, `G/60;d5`, `40/90,SD/30;+30`, `;d0` when none (every one of 6,000 sections rated May–Sept 2026). Previously `Game/60 d/5`, never seen in a rated section. | US Chess rated-sections API |
| `H_AFF_ID` | `A` + seven digits (e.g. A6051416); the previous eight-digit check refused every real affiliate. | Affiliate IDs in saved US Chess pages |
| `D_MEM_ID`, `H_CTD_ID` | Eight digits; `00000000` refused because 2C defines it as "unavailable" and such events are not ratable. A member ID may repeat only for the same person in different sections. | 2C `D_MEM_ID` |
| `D_NAME` | `LAST, FIRST` in capitals, the 2C preferred form; accents folded; particles (de, van, St.) and suffixes (Jr., III) handled; a per-player override and the US Chess lookup cover the rest. Nothing is truncated. | 2C `D_NAME` |
| `D_STATE` | **Since Oct 3: advice, not a blocker** — US Chess accepted blank states in six of seven Boylston reports (52 of 54 in one). Previously required, because 2C only marks `D_MEM_ID` blank as allowed. Filled from lookup, roster import or the player panel; the TD can explicitly apply the event state to the rest. | 2C preamble "all fields are required" |
| `H_END_DATE`, `S_*_DATE` | Event has an optional last day; dates must be ordered and not after today. | 2C date fields |
| `H_CITY`/`H_STATE`/`H_ZIPCODE` | Saved with the event; state must be a USPS code; `H_COUNTRY` is `USA`. | 2C `H_COUNTRY` note |
| `S_SCH_LVL` | Event-level N/S/P/J. | 2C `S_SCH_LVL` |
| `H_OTHER_TD` | Width **255**, character type, matching the published specification. Corrected from 254 on October 3, 2026. **Since Oct 3** filled from Event details (other TDs), with `H_ATD_ID`/`S_ATD_ID` from the assistant chief TD; US Chess credits them as officials. | 2C `H_OTHER_TD` |
| Text fields | ASCII after folding; `" \ | ` ~ ^ < > { } [ ] *` refused; widths checked before encoding. | Defensive |

Still open: MUIR draft validation of a Meow file, Grand Prix and FIDE. Accepted
SwissSys files, blitz, double games and mixed round counts were resolved on
October 3 (see `docs/DBF_COMPATIBILITY.md`). Dates are now C(8) and event IDs
blank, as in every accepted SwissSys report.

## Compatibility recheck — October 3, 2026

**Status: locally tested, not yet verified against SwissSys output or accepted by
MUIR.** We cannot promise exact SwissSys parity or unconditional US Chess acceptance.
The initial review changed documentation only. The subsequent width correction
below updates the export implementation and its checks.

### Sources checked again

- [Official 2C specification](https://secure2.uschess.org/TD_Affil/fileformat.php):
  fresh HTTP 200 download is byte-identical to our archived HTML; SHA-256
  `f8c495dc197f90ccdc61bf87df7609edd535753a8c6bc463cf0021f42a504804`.
- [US Chess TD FAQ](https://new.uschess.org/tournament-director-and-affiliate-frequently-asked-questions)
  and [MUIR rating guide](https://new.uschess.org/sites/default/files/media/documents/us-chess-tournament-rating-guide-2025.pdf):
  three DBFs remain the documented upload route, followed by portal validation.
  The FAQ still describes a separate developer guide as pending. No newer complete
  replacement specification was found; this is not a claim to have reviewed every
  US Chess publication.
- [2026 rules, rule 5C](https://new.uschess.org/sites/default/files/media/documents/us-chess-rule-book-online-2026.pdf):
  remains the reference for rating categories, rather than the old thresholds in 2C.
- [SwissSys USCF report instructions](https://docs.chessroster.com/swisssys/app-docs/user-guide/tournaments/ratings-report-for-uscf/):
  confirms the report utility and three output filenames, but does not establish
  the precise field descriptors emitted by the user's installed version.
- First-hand implementation discussions:
  [March 2026 specification clarification](https://forum.uschess.org/t/up-to-date-dbf-file-format-reference/60661),
  [MUIR upload problems](https://forum.uschess.org/t/reported-problems-with-upload-files-on-muir/59626?page=2),
  and [TD-field mapping](https://forum.uschess.org/t/section-tds-are-still-not-being-mapped-from-the-dbf-upload/59719).
  These document implementation issues; they do not certify our output or prove
  that historical portal bugs still exist today.

### Observed evidence and unresolved differences

Ran `MEOW_PYTHON="$HOME/.local/share/meow-test-tools/bin/python" scripts/ci.sh exports`:
all 13 Dart tests passed, independent `dbfread` verification passed for two sections,
30 entrants and 12 rounds, and corruption rejection checks passed.

Separately compared all 51 generated field descriptors with the freshly downloaded
official HTML. No required non-FIDE fields were missing. The initial comparison
found `H_OTHER_TD` was `C(254)` versus the specified `C(255)`. The writer,
contract test and independent validator now use `C(255)`, preserving character
type rather than introducing a memo field. The earlier tests shared the 254-byte
assumption and therefore did not detect that specification mismatch.

After correction, all 13 export tests, independent decoding and corruption checks
passed again. Comparing the regenerated package against the official HTML now
finds all 51 field descriptors match, with no required non-FIDE fields missing.
Updated evidence: `artifacts/dbf-contract/spec-audit.json`. This resolves the
field-width mismatch; SwissSys comparison and MUIR acceptance remain unverified.

Quads currently use chronological Swiss reporting; the FAQ explicitly permits
that representation. SwissSys might instead emit opponent-column round-robin
data, so a raw cell comparison could be misleading. Normalize games by player
identity and opponent before comparing results.

Current preflight blocks mixed round counts, double-game sections, blitz, and
player transfers after play began. FIDE and Grand Prix metadata are not implemented.
These are capability limits, not proof that US Chess cannot accept those events.
ASCII name conversion, time-control spelling, TD metadata and the optional field
width still need comparison with actual accepted files.

### When the SwissSys files arrive

Keep the original `THEXPORT.DBF`, `TSEXPORT.DBF`, and `TDEXPORT.DBF` together,
without opening and re-saving them in a spreadsheet. Record the SwissSys version,
time control, section setup, and whether MUIR accepted the package. The native
tournament file or final crosstable will help establish the intended game results.

Inspect both packages' dialect, format marker, field names/types/widths/order,
padding, dates, encoding, record counts, IDs, TDs and round representation. Then
compare every player's opponents, colors, results, byes and forfeits using a
semantic mapping; pairing numbers and application/version metadata may legitimately
differ. A legacy SwissSys layout needs its own decoder, not our strict 2C checker.
Finish with authorized MUIR draft validation of the intended real report before
claiming acceptance. No report was uploaded or submitted during this review.

## Fall Equinox Swiss — real-file comparison, October 3, 2026

### Scope and confirmed external result

Read the three original DBFs in `~/Downloads` without modifying them. All three
SHA-256 hashes still match the values recorded before analysis. Decoded records,
local reconstruction, generated packages, comparison scripts and captured public
API responses are under ignored `artifacts/fall-equinox-audit/`; real player data
was not added to committed test fixtures. Production exporter behavior was unchanged.

US Chess's [public rated-event record](https://ratings-api.uschess.org/api/v1/rated-events/202609190383)
confirms event **202609190383**, September 19, 2026, status **Rated**, 29 games,
first rated September 21 and last rated October 3. Read-only standings responses
for sections 1–3 agree with every DBF member ID, active round outcome, opponent,
color and score. This confirms the reported results, but cannot establish the
exact bytes originally uploaded or exclude edits made in the portal.

| Section | Entries | Actual rounds | Played games | Active result cells |
|---|---:|---:|---:|---:|
| Open | 10 | 4 | 17 | 40 |
| U1800 | 7 | 4 | 11 | 28 |
| Side Games | 2 | 1 | 1 | 2 |
| Total | 19 | — | 29 | 70 |

There are 17 distinct member IDs: two players also have side-game entries.
The results include two drawn games, three full-point byes, four half-point
byes, and five active unplayed/zero-point cells. There are no forfeits in this
sample. Six additional physical `U0` cells pad the two side-game records and
are not actual rounds or extra byes.

### End-to-end local reproduction

The Dart probe reconstructs separate section entries, linking repeated member
IDs through `personId` while preserving each entry's supplied rating. It reads
the actual source time-control spelling successfully. Board numbers are synthetic
because DBFs omit them; bye reasons, allocation decisions and withdrawal timing
cannot be recovered. This is a rating-report reconstruction, not an import of
the complete original tournament history or a GUI rehearsal.

1. `validateEvent` passes for the full reconstruction.
2. With the source's blank scholastic classification preserved, preflight reports
   that missing classification and the mixed round counts.
3. With non-scholastic `N` explicitly assumed for this probe, the only remaining
   blocker is mixed round counts. `ratingPackage` rejects the full event.
4. Using the unchanged production `writeRatingPackage`, exporting Open/U1800
   together and Side Games separately succeeds. These are diagnostic packages,
   not a recommendation to submit the real event twice.
5. The independent Python validator passes both packages, including comparisons
   with their source-event JSON. Manifest file sizes match the published files.
6. Comparing by section and member ID finds **zero semantic differences across
   all 19 entries and 70 active result cells**: names, supplied ratings, states,
   points, opponents, colors and result codes agree with SwissSys. Published US
   Chess standings independently confirm those result cells and scores.

### What the sample settles and what differs

| Topic | Observed SwissSys output | Current Meow-Chess / implication |
|---|---|---|
| Format | dBASE III marker `0x03`, `H_FORMAT=2C`, three files | Same format family; this is not a legacy ten-round/pointer layout. |
| Field layout | Same names, widths and order for shared fields; `H_OTHER_TD=C(255)` | Confirms the 255-byte correction. Four date-field **types** differ, below. |
| Text | ASCII bytes, space padding, left-justified character numbers, no memo | Matches our representation for this sample. Non-ASCII behavior remains untested. |
| Mixed rounds | Four detail columns for all players; section counts are 4, 4, 1; unused cells are `U0` | Our full-event export is blocked. This gives a concrete implementation target. |
| Date fields | Header and section beginning/ending dates are `C(8)` | Ours are `D(8)`, following the published specification. Both store identical `YYYYMMDD` date text. Do not mistake Python's decoded date display for different stored bytes. |
| DBF file date | Header year byte is 26: under dBASE's year-since-1900 convention, this means 1926 | Actual event fields say 20260919. Our year byte is 126. Preserve our correct year encoding; the observed header quirk is not a compatibility requirement. |
| Rating category | `S_R_SYSTEM=R` with `G60; d5` | Ours derives `D` and writes `Game/60 d/5`. Published standings have **both R and Q ratings for every entry**, confirming dual rating for this event. |
| Event tracking ID | Blank | Ours uses `MEOW`, a permitted short internal identifier. Neither is the subsequently assigned US Chess event number. |
| Event classification / GP points | Blank / blank, with Grand Prix flag `N` | Ours requires an explicit classification and writes GP points `0`; the latter follows the specification. |
| Program | `SWISSSYS`, without a version number | Ours identifies Meow-Chess and its version. Exact SwissSys version cannot be recovered here. |
| Repeated members | Two IDs occur in a main section and Side Games | Preserve section entries rather than deduplicating people out of the report. One repeated member has supplied ratings 1812 and 1804; the files do not explain why. |
| Names and ratings | All exported names are at most 17 characters despite a 30-byte field; some look shortened | Do not infer a 17-character format limit or truncate our names. Published member names can be fuller; official pre/post ratings also differ from supplied pairing ratings. Those differences do not imply corrupted results. |

The [2026 rulebook, rule 5C](https://new.uschess.org/sites/default/files/media/documents/us-chess-rule-book-online-2026.pdf)
explicitly classifies G/60 d/5 as dual. The organizer's
[event listing](https://boylstonchess.org/events/1566/fall-equinox-swiss) confirms
that time control and the main section setup. Historical
[US Chess implementation guidance](https://forum.uschess.org/t/new-tournament-db-format/15947)
also describes maximum-round detail columns and ignoring surplus columns for
shorter sections. The actual rated side-game result now supplies direct evidence
for that representation beyond the old guidance.

### Next implementation and remaining acceptance work

Prioritize mixed-round export: physical columns through the maximum round count,
each section's own `S_TOT_RNDS`, `U0` padding beyond that section's final round,
and validator logic that checks only real rounds as results. Build anonymized
regression cases for 4/4/1 sections and repeated people in Side Games. This sample
supports that change; this investigation did not implement it.

Keep standards-compliant dates, year bytes and derived rating category unless
provider testing demonstrates a reason to change. Our strict validator is a
contract checker for **our** output, not a universal validator for SwissSys;
rejecting its character-typed dates does not prove the SwissSys files are invalid.

Still untested by this sample: a Meow package uploaded to MUIR, quads/RR encoding,
forfeits, blitz, double games, more than ten rounds, non-ASCII text, assistant TDs,
FIDE and Grand Prix reporting. Exact original upload bytes remain unknown.

Reproduce the local checks (no network calls or source-file writes):

```sh
scripts/ci.sh with -- dart --packages=.dart_tool/package_config.json artifacts/fall-equinox-audit/replay.dart
"$HOME/.local/share/meow-test-tools/bin/python" artifacts/fall-equinox-audit/compare.py
```

The second command reads the captured public API responses and verifies them
against the DBFs and generated outputs. Detailed findings are in
`artifacts/fall-equinox-audit/comparison.json`; decoded originals are in
`artifacts/fall-equinox-audit/swisssys-decoded.json`.
