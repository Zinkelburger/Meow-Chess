# DBF export compatibility checks

Meow exports `THEXPORT.DBF`, `TSEXPORT.DBF`, and `TDEXPORT.DBF`. Those three
files contain the rating report; neither the manifest nor a Meow database is
needed to read it. Supported exports now include completed sections with
different round counts in one event package.

**October 3, 2026 update — matched to what US Chess actually rated.** The
public US Chess API (`ratings-api.uschess.org`, affiliate A5000408) shows what
MUIR rated from each of the seven Boylston SwissSys reports, after any TD edits
in the portal. That is the oracle now, not the SwissSys bytes alone. It showed:

- MUIR derives the rating system from `S_TIMECTL` (SwissSys's `R` for G/60 d5
  was rated dual; its `D` for G/5 d0 was rated blitz) and stores time controls
  in one canonical spelling (`G/60;d5`, `G/90;+30`, `40/90,SD/30;d5`; all 6,000
  sections rated May–September 2026 use it).
- MUIR expands SwissSys's double-game codes into two rated rounds per pairing
  (Rated Friday Night Blitz: 6 double rounds → 12 blitz rounds).
- `H_ATD_ID`, `S_ATD_ID` and `H_OTHER_TD` become credited event officials.
- Blank `D_STATE`, blank `S_SCH_LVL`/`S_GP_PTS` and C(8) dates were accepted in
  every report.

Meow now writes what was proven accepted rather than an untested reading of the
draft text: every field character type (dates C(8)), blank event IDs, the
canonical time-control spelling, quads and round robins as type `R`, double-game
rounds as two single-game rounds (blitz included; `S_R_SYSTEM` carries the `D`
US Chess accepted for blitz), and the assistant chief and other TDs. A missing
player state is advice, not a blocker. Replaying all seven reports through the
MCP tools and comparing every result cell with the rated record finds **no
difference that SwissSys's own report does not also have** (those are portal
edits made after upload). The anonymized reports and rated records are in
`test/fixtures/boylston/`. The header year byte stays year−1900 (126), which
the dBASE format defines; SwissSys writes 26. No Meow file has been uploaded to
MUIR yet: do one authorized draft upload before relying on it.

The earlier Boylston rehearsal's “not ready” conclusion combined export feature
gaps, missing source information and wider application qualification. It did not
mean that the app could not write DBFs. Mixed-round-count, blitz and double-game
exports are now implemented and covered by the replays above. Missing required
metadata and inconsistent source results still block the relevant reports;
acceptance of a newly generated Meow package by MUIR remains unverified.

## What the report holds when the event did not go to plan

`_report` in `lib/infrastructure/dbf_export.dart` builds the rows once for the
preflight, the files and the manifest. None of the cases below has been
uploaded to MUIR; they follow the 2C text and the accepted SwissSys files
(which include all-`U0` players and the same member in two sections).

- **Late entries** get a bye on each round they missed (`H0` or `U0`), like any
  other bye, and no longer count as a section move.
- **Moves and combined sections after play started.** A game is reported in the
  section where it was played. A player who left keeps a detail row there (the
  rounds played, then `U0`) and has a row in the new section (`U0`, or the bye
  recorded, for the earlier rounds). When every player of a game has since
  moved together into a section with the same time control and games per
  round, as when sections are combined, the game is reported in that section in
  the same round, so a combined section sends one set of rounds and the emptied
  section is not sent. An emptied section whose games cannot move (another
  time control) is still sent, with its former players.
- **Players with no played game and no US Chess ID** in a finished section are
  left out, with advice; pairing numbers stay contiguous. Anyone who played a
  game still needs an ID.
- **Sections with no played game** (and none waiting for a result) are left
  out, with advice, once another section has games; section numbers close up.
- **Re-entries** (rule 28S) that share a US Chess ID with the entry they
  replace merge into one detail row; if both entries played in the same round,
  both rows are sent and advice explains the duplicate ID.
- **Time controls with no delay stated** are sent with the rule 5E2 standard
  delay (`G/10` → `G/10;d2`, Quick), never an invented `;d0`.
- **Knockout tie-break games** are not sent (another time control, or time
  odds under rule 5C1); advice counts them. Every match game is sent.
- **Memberships** that the last check found expired before the event's last
  day are listed as advice.

## Run the complete check

On the configured Linux workstation:

```sh
python3 -m venv "$HOME/.local/share/meow-test-tools"
"$HOME/.local/share/meow-test-tools/bin/python" -m pip install dbfread==2.0.7
MEOW_PYTHON="$HOME/.local/share/meow-test-tools/bin/python" scripts/ci.sh exports
```

On another development machine with Flutter/Python available:

```sh
python -m pip install dbfread==2.0.7
python scripts/check_exports.py
```

This regenerates every synthetic package, checks each with `dbfread`
(`scripts/verify_dbf.py`), compares every entrant and active result with its
source event, runs the validator's 16 corruption controls plus a missing source
event (`scripts/test_dbf_validator.py`, also under `python -O`), the 93
mock-importer tests (`scripts/test_mock_uscf_importer.py`) and the 3 Boylston
anonymizer tests. A package a test writes but the script does not list, or one
it lists but no test wrote, fails the check. CI runs the same checks on Linux
and Windows, and on macOS for DBFs written there, using `--validate-only` after
its Flutter test step generates the files. No account or network is needed
after dependency setup.

Eighteen packages are generated, all checked against their source event except
the last:

