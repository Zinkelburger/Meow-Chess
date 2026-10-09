# Boylston tournament rehearsal — October 3, 2026

**Pairing comparison (2026-10-09):** with the US Chess Swiss engine
(`uscf-swiss-29-v1`) in place, `tools/compare_pairings.dart` re-paired every
posted Swiss round of the seven replayed events from the position before that
round (the same field, requested byes and withdrawals) and compared the result
with what SwissSys posted:

```sh
dart run tools/compare_pairings.dart artifacts/<rehearsal-run>/artifacts/<rehearsal-run>/*.meow
```

Over the 49 Swiss rounds (240 boards) the engine reproduced 27 rounds exactly
and 172 of the 240 boards; 134 of those 172 had the same colors, and 13 of the
16 full-point byes went to the same player. Every difference was read against
the rulebook; none is a rule violation by the engine, and the report lists each
one with the engine's own explanation. The recurring causes:

- **Ladders** (April and May, `G45`/`G90`) are not Swiss-paired at all, so
  their rounds are expected to differ and are excluded from the counts above.
- **Late entrants:** SwissSys paired a round-1 field of 28 and added two late
  entrants as their own board; given all 30 at once the engine splits the halves
  at a different place (Spring Festival Open round 1). Both follow 28J.
- **Rating ties and unrated players** are ordered by pairing number (the
  section list), which now matches SwissSys where it mattered.
- **Color switches within the limits:** the engine applies the 29E5e
  preference (a transposition inside 80 points beats an interchange; otherwise
  the smaller switch), while SwissSys sometimes made the larger transposition
  (Rated Friday Night Blitz round 4, Tornado Open round 3).
- **Odd-player choice:** the engine drops the lowest-rated rated player
  (29D1a) where SwissSys dropped an unrated player or a higher-rated one
  (Blitz round 5, Spring Festival U1850 round 5).
- **Byes:** the engine never gives the bye to a player who already had a
  half-point bye (28L4) or to anyone outside the lowest score group (28L2);
  Tornado #147 U1800 rounds 3–4 gave it to a player on 1 point instead of the
  player on 0, which reads as a director's choice.
- **One historical repeat:** Blitz round 6 paired Kai Solter and Vikram
  Manisankar, who had met in round 3; the engine refuses that pairing (27A1).

The comparison fixed four engine defects before the counts above were taken:
double-game rounds no longer carry color history, a floater's color switch
may not force extra drop-downs (29D2), a lower group that cannot be paired now
pulls one more player from the group above instead of falling back to a
global search, and half-point byes recorded in earlier rounds count for 28L4.
The archive's DBF exports were re-run the same day with the same result as
below (zero detail differences in every single-game section; the double-game
sections differ only in how the two legs are serialized, which US Chess
accepts either way).


