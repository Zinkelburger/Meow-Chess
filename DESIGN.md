---
name: Meow-Chess
description: An offline TD workspace for US Chess club events, built like a wall sheet on warm paper.
colors:
  primary: "#1f4e8c"
  primary-dark: "#8fb4e8"
  on-primary: "#ffffff"
  on-primary-dark: "#0f2340"
  paper: "#f4f3ef"
  paper-dark: "#1c1c1b"
  sheet: "#ffffff"
  sheet-dark: "#242423"
  shelf: "#ebe9e2"
  shelf-dark: "#2a2a28"
  step: "#e5e3dd"
  step-dark: "#343430"
  rule: "#7f7b6a"
  rule-dark: "#858278"
  hairline: "#d9d6cc"
  hairline-dark: "#3d3c38"
  ink-inverse: "#1d1d1b"
  ink-inverse-dark: "#0c0c0b"
  practice-amber: "#f8e4b8"
  practice-amber-ink: "#4a3000"
  practice-amber-dark: "#3d2e10"
  practice-amber-ink-dark: "#f6dfa9"
typography:
  headline:
    fontFamily: "Inter"
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.2
  headline-facts:
    fontFamily: "Inter"
    fontSize: "18px"
    fontWeight: 400
    fontFeature: "tnum"
  lookup-answer:
    fontFamily: "Inter"
    fontSize: "24px"
    fontWeight: 400
    lineHeight: 1.25
  score-mark:
    fontFamily: "Inter"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.15
  board-number:
    fontFamily: "Inter"
    fontSize: "19px"
    fontWeight: 600
    fontFeature: "tnum"
  title:
    fontFamily: "Inter"
    fontSize: "15px"
    fontWeight: 600
  body:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 400
  body-small:
    fontFamily: "Inter"
    fontSize: "13px"
    fontWeight: 400
  label:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 500
  caption:
    fontFamily: "Inter"
    fontSize: "12px"
    fontWeight: 400
  mono:
    fontFamily: "SourceCodePro, monospace"
    fontSize: "14px"
    fontWeight: 400
rounded:
  sm: "4px"
  md: "6px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "32px"
  3xl: "40px"
  4xl: "48px"
components:
  button-filled:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "36px"
  button-outlined:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.primary}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "36px"
  button-text:
    textColor: "{colors.primary}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "36px"
  chip:
    backgroundColor: "{colors.paper}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 4px"
  chip-selected:
    backgroundColor: "{colors.step}"
  segmented:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.sm}"
    height: "36px"
  segmented-selected:
    backgroundColor: "{colors.step}"
  input:
    backgroundColor: "{colors.sheet}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
  section-rail-item-selected:
    backgroundColor: "{colors.step}"
    rounded: "{rounded.md}"
    padding: "4px 12px"
  board-row:
    height: "52px"
    padding: "4px 16px"
  score-box:
    backgroundColor: "{colors.paper}"
    typography: "{typography.score-mark}"
    rounded: "{rounded.sm}"
    width: "64px"
    height: "44px"
  score-box-locked:
    backgroundColor: "{colors.shelf}"
  table-header:
    backgroundColor: "{colors.shelf}"
    typography: "{typography.caption}"
  side-panel:
    backgroundColor: "{colors.sheet}"
    width: "360px"
  dock-panel-wide:
    backgroundColor: "{colors.sheet}"
    width: "480px"
  toolbar:
    backgroundColor: "{colors.shelf}"
    padding: "4px 12px"
    height: "48px"
  status-pill:
    backgroundColor: "{colors.step}"
    typography: "{typography.caption}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
  practice-banner:
    backgroundColor: "{colors.practice-amber}"
    textColor: "{colors.practice-amber-ink}"
    padding: "8px 24px"
---

# Design System: Meow-Chess

## Overview

**Creative North Star: "The Wall Sheet"**

Meow-Chess looks like the paper a tournament director tapes to the wall, set on a warm desk. The page is a warm off-white paper (dark: a near-black warm charcoal), tables sit on white sheets, and everything that matters during a round (board numbers, scores, the round line) is set big enough to read from standing height. Chrome is quiet: a pale shelf toolbar, a horizontal section tab strip, a status bar that states what was saved. One deep blue carries action; everything else is warm grey.

The system is an Operate tool, dense where a TD scans and large where a TD or a player has to read at a glance. Change is instant: no ripples, no fades, no slide-ins. Depth comes from borders and surface steps, never shadows. Work happens in place, in the table or in one docked panel on the right, and every edit applies immediately with undo behind it. Paper is a real output, so the screen borrows paper's habits: tabular figures, ruled rows, plain headings.

