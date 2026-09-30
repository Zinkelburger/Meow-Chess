# Design references and report layout

Planning only. The earlier workspace sketch has been retired to avoid conflicting
navigation and shortcut instructions. Use these authoritative contracts:

| Concern | Current specification |
|---|---|
| Event workspace, section tabs, navigation and common workflows | [TD experience](TD_EXPERIENCE.md) |
| Editable player, byes, withdraw/reinstate, transfers and combining sections | [TD operations](TD_OPERATIONS.md) |
| Immediate 1/0/5 and W/L/D results, focus, correction and recovery | [Results entry](RESULT_ENTRY.md) |
| Usability gaps, priorities and realistic rehearsal scripts | [TD usability review](TD_USABILITY_REVIEW.md) |
| Release scope and required proofs | [Requirements](REQUIREMENTS.md) and [delivery](DELIVERY.md) |

One Event tab plus section tabs; within a section use Players, Rounds, Standings,
Reports, conditional Teams and Section settings. Crosstable is in Standings.
Approve pairings, Print and Post online are distinct actions. Save/Cancel applies
to player-detail forms; result shortcuts commit immediately and advance on durable
success. The source and layout details below supplement those contracts.

Reuse table selection, column sizing, navigation and empty/error states where their
semantics agree. Do not force every workflow into one monolithic widget. View models
own feature state so rebuilding tabs preserves the TD's place; user preferences
remain separate from competition policies.

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
