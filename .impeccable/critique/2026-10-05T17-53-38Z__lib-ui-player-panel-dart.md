---
target: Swiss workflow and player editor
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/home/anbernal/Projects/Meow-Chess/lib/ui/player_panel.dart"
target_fingerprint: "sha256:db551024d0097048bfaeb364127932f4bcac872942a4ae265893ea4b2959511f"
target_path: /home/anbernal/Projects/Meow-Chess/lib/ui/player_panel.dart
timestamp: 2026-10-05T17-53-38Z
slug: lib-ui-player-panel-dart
---
# Critique: Swiss workflow + player editor (lib/ui/player_panel.dart and related)

Method: dual-agent (A: design review · B: detector/inventory)

## Health 26/40 (Acceptable)
| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of status | 3 | Withdrawn shown only as muted line in panel |
| 2 | Match real world | 3 | "1/2" vs ½; "swap" means roster swap AND pairing swap |
| 3 | User control | 3 | Undo everywhere; withdraw has 3 different confirm models |
| 4 | Consistency | 2 | Byes/withdraw apply instantly, text fields need Save, same panel |
| 5 | Error prevention | 2 | Swap offered mid-Swiss then fails; requested 1-pt bye offered |
| 6 | Recognition | 2 | Byes only discoverable via hover tooltip or deep scroll |
| 7 | Flexibility | 3 | Keyboard results excellent; context menus mouse-only |
| 8 | Minimalism | 2 | 10-item section-tab menu; 7 always-open fields + 5 groups |
| 9 | Error recovery | 3 | Plain messages, revision guard |
| 10 | Help | 3 | Accurate help; bye deadline promised in TD_DAY not built |

## Priority issues
- P1 Byes buried: only in player panel below 7 fields + US Chess block (player_panel.dart:694-733); no row-menu entry. Fix: "Byes…" in row menu, Byes near top for Swiss.
- P1 Swap not format-gated + player ops duplicated in 4-5 surfaces (workspace.dart:1216-1224, player_actions.dart:39-47, players_view.dart:1139-1185, player_panel.dart:753-907). Fix: Swap only when a quad/RR is involved; Swiss gets Move; drop player ops from section-tab menu; Withdraw in panel header.
- P1 Player panel overload: 7 text fields + US Chess, Byes, Section, Pairing requests, Status (~17 controls before byes multiply). Fix: header actions + Identity open; Byes open in Swiss; US Chess + report name, Pairing requests, Team, Notes collapsed with summaries; auto-expand on report Fix.
- P2 Withdraw is one boolean, no "after round N" (TD_DAY.md:100 promises it).
- P2 Labels: "Team / mixed-doubles name" -> Team; "Private notes" -> Notes (collides with roster "Note" column = registrationNote); delete player_panel.dart:850 sentence and players_view.dart:441 note; "Club / team" import maps to club not team.

## Detector
impeccable detect on lib/ui: [] exit 0. Detector is text/CSS-pattern based; no Flutter widget model, so clean = uninformative. No browser overlay (Flutter desktop).

## Persona red flags
- Power-user TD: no shortcut for bye/withdraw; swap dead end.
- Keyboard/SR: context menus have no keyboard route; bye hint hover-only (N05); unlabeled bye segments.
- Relief TD: withdrawn status muted; "swap" ambiguous.

## Minor
- players_view.dart:1107 hint unreachable (early return at :1056).
- Move "Reason" field shown before play though only needed after.
- Swap partner list is an untyped dropdown.