Cat personality stops at the welcome-screen logo, desktop app icon and the `.meow` file extension. Nothing inside a workflow is themed.

**Key Characteristics:**
- Warm-paper neutrals with one deep-blue accent; amber reserved for practice mode.
- Instant state changes: zero animation durations, no splash, no chip or checkbox animation.
- Flat: borders and three surface steps carry all depth.
- Big, tabular wall-sheet type on the Rounds view; compact 14px Inter everywhere else; nothing under 12px.
- One right-hand docked panel at a time; no modal dialogs.
- A 36px control height shared by every button, field and toggle so rows line up.

## Colors

Warm, low-chroma paper greys with a single deep ink-blue for action, defined as explicit light and dark pairs over a seed-derived Material scheme.

### Primary
- **Ledger Blue** (light `primary`, dark `primary-dark`): filled buttons ("Create pairings", Save), outlined and text button labels, link text in the status bar, checked checkboxes, and the 2px focused border on text fields and score boxes. It is the seed of the whole scheme. On it, `on-primary` / `on-primary-dark`.

### Secondary
- **Seed Secondary Container** (Material `secondaryContainer`, seed-derived, no override): the "good" StatusPill and the pairing-swap banner. Used for positive or in-progress-editing states, always with a text label.

### Tertiary
- **Practice Amber** (`practice-amber` on `practice-amber-ink`; dark `practice-amber-dark` on `practice-amber-ink-dark`): only the full-width "Practice copy" banner under the toolbar. It means "this is not a real event" and is used nowhere else.

### Neutral
- **Warm Paper** (`paper` / `paper-dark`): the page and scaffold, unselected chips and segments, editable score boxes.
- **White Sheet** (`sheet` / `sheet-dark`): tables, cards, side and dock panels, input fills, outlined-button fills. The surface things are written on.
- **Shelf** (`shelf` / `shelf-dark`): toolbar, sticky table column header, locked (read-only) score boxes.
- **Step** (`step` / `step-dark`): selection (section rail item, selected chip and segment), read-only banner, post notes, neutral StatusPill.
- **Ruling Grey** (`rule` / `rule-dark`): outlines of fields, outlined buttons, chips, segments, checkboxes, score boxes. Chosen for at least 3:1 against every surface.
- **Hairline** (`hairline` / `hairline-dark`): decorative dividers, card and panel borders, board-row rules (at 50%), toolbar and status-bar edges. Never the only edge of an interactive control.
- **Ink Inverse** (`ink-inverse` / `ink-inverse-dark`): inverse surfaces.
- Text uses the seed-derived `onSurface` and `onSurfaceVariant` (muted facts, captions, subtitles). Errors use the seed-derived `error` / `errorContainer`.

### Named Rules
**The One Ink Rule.** Ledger Blue means "act here" or "focus is here". Neutral states are carried by surface steps, not by tinting things blue.

**The Three-to-One Edge Rule.** Every interactive control's edge is Ruling Grey (3:1). Hairline is for decoration only.

**The Amber Means Practice Rule.** Practice Amber is exclusive to the practice-copy banner; never use it for warnings or emphasis.

## Typography

**Body Font:** Inter 4.1 (Regular 400, Medium 500, SemiBold 600, Bold 700), bundled.
**Mono Font:** Source Code Pro Regular, bundled, for US Chess IDs, ratings and key hints.

**Character:** One neutral grotesque at two scales: compact for operating the tool, oversized for the wall sheet. Figures that line up in columns (board numbers, scores, round facts, standings) use tabular figures.

### Hierarchy
- **Headline** (600, 26px, 1.2): the Rounds wall-sheet title ("Round 1 of 3") and the player name in the lookup panel.
- **Headline facts** (400, 18px, tabular, muted): the facts run beside the round title ("All 2 in").
- **Lookup answer** (400, 24px, 1.25): "Board 2 · White vs Jamie Patel", readable by a player facing the screen.
- **Score mark** (600, 20px, 1.15): ½ / 1 / 0 inside score boxes.
- **Board number** (600, 19px, tabular): the first column of every board row.
- **Title** (600, 15px): panel titles, section heads, card heads.
- **Body** (400, 14px): tables, list items, forms. Player names in board rows run at 18px.
- **Body small** (400, 13px, muted): secondary lines, descriptions in panels.
- **Label** (500, 14px): buttons, chips, segments.
- **Caption** (400, 12px): score-box captions (playing / disputed / assumed), status bar, StatusPill, table column headers, rail subtitles.

