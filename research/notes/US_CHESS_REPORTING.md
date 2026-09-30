# US Chess rating report interoperability

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
| `S_R_SYSTEM` | Derived, never chosen: total = sum of control minutes + delay/increment seconds; > 65 `R`, 30–65 `D`, 11–29 `Q`; first control ≥ 5 min. Blitz (5–10, first control ≥ 3) has no 2C code and is blocked. | Rules 5C and its TD TIP table (`uscf-rules-2026.txt`) |
| `S_TIMECTL` | `Game/nnn` for sudden death, `40/90, SD/30` for stages, then the rulebook's `d/5` or `inc/30`. | 2C field text; rule 5B2 notation |
| `H_AFF_ID` | `A` + seven digits (e.g. A6051416); the previous eight-digit check refused every real affiliate. | Affiliate IDs in saved US Chess pages |
| `D_MEM_ID`, `H_CTD_ID` | Eight digits; `00000000` refused because 2C defines it as "unavailable" and such events are not ratable. A member ID may repeat only for the same person in different sections. | 2C `D_MEM_ID` |
| `D_NAME` | `LAST, FIRST` in capitals, the 2C preferred form; accents folded; particles (de, van, St.) and suffixes (Jr., III) handled; a per-player override and the US Chess lookup cover the rest. Nothing is truncated. | 2C `D_NAME` |
| `D_STATE` | Required, because 2C only marks `D_MEM_ID` blank as allowed. Filled from lookup, roster import or the player panel; the TD can explicitly apply the event state to the rest. | 2C preamble "all fields are required" |
| `H_END_DATE`, `S_*_DATE` | Event has an optional last day; dates must be ordered and not after today. | 2C date fields |
| `H_CITY`/`H_STATE`/`H_ZIPCODE` | Saved with the event; state must be a USPS code; `H_COUNTRY` is `USA`. | 2C `H_COUNTRY` note |
| `S_SCH_LVL` | Event-level N/S/P/J. | 2C `S_SCH_LVL` |
| `H_OTHER_TD` | Width **254**, not 2C's 255: dBase III character fields hold at most 254 bytes, so some readers refuse 255. The field is optional and always empty. Revisit if MUIR rejects it. | TD decision |
| Text fields | ASCII after folding; `" \ | ` ~ ^ < > { } [ ] *` refused; widths checked before encoding. | Defensive |

Still open: current accepted SwissSys/WinTD files for comparison, MUIR draft
validation, Grand Prix, FIDE, Blitz, double games and mixed round counts.
