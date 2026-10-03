# Between-round rating previews

On Players, open **Player tools → Show rating estimates**. It defaults to off and is
remembered with the view's event preferences. **Est. regular (Δ)** displays, for
example, `≈2200 (+10)`. Corrections and Undo recompute the preview from the recorded
results. No result entry or completed round is required to enable the option.

The preview applies the [US Chess standard formula, April 2026](https://new.uschess.org/sites/default/files/media/documents/us_chess_rating_system_specs-2026-04-06.pdf)
with these explicit approximations:

- Assume 50 prior rated games; calculate the rating-dependent effective game count.
- Use starting opponent ratings in one pass, without the official second pass.
- Include eligible bonus points (threshold 10), and the Regular K reduction for
  players above 2200 in Dual events.
- Apply the absolute floor of 100; personal floors and provisional formulas are
  unavailable.

Only completed played games within that section count. Byes, forfeits, unresolved
games and pairing assumptions are excluded. Sections are estimated independently;
transfers and extra-game sections are not combined into a cumulative event rating.
Regular and Dual time controls are supported. The stored rating is assumed to be
Regular unless its saved provenance explicitly identifies another category.
An unrated player or opponent, a known different rating category, an unsupported
time control, or no played games produces a dash with an explanatory tooltip.

These estimates are for fun. Starting ratings may be stale, and full history is
unavailable. A number crossing 2200 is not title confirmation. Stored ratings,
pairings, rankings, prize classes, printed reports and rating exports are unaffected.

Verified by `test/domain/rating_preview_test.dart` and
`test/ui/rating_preview_test.dart`: arithmetic, bonus eligibility, result filtering,
missing ratings, time controls, correction recalculation, opt-in state, preference
retention and no event mutation from the display option.
