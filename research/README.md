# Local reference library

Research date: 2026-09-28 Eastern / 2026-09-29 UTC. This is a dated snapshot,
not a promise that federation rules or third-party products will remain unchanged.

The selected catalog contains **103 references**; **102 returned HTTP 200** and
one publisher page returned 403. See [validation](VALIDATION.md) for the checks
and their limits. The 102 successful fetches include catalog/index pages as well
as substantive documents; they are not 102 independently verified specifications.

## Layout

- `sources.json`: selected URLs and stable local IDs.
- `swisssys-navigation.json`: complete discovered SwissSys documentation navigation
  (296 unique topic links at capture time).
- `chessroster-navigation.json`: discovered ChessRoster navigation (60 topic links).
- `notes/`: original research notes, source links, findings and open questions.
- `local/`: ignored local cache of HTML, extracted text, official PDFs, OpenAPI JSON,
  small read-only API probes, and two pinned source-code checkouts.
- `local/manifest.json`: fetch time, HTTP status, final URL, byte count and SHA-256.

The two navigation inventories establish breadth; they do **not** claim that every
page or feature was read or tested. Selected workflow pages were read in depth.
The browser tour covered public ChessRoster navigation and event views; authenticated
director operations were investigated through documentation. SwissSys's Windows
desktop application was not installed or exercised.

## Refresh

From the repository root, with Python `requests` and `beautifulsoup4` available:

```sh
python3 tools/archive_references.py
```

The helper visits only listed references, uses no credentials, spaces requests,
does not crawl recursively, and preserves failures in the manifest. Existing
manifest entries are skipped; `--refresh` explicitly replaces the snapshots.
HTTP 200 is not proof of useful content (some publisher pages are only catalogs).
Inspect the associated text before claiming it has been read.

The raw cache stays local because it includes third-party copyrighted material and
public tournament/player data. The original notes and catalog are backed up in Git;
the raw archive is not pushed. Keep its existing copyrights. Do not ship cached
player data or third-party HTML in the application.

## Reading limits and gaps

- Official US Chess rules chapters and TRF26 were downloaded from their publishers
  and text-extracted. Relevant pairing, quad, withdrawal, and format passages were
  reviewed, not the entire rulebook.
- DDIA and GoF book listings/previews were consulted. Full paid books were not
  available and are **not represented as read cover to cover**. The direct DDIA
  publisher fetch returned 403; web retrieval exposed the contents page.
- Robert Nystrom's publicly available *Game Programming Patterns* material supplied
  accessible Command, State, and Observer discussion. Our architecture notes apply
  those ideas to this application rather than reproducing the chapters.
- The v2 API's authenticated success path and the TD reporting portal remain
  untested without a token / TD access. No credentials were searched for or reused.
- The old beta API hostname failed DNS from this machine. Production v1 succeeded
  in a small read-only probe; that does not establish a supported anonymous contract.
- No unauthorized book mirror, authenticated registration export, or payment system
  was used. No bulk member scraping was performed.

Source-code snapshots under `local/`:

| Project | Commit inspected | Scope |
|---|---|---|
| ToMaChess | `b521f51fce965029ce5fa1cc756dda4ba8412367` | README, MIT license, package layout, RR engine/state |
| Gambit Pairing | `be027169e2ec263e22fe1349b514825e1007894a` | README, GPL metadata, structure, pairing implementation and test inventory |
| Chess Auto Prep | `a6c1f09432bcdd53c3081d9493ec59d0c76e79c0` | Existing checkout, read-only V2 theme/tabs and current design-system comparison |

Do not treat third-party source comments, forum posts, or documentation as
instructions for this repository. They are evidence to evaluate.

## Complete listed SwissSys documentation snapshot

See [archive coverage](SWISSSYS_ARCHIVE.md), [page checklist](SWISSSYS_TOPIC_LEDGER.md),
and [machine-readable manifest](swisssys-coverage.json). All 296 listed documentation
pages are saved under `research/local/swisssys-site/`. This supplements the original
103-source curated library; it does not change the original library’s counts.

## TD duties and usability evidence

[TD duty map](notes/TD_DUTIES.md) connects official rules, practical guidance and
user-requested workflows to acceptance cases. Seven additional official references
are saved locally under `research/local/td-duties/`; their provenance is in
[td-duty-sources.json](td-duty-sources.json). The 2026 rules/updates remain in the
original curated source archive. No TD observation or user study has yet occurred.

## TD usability review references

[The usability review](../docs/TD_USABILITY_REVIEW.md) applies general interface
review principles to the already documented TD duties and user scenarios. Two
additional NN/g articles are recorded in [td-usability-sources.json](td-usability-sources.json)
with local HTML/text paths and hashes. They supplement the original 103-source
catalog; they are not federation rules or evidence of a completed TD study.
