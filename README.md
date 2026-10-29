# Meow-Chess

A tournament director's workspace for chess events: pairings, results,
standings, prizes, printing and the US Chess rating report. Offline first,
US Chess first, with FIDE-rated sections too. Free software (AGPLv3).

## Get it

- **In a browser:** https://chessautoprep.com/meow-chess/ (events stay in the
  browser; download a `.meow` copy to keep or to open on the desktop).
- **Desktop, Linux and Windows:** installers and portable bundles on
  [Releases](https://github.com/Zinkelburger/Meow-Chess/releases). Every
  package opens `.meow` files on double-click; the portable zips offer to set
  that up on first launch.

## What it does

- Swiss, quads, round robin, Scheveningen, Holland, knockout, ladder and
  bughouse sections, each with its own time control, rules and prizes.
- US Chess Swiss pairings validated against a club's archive; FIDE Dutch
  pairings through BBP Pairings for FIDE-rated sections (desktop only).
- Results by keyboard: click a cell, type 1, 0 or D, and move on. One-key
  forfeits, corrections that show their consequences, full Undo and
  a History of every change.
- Rosters from CSV or TSV files, pasted tables and club registration pages,
  with a spreadsheet-style import window. US Chess ID checks and name search
  against the official member records.
- Printing: pairing sheets, player lists, standings and
  crosstables, each section on its own page, on a saved printer.
- Reports: standings with US Chess and FIDE tie-breaks, an Awards board that
  settles trophy ties by the tie-breaks, prize reports, the three-file US Chess
  DBF rating report, and TRF26 for FIDE.
- Durable events: one SQLite file per event, backups after every round, and
  recovery from an interrupted session.

## Status

Meow-Chess is a working pilot, not a finished product. Its rating reports pass
independent format checks and match previously accepted reports, but no report
has yet been accepted by the US Chess portal from this app, and an experienced
TD should still review Swiss pairings. [Implementation status](docs/IMPLEMENTATION.md)
and [release qualification](docs/TESTING.md) say exactly what is and is not
verified. Please report problems in
[Issues](https://github.com/Zinkelburger/Meow-Chess/issues).

## Documentation

[docs/README.md](docs/README.md) indexes everything: how to run a tournament
day, the workspace guide, the rules each format follows, the file formats, and
the research behind them. Release notes are in [the changelog](docs/CHANGELOG.md).

## Build it

With Flutter installed:

```
flutter pub get
flutter run -d linux        # or -d windows, -d macos
flutter test
```

[Developing](docs/DEVELOPING.md) covers the CI gate, the release tags, the
browser build and desktop integration.
