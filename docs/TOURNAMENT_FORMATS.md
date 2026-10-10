# Tournament formats: what TDs run, what Meow Chess covers, and how to offer it without clutter

Researched 2026-10-09 from the US Chess rulebook text (`research/local/uscf-rules-2026.txt`),
the US Chess Scholastic Regulations 2026–27, the FIDE Handbook, the Boylston calendar
captures in `research/local/boylston-*.txt`, four club calendars, the US Chess upcoming
tournaments list, and the documentation of SwissSys, WinTD, Swiss-Manager, Vega, Tornelo,
chessroster, Lichess and chess.com. Sources are linked inline; "no source found" is said
where that is the case. The design brief in §5 is a proposal awaiting confirmation.

## 1. The formats

Rating status follows rule 5C: Regular over 65 minutes total, Dual 30–65, Quick 10–30,
Blitz 5–10 (all rounds the same time control), Online per chapter 10 (never dual).

| Format | Pairing unit | Mechanics | Scoring | Who runs it | Frequency | Meow Chess |
|---|---|---|---|---|---|---|
| Individual Swiss with class sections | Player | Rules 27–29 | 1/½/0, rule 34 tie-breaks | Everyone | **Common** (over half of all listings) | Done |
| Accelerated Swiss (28R1 added score; 28R2/28R3) | Player | First two rounds | Same | Large opens, nationals | Occasional | 28R1 done; 28R2/R3 missing |
| Quads, bottom small Swiss | Player | 30G table, 3 rounds | 1/½/0 | Clubs, scholastics | **Common** | Done |
| Round robin, double round robin | Player | Crenshaw or Berger tables, lots | 30B, 34F | Invitationals, norm events, club weeks | Occasional | Done (tables reconstructed, see rehearsal doc) |
| Blitz double-round Swiss (two-game matches) | Player | Swiss on match score, both colors each round, reported as two rounds | 0–2 per round | Clubs weekly, scholastic nationals | **Common at clubs** | Done |
| Blitz or rapid single-round Swiss | Player | Swiss | 1/½/0 | Clubs | Common | Done |
| Combined individual/team Swiss (scholastic) | Player, team tracked | Swiss, team-mates kept apart (28N1; scholastic regs: never until +3 in the last two rounds) | Individual plus team = top 4 (top 3 at grade/blitz); team tie-breaks total Median, Solkoff, SB, Cumulative | Scholastic events, state and national | **Common** (10–15% of listings) | Avoidance done; team standings and team tie-breaks missing |
| Fixed-roster team Swiss (USAT East/North/South/West, Texas Teams) | Team | 31B–31G: 4 boards plus alternate, board order by rating, team average cap, paired by match points then average rating, colors follow board 1 | Match points (1/½/0; variation 2.5 of 4 to win), tie-break 34G2 | A few large events a year | Occasional, large | Missing |
| Team league (Boylston Metropolitan League, high-school leagues) | Team | Scheduled fixtures, two games per board (one each color), home team black in game 1 | Match points, board prizes | Clubs, school leagues | Occasional | Missing (side games cover single matches) |
| Scheveningen (club vs club) | Player | Fixed tables, rounds = boards | Aggregate | Clubs | Rare | Done (`Format.scheveningen`: home team is side A, sides may differ in size, every round printed, match score in the heading) |
| Holland, unbalanced Holland | Player | Round-robin prelims then finals | 1/½/0 | Blitz events | Rare | Done (guided: `make_holland` prelims, `make_holland_final` from standings; 30I qualification) |
| Match (two players, 2+ games) | Pair | Fixed; 400-point gap, rating caps | 1/½/0 | Playoffs, challenges | Rare | Side games cover it; the rating preflight flags a match (400-point gap, caps) |
| Online rated events | Player | Any OTB format; online ratings, never dual | Same | Clubs | Occasional | Flag only |
| Unrated events | Any | Same mechanics | No rating | Clubs | Occasional | Done (no report) |
| Ladder | Player | Challenge the player above; not a rated format | Position | Clubs | Rare | Done: standing list, challenge up to 2 places, a win takes the place; rated unless marked Not rated |
| Bughouse (Scholastic Regulations App. B) | Two-player partnership | Swiss on match score; one match per pairing (two coupled boards), G/5 d0, 5–6 rounds | Match points 1/½/0 to both partners | Scholastic side events, clubs | Rare | Done: partnerships formed before round 1 (Partners panel, `set_partners`), partnership Swiss (`bughouse-swiss-v1`), partners share the match points, always unrated and left out of the rating report |
| Simul, knockout, arena | Various | Not US Chess ratable (ch. 10 3B) or not defined by the rulebook | — | Side events, online | Rare / online only | Knockout done: seeded single-elimination bracket of 1- or 2-game matches, byes to the top seeds, the director decides drawn matches or rapid/blitz/armageddon tie-break legs are posted, placings instead of points (`knockout.dart`); simul and arena out of scope |
| FIDE Swiss (Dutch, Burstein, Lim), FIDE team Swiss | Player / team | C.04 | C.07 | FIDE-rated clubs | Common at big clubs | Missing (planned tranche) |