### Named Rules
**The Twelve Floor Rule.** No text below 12px, anywhere.

**The Tabular Column Rule.** Any number read down a column (board, score, rank, rating) uses tabular figures or Source Code Pro.

## Layout

A desktop workspace: a 48px-minimum toolbar (editable event name, Players / Rounds / Reports, Refresh from URL / Refresh from USCF, then Help / Keyboard, Undo / Redo / History, Theme / Home). Refresh actions use labeled buttons on wide screens and accessible icon buttons at laptop widths; USCF uses the conventional ♔ glyph. Normal 960px windows retain one toolbar row; enlarged text can use a second row. A legacy practice banner appears only in existing practice files.

The section strip contains navigation only: a permanently pinned All sections tab, horizontally scrolling 15px section labels with 12px status subtitles, and a separate outlined New Section action. Selected tabs use a neutral surface and bottom rule. Right-click a section tab for printing, rename/settings, combine, and delete (unplayed sections only); player actions live on the player. Right-click a player (or press the Menu key or Shift+F10 on a focused row) for Byes…, Move… and Withdraw/Reinstate. There is one Move action: moving in or out of a full, unpaired quad asks which player in the destination exchanges places, so a quad always keeps four; a round robin may optionally exchange; a Swiss simply moves. Context menus open instantly; tabs have no visible Actions button. New Section creates an empty Swiss section immediately and opens its right-hand settings, including Side games (off by default). Before play, the Players view offers Create sections for unassigned players, including rating-based quad grouping. Create pairings is one global action for all ready sections; side-game sections offer Pair a side game there. The main view, optional right-hand dock, and saved-status bar complete the workspace.

Spacing snaps to 4 / 8 / 12 / 16 / 24, with 32 / 40 / 48 for larger separations. The page gutter is 24px; the round header pads 16px top and 8px bottom inside it. Board rows are 52px minimum with 16px horizontal padding; score boxes 64px wide. Side panels sit 24px from the right edge.

When the window is narrower than the table plus a panel, the content scrolls horizontally rather than squeezing columns. The toolbar grows with large text instead of clipping.

### Named Rules
**The One Dock Rule.** At most one contextual panel is open on the right at a time, including player details, history, event details, lookup and print. Every tool uses the same reserved 360px column, capped at 48% of available workspace width. The column stays reserved when closed, so opening, closing or replacing a panel does not move the table. Opening another replaces it; asking for the same one again closes it; Esc closes it.

## Elevation & Depth

The system is flat. There are no shadows: cards and dialogs set elevation 0, and panels are bordered sheets. Depth is three surface steps (paper, shelf, step) plus the white sheet, separated by hairline or ruling-grey borders. Selection is a surface step; focus is a ring.

### Named Rules
**The Border, Not Shadow Rule.** If something needs to stand apart, give it a sheet surface and a hairline border. Never a shadow.

## Shapes

Small, tight corners. Buttons, chips, segmented buttons, score boxes, StatusPill, banners and cards use 4px; text fields and section rail items use 6px; the checkbox's inner box is 2px. Side panels are square-cornered bordered rectangles. Rows are ruled, not boxed.

## Components

### Buttons
Plain and immediate.
- **Shape:** gently squared (4px), 36px tall, 12px horizontal padding, Inter Medium 14px.
- **Filled:** Ledger Blue with white label; one per region, for the next step (Create pairings, Save).
- **Outlined:** white sheet fill, Ruling Grey border, blue label (Print packet, Final reports, Missing only).
- **Text / Icon:** no fill; toolbar icons and inline actions.
- **Hover / Focus:** colour changes instantly (zero animation, no ripple). Keyboard focus draws a 2px ring in `onSurface` (dark on light paper, light on dark), so it shows on filled buttons too.

### View tabs
Player lookup opens anywhere with Ctrl+L; Players has only its search box, so the two are not confused. Shortcut reference lives behind the keyboard icon; Rounds does not show a permanent hotkey legend. Undo and Redo use straight arrows with action names in accessible tooltips.
The toolbar's Players / Rounds / Reports switch. The selected tab inverts: `onSurface` fill with `surface` text. Unselected tabs are plain text.

### Chips and Segmented buttons
- **Style:** paper fill, Ruling Grey border, 4px corners, no checkmark (so picking one never shifts its neighbours).
- **State:** selected is the Step surface; focus is the 2px `onSurface` ring. No animation.

