# Full SwissSys coverage: product map

This is the expanded product target requested after the initial US Chess/Boylston
plan. It is a planning specification, not an implementation or a claim of parity.
The first usable release remains US Chess first. **Full coverage is the long-term
scope; incremental delivery is the build strategy.**

The [SwissSys documentation](https://docs.chessroster.com/swisssys/) is the baseline.
The [topic inventory](../research/SWISSSYS_TOPIC_LEDGER.md) accounts for all 296
links in the captured navigation, including duplicate concepts, tutorial pages,
containers, and vendor-specific administration. A navigation link establishes a
research topic, not a tested feature. The previous [research notes](../research/notes/SWISSSYS.md)
record deeper findings. A running licensed SwissSys installation and representative
files are still needed for differential tests and undocumented behavior.

## What “all features” means

1. Cover the tournament outcomes SwissSys supports, with explicit acceptance cases.
2. Preserve information when migrating supported files; identify unrepresentable
   fields before import. Compatibility names an exact format and tested version.
3. Offer comparable printing, registration, correction, and reporting depth.
4. Include international and specialist team formats eventually. They cannot be
   silently excluded while advertising full SwissSys coverage.
5. Replace vendor activation/purchasing with Meow-Chess installation, updates,
   diagnostics, license information, and documentation. Proprietary activation
   behavior is not a tournament requirement.
6. Treat hosted ChessRoster commerce and bughouse innovation as separate tracks.
   Supporting an integration does not mean rebuilding the provider's business.

Never equate identical pairings on one example with general rules compliance.
Several legal pairings can exist; specify the policy and tie resolution, preserve
an explanation, and test invariants and curated TD-reviewed cases.

## Capability catalog

IDs are stable planning identifiers. `A` = first dependable US Chess individual
release; `B` = broader club/scholastic operations; `C` = specialist/team/parity;
`D` = international/integration work with external dependencies. These are proposed
tranches, not time estimates. Every row needs detailed fixtures before building.
The screen names refer to [TD experience](TD_EXPERIENCE.md).

| ID | Capability and required depth | UI home | Tranche / proof of completion |
|---|---|---|---|
| E01 | Create/open/reopen, recent events, duplicate as template, save copy, portable archive | Event library / event menu | A: reopen with identical domain data |
| E02 | Multiple sections, new/rename/reorder/duplicate/extract/import/remove, section-specific settings | Section tabs / Manage sections | A: stable IDs despite renaming and ordering |
| E03 | Event date/site, affiliate/TD, round schedule, time control, rated/unrated and rating category | Event settings / section settings | A: export and print use effective settings |
| E04 | Linked defaults, explicit overrides, reusable club profiles and named event templates | Settings / library | B: preview every affected section before bulk change |
| E05 | Board ranges, reserved/accessibility boards, collisions, room allocation | Event → Boards | A ranges/conflicts; B rooms: no simultaneous duplicate board assignment |
| E06 | First-class Combine with command; preserve entry/history/prize/reporting identities | Section tab menu / Manage sections → Combine | A: before-play 4+6→10 Swiss and tested same-progress transition; C: specialist unequal-schedule/re-entry variants |
| E07 | Side-game sections and manually arranged games | Manage sections / Rounds | C: no double-counting main-event games |
| E08 | Multiple clubs and reusable player lists, import/update club database | Event library → Club | B: event rating snapshots do not mutate retroactively |
| R01 | Manual registration, paste table, CSV/TSV mapping, delimiter/encoding/header review | Players → Import / Add player | A: bad rows repairable without reimporting good rows |
| R02 | Native SwissSys/ChessRoster interchange where documented and tested; DTF, TRF and legacy database adapters | Import / Export | D: versioned fixtures and loss report; no guessed proprietary schema |
| R03 | Search club and federation records, distinguish persons from event entries | Players / Club | A basic exact ID; B search: duplicate identity requires review |
| R04 | Double-click/Enter on player opens editable details: ID, name, rating, team plus visible Byes/Move/Withdraw | Shared player inspector from Players, Rounds and Standings | A core editing/actions; B extended fields: original values retained |
| R05 | Bulk identity validation, membership/eligibility checks and rating refresh | Players → Check players | A: incorrect ID never auto-replaced by a guessed digit |
| R06 | Published/latest/assigned/provisional/unrated ratings, multiple rating systems, supplemental databases | Players → Ratings / Settings | A US Chess; D others: provenance/date visible; unknown not zero |
| R07 | Choose/switch pairing, eligibility and prize rating bases; freeze/reseed explicitly | Section settings / rating review | A: live updates cannot silently reorder published pairings |
| R08 | Late entries, check-in, requested byes by round, inactive status, withdrawal/reinstatement | Player inspector | A: future participation distinct from historical results |
| R09 | First-class single/bulk section transfer, effective round, prior entry history | Player inspector / Players → Move to section | A: reviewed transfer before/after play; C: specialist multi-schedule re-entry |
| R10 | Name formatting, flags, custom fields, bulk edit, sorting and pair-number adjustments | Players table / inspector | B: stable identity independent of displayed pairing number |
| R11 | Local/supplement/custom/secondary database management, Excel databases, import/index/troubleshooting | Club → Data sources | B US Chess; D other formats: partial source failures isolated |
| R12 | Multiple registration stations writing to a staging database, then reviewed import into the event | Event → Staff / Import | D: reference SwissSys network mode is registration staging, not concurrent round editing |
| R13 | Multiple named fee fields, per-section defaults, fee totals and reports | Players / Reports → Fees | B: amounts and totals preserved; accounting is distinct from processing card payments |
| F01 | Individual US Chess Swiss with configured constraints, byes, colors and score groups | Rounds / section rules | A: TD-reviewed normal and adversarial fixtures |
| F02 | Round robin and quads; preview rating groups; remainder as bottom Swiss | Players → Make quads | A: 22 players produces four quads and six-player Swiss |
| F03 | Single/double round robin, lot/seed assignment, Berger/Crenshaw tables, withdrawal handling | Section format / Rounds | A single RR; B others: schedule and rated-game views agree |
| F04 | Double-game pairing rounds, reversed colors and per-game results | Rounds | A: six pairing rounds can represent twelve games |
| F05 | Acceleration and alternative pairing policies, rating range restrictions, team avoidance, color options | Section rules / pairing review | B/C: policy named, applicability explained and fixtures cover exceptions |
| F06 | Ladder events, ladder ordering/rules and manual adjustments | Section format / Standings | C: exact semantics verified against documentation/fixtures |
| F07 | Unrated events, customized scoring and restrictions | Section settings | B: no accidental federation-rated export |
| F08 | Fixed-board teams, teams-only events, substitutions, active roster/board order | Teams / Rounds | C: match totals reconcile with board games |
| F09 | Individual Swiss with team codes, best-N scoring, subtotals, small-team merge, Rollins scoring | Teams / Standings | B basic totals; C specialized: eligibility and discarded scores explained |
| F10 | Scheveningen/team match formats and master team names/pairing list | Teams / section format | C: roster rotation, colors and match accounting validated |
| F11 | FIDE pairing modes and external engine integration | Section policy / engine details | D: current rules, engine rights/packaging and required approval verified |
| P01 | Preview next round; all-section batch proposals; publish separately per section | Rounds / Event | A: stale inputs invalidate draft; one section cannot block unrelated result entry |
| P02 | Explain pairing constraints, integrity validation and unsatisfied preferences | Pairing inspector / Issues | A: distinguish illegal state from allowed policy exception |
| P03 | Manual swaps, color reversal, boards, forced pairings/byes, locks, replacement players | Pairing review / inspector | A: manual edits and locks show impact before applying |
| P04 | Board and alphabetical pairings, team lists and complete RR schedule | Rounds → View / Reports | A individual; C team: all views reference same published revision |
| P05 | Keyboard results grid: 1/0/5 and W/L/D immediate auto-advance, all-round matrix, text import, clear selected results | Rounds | A editor; B batch import: preview conflicts and missing opponents |
| P06 | Played results, forfeits/byes, unplayed/disputed status and separate TD-approved temporary pairing treatment | Result cell → outcome | A: preserve result semantics separately from score |
| P07 | Correct earlier results; withdraw; go back/replace round; preserve later games | Rounds → History | A: explicit impact review; no silent deletion/re-pairing |
| P08 | Board history, opponents/colors and published revision history | Player / pairing inspector | A: old printed pairing can be traced to revision |
| S01 | Standings and crosstable, ties, sorted views, round filters, custom columns | Standings | A: ties displayed honestly; sorting does not change official ranking |
| S02 | Configurable tiebreak order and calculation details, bye/unplayed treatment | Standings → Why this rank / rules | A selected US Chess systems; C complete documented catalog |
| S03 | Individual/team match/game points, board prizes, federation/class/team subtotals | Standings / Teams | B/C: drill down to contributing games and entries |
| S04 | Prize classes, rating ranges, eligibility, overlapping awards, ties and distribution | Standings → Prizes | B: proposed awards with explanation and TD override audit |
| S06 | Pending and clinched prizes, eligibility warnings, unawarded cash, trophy priority, unrated restrictions | Standings → Prizes | C: explicit final/in-progress status; bounded clinch computation; confirm version-specific semantics |
| S05 | Upsets, color win statistics, estimated post-event ratings | Standings → Analysis | B/C: estimates explicitly not federation ratings |
| O01 | Print current/all selected sections: pairings, alphabetical lists, wallcharts, ASCII crosstables and RR grids | Reports | A: matching scores across TXT/PDF/preview |
| O02 | Print templates, headers/footers, logos, fonts, margins, paper/orientation, column widths, page breaks | Reports → Layout | A essential; B advanced: print legible in monochrome and with long names |
| O03 | Registration lists, board signs, certificates, membership/expiry lists, messages, labels | Reports → Templates | B: audience-safe field defaults and editable template content |
| O04 | Team reports, roster sheets, master pairings, match result forms | Reports | C: board and team identity unambiguous |
| O05 | Clipboard/current view export, CSV/TSV/HTML/text, PGN headers | Reports → Export | B: real chess games distinguished from fixtures/byes |
| O06 | US Chess event/section/player DBFs, preflight checks and reproducible package | Reports → Rating submission | A: official schema + accepted package + authorized TD validation |
| O07 | FIDE/TRF, CFC/DWZ rating reports and norm support | Reports → Rating submission | D: separate verified federation profiles and norm rules |
| O08 | Public event page, online publishing/sync, display board and hosted-site integrations | Event → Share | D: last published revision visible; no private fields by default |
| O09 | Email/player notices; optional service integration | Share / player messages | D: explicit recipient/content review, delivery status and consent handling |
| U01 | Search commands/help, contextual guidance, onboarding sample event, scratchpad | Global search / Help / Event notes | A basics; B guided sample: core tasks never require documentation hunting |
| U02 | Dark/light/system, density, column presets, localization, keyboard and accessible labels | App preferences | A dark/accessibility; B full preferences: large text does not hide actions |
| U03 | Autosave, undo, named checkpoints, backup/restore, migration/recovery, logs | Save indicator / History / event menu | A: crash/reopen recovers committed edits; undo has explicit dependency rules |
| U04 | Cross-platform packaging, updates, offline help, version and redacted support bundle | App / Help | A Windows/macOS/Linux validation; no mandatory account |
| U06 | Command-line pairing/automation, structured failures and forced-bye input | CLI / diagnostics | C: same domain validation as UI; file/version contract and noninteractive error behavior tested |
| U05 | Rule/settings profiles, import/export settings, portable preferences | App preferences / event templates | B: local preferences never accidentally alter event rules |

## Beyond SwissSys: explicit product additions

| ID | Addition | Scope boundary |
|---|---|---|
| X01 | Dedicated quad builder with rating bands and bottom-group explanation | First release; rebuilding groups after games start requires explicit historical migration, not reseeding |
| X02 | First-class identity/rating review and correction provenance | First release; API availability and credential management remain external dependencies |
| X03 | Fixed two-person bughouse teams and two-board match entry | Extension; separate unrated policy, clear partner/opponent terminology |
| X04 | Rotating partner matchmaking and skill estimation | Experimental; standings remain official event scoring; uncertainty shown; no invented USCF rating |
| X05 | Boylston-style recurring templates, season standings and playoffs | Later club extension; season points are not game/rating points |
| X06 | Online registration storefront, card payments, refunds, bundles, SMS and member subscriptions | Optional service product; beyond desktop SwissSys replacement and requires separate scope/security/operations plan |

## What prevents a truthful parity claim today

The 296-link topic inventory is a coverage index, not 296 implemented requirements.
Need access to a reference application, sample event files across supported versions,
a detailed tiebreak/prize/team-rule fixture set, authorized US Chess reporting tests,
API v2 token testing, OS printing checks, and current federation-specific validation.
The version-history page is part of the baseline; repeat the gap review before any
public compatibility claim. Do not use this list as permission to fabricate an
unknown export, approximate a norm calculation, or default an unsupported event
silently to an ordinary individual Swiss.

## Design consequence

The user should encounter **Players, Rounds, Standings, Reports** in every section.
Teams appears only for a format that needs it. Event-wide coordination belongs in
Event. Rare configuration stays searchable and also appears at its point of use.
Every capability above has a discoverable home; none requires a permanent toolbar
button. See [the interaction specification](TD_EXPERIENCE.md) and
[the build-agent handoff](BUILD_HANDOFF.md).

## Version-sensitive findings from deeper pages

The captured [version history](https://docs.chessroster.com/swisssys/versions/)
labels 11.80.4 as an August 18, 2026 release and 11.80.5 as upcoming. Its links point
to [downloads and current release notes](https://www.chessroster.com/swisssys/downloads).
Do not treat upcoming behavior as shipped just because it appears in a help page.
The expanded prize documentation includes pending/clinched outcomes and detailed
warning semantics. Capture these as explicit cases, with target-version checks.

Double-game aggregate entry is another compatibility edge: a 1–1 total can mean
two draws or split wins. If importing such a record, retain its aggregate provenance
and ambiguity; never fabricate colors/game outcomes. Offer aggregate entry only
where the event/reporting policy can represent it correctly; otherwise require
individual game results before exporting. Network registration staging must not be
marketed as evidence that arbitrary simultaneous editing is safe.

## Explicit TD flexibility priority

The user requires player editing, byes, withdrawal/reinstatement, section transfers
and combining quads into Swiss sections as core TD operations. These are first-release
gates, including historical-impact handling. [TD operations](TD_OPERATIONS.md) owns
the detailed interaction contract and supersedes any earlier implication that basic
transfers or section combining can wait for specialist parity.

## Prioritize by the director’s work

The [official-duty evidence map](../research/notes/TD_DUTIES.md) defines the basis
for workflow priority. Read it alongside the competitor inventory. Rules establish
applicable duties and constraints; our keystrokes/layout remain design proposals.
[Results entry](RESULT_ENTRY.md) is the concrete first-release keyboard contract.
Core gaps from duty review include unfinished-game handling, house-player context,
private rulings/handover, announced conditions and submitted-report correction status.
