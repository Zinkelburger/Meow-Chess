# SwissSys reference archive: actual coverage

Snapshot completed September 29, 2026 UTC (September 28 Eastern).

## What is saved

**296 of 296 SwissSys documentation pages** listed in both the captured navigation
and the site's XML sitemap were retrieved successfully. No listed documentation
URL is missing. Recursive link discovery also ran until its bounded queue emptied.
Each successful page has raw HTML, extracted article text, title/headings, retrieval
time, response status, byte count and SHA-256 hashes. The snapshot contains about
786,000 characters of extracted text. One linked same-host article asset was saved.

The local reference library is `research/local/swisssys-site/` in this checkout.
Open [the local index](local/swisssys-site/index.html) for page titles and offline text.
The original HTML may still request online styles/scripts; this is a preserved
content reference, not a fully functional offline clone of SwissSys's website.

The tracked [coverage manifest](swisssys-coverage.json) records hashes, source links,
archive status and proposed feature mappings. The raw third-party content is ignored
by Git and stays locally; it was **not uploaded to the repository**. The reproducible
archiver and our own plans/checklists are committed and backed up. A fresh clone
requires rerunning the archiver to obtain its own local reference cache.

## Exact scope and exclusions

The crawler seeds were the 296 navigation links, 296 SwissSys sitemap entries, and
the current product/download pages. Traversal was bounded to:

- `https://docs.chessroster.com/swisssys/`
- `https://www.chessroster.com/swisssys` and its descendants

309 URLs were discovered: 296 successful pages, nine HTTP 404 contact-link targets
ending in `/obfuscated/`, and four excluded by the product site's robots policy:

- `https://www.chessroster.com/swisssys`
- `https://www.chessroster.com/swisssys/downloads`
- `https://www.chessroster.com/swisssys/download`
- `https://www.chessroster.com/swisssys/order`

The broken links were discovered from the pages, not guessed. Their response bodies
and statuses are retained. The product page was separately viewed through web
research; that does not make it part of the local mirrored archive. The site’s
`robots.txt` and sitemap are saved with the snapshot. External links are inventoried,
including tutorial videos and federation/engine sites; those sites and videos were
not recursively mirrored. Installers, account pages, authenticated screens, external
assets and unlinked/unindexed content are outside this archive.

Thus **all listed public SwissSys documentation is archived** is supported.
**The entire SwissSys/ChessRoster web ecosystem is mirrored** is not supported.

## What this proves about features

Archiving is complete within the documentation baseline; exhaustive feature analysis
is not. A help page can contain many independent options, and release notes can
reveal behaviors absent from menu headings. The [page checklist](SWISSSYS_TOPIC_LEDGER.md)
therefore leaves exhaustive extraction pending. The [full feature map](../docs/FULL_FEATURE_MAP.md)
is a broad product specification, not a completed line-by-line parity audit.

For a truthful parity claim, finish page-level extraction, fix the target SwissSys
version, produce acceptance fixtures and compare the supported behaviors against
an actual reference application. Mark upcoming/preview behavior separately. The
captured history calls 11.80.5 upcoming; it must not automatically become a claim
about the released application.

## Reproduce and inspect

Requires Python, requests and beautifulsoup4. From the Meow-Chess checkout:

```sh
python3 tools/archive_swisssys.py
python3 tools/index_swisssys_archive.py
rg -n -i 'quad|pending prizes|network mode' research/local/swisssys-site/*.txt
```

The archiver resumes successful cached pages, uses a single request stream and a
0.6-second delay, honors robots exclusions, never logs in or submits forms, and
records failed retrievals. There is a 1,000-page discovery bound. For a new snapshot,
use `--cache` with a new dated folder; preserve the original manifest for comparison.
The indexer verifies raw/text hashes before generating coverage. Its suggested
feature mappings use titles and must be reviewed; it never auto-marks a page tested.