### Inputs / Fields
- Empty fields have labels and no example placeholders. Saved values and drafts are restored. Searches use one shared field labelled **Search**: 200px wide (220px on the roster), locked to the 36px control height, with the clear button's slot always reserved so typing never resizes the box or nudges its neighbours.
- **Style:** white sheet fill, Ruling Grey border, 6px corners, 8px by 12px padding, dense.
- **Focus:** 2px Ledger Blue border.
- **Error:** the problem stays beside the field in the panel, never in a dialog.

### Checkbox (PlainCheckbox)
24px target, 18px box with 2px corners. Unchecked is a Ruling Grey outline; checked or mixed is a Ledger Blue fill with a white check or dash. Flips instantly; focus is a 2px `onSurface` ring with 4px corners.

### Score box (signature)
The heart of the Rounds wall sheet: a 64px by 44px box at each end of a board row holding the result mark (20px SemiBold). Editable boxes are paper with a Ruling Grey border; read-only boxes are Shelf. Focus is a 2px Ledger Blue border. A 12px caption appears for playing, disputed or assumed; disputed marks and captions turn `error`, assumed marks go muted. Unplayed games use the US Chess letters: X for a forfeit win and F for a forfeit (no-show); F typed on a player marks them absent, and F on both players is a double forfeit. Crosstable byes read B--- (full), H--- (half) and U--- (zero). Keys commit immediately and advance.

### Board row and table
52px ruled rows (hairline at 50%), 19px tabular board number, white on the left and black on the right, row menu at the end. The column header is sticky, on Shelf, 12px. Standings mark shared ranks "T-2".

### Round header
Round title with muted tabular facts and, when there is more than one round, the round chips (1, 2, 3, All) all on one line. The title, the read-only status and the chips each occupy a band one control tall, so the title stays level with the Crosstable title even when the chips wrap. Pane headings are at least one control tall, so a section with round chips and one without (a quad beside a Swiss) start their tables at the same height. Each heading's first line is pinned to a top band one control tall, so when round chips wrap on a narrow pane, the Crosstable title and the round title still share one horizontal axis. Before round 1 the heading reads "Round 1 of N · Not paired yet" and the toolbar stays in place with its filters disabled. The nav row reserves the Create pairings button's height whether or not it is shown.

### Unpaired board sheet
Before pairings exist, the boards pane shows the empty sheet itself rather than an empty-state message: the column header and one blank row per board the section will need (plus a blank Bye row for an odd count), with inert Shelf score boxes. Posting fills the same rows, so nothing moves.

Byes are listed after the boards. The score column carries the points; a pairing-allocated bye shows only the name, and other byes add a short muted reason ("requested bye", "withdrawn").

### Banners
Strips with an icon and words, 4px corners, for states that need a sentence: editing pairings (secondaryContainer, swap icon), quad schedule problems (errorContainer), post notes (Step, info icon). On Pairings they sit inside the boards pane above the boards table, never in the heading or toolbar rows the two panes share, so the crosstable beside them never moves. An earlier round is not a banner: the round heading carries a lock icon and "Read-only" (bold "Read-only · choose Correct a result to change it" after a key is typed into a locked box; "Correcting · review each change before saving" in `error` while correcting), and the boards toolbar swaps Edit pairings for **Correct a result** / **Done correcting**. The round chips are the way back to the current round.

### Side panel and Dock
White sheet, hairline border, square corners, title row (15px SemiBold) with a close button; Esc closes. 360px for details and short forms; 480px for print and the player lookup, whose answer runs at 26px / 24px so it reads from standing height.

### Player card
The player panel leads with what TDs decide mid-event: a muted facts line (section · rating, plus a Withdrawn StatusPill) and outlined **Withdraw after round N** / **Reinstate** and **Move…** buttons. Move… opens the move form in place under those buttons on a Shelf inset (Move to, Swap with when a quad needs it, Reason once play has started, then Move / Cancel); there is no Section group. Identity fields (Full name, US Chess ID, Rating, State) stay open, all the same 36px-class field height; the ID field carries no inline icon, and Find by name / Check ID sit under it as outlined buttons. Check ID never saves anything: it shows the US Chess record on a Shelf inset, a bold verdict line ("ID 12345678 is Alex Chen", or in `error` "…belongs to Someone Else, not Alex Chen" with name matches offered below) over a label/value table of State, Regular, Quick, Blitz, Expires and Supplement. Status lines in this area never end in a period. Everything else is a DisclosureGroup: a hairline-ruled header row with a chevron, the 15px title and, when closed, its value as a 13px muted summary at the right edge ("R3 ½", "Not checked", "Lee / Patel"). Groups open and close instantly; a TD's choice is remembered across players. Byes opens by default in a Swiss; US Chess opens itself for a membership warning or a lookup; a report fix opens the group holding its field. Groups: Byes (hidden for a withdrawn player), US Chess, Pairing requests, Team, Notes. Groups carry no explanatory sentences; labels do the work. US Chess is a label/value table at one 13px size (Expires, coloured only when it needs attention, with its warning word; Checked; Supplement or Registration rating), an outlined Refresh from US Chess button, and the Name on rating report field. Save and Discard draft sit in the panel footer whenever a field is edited. Adding a player shows only Name, US Chess ID, Rating and Section, with the rest under More details.

