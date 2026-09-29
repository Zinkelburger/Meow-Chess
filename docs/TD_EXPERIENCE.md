# Meow-Chess: tournament director experience

Proposed design, September 2026. This expands and refines [UX.md](UX.md); where
navigation names differ, this document is the current proposal. No app UI exists.
The in-conversation concept illustrates layout and local interactions only.

## Product promise

**Know what needs attention, do the next tournament task quickly, and recover from
mistakes without losing trust in the event.** Fun means responsive, understandable,
and satisfying. The product can have a little cat personality in onboarding and
empty states. Results, pairing exceptions and submission errors use plain language.
No confetti, fake success scores, distracting motion or playful error messages.

## The main view

Use one persistent event workspace, in the visual style of Chess Auto Prep V2.

```
Meow-Chess  /  Saturday Quads         Saved locally     Find / commands   Event menu
Event | Quad 1 | Quad 2 | Quad 3 | Quad 4 | Bottom Swiss       All sections / +
Players    Rounds    Standings    Reports                 Section settings
Round 2 of 3    Published · revision 1       2 results missing      Print pairings
Board  White                         Result             Black
9      Alex Chen       1.0            1–0                Jamie Patel    1.0
10     Morgan Reed     0.5            —                  Sam Rivera     0.5
11     Taylor Brooks   0.0            —                  Casey Park     0.0
                                                       Selected game / player
```

The section strip is global within an event, matching the user's requested mental
model. Within each section, the four task views share location, typography and
controls. Do not add a second permanent app sidebar to these two navigation levels.
The inspector is contextual and closable, not a permanent analytics dashboard.

**Default opening behavior:** recent event resumes the previous section and view.
A new section opens Players; first published round offers to open Rounds; selecting
a section preserves that section's view, round, filters, scroll and selected row.
Never jump the user's screen automatically because background validation finished.
The Event tab summarizes section progress and actionable blockers across the event.

### Screen responsibilities

| Place | What the TD does here | Principal action / details |
|---|---|---|
| Event library | Open recent event, restore, start from template, manage club directory | New event; explicit last saved/opened timestamps |
| Event | See section readiness, missing results and imminent rounds; manage sections, boards and schedule | Contextual event action; section rows jump directly to problem |
| Players | Import, register, check in, validate IDs, assign teams/byes and make quads | Import before roster exists; Add player thereafter; check-in count visible |
| Rounds | Review/publish pairings, enter outcomes, inspect/change historical rounds | Review pairings before play; next missing result during play |
| Standings | Read official rank, crosstable and team score; explain ties; calculate prizes | Print standings; segmented Table / Crosstable / Prizes |
| Reports | Preview and produce operational sheets, exports and federation package | Print or Export, with explicit scope and revision |
| Teams, conditional | Set team roster, active boards, substitutes and match rules | Add team; only shown for meaningful team management |
| Section settings | Format, eligibility, scoring, pairing, ratings, tiebreaks and boards | Search settings; show inherited vs overridden values |
| Event menu | Save copy, checkpoints, history, event settings, archive and diagnostics | Stable menu; destructive operations separated |

Do not make users choose an expert mode to discover functionality. Use task-oriented
names, sensible defaults, concise explanations and advanced disclosure in each
relevant place. Keep a searchable command list with SwissSys synonyms: “wallchart,”
“tinker,” “quad setup,” “rating report,” “pair numbers.” Results show the scope and
location before running a command.

### Section strip at scale

At six sections, show named tabs with a small textual state, not dozens of counters.
At twenty or more, preserve selected/pinned tabs and provide searchable All sections;
support keyboard next/previous section and reorder. Tabs may scroll horizontally
on desktop; a section picker replaces them on narrow screens. Never shrink text or
truncate all names to indistinguishable prefixes. Closing a view is different from
deleting a section. Section deletion lists contents/played-game implications.

## Core interaction specifications

### 1. Set up an event

Choose a template: Swiss, Quads, Round robin, Double-game blitz, or an available
team format. Enter name/date, rounds/time control, rated status and rating policy.
Advanced rules remain collapsed with effective defaults summarized in plain text.
Finish opens the relevant working screen, not a generic success page. Clone a prior
event as settings only by default; copying participants is an explicit choice.

Never offer unsupported federation or pairing modes as if functional. Show their
availability honestly. Draft events can be created without affiliate/TD IDs;
submission validation requires the necessary metadata later.

### 2. Import a messy roster

Paste rows or choose file → map columns → review → import. Preview actual interpreted
names, IDs, section, rating and team. Support missing columns, duplicate headings,
extra notes, leading-zero IDs, quoted delimiters and non-ASCII names. Remember a
mapping under a source name, without assuming all future files have the same shape.

