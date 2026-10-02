# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Recorded as `web` only because Impeccable has no desktop value; no iOS/Android guidance applies. The real target is a Flutter desktop application: Linux and Windows are released and first-class, macOS builds from the same code. Design for a laptop screen, mouse plus keyboard, OS-standard window decorations, and printed paper. Mobile, tablet and a web viewer are possible later, not current targets.

## Users

The primary user is a solo club tournament director: one person, one laptop, one printer, running Boylston-style US Chess events (Saturday quads with a bottom Swiss, weekly evening Swiss, double-round blitz) alone. They work under time pressure, helping arrivals at the door, interrupted constantly by players and parents, and switching between sections all day. Their jobs: register walk-ups, make sections, post pairings, take results fast, correct mistakes, answer "where am I playing?", print wall sheets and crosstables, and leave with a report US Chess accepts.

Secondary audiences, confirmed by the docs but not the design target: players reading posted pairings and standings (on paper or a second screen), and a relief TD taking over mid-event.

## Product Purpose

Meow-Chess is an offline-first tournament director workspace for US Chess events. It exists because the incumbent tools, SwissSys above all, make ordinary club formats needlessly hard. Success is a TD running a whole event day, from roster import to rating report, without documentation, without losing their place, and without ever doubting what was saved.

## Positioning

An easy, modern TD tool that makes quads and ordinary Swiss events simple where SwissSys is overcomplicated. Common club formats get a real guided workflow, not a hidden combination of generic section operations, and the default path is the batch path.

Secondary strengths that support that position: keyboard-speed results, walk-up registration and lookup; durable saves with history and understandable recovery; free, open (AGPLv3), offline and cross-platform with Linux first-class.

## Operating Context

- **The tournament day, on the clock:** roster in before players arrive, walk-up registration at the door, round-one preflight, post round, results during play, corrections, standings and prizes, end-of-day reporting. `docs/TD_DAY.md` owns the timeline and targets.
- **Events are files:** each event is a local `.meow` SQLite file, opened from a recent-event library or by double-click. No account or network is needed to run rounds; network only enriches ratings and identity, and a failed lookup never blocks result entry or printing.
- **Paper is a real output:** pairings, wall sheets, ASCII crosstables and round packets are printed on white paper.
- **Inputs:** pasted or imported registration tables (often messy, with stale or conflicting data), the US Chess ratings API, TD decisions at the door.
- **Output to the federation:** the US Chess DBF rating-report package.
- **One workspace:** an Event tab plus one tab per section; within a section, Players, Rounds, Standings, Reports and Section settings. A contextual, closable inspector or side panel, not a second permanent sidebar.

## Capabilities and Constraints

- Shipped (1.0.0): event library and workspace, roster import, identity review, quads and individual Swiss/round-robin sections, keyboard results entry, standings and crosstables, reports and printing, history tree with undo/redo and restore, US Chess DBF export. `docs/IMPLEMENTATION.md` is the authority on what is built and tested.
- Unverified: US Chess federation acceptance of exports and full Swiss pairing-priority conformance. Never claim either.
- Planned scope (team standings, bughouse, online events, leagues, accelerated pairings, FIDE) lives in `docs/PRODUCT_PLAN.md` and `docs/FULL_FEATURE_MAP.md`; it is not shipped.
- No attendance/check-in workflow: pair all eligible registered players. Record no-shows as forfeits and offer withdrawal; do not require an arrival flag before pairing. This is the user’s explicit direction.
- Out of scope: cloud registration, payments, SMS, multi-TD editing, club management.
- No modal pop-ups. Edits happen inline or in a docked side panel beside the table. Result shortcuts apply immediately with undo; forms use explicit Save/Add and preserve partial drafts on Close/Escape. Toasts with Undo and native OS file pickers are fine.
- TD vocabulary is binding (K22): **Post** a round, never "publish"; **Share online** is the network action; use wall sheet, pairing number, house player, bye, withdraw.
- Keyboard contract: result shortcuts (1/0/5, W/L/D) commit immediately and advance; shortcuts never fire while a text field has focus. See `docs/RESULT_ENTRY.md` and `docs/TD_EXPERIENCE.md`.
- Every screen survives being abandoned: half-done forms, imports and result sequences persist across navigation and restart.
- Never jump the TD's screen because background work finished; preserve section, view, scroll and selection.

## Brand Commitments

- Name: Meow-Chess (Meow Chess in prose). Event files use the `.meow` extension, and that joke is the brand's main cat moment.
- Logo: `assets/icon/meow_chess_master.png` (source for every platform size; `meow_chess.svg` also exists). It appears on the welcome screen and in the tournament toolbar.
- Cat personality inside the app is close to zero. Usefulness to a TD wins; nothing cat-themed in workflows, results, pairings, errors or empty states unless the user asks for it. This supersedes the "little cat personality in onboarding and empty states" in `docs/TD_EXPERIENCE.md`.
- Voice: plain, calm, TD-literate. No confetti, fake success scores, distracting motion or playful error messages.

## Evidence on Hand

- Product and TD research: `docs/` (TD day, experience spec, operations, results entry, requirements with usability gates K01–K23) and `research/` (Boylston event survey, SwissSys archive and coverage ledger, TD duties, US Chess reporting and API notes).
- Real-format demo data: the in-app **Try a practice event** (22 synthetic entrants, four quads and a six-player Swiss), `samples/sample_players.csv`, `research/examples/quad-crosstable.txt`.
- Screenshots of the current app: `artifacts/*.png` (workspace, results, standings, reports, history, branding) and `artifacts/round-packet.pdf`.
- Absent, and must not be fabricated: observed rehearsals with working TDs, testimonials, user counts, federation acceptance of exports, and any claim of SwissSys parity beyond what `docs/IMPLEMENTATION.md` records as tested.

## Product Principles

1. **Simpler than SwissSys for the common case.** Quads and an ordinary Swiss should be obvious; advanced options are disclosed, never a prerequisite.
2. **Never lose the TD's place or trust.** Save durably before saying Saved, preserve original input, treat posted pairings as revisions, and make every mistake undoable.
3. **Act, then let them fix it.** The default path is the batch path; do the work immediately and offer undo instead of asking for confirmation.
4. **Speak TD and put time on screen.** Use the TD's words, show the round clock, and explain a pairing or validation problem at the board or player where it matters.
5. **Useful before charming.** Every element earns its place by helping a TD under pressure.

## Accessibility & Inclusion

Required (N05): keyboard-only operation of every core workflow, screen-reader labels, status never conveyed by color alone, visible focus rings, and no clipped actions or hover-only information at 200% text or zoom. The player lookup panel must be legible from standing height and readable by a player facing the screen. Honor reduced motion. Printing uses a high-contrast white-paper style.