### Bye grid
A compact table: a 12px muted "Round" header row with the unpaired round numbers across, then rows 0 pt, ½ pt, 1 pt (in that order) of 32px cells. Empty cells are outlined; a chosen cell fills with `onSurface` and shows its points in `surface` (13px SemiBold); choosing it again clears it. Hover is the Step surface; focus is the 2px ring outside the cell. Cells grow with text scale and the table scrolls sideways if rounds run past the panel.

### History
The History dock is a single timeline rail, newest first. Each row leads with what happened in TD words (a result reads "Alex Chen – Jamie Patel  0–1", with section, round and board beneath in 12px muted); the time shows only where it changes. The current state carries a **Now** StatusPill and a ringed dot; undone steps carry **Undone** and a hollow dot; undone work that was replaced hangs on a second rail in a collapsible group. Selection is the Step surface. Selecting a row expands its consequences inline, then the one action that commits them. No transaction numbers or graph vocabulary appear.

### Result correction
A docked panel, never a dialog. Results are a ruled radio group named for the players, with key hints at the right edge and the recorded result marked by a StatusPill. The score change sits on a Paper inset in tabular figures. Later paired rounds get a second radio group. The note is optional. Save explains in words why it is unavailable. After saving, the panel confirms the change with Undo and Done.

### Selectable text
The workspace and welcome screen sit in one selection area: any name, ID, score or message can be dragged over and copied (Ctrl+C), the same as on paper. Buttons, rows and score boxes keep their own clicks and keys.

### Status bar and messages
The bottom bar states the save in words ("Event saved 23:39"), at 12px muted. Successful actions use quiet inline text beside the affected content or control, without overlays or timeouts. File confirmations include a selectable path; report status distinguishes the exported revision from newer changes. New things appear in the right-hand column, never above a table: the USCF rating review, bulk actions for ticked players, and confirmations of imports, rating updates, moves and withdrawals (a check line with Undo and Done, as in result correction). Undo is offered only while the confirmed change is still the latest; otherwise the panel points to History. Skip redundant confirmations when the updated content is sufficient. Withdrawal actions belong beside forfeiting players and remain available while relevant. Undo stays in the toolbar and History. SnackBars are reserved for errors: persistent red, with an icon, copy action and close button, and no timeout. All changes appear without animation.

### StatusPill and EmptyState
StatusPill: 12px text, 4px by 8px padding, 4px corners, Step (neutral) or secondaryContainer (good), always a word, never a dot. EmptyState: centred 40px muted icon, title, body, optional action, max 440px wide.

## Do's and Don'ts

### Do:
- **Do** put edits inline or in the single right-hand docked panel, apply them immediately, and offer Undo instead of a confirmation.
- **Do** keep every control at the 36px control height with a 3:1 Ruling Grey edge.
- **Do** show keyboard focus with the 2px ring (`onSurface` on buttons, chips and checkboxes; Ledger Blue on text fields and score boxes).
- **Do** pair every status colour with a word or icon: banners name their state, pills carry text, disputed scores carry a caption.
- **Do** use tabular figures for anything read down a column, and Source Code Pro for IDs and ratings.
- **Do** use the TD's words: Post a round, wall sheet, pairing number, house player, bye, withdraw; Share online for the network action.
- **Do** separate surfaces with borders and surface steps (paper, shelf, step, white sheet).