The review groups exact duplicate records, possible identity collisions and invalid
fields. It permits importing valid rows while retaining rejected rows for repair.
Reimport presents additions, changes and withdrawals as a diff; never erase a player
merely because they disappeared from an incomplete external list. Source roster is
provenance, not the unquestioned owner of live tournament state.

### 3. Validate players and update ratings

One action starts a queued lookup. Each row has a plain status: Verified, Name
mismatch, ID not found, Membership issue, or Could not check. Clicking opens local
and federation values side by side, with source timestamp and rating category.
Accept a verified correction individually or apply a batch of reviewed safe changes.
No fuzzy match is automatically accepted. A lookup failure is not evidence an ID is
invalid. “Latest unavailable” is distinct from the published rating.

Show effective pairing rating independently from fetched values. Changing it after
pairing warns about eligibility, prize classes and draft pairings; an existing
published round is immutable until explicitly revised. API key settings belong in
Data sources; missing credentials do not prevent local tournament operation.

### 4. Make quads without section gymnastics

Players → Make quads opens a wide preview with three clear steps:

1. **Choose pool:** checked-in entries by default; show excluded and unrated entries;
   choose/freeze rating basis and tie ordering.
2. **Review groups:** display compact four-player groups in seed order, rating range,
   board range and names. For 22 players propose four quads plus a six-player Swiss.
   Explain the last group directly: “Six players remain; play a three-round Swiss.”
   Allow explicit alternative sizes and reviewed player moves; offer keyboard
   Move to group as well as drag/drop. No orphan groups of one or two by surprise.
3. **Create sections:** summarize groups, format, rounds and exceptions. One atomic
   action creates all sections. Undo is available before dependent actions.

This is a normal top-level workflow, not a hidden utility. Section generation is
separate from publishing round-one pairings. A late player prompts a controlled
choice about the affected group; it never silently repartitions every quad.

### 5. Pair and publish a round

Click Review next round → inspect draft board table → resolve issues → Publish.
Draft and published labels are unmistakable. Show changed/exception rows, an
explanation for each pairing, reserved boards and unpaired entries. A warning says
what will happen and whether it blocks publishing. TD policy overrides record a
reason; structural invalidity (one player on two boards) cannot be waived.

Publish makes a durable local revision available to print. Public online posting is
a separately configured action, with its own status. Failure to post online does
not roll back local pairings. Manual edits after publication produce a replacement
revision and indicate that previous paper/web copies are stale.

### 6. Enter results at tournament speed

Rows show board, white name/rating/score, outcome, black name/rating/score. Clicking
an outcome opens compact win/draw/loss choices plus Other outcome for forfeits/byes.
Keyboard 1 / = / 0 applies only with a focused game result cell; Enter advances to
the next missing result. Names and board numbers remain visible during entry.
No global single-key destructive shortcuts; announce player names/outcome to assistive
technology. A result-entry footer can show keys, with a preference to hide it.

Save each confirmed result transaction immediately; offer Undo without a modal.
Already-entered outcomes require an explicit correction action, not accidental
cycling. `—` means unreported. `0–0` means a specific confirmed outcome, never an
empty result. Double-game rounds expose Game 1 and Game 2, plus their match total;
the total is not an editable substitute for individual ratable games.

The missing-results filter is a toggle with count. Clearing the last missing result
shows “All results entered” and enables Review next round. Do not publish a round
because the last result was entered. User remains in control of timing.

### 7. Correct an earlier mistake

Select historical round/game → Correct result → review effect on score, ranking,
prizes, published reports and any later pairing. If later games have happened,
retain them; give the TD policy-specific options. No cascading silent deletion.
If reverting an unplayed round, show exactly which proposals/publications become
superseded. Keep audit trail and prior exports. The history view shows who/when/why
where available, and distinguishes correction from restoring an older event copy.

### 8. Print what the room needs

Reports has a compact template list at left, page preview center and collapsible
layout controls. Most-used templates first: pairings, alphabetical pairings,
standings, crosstable. Scope is explicit: this section / selected sections / all.
Round and publication revision are visible. Remember layout per report, not as an
unexpected global printer preference. Print all sections as separate labeled pages.

ASCII crosstable uses a monospace preview and downloadable text; expose printable
name aliases if transliteration is needed. Original Unicode name remains intact.
PDF/print defaults use white paper, high contrast and repeat table headers. Warn
about columns that cannot fit, with sensible landscape or multi-page alternatives.
Printing failure retains the preview and allows PDF/text export.

### 9. Finish and submit

Rating submission is a guided workspace: Event details → Check games/players →
Preview package → Export. Group issues by actionable problem, with links to exact
records. Explain why forfeits/unplayed games differ from scored points. Produce
three US Chess DBFs and a human-readable manifest from one event revision.
“Exported” does not mean “Submitted” or “Accepted.” The TD can record submission and
acceptance details; automated submission needs a separately verified integration.

