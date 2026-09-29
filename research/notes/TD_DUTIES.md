# TD duties → product workflows → acceptance evidence

Checked September 29, 2026 UTC. The purpose is to derive the product from directing
work, rather than collect attractive features. The earlier SwissSys inventory is
useful for comparison but is not a substitute for this model.

## Is there an official list?

Yes. **Rule 21B** in the [2026 online rulebook](https://new.uschess.org/sites/default/files/media/documents/us-chess-rule-book-online-2026.pdf)
explicitly enumerates chief-TD responsibilities. Rules 21A/C cover authority and
delegation; Chapter 2 expands tournament operations. The [US Chess TD hub](https://new.uschess.org/tournament-directors)
collects certification, rules, reporting, accessibility and educational resources.

There is also a practical [Guide to Scholastic Chess, 11th edition](https://new.uschess.org/sites/default/files/media/documents/11th-edition-guide-to-scholastic-chess-6-29-21.pdf):
printed pages 32–36 discuss directing/registration/results, page 52 is a planning
worksheet, and page 53 is a supplies checklist. It is useful operational guidance
from 2021, not the current authority for membership fees, certification or every
adult tournament policy. Use the current rulebook/updates and
[TD/Affiliate FAQ](https://new.uschess.org/tournament-director-and-affiliate-frequently-asked-questions)
for current applicable procedures.

US Chess does not prescribe a complete software screen/keystroke specification in
these documents. The obligation, event-specific policy, and proposed UI interaction
must be identified separately. A feature can be an excellent usability decision
without pretending it is a federation mandate.

## Evidence classes

- **Rule:** authoritative rule for its applicable event/policy; cite rule number.
- **Official procedure:** federation submission, certification or administrative guidance.
- **Operational guidance:** recommended practice; does not automatically bind every event.
- **Observed demand:** explicit user requirement or documented local event workflow.
- **Design proposal:** our chosen interaction; must be validated with working TDs.

The source descriptions below are deliberately short. The right-hand columns are
our product design and acceptance proposals, not quotations or federation mandates.

## Duty-based coverage

| Job / trigger | Basis and locator | Proposed interaction | Acceptance evidence |
|---|---|---|---|
| Accept and maintain entries | Rule 21B; guide p35 | Searchable roster; double-click editing; pending issues | Register late arrival while correcting an ID without losing either change |
| Verify identity, rating and membership | Guide p35; current FAQ member sections | Review identity/rating evidence; maintain exceptions separately | Wrong ID, name variant, unverified renewal, provisional and unrated records remain distinct |
| Correct rating-based eligibility | Rules 28C–H | Rating correction shows affected section/prize eligibility and transfer options | A correction cannot leave an unacknowledged eligibility conflict |
| Apply announced event terms | Rules 25–26; guide p52 | Event conditions sheet with versioned round/bye/prize policies | Printed terms match the effective rules; later changes are visible |
| Handle arrivals, absences and byes | Rules 22, 28K–L/P; SwissSys withdrawal workflow | Round-specific participation editor | No-show, requested bye, allocated bye and completed loss are distinct |
| Deal with odd fields | Rules 28M1–4; official house-player guidance | Bye resolution with house-player/extra-game paths | Consent, eligibility, opponent and rating treatment preserved |
| Prepare and check pairings | Rules 21B, 28–29 | Review/publish; manual opponent/color/board changes | Explain constraints and revisions; no duplicate participant |
| Collect scores and post results | Rules 15H, 28O | Large keyboard-operated results grid; current wallchart | Fast entry advances predictably and updates both opponents |
| Correct mistaken results | Rules 15I, 29H | Direct correction plus dependency review | Correct score retained; existing later games not silently erased |
| Next round with unfinished games | Rules 28Q, 29F/H | TD-approved temporary pairing treatment, separate from final result | Pairing can proceed under supported policy without fabricating a draw |
| Run a quad after a withdrawal | Rules 30B–G | Participation change with scoring/schedule preview | Competition treatment and ratable game history remain separate |
| Assign teams and manage team events | Rules 28N, 31A–G | Team field for individual-team format; roster/lineup tools for team matches | Changing a team label does not silently convert the competition format |
| Resolve disputes and appeals | Rules 21F–L | Private game-linked decision record with rule/version, outcome and review state | A pending appeal is visible before prizes/submission; no automated adjudication |
| Coordinate assistants | Rules 21B–C; guide p32 | Event staff assignments and handover notes | Next TD sees unresolved work; no requirement for multi-user cloud editing |
| Allocate prizes and resolve ties | Rules 32–34 | Explained awards/eligibility, announced tie procedures and payout status | Cash allocation and trophy ordering not conflated |
| Set suitable playing conditions | Rules 21B, 23; accessibility guide | Board/location constraints and minimal accommodation notes | A fixed accessible board survives re-pairing; private information stays private |
| Finish the rating report | Current FAQ: submission/participant coding/time controls | Preflight and report package; distinguish exported/submitted/accepted | Required metadata, ratable games and portal state reconciled |
| Correct a submitted report | Current FAQ: correcting reports | Submission-linked correction summary with old/new data | TD can identify the exact event/section/player/game and required follow-up |
| Prepare site, equipment and supplies | Guide pp52–53 | Optional printable preparation list, connected to event settings | Printer/board-sign/round-schedule needs are visible without blocking pairing |
| Follow applicable Safe Play procedures | Current Safe Play hub, linked policy/training resources | Links and concise event preparation status | App never claims checklist completion substitutes for training/reporting obligations |

Sources beyond the rulebook/guide:
[house players](https://secure2.uschess.org/TD_Affil/houseplayer.php),
[accessibility guidelines](https://new.uschess.org/sites/default/files/wp-thumbnails/2020/04/Accessibility-Guidelines-April-2020.pdf),
[Safe Play hub](https://new.uschess.org/us-chess-safe-play-hub),
[certification document linked by the TD hub](https://new.uschess.org/sites/default/files/media/documents/tournament-director-certification-2026-v2-pdf.pdf).
The house-player page includes old pricing text: do not import those amounts into
current defaults. National/scholastic-specific provisions do not become universal
club rules. Team restrictions and scoring require the selected rule variant;
“never pair teammates” is not a universal rule for every team-labelled event.

## What changes in our plan

These are prioritization corrections grounded in the duties above:

1. **Result entry is an operating surface.** A grid with reliable keystrokes,
   focus, correction and missing-result navigation is core. A dropdown per game
   is insufficient. See [the exact keyboard contract](../../docs/RESULT_ENTRY.md).
2. **Round readiness needs a TD resolution path.** Missing, unreported, disputed and
   unfinished games are not the same. Default to obtaining real results; provide
   supported temporary pairing treatment when the TD selects it. Keep final scores,
   pairing assumptions and rating outcomes distinct.
3. **House players and extra games are distinct from merging sections.** The app
   needs the concepts and a reviewed manual workflow. Automatic cross-round and
   cross-section pairing is specialist work with its own acceptance cases.
4. **Announced conditions matter throughout the event.** The settings screen should
   expose the effective published policy, not just independent toggles. A section
   combination remains the user's requested workflow; it is not blanket authority
   to change any prize/eligibility/rating rule mid-event.
5. **Rulings and handover are missing from a score-only app.** Add a lightweight
   private decision log attached to a player/game/round and a pending decision list.
   Record clock penalties as actions, not fictional score changes. Keep sensitive
   incident reporting outside ordinary public event files and link official channels.
6. **Completion extends past generating DBFs.** Record submission/reference and
   outstanding corrections. Leave portal payment/submission to the authorized TD
   until an integration is verified.

This does not mean adding six permanent dashboard panels. Keep common actions at
Players and Rounds; show unresolved duties in the existing event issue list. Event
preparation and post-event administration can use compact task lists. A task should
open the record/action that resolves it rather than merely display a checkbox.

## What remains a hypothesis

The dark theme, double-click inspector, command search, exact keyboard bindings,
layout, time targets and grouping-preview design are proposed or user-requested
interactions. No usability study has established they work well yet. Dynamic
bughouse strength is experimental; it is not an ordinary US Chess TD obligation.
Full SwissSys parity is a compatibility target, not the priority ordering for the
first usable release. Payments/storefront features remain separate optional scope.

## Observe the work before freezing the UI

Run a realistic event rehearsal with an experienced TD and a newer TD. Ideally
observe one actual club event with permission, using a separate synthetic rehearsal
for errors. Do not alter the live tournament or contact anyone without authorization.

Use task prompts, not instructions telling the TD which button to click:

- A player arrives with an incorrect ID, needs a future bye, and changes section.
- Registration leaves four quads plus six players; combine the last quad and Swiss.
- Result slips arrive out of board order; enter 20 results, leave two unknown,
  correct one and continue without touching the mouse.
- Someone withdraws while currently paired; another player can serve as a house player.
- A long-running game is unfinished when the next round must be prepared.
- A result is disputed after later pairings; record the decision and affected outputs.
- A school team changes its roster; verify the event's team scoring/avoidance policy.
- Reprint only the changed section; finish prizes; prepare submission; log a correction.

Measure successful completion, incorrect edits, lost focus, recovery steps, time,
and need for outside explanation. Record the source of each scenario and observer
notes. Failed workflows revise the interaction design before more feature breadth.
The build handoff must trace **duty → scenario → interaction → acceptance test**.
A source link alone is not proof of usable software.

## Saved references

Seven additional official reference pages/PDFs and extracted text are saved under
`research/local/td-duties/`; [metadata and hashes](../td-duty-sources.json) are tracked.
The rulebook and 2026 changes already exist in the curated archive under
`research/local/uscf-rules-2026.pdf` and `research/local/uscf-rules-updates-2026.pdf`.
The linked 2026 combined PDF includes amendment material but retains older page
footers; preserve its full version context. The source archive is local only and
has not been republished. This review is focused on duties and workflow gaps, not
an assertion of exhaustive rule interpretation or completed TD observation.