### Don't:
- **Don't** open modal dialogs or pop-ups for edits, confirmations or previews. Native OS file pickers and persistent error SnackBars are the only exceptions.
- **Don't** put information only in a hover or tooltip; it must be on screen or reachable by keyboard.
- **Don't** convey status by colour alone.
- **Don't** say "publish"; a round is Posted.
- **Don't** add cat personality to workflows, results, pairings, errors or empty states; the logo and `.meow` are the brand's cat moments.
- **Don't** animate: no ripples, fades, slides, scale-ins or confetti. State changes are instant.
- **Don't** use shadows or elevation.
- **Don't** set text below 12px.
- **Don't** use Practice Amber for anything but the practice-copy banner.

The older "V2 dark tokens" in `docs/TD_EXPERIENCE.md` are superseded by this file.

### Interrupted work and output scope

Forms keep partial and invalid input as local drafts, separate from audited event revisions. Save/Add applies the form; Close/Escape preserves it; Discard draft restores the committed record. A failed draft write is visible and retryable. The event save indicator never promises draft durability. Results restore the last board, side, search and scroll per section; historical rounds reopen read-only and newly posted rounds reset the view.

Print previews name their sections and rounds (per section when they differ), never internal revision numbers. They retain their scope while refreshed; event changes disable printing until the TD refreshes or explicitly chooses the older revision. Prize-class filters carry into printed standings. Report blockers link to their repair fields, and the finish-event checklist distinguishes exported revisions, backups and manually recorded submission notes from external acceptance.

### Reviewed external changes

Website imports, rating updates and player transfers use explicit before/after confirmation in the dock or the selection panel. Existing-player website changes start unchecked; missing website entries stay local. Registration ratings are labelled self-reported. Help opens searchable offline articles in the same dock, with contextual pairing explanations. These deliberate confirmation steps supersede the general immediate-edit guidance for these workflows.

### Players and Pairings workflow (October 3 update)

The top navigation separates **Players**, **Pairings**, and **Reports**, retaining
the selected section. Players is the roster setup view: names, ratings, USCF
expiry, registration edits, and section assignment. An empty roster leads with
**Add from URL**, then file import, paste, and one player. Once players exist, the
toolbar shows **Add player** and **Refresh from USCF** (ratings and membership
expiry in one pass); the compact **Player tools** menu holds Refresh from URL,
import/paste, and optional rating estimates and IDs. These actions do not live in the global
toolbar. Players has no round columns, scores, standings, or create-pairings action.

Pairings owns creating rounds, editing boards, entering results, and the
two always-visible tables. Both tables use the Players table's compact
14px type, 32px minimum rows, and 24px score fields. On wide windows, equal compact panes
share heading and toolbar rows so their table headers align even when controls
wrap. The panes sit either side of a 40px gutter with a centred hairline (64px between the tables), and the right-hand editor column stays reserved.
Narrow windows stack boards above the crosstable in one vertically scrolling page.
There are no view-toggle chips. Missing only is an event-wide saved preference
that carries across sections. Print packet always opens the preview. Selected
sections omit redundant in-table section summaries; All sections keeps names only.
Result counts explicitly say “1 of 2 results in”.
The crosstable shows rank, rounds, and points;
prize filters, BH/SB columns, and a permanent result-key legend are omitted.
Membership and optional rating estimates remain in Players. The roster keeps
Name, Rating and USCF expiry in a compact, content-width table instead of
stretching the name column across the window. Optional columns extend the table;
both tables scroll when necessary. The same right-hand details column remains
reserved while closed so opening a player card never reflows the table; it does
not hold a duplicate pairings list.

Pairings are created in one step for all ready sections; waiting sections keep
their games. Setup quad previews are read-only. Move and Withdraw remain
explicit roster actions. Result entry is typing only: 1/W wins, 0/L loses, and D
draws. Score cells display 1, 0 or ½ and update the opponent atomically. Crosstable
rows stay in place during entry. Corrections to dependent rounds retain their
review. Printer icons use the last selected printer, with a picker on first use
and preview/settings still available.

### Export view (October 5 update)

Export is only the US Chess rating report, which always covers every
section, so the section strip is hidden there. The header states readiness
("6 problems to fix before generating" or "Ready to generate · 2 sections")
beside the one filled action, Generate DBF files, with the saved path and
revision below it. A Problem / Fix table lists blocking checks with their
repair links in the Fix column (per-player links wrap under the problem);
optional advice folds into an "Optional" group row with its bulk state
actions. Report details is a label/value table holding the event facts
(Edit event details opens the dock) and the inline site and event-type
fields. "Sections in the report" is a table of players, reported rounds,
time control and rating system. Backup state and submission notes close the
page. Standings, crosstables and their CSV/text copies live in the standings
print panel (Standings / Crosstable switch), not on Export.
