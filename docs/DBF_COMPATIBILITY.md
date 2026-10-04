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

This generates eight synthetic packages, checks their contents with `dbfread`,
compares every active result with its source event, runs the existing seven
validator corruption controls, and runs 51 mock-importer tests. CI runs the same
checks on Linux and Windows using `--validate-only` after its Flutter test step
generates the files. No account or network is needed after dependency setup.

The packages exercise 1, 3, 12 and 32 rounds; mixed round counts with the short
section first or last; independent side-game entries for the same members;
1,000 players and four-digit opponent numbers; chronological quad reporting;
regular, dual and quick categories; unrated players; leading-zero IDs; maximum
text widths; accent folding; multi-day dates; wins, draws, losses, forfeits and
full/half/zero byes. Generated files live under ignored `artifacts/dbf-contract`
and `artifacts/dbf-importer`. These synthetic tournaments must not be submitted.

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

It assumes exact filenames, field order, types, widths, ASCII bytes, zeroed
reserved header/descriptor bytes, left-justified character numbers, undeleted
records, exact file lengths and EOF markers. It checks section/player counts,
event links, section-local pairing numbers, reciprocal opponents/results/colors,
calendar dates, IDs, and nonplayed-result codes. The negative tests corrupt
these properties and require the specific expected rejection.

This intentionally narrow consumer supports Meow's non-FIDE, non-Grand-Prix,
chronological Swiss output. It is stricter than the published format in several
respects: colors are mandatory, result spelling is compact, and optional DBF
variations are rejected. It follows the published `D(8)` date descriptors, so it
deliberately rejects the `C(8)` date variant observed in the supplied SwissSys
files. Rejecting another program's output here is not evidence that US Chess
rejects it. These assumptions stress our output, not emulate undocumented MUIR
internals. The general-purpose `dbfread` check and source-event oracle remain
separate: a format reader alone cannot detect two mutually consistent results
that both differ from the actual game.

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
