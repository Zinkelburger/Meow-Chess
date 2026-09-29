# Event workspace and design system

This is an interaction specification, not a built screen or tested mockup.

## Main workspace

```text
Meow-Chess  /  September Quads        Saved 20:14   Offline   Print  Export
Overview | Quad 1 | Quad 2 | Quad 3 | Quad 4 | Bottom Swiss 6 | + Section
------------------------------------------------------------------------
Players   Pairings & Results   Crosstable   Standings   Settings
Round 2 of 3      1 result missing                 Review next round
Find player or board...                           View options
------------------------------------------------------------------------
Board  White                  Result   Black              | Board details
  1    A. Example (1810)       1-0      B. Example (1770)   | Rating sources
  2    C. Example (1790)       --       D. Example (1750)   | Pairing reason
                                                         | Result history
------------------------------------------------------------------------
4 checked in  /  4 entered     Current section: Quad 1     No blockers
```

One persistent top tab per section follows the user's requested SwissSys mental
model. Overview is the event-wide control surface: check-in totals, unresolved
identity issues, each section's current round and reporting status. It is not a
second editable copy of all section data.

Opening a new event leads to Players/registration. During play the selected
section returns to Pairings & Results at the last round. Do not move the TD to a
different tab when an API lookup completes. Each section retains scroll, filters,
focused row and the open details panel. Section IDs survive renaming/reordering.

Many quads require horizontal tab scrolling plus a searchable section switcher,
keyboard previous/next section and status badges. Closing a view never deletes
a section. Deleting/removing a section is a separate explicit operation.

## A quad flow people can trust

From Overview: **Create quads** → choose checked-in pool and rating policy → review
ordered groups → adjust ties/unrated placements → inspect the bottom Swiss and
bye implications → create sections → review round one.

The preview says “22 players: 4 quads + 1 six-player Swiss, 3 rounds each.” A late
arrival updates only a draft preview. Once applied, later changes show which
players/sections would move and whether any pairings invalidate. Keep source
registrations; do not duplicate entrants as independent people.

## Import and identity review

Use one reusable import review table: raw input, mapped field, normalized value,
finding and proposed action. Recognize likely headers but keep mapping editable.
Show a compact count of rows ready, needing review and excluded. Importing a public
entries table does not automatically mark everyone present or paid.

**Validate players** opens a cancellable batch. The review pane compares entered
name/ID with the official record and separately offers name, membership and rating
updates. Exact IDs with discrepant names receive attention; possible one-digit
repairs remain proposals. Show published and latest ratings together, with source
and date available on demand. Unverified latest data must remain visibly unverified.

## Pair, enter, correct

Pairing generation opens a proposal in place. Show score-group/color explanations,
byes and unresolved restrictions. Publish is the strongest action. Re-pairing a
posted round previews its impact and creates a new revision.

Result cells support tab/arrow navigation and clear win/draw/loss commands. Suggested
keys are `1`, `=`, `0` for White win/draw/Black win when the result cell owns focus;
never apply them while typing in search. Provide a labelled menu for byes/forfeits
and other states. `--` means unreported, not zero. A double-round match expands to
two leg results; aggregate entry must be unambiguous or require the individual
results before rating export.

A saved edit shows a short acknowledgment; errors stay at the row. For an older
round, show correction consequences before applying. Display who/when/why in
history without burying normal entry under repeated confirmations.

## Reusable components worth building

EventWorkspace, SectionTabStrip, SectionSwitcher, TournamentTable, ResultCell,
PlayerIdentityCell, RatingBadge, ValidationSummary, ReviewDiff, DetailsPane,
SaveStatus and ReportPreview. Reuse table selection, column sizing, keyboard
navigation and empty/error/loading states across screens. Do not force every
workflow into the same monolithic table widget if editing semantics differ.

Keep app services out of widgets. Store state in view models/domain owners so
rebuilding a tab does not reset an event. Persist user column preferences separately
from competition settings.

## Chess Auto Prep V2 references

Read-only source inspection at commit `a6c1f09432bcdd53c3081d9493ec59d0c76e79c0`:
`lib/v2/ui/theme.dart`, `lib/v2/ui/pane_tabs.dart`, `lib/v2/app/document_tabs.dart`
and `lib/v2/app/shell.dart`; also the newer `lib/design_system/theme/` and
`lib/design_system/layout/` to distinguish V2 appearance from current migrations.

The original V2 palette uses surface `#1B1B1D`, panel `#242427`, selection
`#38383D`, text `#E6E6E8`, muted `#9A9AA0`, accent `#8EAAD2`. Its spacing scale is
4/8/12/16/24 and pane tabs are compact. The newer design system uses a different
neutral palette (`#121212`/`#1E1E1E` surfaces); do not accidentally claim the two
are identical.

Proposed Meow-Chess appearance: V2 charcoal/blue as the initial reference, semantic
theme tokens throughout, Inter text and Source Code Pro for numbers/ASCII previews,
compact rows with an accessible roomy setting. Use 14px body and no ordinary text
below 12px; validate 150/200% scaling. Default Dark; support Light/System and a
separate high-contrast white print style. Verify contrast rather than assuming
copied colors pass. Fonts require their own retained licenses.

Reuse design concepts first. Do not bring along PGN, Stockfish, repertoire,
chessboard, or analysis dependencies. If source widgets are later copied, keep
AGPL attribution and extract only genuinely independent pieces.

## Reports

Print current section or selected/all sections; choose pairings, alphabetical
pairings, crosstable, standings or registration list. Show event, section, round,
revision timestamp, legend and page number. Repeat headers, avoid splitting rows,
and use a new page for a section when requested. Support Letter/A4, orientation,
margins and scale without shrinking text into illegibility.

ASCII output is space-padded with a fixed-pitch font. Use `0.5`, not a Unicode
half glyph, and ASCII line characters. Preserve full Unicode names in the event;
preview a deterministic transliteration/export alias when ASCII is requested.
Offer UTF-8 text separately. Wide events need explicit landscape/column splitting,
not silent clipping or arbitrary removal of rounds. All renderers consume the same
immutable report snapshot; exporting to text and PDF must not recalculate different
standings.

See the [synthetic ASCII crosstable](../research/examples/quad-crosstable.txt)
for a concrete fixed-width example. It is a planning artifact, not generated app output.

## Desktop first, adaptable later

At narrow widths the details pane becomes a drawer and section switching becomes
a compact selector. Keep current section/round always visible. Tablet result
entry is a possible future mode; phone administration is not claimed now.
Screen readers need semantic table headers, result labels and announced errors;
color must never be the sole signal for a conflict, bye or save state.
