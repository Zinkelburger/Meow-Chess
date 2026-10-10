# BBP Pairings (vendored)

The FIDE Dutch pairing engine for FIDE-rated Swiss sections.

- Upstream: https://github.com/BieremaBoyzProgramming/bbpPairings
- Commit: `8f9e3c5ffdc4d7a08a33d31c6fb49b4e7acef4d5` (v6.0.0-5-g8f9e3c5,
  30 July 2026): v6.0.0 (the 2025 Dutch rules, effective February 2026,
  and TRF-2026) plus TRF26 record 162 and 192 parsing fixes.
- Licence: Apache-2.0 (`LICENSE.txt`, `Apache-2.0.txt`); shipped in the
  app's licence page from `assets/licenses/LICENSE-bbpPairings.txt`.

`src/` is upstream's source, unmodified. `meow/meow_bbp.cpp` is Meow-Chess's
C entry point: the `--dutch input -p` path of `src/main.cpp`, reading the
tournament from memory. `hook/build.dart` compiles both (without `main.cpp`,
the random tournament generator or the checker) into the dynamic library
behind `lib/engine/bbp_pairings.dart`.

To update: replace `src/` and the licence files from a new upstream commit,
update the commit above, and run `python scripts/check_fide_trf.py` and
`flutter test test/engine test/domain/fide_test.dart`.
