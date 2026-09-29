# SwissSys and ChessRoster reference

## The practical quad recipe

The [SwissSys quad instructions](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/utilities-menu/quad-tournaments/)
describe this sequence:

1. Register everyone into a single temporary section.
2. Open Tournament Setup, then **Tools → Quad Setup**.
3. Use group size **4**; SwissSys creates the quad sections.
4. Finish setup and accept the prompt to seed them from the temporary section.
5. Run each resulting group as its own section.

Before generating pairings, inspect the rating order, group memberships, and each
section's tournament type. The final group with more than four entrants should
play Swiss. For 22 players, expect 4+4+4+4+6, not five quads and two stranded players.

This is a documentation-based guide, not a reproduction of the user's failure.
The exact failure still needs the SwissSys version and the event's pre-failure
state. Save a copy before experimenting with a live event.

Likely checkpoints: everyone registered in the source section; seeding prompt
accepted; intended ratings actually active; last group set to Swiss; round one
not already paired under another tournament type. SwissSys documents recovering
a wrong type using an earlier save/backup, a round-zero rollback, or club-list
export/re-import. Those can discard tournament progress and should be done only
on a copied file. See [tournament types](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/utilities-menu/tournament-types/)
and [setup tools](https://docs.chessroster.com/swisssys/app-docs/tutorials/tournament-setup-and-tools/).

Meow-Chess should show the entire partition before creating sections, show the
bottom Swiss explicitly, and explain why a grouping cannot be applied. No hidden
pseudo-section or mandatory menu sequence should be needed.

## Feature inventory and our response

This groups the discovered documentation rather than promising 1:1 parity.
Full topic links are in `../swisssys-navigation.json` (296) and
`../chessroster-navigation.json` (60). Read selected pages using the source catalog.

| SwissSys capability family | Documented examples | Meow-Chess decision |
|---|---|---|
| Event/section setup | Types, per-section settings, board ranges, quad seeding, extract/import/merge sections | Core; explicit preview and validation |
| Registration | Manual, database, club lists, online search, CSV/spreadsheet/DTF, late entrants | Core manual/paste/CSV; additional adapters from fixtures |
| Identity/rating checks | ID/name/state updates, membership expiration, rating profiles, primary/secondary data | Core with a review batch and source provenance |
| Player lifecycle | Withdraw/reactivate, byes, section moves, pairing numbers, board history | Core with historical records preserved |
| Pairings | Rules, color preferences, restrictions, manual adjustment, integrity checks, allocated bye | Core US Chess policy with explanations |
| Specialized systems | RR Crenshaw/Berger, double rounds, acceleration, ladders, Scheveningen | RR/double rounds first; others explicitly staged |
| Results | Per-board/all-round entry, corrections, missing results, rollback, imports | Core keyboard workflow and revision history |
| Standings | Crosstable, wall chart, tie-break order, RR chart, team standings | Core individual views; team aggregation staged |
| Team play | Individual teams, fixed rosters, board order, team-only results, team withdrawals | Model as distinct competition structures |
| Awards | Prize classes, allocation, certificates, upset reports, color statistics | Simple standings/prize notes first; calculators later |
| Printing | Registration lists, pairings, standings, board signs, team result sheets, multi-section exports | Pairings/crosstable/standings first, other views later |
| Export | Text, HTML, PDF, spreadsheets, USCF DBFs, FIDE TRF, other federations | USCF + ASCII/PDF first; HTML/CSV useful; FIDE deferred |
| Recovery | Saves, backups, previous rounds, logging | First-release requirement |
| Presentation | Section panels, columns, fonts, headers, profiles, localization, colorblind mode | Section tabs, reusable table controls, accessible states |
| Network/internet | Registration networking, hosted reports, sync, emails | Optional later; offline TD work cannot depend on them |

The [team overview](https://docs.chessroster.com/swisssys/app-docs/user-guide/tournaments/team-tournaments-overview/)
distinguishes individuals carrying team scores from fixed-roster teams paired as
units. Bughouse teams are a third concept. Keep all three separate.

## Files and print compatibility

| Format / workflow | Verified from documentation | Planning implication |
|---|---|---|
| US Chess `THEXPORT/TSEXPORT/TDEXPORT.DBF` | [USCF report utility](https://docs.chessroster.com/swisssys/app-docs/user-guide/tournaments/ratings-report-for-uscf/) converts final section files | Must produce accepted federation files; no need to mimic internal save layout |
| ASCII/text crosstable | [Export formatting](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/utilities-menu/exports-formatting/) allows space-padded columns and optional headers | Fixed-width text with a monospaced print layout; offer explicit ASCII transliteration |
| View export | [Export View](https://docs.chessroster.com/swisssys/app-docs/getting-started/export-view/) supports text/HTML/PDF/spreadsheet and current/all sections | Shared report model with separate renderers |
| CSV/DTF | [DTF reference](https://docs.chessroster.com/swisssys/app-docs/user-guide/menus/utilities-menu/delimited-text-files-dtf/) documents mappings and explicit result encodings | Do not assume every CSV is a roster; show import purpose |
| ChessRoster registration download | [Director download](https://docs.chessroster.com/chessroster/director/download/) currently documents only SwissSys 11 SJSON; SwissSys 11.74+ required | CSV is not established as ChessRoster's current export; SJSON needs real fixtures |
| ChessRoster sync | [Managing Pairings](https://docs.chessroster.com/chessroster/director/managing-pairings/) describes SwissSys-generated pairings and sync/report upload | Do not assume a public Meow-Chess integration API |

SJSON documentation describes sections, registration ratings, federation IDs,
membership, team/club fields and requested byes, and excludes non-completed and
withdrawn registrations. That is useful semantics but not a formal JSON schema.
No SJSON round-trip compatibility claim is justified yet.

## ChessRoster public browser tour

Actually visited the live site, tournament discovery, an upcoming FMCA quad's
Info/Sections views, and the documentation navigation. Observed search, status/date
filters, proximity filtering, card/table views, public event tabs, round schedules,
and a disabled Live View explaining that reports/broadcasts are needed.
The public site advertises online registration, payments, membership verification,
byes/withdrawals and SwissSys sync. These are product claims, not tested back-office
operations. We did not register, pay, upload or create an organizer account.

Documented additional features include staff roles, pricing tiers, custom questions,
team registration, financial reports, club memberships, bundles, discount codes,
notifications, SMS results and a TV-oriented live display. These belong to a hosted
registration ecosystem, not the initial local tournament application.

The home page calls notifications “coming soon,” while director docs describe
preview access. Treat availability as deployment/account dependent. Likewise,
[ChessRoster's FIDE engine page](https://docs.chessroster.com/chessroster/about/fide-pairing/)
explicitly says not yet approved and for testing only. Documentation existence is
not proof of general availability or federation approval.