**Second follow-up (same day):** all seven events now export as one package
each, including Rated Friday Night Blitz and the May Ladder double-game section.
Compared with what US Chess actually rated (public API), Meow's reports have no
difference that SwissSys's own reports lack; see
[DBF compatibility](DBF_COMPATIBILITY.md#dbf-export-compatibility-checks). The
Spring Festival round-three “inconsistency” below is not one: 2C forfeit codes
carry no opponent, and US Chess rated those two cells as a full-point and a
half-point bye, which is what Meow writes.

**Follow-up:** [DBF compatibility work](DBF_COMPATIBILITY.md) removed the
mixed-round export restriction. The reconstructed Fall Equinox event now exports
as one package, with 19 entries / 70 active result cells matching SwissSys.
The blocker table below records the earlier rehearsal's state; its unequal-round
blockers are superseded. Other listed blockers remain.

The new MCP server ran seven supplied events through the application controller,
saved `.meow` databases, entered 360 games, exported reports, and reopened the
saved files. Six events replayed completely. All **175 entries in completed
sections** match their final native SwissSys scores. Spring Festival Open stops
at an inconsistent round-three source record; its remaining results were not
invented. This is compatibility evidence, not a club-readiness sign-off.

The populated HTML standings contribute **123 matching player-score checks** at
the corresponding saved checkpoints. April's April 16 wallcharts contribute
**46 matching cumulative-score checks**. Earlier HTML is compared with that
round, not with a later month's final score.

| Event | Entries / sections | Replay | Whole-event DBF blockers |
|---|---:|---|---|
| March Quads | 47 / 11 | All 3 rounds; every score matches | One missing player state |
| Tornado #147 | 28 / 2 | All 4 rounds; every score matches | One missing player state |
| April Ladder | 25 / 2 | 4 and 6 rounds; every score matches | Unequal round counts; six missing states |
| Fall Equinox Swiss | 19 / 3 | 4, 4 and 1 rounds, including side game; every score matches | Unequal round counts |
| May Ladder | 14 / 2 | 3 double-game and 4 single-game rounds; every score matches | Double games, unequal round counts, five missing states |
| Rated Friday Night Blitz | 19 / 1 | All 6 double-game rounds; every score matches | Blitz/double-game export; three missing states |
| Spring Festival | 54 / 3 | U1850 and side game complete; Open stops after round 2 | Source inconsistency; incomplete Open; unequal round counts; 52 missing states; compact `G90d5` notation rejected |

Double-game SwissSys snapshots preserve aggregate match results, not reliable
chronological per-leg outcomes. The rehearsal uses an explicitly marked
realization with reversed colors and the same opponent and total. This proves
aggregate scoring, including the two-point allocated bye; it does **not** prove
which blitz game was won first. The May double-game totals have the same limit.

## Actual DBF comparison

The full event preflight is preserved. To compare valid data without guessing
missing states or bypassing checks, the harness also explicitly exported each
completed section as its own package. **16 section packages, covering 92 player
rows, have zero differences in the compared detail fields**: member ID, rating,
state, pairing number, opponent, result and color. They cover April G90; all
three Fall Equinox sections; March Quads 1–10; May G90; and Tornado Open.

Section numbers are remapped to 1 for those separate packages; whitespace inside
round cells is ignored. Player-name presentation and internal event IDs are
excluded from the detail equality claim. Separate packages are comparison
artifacts, not instructions to submit one original event as many events.

Metadata differences remain and are listed field-by-field in the JSON:

- Meow derives dual rating for G/60 d5, while the reference says regular.
- Meow serializes quads as round-by-round Swiss; the reference uses round-robin
  section type. Results/opponents still match.
- Time-control spelling is normalized. Program identifiers and internal event
  IDs differ. Meow uses explicit non-scholastic and zero Grand Prix values
  where some reference cells are blank.
- Assistant and other TD IDs from the reference are not represented by the
  current event metadata, so those exported fields are empty.

The archive itself contains empty player-state cells. Meow's current preflight
requires states; it does not infer Massachusetts merely because the event was
held there. This is an interoperability discrepancy for the separate DBF-format
review to resolve. No identity lookup, state assumption, upload or submission was
performed during the historical reconstruction.

## Source discrepancies

Five HTML files are empty. Queens #6 has an empty wallchart and no reference DBF;
BBQ and Blitz has no HTML or reference DBF. Those two events were inventoried but
not included in this seven-event reconstruction.

Backup filenames are not authoritative. Spring Festival `Side Game.S5C` contains
31 Open players; the actual side game is in `Side Game.S1C` with two players.
The harness rejects the former using the reference section roster count. April
Ladder also contains an unrelated May Quads tournament and quad files; these are
not counted as extra April sections.

Spring Festival Open round 3 gives one player an `X` forfeit win against a named
opponent, while that opponent has a `Z`, half-point, no-opponent record. Those
are not complementary results. The user did not confirm how it should be
resolved; the replay preserves the evidence and stops before that round.
Separate tests verify normal forfeit wins and independent half-point byes.

The Spring Festival side-game HTML has only one row and abbreviates its player's
first name differently from the native roster. The harness deliberately does
not resolve that identity by fuzzy name matching; native side-game scores match.

## Features added from the rehearsal

- Shared controller commands for Flutter, standalone CLI and 24 local MCP tools;
  revision checks, validated arguments, persistent history, confined output paths.
- Section time-control overrides in the model, Section settings, printed reports,
  rating preflight and individual section DBF fields.
- Shared places by score as the default, with **Use tie-break rankings** in Event
  details. The setting travels with the event; the screen and printed standings
  agree. Game scores and rating-report outcomes are unaffected.
- Separate section entries for the same person, with independent scores and
  retained identity. Accidental duplicate registration remains blocked.
- **Sections → Pair a side game…** and MCP `pair_side_game`: choose arbitrary
  opponents, create separate entries, and keep main scores unchanged. A resolved
  main-game forfeit frees that player while other main-section games continue.
  Concurrent unresolved games for one person are rejected atomically.
- Correct two-point allocated byes in double-game sections.

The side-games section is excluded from automatic Swiss pairing. Multiple
disjoint games can share a batch; another appearance by the same person requires
that batch to finish. Native SwissSys import is currently a rehearsal script,
not a GUI import capability. Standings ranking is an event setting, not yet an
application-wide preference. Missing metadata, mixed-round DBF output, blitz and
double-game DBF output remain work before all these events can be submitted.

## Artifacts and checks

Private sample-derived files stay in the ignored tree:

- `artifacts/boylston-validation-2026-10-03/comparison.json`: detailed results,
  preflight blockers, source choices and field-level DBF differences.
- In that same directory: seven `.meow` files, full-event CSV/text/JSON exports,
  separately scoped section exports, and per-event MCP JSONL transcripts.
- `artifacts/mcp-synthetic-2026-10-03`: generated quad, seven-player Swiss and
  five-player double-game rehearsals. Quad and Swiss produced all three DBFs;
  double-game output correctly remained blocked. All identities there are
  explicitly synthetic and must never be submitted.

Five standalone process tests cover MCP handshake and stdout, real SQLite
commands, stale requests, invalid-input atomicity, path traversal and symlinks,
exports, history/reopen, double games and the forfeit-to-side-game workflow.
Eight new application/UI/export tests pass. Static analysis and Linux release
build pass. The full shared-checkout suite ran 251 tests: 248 passed and three UI
checks failed while other work on result correction/history was changing. Those
failures are recorded in the local full-suite log. A targeted recheck of those
three files passed 36 tests and left one failure: the history panel at 1280×720
with 200% text. This report does not claim a clean full release gate.

See [setup, tool workflow and reproduction commands](TOURNAMENT_AUTOMATION.md).
