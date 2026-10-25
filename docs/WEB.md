# The browser version

Meow-Chess also runs in a browser, at **https://chessautoprep.com/meow-chess/**.
It is the same Flutter app as the desktop one, built for the web, so the
workspace (players, pairings, results, standings, prizes, reports) is the same
code and looks the same. It is a static copy: the Chess Auto Prep website serves
the built files, and nothing runs on a server except one small fetch function.

> **Keep the website's copy current.** The site does not build Meow-Chess. It
> serves whatever was last copied into Chess-Auto-Prep, so a new feature or fix
> here does not reach chessautoprep.com until someone syncs it (see
> [Updating the website](#updating-the-website)). Sync after any release, and
> after any change a TD would notice. `meow-build.json` on the site
> (https://chessautoprep.com/meow-chess/meow-build.json) names the commit it was
> built from; compare it with `git log -1` here.

## What is different in the browser

| Desktop | Browser |
| --- | --- |
| Each event is a `.meow` file you choose a place for | Events are kept in this browser (IndexedDB) and listed on the start screen. **Download** on the start screen, or **Download copy** under Backups, saves a `.meow` the desktop app opens; **Upload event** brings one in (including one saved by the desktop app). |
| Backup folder copies after each round | No folders. The Backups panel and the status bar say to download a copy instead. Clearing the browser's site data deletes the events. |
| Save dialogs for reports, DBF and TRF exports | Downloads. The US Chess rating package is one `.zip` (the three DBFs and `manifest.json`); the FIDE report is a `.zip` of TRF files. |
| FIDE-rated sections pair with BBP Pairings (native C++) | Not available yet: pairing a FIDE-rated section says to use the desktop app or pair by hand. US Chess Swiss, quads, round robins and the other formats pair as on desktop. |
| FIDE rating list download and lookup | Not available (a 45 MB list indexed on disk). Enter FIDE ratings by hand. |
| Web roster import, US Chess rating lookups | The same, through the site's fetch function (below). |
| Several windows | One tab at a time: a second tab says Meow-Chess is open elsewhere, because two tabs would overwrite each other's copy of an event. |

Printing uses the browser's print dialog. Pairing runs on the page's own thread,
since browsers have no isolates; a large section can pause the page briefly.

## How it works

- **Entry point.** `lib/main_web.dart` replaces the desktop start screen (file
  pickers, recent files) with one over the browser's stored events, then opens
  the same `Workspace` the desktop app uses.
- **Storage.** `package:sqlite3`'s WebAssembly build over an IndexedDB file
  system (`lib/infrastructure/sqlite_platform_web.dart`), so
  `SqliteEventRepository` is unchanged apart from where files live.
  `sqlite3.wasm` is fetched by the build script, pinned to the `sqlite3`
  version in `pubspec.lock` and checked against a SHA-256. Uploaded desktop
  events are switched from WAL to rollback-journal mode in their header, since
  the browser's SQLite has no shared memory for WAL.
- **Native-only code** has a web stand-in chosen by conditional import:
  `publish_file.dart` (atomic file publication), `engine/bbp_pairings.dart`
  (FIDE Dutch engine) and `browser_download.dart` (downloads; never called on
  desktop). Elsewhere `kIsWeb` picks the download path or hides folder-only
  controls.
- **Other websites.** US Chess, FIDE and club sites send no CORS headers, so a
  browser page cannot read them. Every `http.Client` the app creates is a
  `ProxyClient` (`lib/infrastructure/proxy_client.dart`), which sends requests
  to `/meow-chess/fetch?url=…`. That is a Cloudflare Pages Function in
  Chess-Auto-Prep (`python/twic-position-finder/frontend/functions/meow-chess/fetch.js`).
  It fetches only HTTPS URLs on an allowlist (boylstonchess.org,
  beta.boylstonchess.org, ratings-api.uschess.org, ratings.fide.com), forwards
  only `Accept`, `Content-Type` and `X-Api-Key`, and returns redirects without
  following them, as the desktop app does. A club website not on the list fails
  in the browser with "could not read"; add its host to the function's
  allowlist (and its roster source here) to support it.

## Building

```sh
python3 scripts/build_web.py
```

builds `build/web` for `/meow-chess/` with CanvasKit served alongside the app
(not from Google's CDN) and writes `meow-build.json` (commit, `git describe`,
whether the tree had uncommitted changes, build time). The first visit
downloads about 13 MB (less once Cloudflare compresses it); browsers cache it
after that.

To try it locally, serve `build/web` under `/meow-chess/` (for example with the
Chess-Auto-Prep site's `npx wrangler pages dev dist` after syncing and building
the site, which also runs the fetch function).

## Updating the website

From this checkout, with Chess-Auto-Prep checked out beside it:

```sh
python3 scripts/build_web.py --site ../Chess-Auto-Prep
cd ../Chess-Auto-Prep
git add python/twic-position-finder/frontend/public/meow-chess
git commit -m "Update Meow-Chess on the website to <describe>"
git push   # then deploy the site as usual (Cloudflare Pages)
```

`--site` replaces `frontend/public/meow-chess/` wholesale. Build from a
committed tree, so `meow-build.json` names a real commit. If you change what the
app fetches from other sites, update the fetch function's allowlist in the same
sync.
