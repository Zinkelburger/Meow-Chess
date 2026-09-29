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

## Expanded scope and archive validation

September 29, 2026 UTC: archived all 296 SwissSys navigation/sitemap pages; verified
592 HTML/text hashes. Recursive discovery recorded 309 URLs: 296 HTTP 200, nine
HTTP 404 obfuscated contact links, four product-site robots exclusions. No listed
documentation URLs are missing. One article asset returned HTTP 200.

Generated a 296-row page ledger and checked candidate references against 67 unique
capability IDs. Candidate routing is research triage, not completed feature extraction.
Both new research scripts passed Python syntax parsing; all 59 local Markdown links
in the expanded top-level planning corpus resolve (the ignored reference cache lives
in the main checkout). `git diff --check` passed.

The in-conversation UI concept was visually inspected in the browser. Changing a
sample result updated missing-result count and standings; section navigation,
grouping preview and report view were exercised. It is a planning mockup, not a
Flutter app, pairing implementation or usability study. No production code added.

## TD flexibility specification refinement

Promoted basic player transfers and section combination to first-release scope;
added direct player editing, participation actions, effective-round transitions
and seven P0 requirements (D01–D07). Checked all 55 local links in README and docs
and `git diff --check`. Planning/documentation only: no executable app changes or
new claims of tested tournament rules, printing or federation export compatibility.

## Official-duty evidence and result-entry contract

Checked the current US Chess TD hub, 2026 rulebook/updates links, TD FAQ, house-player
guidance, accessibility guidance, certification document and Safe Play hub. Read
the scholastic guide’s directing/registration/results discussion and planning/supply
checklists. Saved seven additional reference snapshots and extracted text; all
seven raw hashes and nonempty text files verified. Checked 76 local links across
README, docs, the duty note and research index; `git diff --check` passed.

Added duty-to-workflow traceability and a concrete numeric/WLD results-grid contract.
No app code or browser prototype was changed in this refinement. Keyboard behavior,
TD rehearsal, interpretation of exceptional rules and federation export paths remain
acceptance work for the future implementation; none is claimed tested here.
