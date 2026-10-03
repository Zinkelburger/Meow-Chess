# Diagnostic logs

Meow-Chess records operation starts, results, and error stack traces in the
console and a local `logs/diagnostics.log` file automatically on every launch.
Logging is always on: no setting, export, or running terminal is required. The
UTF-8 text file appends across launches and can be opened in any text editor;
stack traces appear on separate indented lines. Open **Help → Export diagnostic
log** only to save a copy, or copy the displayed log path. Nothing is uploaded.

For example:

```text
2026-10-03T18:30:00.000Z ERROR import website roster — failed
  selected: 24
  Error: ...
  Stack trace:
    #0 ...
    #1 ...
```

The log lives under the platform application-support directory supplied by
`path_provider` on Windows, macOS, and Linux. When `MEOW_DATA_DIR` is set, that
directory is used instead. Logs rotate at 2 MiB and retain one previous file;
export includes both. Logs can contain local paths, event identifiers, and
player names in save-action descriptions, so review them before sharing.

Website imports record fetch counts, selected changes, save revisions, and any
exception with its full stack. USCF refresh records totals and failed player
lookups. The application also records uncaught Flutter and asynchronous errors.
A log write failure never prevents saving a tournament. No full rosters, provider
responses, or API-key headers are intentionally logged; source URL context drops
credentials, query parameters, and fragments.

For a failed import, export the log after the failure and include which button
was clicked. `fetch website roster`, `import website roster`, and `save event`
entries distinguish a network/parser failure from validation or storage failure.
A source-code hot reload can leave old in-memory objects after structural
changes; fully restart the development app before reproducing those failures.
