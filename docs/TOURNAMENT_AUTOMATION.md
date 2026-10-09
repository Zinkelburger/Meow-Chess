# Tournament automation

Meow Chess has a local stdio MCP server and a JSON-lines CLI. They use the same
commands, SQLite files, history, pairing engine, standings and report encoders
as the desktop app. Flutter notifications wrap a platform-independent controller;
the command adapter does not require a display server.

Build on this workstation:

```bash
scripts/ci.sh with -- dart build cli --target=tools/tournament_mcp.dart --output=build/tournament-cli
python3 scripts/test_tournament_mcp.py
```

Use `dart build cli`, not `dart compile exe`: SQLite needs the bundled native
asset. Keep `bundle/bin` and `bundle/lib` together. On another workstation run
the same Dart build command with its resource limits.

The repository's `.mcp.json` registers `meow-chess` for Claude Code when launched
in this checkout. It runs `scripts/tournament_mcp.sh` and confines files to
`artifacts/mcp-events`. Claude currently reports “Pending approval” for this project server. Open `claude`
in the checkout and accept its one-time project MCP prompt to enable it.
No user-wide Claude configuration or API credentials are needed or changed.
For another client, configure an absolute path to the wrapper and optionally
pass a different data-directory argument. The wrapper resolves the repository
from its own location, and stdout contains protocol messages only.

Example requests to an MCP client:

- “Create a practice event called Saturday Quads, dated 2026-10-03, in saturday.meow. Register these players, show me the quad groups and pair round one.”
- “Read the current event and record a draw on board 2.”
- “Mark this main game as a white forfeit win, then pair these two people in Side Games.”
- “Export the standings and run rating preflight. Explain any blockers.”

The server implements [MCP's 2025-06-18 lifecycle and tools protocol](https://modelcontextprotocol.io/specification/2025-06-18/server/tools).
It advertises that version during initialization. It is local stdio, not a
network listener or a live control channel into an already-open GUI window.

## Workflow and tools

`create_event` requires a filename, name and date; it defaults to practice mode.
`open_event`, `get_event` and `close_event` manage the current file. Close it in
one application before opening it in the other; SQLite retains exclusive ownership.

`update_event` and `create_event` also take `assistantTdId` and `otherTdIds`
(comma-separated US Chess IDs); both go into the rating report. A practice
copy stays one: `update_event(practice: false)` on it is refused with a reason.
Time controls are checked when they are set, not only at export.
`update_section` edits a section's name, time control, planned rounds or first
board.

`add_players`, `update_player`, `create_section`, `make_quads`, `move_players`,
`add_section_entry` and `reserve_bye` handle registration and sections.
Section creation accepts a time-control override and `sideGames` flag.
Ordinary registration still rejects accidental duplicate US Chess IDs.
`add_section_entry` explicitly preserves a person's identity while starting a
separate score in another section. It works before the target section begins.

`propose_pairings` returns a preview and proposal ID; `post_pairings` commits
that proposal. A change to the event invalidates it. `post_manual_round` accepts
explicit games and byes, with a reason; it does not invent results. `start_round`
and `record_result` use the same commands as the GUI. `pair_side_game` chooses
arbitrary opponents, creates separate entries as needed and posts an independent
game. Side sections are excluded from automatic Swiss/quad pairing.

Mutation tools require `expectedRevision` from the last read/response. Invalid
arguments, stale revisions, overlapping active games and storage failures are
reported as tool errors. Scores and bye values are integer half-points: 1 means
half a point, 2 means one point, and an allocated double-game bye awards 4.
Sonneborn–Berger values in the structured standings are quarter-points.

`standings`, `rating_preflight`, `export_event`, `backup_event`, `undo` and `redo`
complete the workflow. Exports produce event JSON, standings CSV, a text
crosstable and preflight JSON. The three DBFs and a `manifest.json` (marked
unverified until a TD validates the upload) are included only when the normal
rating preflight passes. `rating_preflight` and `export_event` list blockers
separately from `advice` that US Chess does not require, such as missing player
states. Exports are written to a hidden staging folder and renamed into place. An optional `sectionId` exports one section as an
explicitly separate package; this does not bypass that section’s preflight. Exports never upload or submit anything. Export and
backup destinations must be new; traversal and symlinks outside the chosen
root are rejected. Do not use the sample archive as the output root.

For shell automation, run the bundle with `--cli-root DATA_DIRECTORY` and feed
one object per line: `{"tool":"get_event","arguments":{}}`. Responses are JSON
objects with `result`, or `isError` and text content. This has the same tool
schemas and revision checks as MCP. EOF closes the event safely.

## GUI equivalents

- Event details → **Use tie-break rankings**: off by default, so equal scores
  share a place; on uses Buchholz, then Sonneborn–Berger. This is saved with the
  event, including reports, rather than depending on another computer's settings.
- Section settings → **Time control (blank uses event default)**: ladders can
  store different controls. Each section's rating category and printed packet
  use its own effective control.
- A second entry for the same person in another section (a ladder) keeps the
  original entry. It is available through the `add_section_entry` automation
  tool; the player card no longer offers it.
- Sections → **Pair a side game…**: choose White and Black. Record the main-game
  result/forfeit first if either person is still playing. Main and side scores
  remain independent. Multiple disjoint games can share a side-game round;
  repeat appearances need the current side-game round to finish first.

These additions do not claim US Chess acceptance or certified Swiss pairing
parity. Remaining export restrictions and real source discrepancies are listed
in [the Boylston rehearsal](BOYLSTON_REHEARSAL.md).

## Reproduce the archive rehearsal

```bash
python3 -m venv /tmp/meow-boylston-venv
/tmp/meow-boylston-venv/bin/pip install xlrd beautifulsoup4
scripts/ci.sh with -- /tmp/meow-boylston-venv/bin/python scripts/rehearse_boylston.py \
  "$HOME/Downloads/Sample Boylston Tournaments" artifacts/new-boylston-run
python3 scripts/rehearse_synthetic.py artifacts/new-synthetic-run
dart run tools/compare_pairings.dart artifacts/new-boylston-run/artifacts/new-boylston-run/*.meow
```

The last command re-pairs every posted Swiss round with the engine and prints,
per round, how many boards, colors and byes match the historical pairing and
the engine's explanation for each board that differs. Its findings are
summarized in [the Boylston rehearsal](BOYLSTON_REHEARSAL.md).

Output directories must not already exist. The harness inventories empty HTML,
selects completed snapshots using roster counts, checks HTML checkpoints,
registers real entries, posts manual pairings, enters results one game at a time,
exports and reopens each database. JSONL transcripts preserve every MCP request
and response. Double-game snapshots only establish match totals: their per-leg
realization is explicitly marked inferred and must not be treated as historical
chronology. Native-file parsing is an archive rehearsal utility, not a general
SwissSys import feature in the GUI. All private sample-derived artifacts are
under the ignored `artifacts/` tree.
