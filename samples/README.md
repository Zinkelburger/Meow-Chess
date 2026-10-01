# Sample data

Synthetic people only; IDs and ratings are made up.

| File | Exercises |
|---|---|
| `sample_players.csv` | Basic `Name, US Chess ID, Rating, Club` roster (24 players, two unrated) |
| `swiss_open_36.csv` | `First Name` / `Last Name` columns, `USCF ID`, `Rtg`, `State` headers |
| `scholastic_teams.csv` | Low and `unr` ratings, school in a `Team` column (imported as club) |
| `headerless_quick_entry.csv` | No header row: name, ID, rating by position |
| `messy_import_errors.csv` | Five rejected rows, two duplicates skipped on import, quoting and whitespace |

## Ready-made events

`.meow` files are gitignored, so generate them:

    dart run tools/make_sample_events.dart

This writes to `samples/events/`:

- `fall_open_round3.meow`: two-section Swiss (Open, U1800), 4 rounds. Rounds 1–2
  are complete; round 3 is started with four boards unreported. It includes one
  withdrawal after round 2 and one requested round-4 half-point bye.
- `saturday_quads_finished.meow`: four quads, all three rounds played.

Open one with `flutter run -d linux -a samples/events/fall_open_round3.meow`.
Both events are marked practice and have a full revision history for Undo.
