# Boylston as the initial customer model

Surveyed the [September calendar](https://boylstonchess.org/calendar/),
[April calendar](https://boylstonchess.org/calendar/april-2026), and representative
event pages. This is a sample across seasons, not a claim that every historical
event has been inventoried. The rolling calendar URL must be read with its
archived date; the April URL is stable.

| Actual event | Observed format / important detail | Product implication |
|---|---|---|
| [September Quads](https://boylstonchess.org/events/1561/september-quads) | Three-round RR, G/65 d10; groups by rating; bottom 5–7 play Swiss; no requested byes/withdrawals | Quad planner and per-section pairing systems; exception handling still needed if someone leaves |
| [Big Money Swiss](https://beta.boylstonchess.org/events/1562/big-money-swiss) | Public registration table and final section crosstables; Open/U1900/U1500 entries | Multi-section import and post-registration corrections |
| [Tuesday Night Swiss](https://boylstonchess.org/events/1560/september-tuesday-night-swiss-otb) | Five weekly rounds, G/90 +5; Open/U1910/U1510; small sections may merge; more than one rating basis can permit play-up | Dates per round; explicit eligibility policy; controlled merge before pairing |
| [Rated Friday Blitz](https://boylstonchess.org/events/1576/rated-friday-night-blitz) | Six double rounds, G/5 d0; one game with each color | Separate pairing rounds and games; two results per match; Blitz export |
| [Big Money Blitz](https://boylstonchess.org/events/1575/big-money-blitz-unrated) | Explicitly unrated | Membership/reporting requirements must depend on section status |
| [Weekend Rapid](https://boylstonchess.org/events/1504/weekend-rapid) | 4SS, G/15 +10; Open/U1600; fewer than ten can trigger merge and acceleration | Quick category; acceleration is a separate rules feature |
| [Tornado #147](https://boylstonchess.org/events/1505/tornado-147) | 4SS, G/60 d5; Open/U1800; merge threshold eight | Templates with different merge thresholds; delay-aware rating classification |
| [September Scholastics](https://boylstonchess.org/events/1558/september-scholastics) | 4SS, G/30 d5; rating sections, under-18 eligibility, Championship rating range | Age-at-event validation when needed; trophy standings; minimize birth data |
| [Six-week Online Swiss](https://boylstonchess.org/events/1559/early-autumn-six-week-swiss-online) | 6SS or double quad; G/60 +10; Lichess usernames; rescheduling; delayed reporting for fair-play review | Online federation categories and scheduling, without building an online chess server |
| [Boston Metropolitan League](https://boylstonchess.org/events/1545/boston-metropolitan-chess-league-team-signup) | At least four boards; two games per opponent; divisions, changing rosters, season/playoffs | True team matches and lineups; a team tag alone is insufficient |
| [Boston Queens series](https://boylstonchess.org/events/1553/boston-queens-series-event-1-the-start) | Simul plus unrated accelerated double blitz; series points | Multi-activity day, acceleration, independent series scoring; not first-release parity |

The calendar also has socials, club nights, lessons and administrative meetings.
Those do not require a tournament pairing engine. A general club-management and
payments product is outside the current app's purpose.

Some pages contain stale boilerplate (the April rapid page refers to a January
registration cutoff; the quad page has a generic withdrawal footer beneath a
no-withdrawal policy). Imports must preserve source text and prompt the TD to
resolve conflicting event settings, not mechanically trust every scraped label.

## What the user's registration example proves

The public table exposes `Name`, `Section`, `USCF ID`, `Rating`, `Live`, and `Byes`.
It includes rating strings with provisional counts, unrated entries, a blank ID,
and a registered ID that differs by a digit from the final crosstable for the
same displayed name. This is concrete evidence that registration cannot be treated
as an authoritative identity database. It does not prove how those corrections
were made or establish anyone's identity independently.

The final crosstables also contain changed section membership and entrants not
identical to the registration list. An importer must distinguish **entries** from
**results**, even when both appear on the same page. Public absence does not
reliably mean withdrawal, unpaid status or incomplete registration.

No organizer CSV/export button was established on Boylston's public page. We do
not know its administrative export schema. Proposed import priority:

1. CSV/TSV files and pasted spreadsheet tables with visible column mapping.
2. A saved Boylston entries table, or a narrowly supported public-page adapter
   that previews the extracted roster before applying anything.
3. An actual organizer export once a sample is available.
4. SwissSys SJSON after a versioned sample/contract is obtained.

Proposed canonical CSV columns (not a claim about Boylston's export):

```text
registration_id,name,uscf_id,section,rating_published,rating_live,byes,team,checked_in
```

IDs remain strings. Import a value such as `1566/17` as value 1566 with 17
provisional games, while preserving the original string. “Unrated” is not a rating
of zero in the domain. A `Byes` cell containing `1,2` specifies round numbers but
does not by itself establish half-point versus zero-point scoring. Require mapping
or the event's announced bye policy. Do not infer check-in or payment from the
public entry list. A title embedded in a name should be proposed as a separate
field, not destructively stripped.

Support import dry-run, unmapped columns, row-level errors, duplicate review and
idempotent re-import. Re-imports can update confirmed registration metadata but
must not erase results, change an established identity, or move paired players.

## What to ask a Boylston TD

Obtain a representative registration export with personal contact columns removed,
one accepted rated Swiss export, one mixed quad export, and one double-blitz export.
Confirm which ratings seed quads, whether check-in determines the field, how equal
ratings/unrated players are placed, play-up and prize rules, emergency withdrawal
practice, and preferred print layouts. Observe the actual laptop/printer workflow
before freezing the UI. No outreach was sent in this research phase.