Sources: rulebook 27–31, 34, chapter 10; [Scholastic Regulations 2026–27](https://new.uschess.org/sites/default/files/media/documents/us-chess-scholastic-regulations-2026-2027-v1.0_8-9-2026.pdf) §5, §10, §12, App. A–B; [USAT East 2027](https://njscf.org/world-amateur-team-2027); [USAT North 2026](https://www.kingregistration.com/event/usatn2026); [Texas Teams 2026](https://sites.google.com/view/2026-texas-teams/tournament-format-regulations); [FIDE C.04](https://handbook.fide.com/chapter/C0401202507); [FIDE team Swiss](https://handbook.fide.com/chapter/SwissTeamPairingSystem202602); US Chess FAQ on matches (`research/local/uscf-faq.txt`); [Lichess arena](https://lichess.org/tournament/help?system=arena).

### Frequency evidence

- US Chess upcoming tournaments, 90 listings for 10–27 October 2026: 18 labelled Swiss, 28 weekly one-game-a-night events (structurally Swiss), 12 blitz, 10 rapid or quick, 14 scholastic (quads and Swiss), 5 quads or round robins, 3 online, 0 team.
- Marshall Chess Club, 42 listings: 41 Swiss (11 FIDE-rated), 1 quads, 0 team. Mechanics' Institute, 21: 4 scholastic Swiss, 4 quads, 4 one-day club events, 3 FIDE weekends, 2 blitz, 1 rapid. Charlotte, 22: 5 scholastic, 2 quads, 2 rapid, 1 blitz, 1 norm round robin, weekly Swisses, 0 team.
- Boylston, September and April 2026 calendars, about 24 events: 7 OTB Swiss, 3 online, 4 quads, 7 blitz (3 unrated), 1 rapid, 2 scholastic, 2 league nights, 1 simul.

Rough shares: individual Swiss 55–65%, blitz 10–15%, scholastic individual/team 10–15%, quads and round robins 8–12%, team Swiss, leagues and matches 2–5%, everything else under 1%.

### What a fixed-roster team event needs (for when it is built)

From rules 31B–31G and 34G plus the USAT pages: a team as the entry, with a name, a captain, four boards in rating order (an alternate must be lower rated than the regulars), a team average rating with the event's cap and board-gap rules, a per-round lineup with lower boards moving up when someone is missing, a match result built from four board results (match point 1/½/0; some events require more than half the game points to win), standings by match points with game points and the USAT tie-break (opponents' match score times game points scored against them), two wall charts, and a rating report that still lists every board game. Scholastic individual/team needs far less: the existing team label, a top-N team score, and team tie-breaks summed from the individual ones.

## 2. How other tools present the choice

