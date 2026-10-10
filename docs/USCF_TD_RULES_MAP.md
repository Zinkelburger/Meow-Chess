# US Chess rulebook → TD operations map

This file maps what the US Chess rulebook requires a tournament director to do onto
what Meow Chess implements. Use it as the backlog for rules conformance. Status is
taken from code and probes, not from the planning documents; IMPLEMENTATION.md still
owns the shipped scope.

**Source:** *US Chess Federation's Official Rules of Chess*, 7th edition, free online
chapters 1, 2, 10 and 11, revised 2020-08-21
(`us-chess-rule-book-online-only-edition-chapters-1-2-10-11-9-1-20.pdf`). PAIRING.md
cites the 2026 combined PDF and its amendments. Before claiming conformance, check each
rule below against that edition too.

**Audited:** 2026-10-07 at v1.2.3 (`0d2139a`); **updated** 2026-10-09 after the rules-conformance pass (§1, §5, §6, §7 and the administration rows reflect the shipped code).

Status: **Done** = implemented and matches the rule · **Partial** = present but deviates
or is incomplete · **Missing** = absent · **N/A** = over-the-board judgment with no
software role.

---

## 1. Swiss pairings (Rules 27–29): the critical path

The engine is `pairSwiss` in `lib/domain/swiss_pairing.dart`, policy tag
`uscf-swiss-29-v1`, called from `proposeRound`. It follows the rulebook's order of
work: the full-point bye (28L), the house player (28M1), score groups from the top
(29B), odd players chosen under 29D with a look-ahead into the next group, upper half
against lower half (29C1), repeat and restriction fixes (27A1, 29C2), then color
improvement by transposition and interchange within the 80- and 200-point limits
(29E5a–g) and color assignment under 29E4. Every departure from the natural pairing
is recorded in `Round.explanations` (29E TIP) and the notable ones are shown after
posting. Rule-linked fixtures built from the rulebook's worked examples are in
`test/domain/swiss_rules_test.dart`; the property simulation in
`test/domain/pairing_properties_test.dart` checks every invariant over random events.

### 1.1 Defects confirmed by probe (2026-10-07)

All four are fixed and covered by fixtures (`28J and 29E2 first round`, `S1`, `28L2`).

| # | Rule | Was | Now |
|---|---|---|---|
| S1 | 29C1 / 27A3 | Fold pairing within score groups | Upper half plays lower half in order; transpositions only for repeats and colors. |
| S2 | same | 1v4, 2v3 in a group of four | 1v3, 2v4. |
| S3 | 28J / 29E2 | Higher-rated player white on every board | One recorded toss (`Event.colorToss`, set when the first Swiss round posts and shared by every section), colors alternate down the boards. |
| S4 | 28J / 28L2 | Bye to an unrated player | Never, while any rated player is eligible. |

### 1.2 Rule-by-rule status

