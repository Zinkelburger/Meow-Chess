# Meow-Chess and BBP Pairings

This comparison covers the current BBP documentation and Meow-Chess's implemented
features. BBP is a command-line pairing engine, not a tournament-management app.
Its TRF format can carry metadata beyond the fields its pairing engine uses.
Features were implemented independently; no BBP source or dependency was added.

| Area | BBP Pairings | Meow-Chess now |
| --- | --- | --- |
| Swiss systems | FIDE Dutch (2026-effective rules); its README describes the older Burstein implementation as flawed | US Chess-focused Swiss pilot; no FIDE Dutch or Burstein mode |
| Acceleration | Explicit virtual-point inputs; legacy Burstein defaults | Custom per-player schedules plus previewable top-half +1 presets for one or two rounds |
| Other formats | Documented as a Swiss engine | Quads, round robin, and two-game rounds already available |
| Registration/editor | File-based input, no player-management UI | Editable player panel, registration import, check-in, withdrawal, requested byes, house players, restrictions, private notes, and US Chess lookup |
| Additional player metadata | TRF includes title, FIDE rating/ID, federation, birth date, sex | Added title, reference FIDE rating/ID, federation and private birth date; also added school/grade and exposed existing club editing. No sex field added |
| Team management | No documented team roster/board-lineup or team-match management workflow | Assign team labels; now report best-N or all-member individual scores with member contributions |
| Team matches | TRF's ability to describe team events does not establish BBP team-match support | Still missing team-versus-team pairing, fixed boards, substitutes, and match-point standings |
| Diagnostics | Checklists, pairing checker, seeded generator | Saved-input checklist/replay and seeded practice events from the preceding work |
| Interchange | TRF-2026 and older TRF inputs | Meow event files and roster CSV/TSV; no TRF import/export yet |
| Rating submission | No US Chess DBF exporter documented | US Chess 2C DBF export with local byte/source checks; portal acceptance remains unverified |

## Acceleration scope

The new presets add one pairing-only point to the highest-rated half of the
current non-withdrawn roster, rounded down, for the selected first one or two
rounds. Later rounds receive zero. Ratings tie by name and stable entry ID.
A preview lists the selected players. Requested-bye players stay in the initial
ranking. Scores, awards, and rating results do not receive these points.

This is an accessible setup for the existing virtual-point Swiss pilot. It is
not a newly certified engine, the FIDE Baku algorithm, or an implementation of
every US Chess accelerated-pairing exception. Custom schedules can still be
entered explicitly. The selection does not silently change after late entries
or rating edits; review it before posting the first round.

## Team scope

Best-two totals can support a mixed-doubles-style leaderboard; best-four totals
can support school/club standings within an individual event. The report does
not check event-specific eligibility or award prizes automatically. It shows its
policy, counted/un-counted contributions, and shared places on tied totals.
Section totals remain separate, so scores under different section scoring or
schedules are not silently combined. True team-match events remain future work.

## Evidence

- [BBP README](https://github.com/BieremaBoyzProgramming/bbpPairings/blob/master/README.txt): supported systems, scope, acceleration, interchange, checking, and simulation.
- [Official FIDE TRF26 specification](https://handbook.fide.com/files/handbook/TRF26.pdf): player and team record fields. A file format's fields are not proof of an engine's team capabilities.
- [US Chess 2C format](https://secure2.uschess.org/TD_Affil/fileformat.php): the separate contract used by our DBF exporter.
- [Implementation details](IMPLEMENTATION.md) and [testing record](TESTING.md): local behavior and limits.