| Tool | How the format is chosen | What that first screen asks | Hidden or advanced |
|---|---|---|---|
| SwissSys 11 | Per-section "Event type" dropdown (Regular Swiss default; Individual/Team, Fixed-Roster Team, Round Robin, Ladder, Team Match), a "Dbl" style for double rounds, quads through a Tools wizard; locked after round 1 | Name, type, style, coin toss, rating type, time control, rating range, first board, final round, exclude from report, side game, entry fee | Rules for Pairing: engine, hard/soft restrictions, three-colors-OK, oddman method, equalizing limits, bye strictness, accelerated, 1-vs-2; six tie-breaks in a two-list picker; settings live in a machine-level INI by default |
| WinTD | Section dialog with Section Type and "Pair As" (Swiss, round robin, accelerated variants, Scheveningen, ladder), games per round | Title, boards, type, rounds, games per round, time control, rated flags | Pairing Rules tab (US Chess/FIDE, color importance, 200/80 limits), preferences, team weighting |
| Swiss-Manager | Four file types at New (Swiss, team Swiss, round robin, team round robin); "every format is one of these plus a few parameters" | Tabbed setup: general facts, tie-breaks pre-filled | Team boards, bye points, replays; "Copy tournament data" from the last event is the preset |
| chessroster | Three-step wizard, step 1 is "name, place, dates, format" in a minute; pairing settings on their own screen, FIDE mode "collapses the screen to almost nothing" | Essentials only | Full US Chess controls in expandable groups with inline help; organizer defaults copied into each event, never live-linked |
| Tornelo | Format tab per section; team battle is a checkbox on Swiss | Format and tie-breaks | "All-play-all in two clicks" |
| Lichess, chess.com | Separate create pages per type (arena, Swiss) | Clock, rounds, start time | Entry conditions |

Patterns that worked: the type chooses the option set; essentials first and the rest later; copy-last-event as the preset; persistent rules kept apart from per-round knobs. What drew complaints: federation-biased defaults buried in settings, rules living on the laptop instead of in the file, formats locked after round 1 with workaround folklore, quads with no first-class type anywhere, and "the UI feels stuck in 2003".