### 10. Teams and bughouse

Individual team labels, fixed-board team matches, and fixed-partner bughouse are
separate event templates. Teams view shows roster and eligibility; Rounds shows
matches with expandable board games. Match points and board points use explicit
labels. Team-name autocomplete shares a club dictionary without altering past
names. Replacing a team member is effective from a chosen round.

Bughouse match rows show both partnerships and two boards. Define result conventions
before UI implementation. Experimental estimated strength belongs in Matchmaking
settings and an explainable preview; ordinary scores remain the standings. Permanent
partners alone cannot establish reliable individual skill differences.

## Visual language and reusable components

Use V2's dark neutrals: background `#1B1B1D`, panel `#242427`, selected surface
`#38383D`, primary text `#E6E6E8`, secondary `#9A9AA0`, accent `#8EAAD2`. These are
starting tokens, with contrast verified for real states. Use restrained borders,
small corner radii, Inter for UI and a monospace face for IDs/ASCII output. Use
4/8/12/16/24 spacing. Comfortable default row height about 44px; compact about 36px;
coarse-pointer targets at least 44px. Body text 14–16px, secondary no smaller than
12px. Actual zoom/system text settings take precedence over density.

Use accent for selection and one principal action. Status includes a word/icon,
never color alone. Keep scan-critical names and scores aligned; right-align numeric
columns and use tabular digits. Avoid zebra-striping plus heavy grid borders plus
colored cell backgrounds simultaneously. Focus rings are always visible. Honor
reduced motion. Light/system appearance must reuse semantic tokens; printing has
its own white-paper theme.

Reusable primitives: EventShell, SectionTabs/SectionPicker, TaskNavigation,
TournamentTable, ResultEditor, PlayerIdentity, RatingObservation, IssueList,
ContextInspector, ReviewChanges, PairingProposal, ReportPreview, SaveStatus,
CommandSearch and HistoryView. These are responsibilities, not a mandate for one
class per label. Keep business decisions out of widgets.

At narrow widths, fold the inspector into a sheet and use a section picker; give
results a board-card layout preserving both player names. Desktop is the first
editing release. Mobile is a deliberate responsive design, not a shrunken desktop
table. A browser spectator view and offline native desktop editor have different
requirements; Flutter sharing does not erase those differences.

## State and feedback rules

| Condition | Presentation and behavior |
|---|---|
| No roster | Import/paste and Add player; small link to sample event |
| Loading ratings | Inline progress/cancel, other tasks usable; retain existing values |
| Offline | Saved locally plus data-source status; pair/score/print still work |
| Unsaved/error saving | Persistent high-priority explanation and recovery path; do not pretend saved |
| Validation issue | Named problem, affected records, direct repair action |
| No legal pairing found | Show constraints and unresolved entries; allow reviewed policy change/manual proposal |
| Stale draft | Explain input changed; regenerate or review changes before publish |
| Deleted record with history | Archive/withdraw or explicit supported migration, never erase played games invisibly |
| Operation cannot run | Explain missing prerequisite alongside control; not a mysterious disabled button |
| Long operation | Progress/cancel where safe, repeat invocation prevented, last good state retained |

Use a single issue system with scopes (event/section/player/game/report) and
severities (blocking/warning/info), not independent red badges in every tab.
Ordinary actions are undoable. Confirmation belongs to destructive or externally
visible actions with meaningful consequences, not every keystroke.

## Usability acceptance: validate before building the whole product

Test with at least one experienced SwissSys TD and one newer TD; expand beyond two
before claiming broad usability. Use realistic synthetic data and observe task
completion, errors and recovery, not just whether participants like the colors.
The following are proposed targets to measure, not results already achieved:

| Task | Acceptance target |
|---|---|
| Import 22 mixed-format names/IDs and fix one mismatch | Finish without developer explanation; no valid rows lost |
| Create four quads and bottom Swiss | Find workflow unaided; grouping/remainder understood; under 2 minutes after check-in |
| Enter 20 board results | Keyboard-only possible; target under 60 seconds once familiar; all correct |
| Correct round-one result after round two | Understand impact; later played games preserved |
| Print crosstables for five sections | One scope choice and one print action after preview; readable paper output |
| Recover after simulated crash | All acknowledged edits recovered; backup location discoverable |
| Explain why a player is ranked third | Locate tiebreak calculation from ranking without opening settings |
| Use 200% text/keyboard/screen reader | Complete core workflow without clipped actions or hover-only information |

Record failed steps and revise the prototype first. Completion rate and error rate
matter more than minimizing clicks. The interaction specification is the contract;
the visual concept is a discussion aid, not evidence of tested usability.