| Package | Written by | Exercises |
| --- | --- | --- |
| `dbf-contract` | `rating_contract_test.dart` | 2 sections, 12 rounds, every outcome and bye, unrated player, leading-zero IDs, accent folding, explicit report name, multi-day dates |
| `dbf-importer/mixed-long-first`, `mixed-short-first` | `dbf_importer_test.dart` | sections of 12 and 1 rounds in both orders; U0 padding |
| `dbf-importer/rounds-1`, `rounds-32` | `dbf_importer_test.dart` | the smallest and largest round counts |
| `dbf-importer/quad` | `dbf_importer_test.dart` | chronological quad reported as round robin `R` |
| `dbf-importer/side-games` | `dbf_importer_test.dart` | independent one-round side-game entries for the same members |
| `dbf-importer/four-digit-opponents` | `dbf_importer_test.dart` | 1,000 players, four-digit opponent numbers, rating 4000 |
| `dbf-importer/double-blitz`, `blank-state` | `dbf_importer_test.dart` | double-game blitz with legs and both bye sizes; assistant and other TDs; a blank `D_STATE` |
| `dbf-importer/categories` | `dbf_byte_contract_test.dart` | regular, dual, quick and blitz sections |
| `dbf-importer/double-byes-forfeits` | `dbf_byte_contract_test.dart` | double-game byes split across legs; forfeits with no opponent |
| `dbf-importer/round-robin-bye` | `dbf_byte_contract_test.dart` | three-player round robin with its U0 bye |
| `dbf-importer/withdrawal-half-bye` | `dbf_scenarios_test.dart` | a withdrawal reported as U0; a final-round half-point bye |
| `dbf-importer/officials-sections` | `dbf_scenarios_test.dart` | assistant chief TD and 28 other TDs (251 of 255 characters); two sections with section-local pair numbers |
| `dbf-importer/field-widths` | `dbf_scenarios_test.dart` | event name, city, section name and player name at exactly 35, 21, 30 and 30 characters |
| `dbf-importer/rating-mix` | `dbf_scenarios_test.dart` | ratings 4000 and 850 beside unrated players with assigned or foreign ratings (reported as 0) |
| `dbf` (reciprocity only) | `import_reports_test.dart` | a completed quad, without a source event |

The byte contract tests (`dbf_byte_contract_test.dart`,
`dbf_scenarios_test.dart`) also pin, without writing packages: golden bytes
for every record of the minimal event and the scenarios above; that a value one
character over its field width is refused rather than truncated; four-digit
`D_PAIR_NUM` and `S_LST_PAIR`; that 10,000 entrants in a section and a 29th
other TD are refused; and that players moved between sections before play
started are reported where they now play. Generated files live under ignored `artifacts/`. These synthetic tournaments
must not be submitted.

## The deliberately fragile importer

```sh
python scripts/mock_uscf_importer.py artifacts/dbf-importer/mixed-short-first
python scripts/test_mock_uscf_importer.py
```

The mock uses only Python's standard library and opens only the three DBFs. It
does not import the app's encoder, the existing validator or its schema, or read
the manifest/source-event sidecars. It emits a JSON event with sections, players,
active round results and independently calculated scores. Failure reports a
specific field/record and exits nonzero, including under `python -O`.

Its baseline is empirical: everything the seven accepted Boylston SwissSys
packages contain is accepted, including all-character descriptors (dates as
C(8)), a 26 or 126 header year byte, nonzero reserved header bytes, blank event
IDs, `S_SCH_LVL`, `S_GP_PTS` and `D_STATE`, loose time-control spellings, round
robin type `R`, SwissSys double-game codes and `X0`/`F0`/`Z0` cells with no
opponent. It stays strict about exact filenames, the field list and widths,
header and record lengths consistent with the file size, the EOF byte, section
and player counts, section-local pairing numbers 1..`S_LST_PAIR`, reciprocal
opponents, results and colors, member-ID shape, calendar dates and ASCII. Some
strictness is defensive rather than proven: field order, colors on played
games, `U0` in padding columns and `S_R_SYSTEM` limited to `R`/`D`/`Q`. The
negative tests corrupt these properties and require the specific expected
rejection.

This narrow consumer supports non-FIDE, non-Grand-Prix output only. Rejecting
another program's output here is not evidence that US Chess rejects it; it
stresses our output and does not emulate undocumented MUIR internals. The
general-purpose `dbfread` check and source-event oracle remain separate: a
format reader alone cannot detect two mutually consistent results that both
differ from the actual game.

## Mixed-round fix and real-file evidence

The detail file now has columns through the largest section's round count.
`S_TOT_RNDS` retains each section's own count; shorter sections' unused cells
contain `U0`. The importer discards those padding cells instead of counting extra
rounds or byes. Both section orders are tested to prevent accidentally choosing
the first section's count as the file-wide maximum.

On October 3, 2026, the existing Fall Equinox reconstruction exported as one
package with all three sections (4, 4 and 1 rounds). Both independent readers
passed. All **19 entries and 70 active result cells** matched the original
SwissSys detail records. This probe explicitly assumed non-scholastic `N` for
the source's blank classification, as the prior reconstruction did; it did not
change results or original files. Evidence is in ignored
`artifacts/dbf-full-event-check`, including the three DBFs, source-event oracle
and `mock-import.json`.

The [earlier source comparison](../research/notes/US_CHESS_REPORTING.md)
also checked the public rated standings. The files generated by Meow have not
been uploaded to MUIR. Local parsing, corruption rejection and semantic parity
are established for these cases; live portal acceptance remains unverified.