Sources: `research/local/swisssys-tournament-types.txt`, `research/local/swisssys-rules-for-pairing.txt`, `research/local/swisssys-tournament-setup-and-tools.txt`, [WinTD section dialog](https://estima.com/chess/wintdhelp/topics/dialogboxaddeditasection.html), [Swiss-Manager guide](https://www.chess.com/article/view/swiss-manager), [Vega manual](https://www.vegachess.com/download/vega_en.pdf), [Tornelo pairing options](https://home.tornelo.com/knowledge-base/what-pairing-options-can-i-use/), `research/local/chessroster-organizer-pairing-settings.txt`, [SwissSys vs WinTD](https://forum.uschess.org/t/swisssys-vs-wintd/17980), [TD software thread](https://www.chess.com/forum/view/general/chess-td-software).

## 3. What TDs change, by cadence

- **Per event:** name, dates, time control, rounds, rating system, sections and their rating caps, bye policy and deadlines, prizes, tie-break order (rarely changed from the default).
- **Per section:** format (Swiss, quads, round robin, team), first board, rating cap, one or two games per round, team-mate avoidance, side-game status.
- **Per round, rarely:** a forced bye or pairing, acceleration on or off.
- **Almost never:** color variations, the 80/200 limits, odd-player method, bye strictness, round-robin table choice, lot method. SwissSys stores these per laptop and tells first-timers to accept the defaults; chessroster's FIDE mode removes them from view entirely.

## 4. Where Meow Chess stands

The engine covers the common 85–90% of events: individual Swiss in every rated speed, double-round blitz, quads with a bottom Swiss, round robins, re-entries, accelerated pairings, team-mate avoidance, prizes, tie-breaks and bye policy. The visible gaps, in order of how often a club TD would meet them: scholastic team standings (a day or two, reusing the team label), fixed-roster team events (a new tranche: team as entry, lineups, match scoring), FIDE Dutch pairings for FIDE-rated clubs, then rarities (Scheveningen, Holland). Today's risk is not missing formats but the opposite: the rules-conformance pass added seventeen fields to the section settings panel, which is exactly the SwissSys failure the product exists to avoid.

## 5. Design brief: offering every format without a thousand options

Mode: Operate. Visual world: the incumbent "Wall Sheet" system in `DESIGN.md`; this is a refinement of the New section and Section settings panels, not a redesign. Written without a discovery interview (the director was away), so the assumptions at the end are explicit and need a yes or a correction.

**Job and audience.** A solo club TD making a section before players arrive, or adjusting one between rounds, under interruption. They think in what they announced ("5SS, G/90+5, Open/U1910/U1510", "Friday blitz, two games a round", "quads, bottom Swiss"), not in engine settings. Success: the common formats take three decisions, the announced rules are visible in one glance, and nothing the rulebook decides for them ever has to be opened.

**Outcome and proof.** Creating a Saturday quads, a weekly Swiss or a Friday blitz section asks for nothing beyond what the TD already announced. The printed event conditions sheet is correct for a TD who never opened an advanced group. A TD who runs a scholastic with team awards or a USAT-style event finds those as formats, not as settings scattered across groups.

**Selected direction: ask for the announcement, not the mechanism.**

1. **Format stays a three-way choice,** Quads / Swiss / Round robin, exactly as today. It is the pairing unit and method, the one decision that changes everything else. It grows only when a new pairing unit ships: a fourth segment **Teams** for fixed-roster team events, and nothing else. Blitz, rapid, online, unrated, scholastic, accelerated and class sections are not formats; they are properties of a Swiss and never appear on this row.
2. **The announcement line** replaces today's loose rounds field and "More settings": directly under the format, the three things every TLA states, on one ruled band: **Rounds**, **Time control**, and **Games per round** (One / Two, the two-game blitz match, replacing "Two games each" for round robins and newly offered for Swiss). The time control's rating category is shown as a muted word beside it ("Regular", "Dual", "Blitz") because that is what the TD checks, and the 5E2 delay hint lives there. Quads keep their fixed three rounds and show the bottom-Swiss sentence instead of a rounds field.
3. **Everything else is an announced rule, inside closed DisclosureGroups** (the ruled header rows with a chevron and a right-edge muted summary that the player card already uses). Four groups, each with the rulebook default pre-filled so the summary reads **US Chess default** until a TD changes something:
   - **Byes** — last round for half-point byes, limit per player, request deadline, irrevocable from round (22C). Summary: "Half-point byes any round" or "Through round 3 · 2 per player · irrevocable from round 5".
   - **Pairing rules** — for Swiss: accelerated (off / added score), keep team-mates apart, the four announced variations as checkboxes named in words ("Color priority to the lower-ranked player in minus groups (29E4a)"); for round robins: table (circle or Crenshaw-Berger), second cycle with colors reversed, and the **Draw lots** action; nothing for quads. Summary: "Standard rules" or "Accelerated rounds 1–2 · team-mates apart".
   - **Prizes** — the existing prize table editor, moved here from the section menu. Summary: "None" or "$500 · 6 prizes".
   - **Players** — side games, first board number, rating cap. Summary: "Boards from 5" and so on.
   Tie-breaks stay event-wide in Event details, and the group header for Pairing rules carries one muted line "Tie-breaks: US Chess default · Event details" as a link, so a TD looking for them in the section finds the way.
4. **Lock, do not disable.** Once round 1 is posted, Format, Games per round and Pairing rules show a lock glyph and "Set before round 1" in the summary instead of greyed fields; Byes, Prizes and Players stay editable. This replaces SwissSys's workaround folklore with a plain statement of what is fixed.
5. **New section and Section settings become one panel.** The New section panel keeps its "Who goes in" radio group on top; below it the format row, the announcement line and the four groups are the same component the settings panel shows, so nothing is learned twice. The filled button stays the only blue in the panel and keeps naming the outcome.
6. **The preset is the last event.** No template gallery. The welcome screen's New event offers **New event like…** with the recent events list; it copies sections (names, formats, announcement lines, groups, prizes), the event's tie-break order, time control and TD IDs, never players or results, and says so in one line. A club that runs the same Friday blitz every week makes it in one click. This is the pattern that works in Swiss-Manager and chessroster and the one SwissSys lacks.
7. **Format-specific intelligence stays in the format, not in settings.** Quads already decide the bottom Swiss; a round robin shows "n players: n−1 rounds"; two games per round sets bye values and doubles reported rounds; a Swiss with team labels on its players offers **Team awards** (top-N scoring) as a fifth group only when at least two teams exist (this is the scholastic feature to build next); the future Teams format brings its own panel section (boards, lineup, match scoring) and hides the Swiss-only groups.
8. **What never appears anywhere:** the engine's internals (look-ahead versus top-down, the 80/200 limits, odd-player ordering, bye tiers, search budgets). They are the rulebook's defaults, they are explained per round in the pairing explanations, and the event conditions sheet names the variation set. A TD who wants a different engine behavior changes an announced rule, never a dial.

**Scope and boundaries.** Fidelity: production panel, laptop width, 200% text, keyboard-only; the 360px dock. Breadth: New section panel, Section settings panel, the section context menu (Prizes… and Draw lots move into the panel), Welcome screen's New event like…. Untouched: Players, Pairings, Reports, Export, the import window, the Event details panel beyond its existing Standings group. Anti-goals: no wizard with steps, no modal, no "advanced mode" toggle, no icons for formats, no per-laptop settings file, no fourth format segment before the Teams tranche exists.

**States and ranges.** Sections from 2 to 300 players; 1 to 32 rounds; summaries must fit the 360px panel at 200% text (two lines allowed, truncated with the full text on open). Empty prize table, no teams, a section already paired (locked), a section converted from quad to Swiss by player count (the format row shows "Swiss (was quads: 6 players)").

**Interaction and layout.** Top to bottom: title; Who goes in (New section only); Format segments; the announcement band: Rounds and Time control as two 36px fields on one row with the rating category word under the time control, then Games per round as a two-segment control; then the four ruled group rows; footer with the one filled button and Discard draft. Groups open instantly, remember their state across sections, and every field inside applies on Save with undo like today. Problems stay beside the field in the group, and a problem inside a closed group opens it.

**Constraints and open decisions (assumptions to confirm).**
- A1: Tie-breaks stay event-wide (rule 34B posts one order for the event). If a club wants per-section orders, that is a later change.
- A2: Prizes move from the section context menu into the panel's Prizes group; the context menu keeps Print, Rename or settings, Combine, Delete.
- A3: "New event like…" copies structure only; it never copies players, even withdrawn ones.
- A4: Team awards (scholastic top-N) is the next format feature to build; fixed-roster Teams is a separate tranche and does not get a placeholder segment.
- A5: The seventeen-field settings panel shipped on 2026-10-09 is replaced by this layout before the next release; the fields themselves (and their MCP tools) keep their current names.

## 6. Build order suggested by this research

1. The panel restructure in §5 (one or two days): it removes today's clutter and needs no new engine work.
2. New event like… on the welcome screen.
3. Scholastic team awards: top-N team standings, team tie-breaks (Scholastic Regulations §12.3.3), a team standings report and a Team awards group.
4. Fixed-roster team events (31B–31G, 34G2) as the Teams format, after a TD confirms the demand.
5. FIDE Dutch pairings and FIDE tie-breaks for FIDE-rated clubs (planned tranche).

## 7. The rare formats (built 2026-10-09)

Arena and simuls are skipped on purpose (nothing to pair; not ratable). Everything
else is being built on one shared contract so the main UI does not grow:

- `Format` gained `scheveningen`, `knockout`, `ladder` and `bughouse`; `Format.common`
  says which three sit on the format row, and the rest are reached through
  **Other format…**. Holland is not a format but a guided creation (prelim round
  robins, then a final) carried by `Section.holland`.
- The model carries each format's own data: `Section.homeTeam` (Scheveningen side A),
  `Section.bracket` (knockout seeds, games per match, optional tiebreak games, the
  bracket as played), `Section.partners` and `Game.whitePartner`/`blackPartner`
  (bughouse), `Section.unrated` (left out of the rating report), and a ladder's
  positions are simply the order of `Section.players`.
- `proposeRound` dispatches by format to `scheveningenRound`, `knockoutRound` and
  `bughouseRound`; a ladder has no rounds to create and refuses with a plain
  message; quads and round robins keep their fixed schedule; `hasFixedSchedule`
  replaces every "not Swiss" test that really meant "quad or round robin".
- The section panel never learns a format's fields: each format registers a
  `FormatExtension` (fields, values, apply, summary, problem) in
  `lib/ui/format_extensions.dart`, and the panel shows them inside Pairing rules
  for that format only. Adding a format later is one domain file, one extension
  and one line in the pairer's switch.
- Knockout ties: the director decides who advances by default; rapid, blitz or
  armageddon tiebreak games are an option, never the default.
