---
target: history menu + result correction flow
total_score: 19
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 3
target_identity: "file:/home/anbernal/Projects/Meow-Chess/lib/ui/history_panel.dart"
target_fingerprint: "sha256:58cf3bb9a9ad702b403c66fa9d176e246cdb0af62d70fe776a7a772181d2b19c"
target_path: /home/anbernal/Projects/Meow-Chess/lib/ui/history_panel.dart
timestamp: 2026-10-05T15-17-00Z
slug: lib-ui-history-panel-dart
---
Method: dual-agent (A: design review · B: detector + grep evidence)

Target: History panel (lib/ui/history_panel.dart) and the correction modal it launches (lib/ui/result_correction_dialog.dart)

## Heuristics: 19/40 (Poor)
1 Visibility 3 · 2 Real-world match 1 · 3 Control 2 · 4 Consistency 1 · 5 Error prevention 2 · 6 Recognition 2 · 7 Efficiency 2 · 8 Minimalism 1 · 9 Error recovery 2 · 10 Help 2

## Verdict
The content is TD-specific: change lines name the player, board and score change. The interface around it is a git client (lane graph, #ids, Transaction, operations, branch, Apply). The correction flow is a stock Material modal wizard. The detector has no Dart coverage, so its [] result is not a pass; grep confirmed AlertDialog at history_panel.dart:37 and result_correction_dialog.dart:159.

## Priority issues
- [P0] The correction flow and the multi-step restore review are modal AlertDialogs (result_correction_dialog.dart:17,159; history_panel.dart:37-95). This breaks the no-modal rule, and Esc or a scrim click discards the typed reason. Fix: a docked "Correct result" panel, with the restore review shown inline in the expanded History row.
- [P1] History uses git vocabulary and a git layout (history_panel.dart:299,370,442,462,532,562,603; painter 626-709). Rows lead with "#9 Current 11:12" and the titles are bold, flat and truncated. Fix: title first; time muted on the right; group by section and round; plain TD wording ("Go back to here", "2 undone changes (kept)"); a single timeline rail.
- [P1] The result picker is a field that looks editable but isn't (result_correction_dialog.dart:184-211). Clicking does nothing, keys are hidden, and typing "0-1" lands on 1–0. Fix: explicit [Alex Chen] [Draw] [Jamie Patel] [Forfeit ▾] buttons, with the keys shown as captions.
- [P1] Actions come before their consequences, and "Undo this result…" and "Restore #N" compete (history_panel.dart:574-607). The ←/→ keys change the live event inside a list labelled "Review · live unchanged". Fix: show consequences first, then one primary "Fix this result" and a secondary "Go back to here"; arrow keys move the selection only.
- [P2] Drift from the design system: the dock is 400px instead of 360 (259); blue tints on the selection, "Current", the step icons and the reopen border break the One Ink rule; the keyboard legend is tooltip-only (300); the graph has no semantics; Save is disabled with no reason given; at 200% text only about 1.5 rows show.

## Personas
- Alex (keyboard user): ← undoes the live event without warning; Enter restores; no Ctrl+Enter; a reason is required for every correction.
- Sam (screen reader, 200% text): the graph conveys nothing; the result control has no role; the legend appears only on hover; at 200% the panel shows about 1.5 entries.
- Solo TD, interrupted: correcting a result takes 30–60 seconds or more, and one Esc loses everything.

## Minor
- The prefilled reason "Undo result from transaction #N" writes jargon into the permanent record.
- "Use Post round 2" should be "Create pairings".
- "Undo 2 · Apply 0" shows a zero count.
- "You are here." duplicates "Current".
- The checkbox "I checked that none of these games have actually started" reads like liability wording.
- In the correction row, the score wraps as "0–" / "1".
- Row titles are raw command strings.

## Questions
1. Should "Fix result" live on the board row, with History only as a safety net?
2. Does the reason need to be mandatory?
3. Does a TD need to see branches at all?