| Rule | Requirement | Status | Notes / gap |
|---|---|---|---|
| 27A1 | No player meets the same opponent twice; a no-show forfeit doesn't count as a meeting | Done | Only played games (or games with a TD assumption) count. |
| 27A1 | If a repeat is unavoidable, pair a second meeting before any third | Done | Meetings are allowed one tier at a time only when no legal pairing exists; the round explains it and the simulation test checks that it is never silent. |
| 27A2 | Pair equal scores whenever possible | Done | Score groups paired top-down; only odd players and unpairable members drop (29D). |
| 27A3 / 29C1 | Within a score group, the upper half plays the lower half in order | Done | Fixture S1. |
| 27A4 / 27A5 / 29E3 / 29E4 | Due color: equalize first, then alternate; priority rules 1–5 | Done | 29E4 rules 1–5 as written, including rule 4 (latest round in which colors differed) and rule 5 by rank. Fixtures for each rulebook example. |
| 29E1 / 29E3a | Byes and forfeits don't count toward color history | Done | |
| 29E2 / 28J | Coin toss for board 1, then alternate; the toss carries across sections | Done | `effectiveColorToss` derives a reproducible toss from the event until one is recorded; `post` records it. Editable through MCP `update_event`. |
| 29E5 / 29C2 | Transpositions and interchanges to fix colors and avoid repeats | Done | Look Ahead (29E6a): the switch that removes the most conflicts, then the 29E5e preference. |
| 29E5a | 80-point limit for due-color switches | Done | |
| 29E5b | 200-point limit to prevent a two-game imbalance | Done | Also used for a third color in a row. |
| 29E5c–e | Smaller of the two differences; transposition within 80 beats an interchange; else the smaller switch | Done | Fixtures 29E5c, 29E5e examples 1 and 2, 29E7 examples 1, 2, 4 and 5. |
| 29E5f | Never the same color three times in a row | Done | Counted as a strong conflict; when unavoidable the explanation says so. 29E5f1 (last-round exception) is implicit: the explanation notes the last round. |
| 29E5g | Switches to or from an unrated player are exempt from the limits | Done | |
| 29E6a | Look Ahead method | Done | Implemented as "reduce the group's conflicts most, at the smallest switch". 29E6b (Top Down) is not offered. |
| 29A | Rank = score, then rating | Done | `effectivePairingRating` (28A TIP / 28F). |
| 28A TIP / 28F | Pairing-only and prize-only ratings | Done | `Player.pairingRating`, `Player.prizeRating`. |
| 28B | Late entrants ranked by rating | Done | |
| 29D1a | Odd player = lowest-rated rated player; plays the highest-rated opponent they can in the next group | Done | |
| 29D1b | Else the next-lowest odd player, or a lower opponent within the color limits | Done | Alternatives tried next-lowest first; the switch is measured by 29E5c arithmetic (29E7 example 5). |
| 29D1c | An all-unrated group drops an unrated player | Done | |
| 29D2 | One player dropping several groups over several dropping | Done | A floater without an opponent continues down; members of an unpairable group drop lowest-rated first. A complete search is the last resort before any repeat, and is explained. |
| 28L2 | Bye: lowest-rated rated player in the lowest group; then a recent unrated member; then NEW | Done | NEW = unrated without a US Chess ID. |
| 28L3 | No second full-point bye; none to a forfeit winner | Done | Relaxed, with an explanation, only when nobody is eligible. |
| 28L4 / 22C6 | No full-point bye to a holder of a half-point bye, unless everyone in the group has had one | Done | Past and future requested byes count. |
| 28L2a (variation) | Bye to a higher-rated player for colors | Done | Variation `28L2a`: a higher-rated player of the lowest group takes the bye when that reduces the group's color conflicts, within 80 points (200 when it removes a two-game imbalance or a third color in a row). |
| 28L5 | Four-round events: avoid a NEW player's bye | Done | The group above is tried first. |
| 28K | Late entrant: half-point bye or forfeit for missed rounds | Partial | Missed-round scoring is still a manual bye. |
| 28M1 | House player: paired only when the field is odd | Done | `Player.house`; sits out with a 0-point bye when the field is even. |
| 28M2 / 28M3 / 28M4 | Cross-round and cross-section pairings; extra rated games | Partial | Side-game sections stand in for an extra-rated-games chart. |
| 28N1 | Team-mates avoided by the plus-two method | Done | `Section.avoidTeammates`; below plus-two a team-mate drops a group rather than meet (28N1b); at plus-two or above they stay and meet only if there is no other way (28N1c). 29E8: teams precede colors. 28N2–N4 variations not offered. |
| 28T | Requested non-pairings | Done (stricter) | A hard constraint. |
| 28Q / 29H5–7 | Pair around unfinished games | Done | |
| 29H2–4, 29H8 | Non-reporters held out | Done | `holdOutNonReporters` (29H3 double forfeit, 29H4 half-point byes) via MCP; see §4. |
| 29G1–3 | Re-pair a round | Done | Unstarted rounds can be replaced. 29G3: `repairUnstarted` (MCP `repair_round`) keeps the listed games and re-pairs the waiting boards as a separate group; the round's bye holder rejoins it. No GUI control yet. |
| 28R1 | Accelerated pairings, added score | Done | `Section.accelerated = addedScore`: the upper half of the round-1 field pairs with an extra point in rounds 1–2. |
| 28R2 / 28R3 | Adjusted rating method; sixths | Done | `Section.accelerated = adjustedRating` or `sixths`. Round 1: A1 v B1, C1 v D1 (or sixths), even-sized groups with any extra boards on top. Round 2: A2, B2 v C2, D2 with the ±100 draw adjustments and the B2/C2 balancing, all listed in the explanations; when the groups cannot be balanced (C2 larger than B2 and D2 together) the round pairs by score groups and says so. |
| 28S1–S3 | Re-entries: no repeat against the earlier entry's opponents unless both re-entered; colors restart | Done | `Player.reentryOf`, set in the player panel or MCP. |
| 28S4 / 28S5 | Re-entry byes and the better score carried forward | Done | `reentryCarries` (`lib/domain/reentry.dart`): scores compared through the earlier (withdrawn) entry's last round; the better carries, the latest when equal, always the latest under variation `28S5latest`. Used by pairing (with the carried entry's colors) and by every standings table, so prizes too. 28S4 byes are still entered by hand; a carried entry's own tie-breaks (34H a) still come from the re-entry's games. |
| 28I | Expelled player's opponents | Missing | |
| 29I / 29J | Class pairings; unrateds in class sections | Done | Variations `29I` (full-class, 29I1) and `29I2` (class-prize contenders), last round only. Classes come from the class and under prizes, else the 200-point classes; a class with a player who can still win a place prize above its class prize is paired normally. `29J`: unrateds on plus scores in one score group play each other. |
| 29K / 29L / 29L1 | Small Swiss to round robin | Done (hint) | Section settings show the 29K hint; the Crenshaw-Berger tables are available for the round robin (§5). No 1-v-2 mode. |
| 29E4a, 29E4b, 29E4d, 29E5h | Announced color and priority variations | Done | `Section.variations` (section settings and MCP); listed on the event conditions sheet. 29E5b1, 29E5f1, 29E6b and 29E8 are not separate settings (29E8 is the default behaviour). |
| 20M3 / 35 | Fixed boards | Done | `Player.fixedBoard`; other games fill around it. |
| 36 | Computers never paired together | Done | `Player.computer`. |

