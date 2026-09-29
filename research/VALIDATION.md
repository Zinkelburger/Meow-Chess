# Planning validation

Run on September 28–29, 2026. This verifies planning artifacts and a bounded
experiment, not a tournament application.

| Check | Result |
|---|---|
| Dart format and static analysis of `poc/quad_partition.dart` | Passed; no analyzer issues |
| Quad experiment with Dart 3.13.4 | Passed: 497 field sizes (4–500), four small-field rejections, four color choices |
| Synthetic ASCII crosstable | ASCII encoding, four player totals and six reciprocal games verified |
| Original planning Markdown links | 13 documents / 78 links checked in the main corpus; all local targets exist |
| SwissSys/ChessRoster documentation links | Matched against the captured navigation catalog |
| Source catalog and local manifest | 103 unique references, corresponding manifest entries and SHA-256 hashes checked |
| Reference downloads | 102 HTTP 200; DDIA publisher chapter request HTTP 403, retained as an explicit failed retrieval |
| Research archiver | Python syntax check passed; executed against the explicit source list |
| Whitespace | `git diff --check` passed |
| Chess Auto Prep references | Copied reference files match the inspected `a6c1f094…` commit; no source edits made by this task |

The source manifest records successful retrieval, not verification of every claim
on every page. Some publisher pages expose only a catalog/preview. The public
browser inspection and documentation review have different coverage; see the
[SwissSys notes](notes/SWISSSYS.md).

Read-only integration observations: production US Chess v1 member/history returned
200, unauthenticated v2 member returned 401, and the legacy beta hostname failed
DNS here. These observations do not establish a supported anonymous client contract
or authenticated latest-rating correctness.

Not run / not available: Flutter app build or UI tests (no app exists), competitor
desktop execution, authenticated organizer export, v2 authenticated success cases,
US Chess portal upload validation, native printing, FIDE conformance, and bughouse
rating calibration. These are named future acceptance gates, not passing checks.

The only executable Dart artifact is the isolated planning POC. There is no
`pubspec.yaml`, production `lib/`, platform scaffolding, database or pairing app.
