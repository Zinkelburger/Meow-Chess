# Pairing, teams, and bughouse

## US Chess Swiss is a specific rules policy

Use the [2026 official downloadable rules](https://new.uschess.org/sites/default/files/media/documents/us-chess-rule-book-online-2026.pdf)
and [2026 amendments](https://new.uschess.org/sites/default/files/media/documents/summary-of-major-us-chess-rules-updates-in-the-seventh-edition-2026.pdf),
not a README claiming “Swiss.” Relevant anchors include 27A, 28, 29, 30 and 34.
Some pages in the combined PDF retain older footer dates; keep the update document
alongside it and record the exact rule revision used.

The basic hierarchy starts with avoiding repeat opponents, pairing equal scores,
top half against bottom half, then color equalization and alternation, with explicit
exceptions and transposition/interchange rules. A weighted nearest-rating matcher
is not automatically a conforming implementation. Rules such as 29E5's 80/200-point
procedures must be traced to the actual chosen rule variant.

Build a rule-to-test matrix covering seeding/unrated ratings; first-round colors;
score groups and floaters; unplayed-game color history; prior byes; forfeited
pairings; requested byes; withdrawal/reactivation; late entry; manual restrictions;
last-round exceptions; reentries; and impossible constraints. The baseline rule
does not mean repeats can never occur under every exceptional tournament condition.
Require an explicit diagnosed exception instead of a hidden fallback.

Proposed engine contract: input = immutable entrants/history/policies/revision;
output = a complete proposal with explanations or a failure with constraints that
prevent completion. Keep the engine version and any random decisions. The TD can
edit the proposal, see fresh validation and publish a revision.

Comparison against SwissSys is useful evidence, but different permitted variants
can legitimately produce different pairings. Match rule validity and configured
priorities, not just identical board lists. Have an experienced TD review fixtures.

## Quads: the important special case

For a sorted eligible checked-in field of size `n >= 4`:

- If `n % 4 == 0`, make `n / 4` four-player groups.
- Otherwise keep the lowest `4 + n % 4` players together as a 5–7-player Swiss;
  divide the rest into quads.
- Below four, stop and offer a TD choice. Do not manufacture a singleton/two-player
  quad or silently turn it into a potentially reportable match.

| Entrants | Proposed groups |
|---:|---|
| 4 | 4 |
| 5, 6, 7 | One small Swiss of that size |
| 8 | 4 + 4 |
| 9, 10, 11 | 4 + bottom Swiss of 5, 6, 7 |
| 20 | 4 + 4 + 4 + 4 + 4 |
| 21 | 4 + 4 + 4 + 4 + 5 |
| 22 | 4 + 4 + 4 + 4 + 6 |
| 23 | 4 + 4 + 4 + 4 + 7 |
| 24 | Six quads |

Rule 30G explicitly discusses the lowest 5–7 and the disadvantage of byes in the
odd cases. Preview sit-outs for 5/7, offer adding a house/late player where allowed,
and let the TD choose a different announced format. A five-player RR requires
five time slots, so never silently substitute it for a three-round event.

Rule 30G's preferred quad table uses rating-order numbers: round one 1–4, 2–3;
round two 3–1, 4–2; round three 1–2, 3–4 with colors decided by toss. Record the
actual color choices. Ordinary larger round robins use lot numbers; do not assume
that all RR seeding is the same. The rule notes that some TDs use lots for quads.

Keep equal-rating ordering deterministic and visible, with a documented tie policy
and optional TD override. An unrated entrant requires an explicit placement/assigned
pairing rating. Repartitioning is a single reviewed transaction; once games are
published/played, changing groups is a correction workflow, not a sorting operation.

## Withdrawals and standings

Rule 30B distinguishes prize scoring from rating played games for a player who
leaves before completing half the scheduled RR games. Preserve all actual played
results and derive the applicable standings projection. Never delete those games
to make the wall chart look right. Requested bye restrictions do not justify
crashing or inventing results when a person actually leaves.

Swiss withdrawal, allocated bye, requested half-bye, zero-bye, forfeit and unreported
result need separate states. Scoring two halves is not sufficient information to
reconstruct what happened.

## Three different meanings of “team”

| Structure | Pairing unit | Scoring |
|---|---|---|
| Individual tournament with team/club labels | Individual player | Individual points; optionally best-N/all-member aggregate |
| Fixed-roster standard-chess team event | Team, then board lineup | Board results plus separately defined match points |
| Bughouse with permanent partners | Two-person partnership | One match result from two simultaneous coupled boards |

Team affiliation can be an avoidance preference in an individual Swiss. A fixed
roster needs team IDs, board order, reserve/substitution rules and per-round lineup
snapshots. Bughouse needs two opposite-color partners, four-person availability,
one match result, and its own announced rules for wins, simultaneous endings,
draws and penalties. It is not “two boards of ordinary team chess.”

No US Chess-rated bughouse reporting support was established. Initial bughouse
must be explicitly unrated and excluded from standard-chess rating exports.

## Does dynamic bughouse Elo make sense?

Yes, as a local matchmaking estimate with uncertainty. It should not replace the
announced score used to determine a tournament winner. A short event contains too
little evidence to treat a fitted performance number as an objective ranking.

For permanent partnerships, start with Swiss pairing by team score (or team RR
for a small field), a declared seeding estimate and normal standings. Maintain an
optional **team** skill estimate across games/events. Standard chess ratings may
provide weak initial clues, but they are not calibrated bughouse strength.

For rotating partners, team-aware Bayesian models are more appropriate than
updating everyone using a naive two-player Elo formula. [TrueSkill](https://www.microsoft.com/en-us/research/project/trueskill-ranking-system/)
models skill uncertainty and team results. The [Weng–Lin paper](https://jmlr.org/papers/v12/weng11a.html)
provides another team/multiplayer ranking framework; [OpenSkill's manual](https://openskill.me/en/stable/manual.html)
is an implementation lead. Check exact algorithm/implementation licensing before
porting; choosing the mathematical idea is not a license audit.

A simple illustrative model is:

```text
team_strength(A,B) = mu[A] + mu[B]
P(AB beats CD) = logistic((mu[A] + mu[B] - mu[C] - mu[D]) / scale)
```

This is a conceptual example, not a validated bughouse model or production update
formula. Uncertainty, draw probability, calibration and partner interaction are
missing. With permanent teammates, replacing `mu[A]` by `mu[A]+c` and `mu[B]` by
`mu[B]-c` gives the exact same likelihood. Their individual abilities are not
identifiable from those team results alone. No rating algorithm can manufacture
that missing evidence. Rating the partnership is more honest.

Rotation helps identify individual strength only when the partner/opponent graph
is sufficiently connected. A person who always plays with one partner remains
confounded. Do not reward or penalize someone using “weak partner” estimates that
are themselves based on two noisy results. Strong priors, uncertainty bands and
slow updates are essential; skill synergy and board asymmetry remain model risks.

## Proposed experimental casual mode

Hard constraints: available players, four distinct participants, fixed partnerships
where declared, sufficient boards, and no simultaneous duplicate assignment.
Priorities after feasibility: equal sit-outs; avoid repeated partners/opponents;
reasonable score-group proximity; then predicted match balance. Expose the tradeoff
rather than hiding it in one arbitrary weighted score. If constraints conflict,
show the best alternatives and what each relaxes.

Keep **points**, **tie-breaks**, **seed rating**, and **estimated skill ± uncertainty**
as distinct concepts. Label the format “casual balanced pairings,” not US Chess
Swiss. Store the policy/seed and allow explaining each suggestion. Freeze the model
version and update cadence for an event; changing algorithms mid-event changes
the competition experience.

Before shipping, simulate synthetic populations across 3/6/12 rounds, fixed and
rotating partners, newcomers and unbalanced priors. Compare score-Swiss, random
balanced teams, team Elo, and a Bayesian candidate on repeated opposition,
sit-out inequity, predicted-vs-observed calibration, uncertainty coverage and
schedule strength. Then run a real casual pilot with participant feedback.
No bughouse rating experiment or engine analysis was run in this planning phase.