### 1.3 Still to do

1. **TD review of full event replays** (DELIVERY.md exit criterion): the fixtures
   cover the rulebook's examples. `tools/compare_pairings.dart` re-pairs the
   Boylston archive's 49 Swiss rounds and explains every board that differs from
   SwissSys (27 rounds identical, 172 of 240 boards; see BOYLSTON_REHEARSAL.md).
   A certified TD still needs to read those differences.
2. 28I (an expelled player's opponents).
3. A GUI control for 29G3 selective re-pairing (MCP `repair_round` exists).

---

## 2. Registration, ratings and membership

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 28A | Enter name, rating and US Chess ID; school/team code at scholastics | Done | Import, paste, walk-up and member lookup. |
| 28C | Pairing rating from the rating list named in the TLA | Done | Supplement chosen by date and system (R/Q/B); locked once pairings are posted. |
| 28C1 | Combine a player's duplicate US Chess ratings | Missing | Rare. |
| 28C2 / 28D1 | Foreign/FIDE rating disclosed and converted (FIDE+50, 0.895·FIDE+367, FIDE+100, other countries' formulas) | Done | `Player.foreignRating`/`foreignFederation`; `convertForeignRating` in `us_chess.dart` uses the 7th-edition formulas (FIDE two-part general conversion, FQE +100, England ×8+700, Ingo 2940−8×, USSR/Philippines +250, others +200; Brazil/Peru/Colombia and unknown codes return no number with a reason). Player panel "Assigned ratings" group with "Use converted rating". |
| 28D2–D7 | Rules for assigning ratings to unrated players (not under 2200 if it would make them class-prize eligible, etc.) | Partial | 28D2/28D5: an unrated player's assigned rating under 2200 that qualifies for a class/Under prize in their section is refused unless a cause (the 28D1 verification) is stated. 28D3/D4/D6/D7 remain judgement calls. |
| 28E | TD assigns a rating no lower than the published one, for reasonable cause | Done | `pairingRating`/`prizeRating` (28F) with `ratingNote` as the 28E2 cause. `savePlayer` refuses an assignment below the published rating, or below the converted foreign rating of a player without one (28E1), and requires a cause for a rated player (28E2). MCP `update_player` accepts the fields; history describes them. |
| 28H | Rating revised mid-event and the player is now ineligible for the section: remove or reassign with half-point byes | Partial | A rating change that reaches the section's `ratingCeiling` saves and sets `controller.playerNotice`, shown in the player panel with the 28H1/28H2 options. The move and the byes remain manual. |
| 23C | Each player is a US Chess member for the event dates | Partial | Expiry check is advisory only. |
| 36 | Computer entrants: only prizes designated for computers; never computer vs computer | Partial | `Player.computer` checkbox in the player panel and `update_player`. Rule 36 is deleted in the 7th edition text; pairing avoidance is not enforced. |

## 3. Unplayed games, byes and withdrawals

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 22A / 28P | No-show = forfeit (X/F), unrated; the player is dropped unless excused | Done / Partial | Forfeit codes exist. Automatic withdrawal after a no-show is a manual choice (see also no-checkin-flow memory). |
| 13F | Double forfeit when both players are absent | Done | |
| 22B / 28L | Full-point bye for the odd player | Partial | See §1 (S4, 28L3–L4). |
| 22C1 | Half-point byes in the first half; second-half byes only if advertised | Done | `Section.byeRules.lastHalfByeRound` (section settings, MCP `update_section`); `reserveBye` refuses a half-point bye past it. Zero-point byes are never limited. |
| 22C2 | Bye request deadline (default one hour before the round) | Partial | `byeRules.deadlineMinutes` (default 60) is announced in the player panel and on the conditions sheet; requests are still accepted until the round is posted. |
| 22C3 | Optionally limit half-point byes per player | Done | `byeRules.maxHalfByes`, enforced in `reserveBye`. |
| 22C4 / 22C5 | Irrevocable last-round byes, declared by a deadline; a cancelled one that wins scores as a draw for prizes | Done | `byeRules.irrevocableFromRound` requires the declaration (`Player.irrevocableByes`, player-panel checkbox, MCP `irrevocable`). Cancelling keeps the declaration; a win in that round gets `Game.prizeOutcome = draw` with a 22C5 note when the result is recorded or corrected. |
| 28P / 13G | Withdrawal: remaining games score zero | Done | Withdraw and reinstate. |
| 30B | RR: a player who withdraws before playing half their games counts as not having competed (games still rated) | Partial | The logic exists in `standings(forPrizes)`, but the UI never enables it. |
| 30E | RR withdrawals: Crenshaw-Berger color adjustments | Missing | The Chapter 12 color-adjustment tables are not in the rulebook text we hold (`research/local/uscf-rules-2026.txt` stops at Chapter 11), so nothing to implement against yet. |

## 4. Results and corrections

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 15H / 28O | Record results; post the wall chart promptly | Done | |
| 15I | Wrong result found later: correct it, re-pair if just paired, choose whether it counts for prizes | Partial | Corrections and later-round impact review exist. No "rated but not for prizes" flag (needed with 28M4). |
| 29H | Unreported results | Done | Assumptions; see §1. 29H3/29H4: `holdOutNonReporters` (MCP `hold_out_non_reporters`) double-forfeits the unreported games or reserves half-point byes for the next round, in one revision. |
| 18G | Adjudication, emergency only | Done | "Adjudicated" checkbox in the result correction panel sets `Game.adjudicated`; crosstable cells show `ADJ`. |
| 13I / 20K | Penalties, time deductions, "game lost by both players" | Done | Double forfeit exists; penalties are logged in the Rulings panel (`Event.rulings`, MCP `log_ruling`). |
| 21H–21L | Appeals: within 30 minutes, committee or special referee, written decision; US Chess appeal within ten days | Done | Docked Rulings panel (toolbar gavel) logs rulings, penalties, appeals and adjudications newest first, applied through `controller.change` so undo works, with the 21H1 (30 minutes) and 21L1 (ten days, as the 7th edition states) deadlines shown. |

## 5. Round robins, quads and other formats

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 30A | Numbers by lot; Crenshaw tables (Chapter 12) | Done | Section setting `rrTable` = Crenshaw-Berger (3–24 players, `crenshaw-rr-v1`; 3–4 is the 30G table, 5–6 Table B, 7+ the Berger tables in reverse round order) or the circle method (default, `circle-rr-v1`). "Draw lots" in section settings and MCP `draw_lots` shuffle pairing numbers with a seed recorded in history; refused once a round is posted. |
| 30F | Double round robin: second cycle with colors reversed | Done | `doubleCycle` appends a second cycle with every color reversed; planned rounds must be the full double length (2(n−1), or 2n for an odd field), checked in section settings and MCP. `doubleGames` (both games in one round) is unchanged. |
| 30G | Quads in rating order: 1–4, 2–3; 3–1, 4–2; 1–2, 3–4 with a toss | Done | Bottom 5–7 become a Swiss, as the rule suggests. |
| 30H / 30I | Holland and unbalanced Holland (blitz) | Missing | Low priority. |
| 31A–31G | Team tournaments: match points, team average rating, board order, team wall charts | Partial | 31A combined individual/team events are done (see 31A1); fixed-roster team events (31B–31G) are a later tranche (PRODUCT_PLAN). |
| 31A1 / 28N | Combined individual/team scoring (top-N scorers, Rollins) | Done | `lib/domain/team_standings.dart`: settings in `Section.prizes['teams']`; top N (Scholastic Regulations 10.2.1) or Rollins (31A1: field size − place); 2-player minimum (10.2.2); team tie-breaks total Modified Median, Solkoff, SB, Cumulative, then coin flip (12.3.3); team prizes `kind: 'team'`. |

## 6. Prizes (Rules 32–33)

Implemented in `lib/domain/prizes.dart` (table schema, allocation engine), the
section's Prizes panel, the Prizes print report and the `prize_report` MCP tool.

| Rule | TD operation | Status |
|---|---|---|
| 32B1 | One cash prize per player; a clear winner gets the most valuable one | Done — `allocatePrizes`: one prize per player, the largest first |
| 32B2 / 32B3 | Tied players pool and split the prizes involved; at most one prize per player goes into the pool; no one gets more than their best prize without the tie | Done — equal-points groups pool one prize each, capped at the prize they would win alone; a sub-group keeps prizes the rest cannot win when that pays more |
| 32B4 | Equal amounts: place beats class, higher class beats lower, rating class beats junior/senior | Done — prize precedence breaks equal amounts |
| 32C1–3 | Players who withdraw are ineligible; a class prize is paid even with one finisher | Done — `withdrawnEligible` overrides 32C1; an unclaimed class prize is listed as not awarded (32C3) |
| 32C4 / 32E | Based-on payouts: proportional, at least 50% if the fund is over $500; partial guarantees | Done — `basedOn` per section, the 50% floor uses the whole event's announced funds, `guaranteed` prizes pay in full |
| 32C5 / 32C6 | Re-entry prizes; limited (unrated) prizes and how the remainder is redistributed | Done — a replaced entry wins nothing; `unratedCapCents` limits unrateds, the remainder goes to the tied rated players, else to the next score group in the same prize |
| 32F / 32G / 33D | Trophies and non-cash prizes: one per player, ranking, tiebreak or playoff; money and trophies calculated separately or together | Partial — one trophy per player by standings order and prize rank (33D2 mainline); variation 33D2a (trophy follows the money) and playoffs are not offered |
| 33C / 33F | Class vs Under prizes; unrated players only eligible for place and unrated prizes | Done — `class` is an inclusive range, `under` an exclusive ceiling; unrateds (prize rating 0) win only place, points and unrated prizes |
| 33E | Prizes by points scored | Done — `points` prizes pay every player at or above the score, one per player, never pooled |

Junior and senior prizes name their eligible players (`eligible`) because the
roster keeps no birth dates. Computers (rule 36) win only `computer` prizes and
house players (28M1) nothing. Tests: `test/domain/prizes_test.dart` replays the
rulebook's worked examples under 32B5 and 33D2a.

## 7. Tiebreaks (Rule 34)

| Rule | Method | Status | Notes |
|---|---|---|---|
| 34E1 | Modified Median, the **default first tiebreak**, with unplayed-game adjustments (opponent's unplayed games = ½; the player's own = an opponent with 0) | Done | `lib/domain/tiebreaks.dart` `modifiedMedian`: plus scores drop the lowest opponent, minus the highest, even both; two from each end in a 9+ round section. Opponents' adjusted scores count ½ per round held that they did not play out (byes, forfeits, absence); the player's own unplayed games add opponents on 0. Half-point units. |
| 34E2 | Solkoff | Done | `solkoff`: the 34E1 adjusted list with nothing discarded. `Standing.buchholz` (raw played-opponent sum) remains only for legacy callers; no report prints it. |
| 34E3 | Cumulative, minus 1 per unplayed win and ½ per half-point bye | Done | `cumulative`: running score per round held, less the points of every forfeit win and bye. Default #3. |
| 34E9 | Cumulative of opposition | Done | `cumulativeOpposition`: 34E3 of each played opponent. Default #4. |
| 34E4–E8, E10, E11, E13 | Median, head-to-head, most blacks, Kashdan, Sonneborn-Berger, opponents' performance, average opponent rating, coin flip | Done | All selectable. Head-to-head is wins minus losses within the group still tied on points and every earlier method (34E5's plus/minus); a cycle or unmet pair stays tied. Opponents' performance leaves out games between tied players and skips unrated opponents; average opponent rating skips unrated. Coin flip is a recorded six-digit lot hashed from the event and player IDs. |
| 34E12 | Speed playoff | N/A | Played over the board, not computed. |
| 34B | Ordered tiebreak list, configurable and posted | Done | `Event.tiebreaks` (method codes; empty = US Chess default per section format). Event panel → Standings: up to four ordered slots, applied immediately with undo; MCP `update_event.tiebreaks`. The standings PDF footnote, the CSV header, the crosstable columns and the MCP `standings` tool name the methods in order. The Tie-breaks switch still decides whether equal points share a place. |
| 34C | Tiebreaks never split cash, only indivisible prizes | N/A until prizes exist | |
| 34F | RR: Sonneborn-Berger, then results between the tied players | Done | Round robin and quad sections default to `sonnebornBerger`, `headToHead`. SB adds nothing for unplayed games. |
| 34G / 34H | Team tiebreaks; re-entry tiebreaks | 34H done; 34G missing | Each entry is its own player ID, so a re-entry is ranked on its own games and opponents see only the entry they played (34H a, b); the earlier entry's unplayed rounds count ½ in its adjusted score like any withdrawal. No team events, so no 34G. |

## 8. Time controls, rating systems and reporting

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 5C | Classify each section's time control as Regular / Dual / Quick / Blitz by base minutes plus delay/increment seconds | Done | `us_chess.dart`. |
| 5C Note 3 | Merged schedules report the slowest time control | Partial | One time control per section. |
| 5C1 | Time-odds games aren't ratable | N/A | |
| 5E2 | Unspecified delay means the recommended minimum | Done | `delayHint` shows the 5E minimum (d5 / d3 / d2) under the time-control fields in the event panel and section settings, and on the conditions sheet. |
| Ch. 11 | Blitz: 5–10 min total, base at least 3 min, all rounds the same time control | Done | Classification only. |
| 21B / Ch. 10 §15 | Report results and fees; online events marked as online | Done / Partial | `Event.online` (event panel "Reporting", MCP `update_event`). The 2C format has no online marker, so the rating preflight advises that online events are rated under the online categories and never dual-rated, and the manifest records `online`. |
| 28M2 | Cross-round pairings marked on the rating report | Missing | |
| 28I3 / 28M4 / 29H3 | Extra rated games reported separately | Partial | Side-game sections. |

## 9. Event administration and displays

| Rule | TD operation | Status | Notes |
|---|---|---|---|
| 21B | Appoint assistant TDs | Done | Chief, assistant and other TD IDs. |
| 26A / 34B / 25 | Post variations, tiebreaks and prizes before round 1 | Done | `ReportKind.conditions`: one printable sheet per event with venue/TDs, time controls (with the 5E2 note), pairing settings and variations, tie-break order, bye policy, prize tables, irrevocable byes and the announced conditions text. From the Reports view ("Before round 1"). |
| 28J TIP | Alphabetical pairings list as well as by board | Done | Print panel checkbox "Also list each round by name" (`reportPdf(alphabetical: true)`) adds a Player / Board / Color / Opponent table after each round's boards. |
| 28O / 31F | Wall chart with cumulative score per round, circled or F for unplayed, NEW for unrated | Done | Text and PDF crosstables show the score after each round in every cell (`W12b 1.5`), `X`/`F` for forfeits, and `NEW` (no rating, no US Chess ID) or `UNR` in the rating column. Team wall charts (31F) remain with the team tranche. |
| 22C4 | Post irrevocable byes near the wall chart | Done | Listed on the conditions sheet with the round (and whether cancelled). |
| 17B1 | Note a delayed start time on the pairing sheet | Done | `Round.note` prints under the round title on the pairing sheet. |
| 20M3 / 35 | Fixed boards for a disabled player, or to keep two players apart | Missing | Board numbers always follow pairing order. |

## 10. Online play (Chapter 10)

This chapter is mostly about the host platform and fair play. The parts that touch
the app: a list of registered players with the ratings used (7A); pairings and
standings visible to all (8B); per-event bye policy (8C); unfinished games scored as
losses (8D2); and the rating report flagged as online with online rating categories
(15B, 2B). Implemented: the per-section bye policy (8C, see §3) and the online flag
(`Event.online`) with its preflight advice and manifest entry (15B, 2B, see §8). The
rest only matters if online events are in scope.

## 11. Not software (N/A)

Rules 2–4 and 6–12 (board, pieces, moves), 13A–C and 14 (decisive and drawn games,
claims), 15A–G (scorekeeping), 16 (clock use), 18–19 (adjournments), 20 (conduct,
except logging penalties), 35F (rules for disabled players at the board) and
Chapter 11's blitz claim rules. These are rulings at the board. At most, the app could
log the ruling (§4).

---

## Priority backlog

Shipped on 2026-10-09: the §1 Swiss engine, rule 34 tie-breaks (§7), the prize
engine and report (§6), bye policy, assigned and foreign ratings, the rulings log,
the online flag and the event conditions sheet (§2–§4, §8–§10), Crenshaw-Berger
tables, lots, double round robins, the 30B toggle, the wall chart and the
alphabetical pairing list (§5, §9).

1. **TD review** of full event replays against the engine's explanations
   (DELIVERY.md exit criterion), and a check of the reconstructed Crenshaw-Berger
   tables for 5–6 and 7+ players against the printed Chapter 12.
2. **Swiss remainder:** 28I, and a GUI control for selective re-pairing (29G3).
3. ~~**Scholastic team scoring** (31A1 / 28N) and team tie-breaks~~: done
   (`team_standings.dart`, Scholastic Regulations 10.2 and 12.3.3).
4. **Prizes:** trophy-follows-the-money (33D2a), playoffs, a shared based-on goal
   across sections, birth dates for junior/senior eligibility.
5. **Administration:** enforce the bye request deadline against the clock (22C2),
   28H move-and-byes in one step, 30E withdrawal color tables (not in the online
   rulebook text), a results-view entry point for 29H hold-outs, 28C1 duplicate
   ratings.
