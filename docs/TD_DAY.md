# A tournament day, in order

The other documents are organized by feature. This one is organized by the clock,
because that is how a TD experiences the product. Every moment names what the TD
is trying to do, what the screen must offer without hunting, the target speed, and
the requirement IDs that own it (see [Requirements](REQUIREMENTS.md), section
“Tournament-day usability gates”). It is a design proposal to be rehearsed with
working TDs, not a measured result. No application exists yet.

The example is a Saturday quads event with a public pre-registration list, one TD,
one laptop and one printer, with a Tuesday-night weekly Swiss noted where it differs.

## T‑60 min · Before players arrive

**Goal:** the roster is in, obvious problems are known, nothing else.

- Open the event from the library, or create one from the Quads template with a
  name and date only. Time control, rounds, rating basis and board numbering come
  from the template and are shown as one plain sentence (E04, K05).
- Paste the registration table. The review shows ready / needs review / excluded
  counts; valid rows import now, rejected rows stay repairable (I01–I03).
- Run Check players once. Membership-expired and name-mismatch flags are visible in
  the roster; nothing blocks yet (R01–R05).
- Choose a practice copy if this is the TD's first event with the app (K16).

Target: roster imported and checked in under five minutes with no documentation.

## T‑30 min · The door

**Goal:** mark who is here, register walk-ups, resolve door-side problems, never
lose the queue.

- Press the check-in shortcut. Type a few letters of a name; Enter marks present.
  The list is keyboard-first and legible from standing height (K01).
- A name that is not in the roster becomes a walk-up: name, ID if known, rating or
  “assign”, section. Saving returns to the check-in prompt (K01).
- A membership or ID flag on a checked-in player shows its door-side resolution:
  renewed on site, TD exception with a note, or leave open. The choice is recorded
  and carried into preflight and export preflight (K02).
- A player registering above a section's rating ceiling, or below a floor, is
  flagged here with a move-up option and a reason field (K03).
- Private notes typed at the door (“must leave by 3”, “wants a bye in round 4 if
  it runs late”) appear later in the inspector and the pairing draft (K18).
- “Not yet here” is one filter and one printable list (K01).

Target: 40 pre-registered check-ins and 3 walk-ups in under five minutes,
keyboard only.

## T‑5 min · Preflight

**Goal:** know in one glance whether round one can be posted, and fix what can't.

The Event tab shows a round-one preflight list. Each row opens the record or action
that resolves it (K04):

```
Checked in 22 of 25        3 not here → exclude / include / bye for round 1
Identity issues 1          open review
Membership blocks 0
Sections: not created      Make quads (22 → 4 quads + 6-player Swiss)
Announced minimum 8        Bottom Swiss (6) is below the announced merge minimum → keep / combine
Pairings: none posted
```

- Make quads shows the whole partition, the bottom Swiss and why (Q01–Q04, CAP-X01).
- Unchecked pre-registrations are resolved once for the round, not per person (K01).
- On the Tuesday Swiss, an under-minimum section proposes the announced merge from
  the event conditions rather than waiting for the TD to remember (J02, K21).

Target: preflight clean in under two minutes after the last check-in.

## T‑0 · Post and print

**Goal:** everyone at a board with a clock running, in three actions.

- Post round 1 for all ready sections. Quads have a fixed schedule; nothing opens
  for review unless there is a warning (K05).
- The bye recipient and reason for any odd section sits at the top of the posted
  round, because that is the first question asked (K20).
- Print the round packet: board-order pairings with a result column, alphabetical
  pairings, and current standings if a round has been played. Boards are numbered
  globally across sections; the printed order matches the entry grid exactly (K09, K10).
- After players are seated, Start round records the actual start separately from
  posting. Show scheduled/actual start and any estimated finish with its move-count
  assumption; never claim a hard finish time from delay/increment alone (K06).

Target: make quads → post → print in three actions; under sixty seconds from a
clean preflight to paper on the wall.

## During the round · Questions, changes, one correction

**Goal:** answer players without changing anything by accident; make the one
inevitable change safely.

- “Where am I playing?” Player lookup by name or pairing number shows board,
  color, opponent, score and next-round bye status in a large panel that can face
  the player. It never enters a result (K11).
- “Can I have a half-point bye in round 3?” Double-click the name → Byes. The
  event's announced bye deadline is shown at the decision (D01, D02, J02).
- “I have to leave now.” Withdraw asks whether it starts now or after the current
  game and shows the unresolved board (D03).
- Two players were paired wrong. Edit the posted round, swap, post the replacement
  revision, reprint only that section (P02, P03, K09).
- A no-show at board 7 after the default wait. Forfeit keystroke, then the offer to
  withdraw the absent player from the remaining rounds (K08).
- The TD is interrupted mid-form. Whatever was half-typed is still there on return
  and after a restart (K14).

Target: any lookup in under five seconds; a pairing swap posted and reprinted in
under sixty seconds.

## Results · Collecting from the wall or the room

**Goal:** twenty results, two unknown, one correction, no mouse.

- Open the event-wide results grid in global board order, or the section's grid.
  The keystrokes are identical (K07, G01, [Results entry](RESULT_ENTRY.md)).
- The round number and the result perspective are always visible; entering into
  the wrong round is the mistake the layout is designed against.
- Missing-only filter, board jump, Undo naming its action (K13).
- A long game is still running when the next round is due: the TD-approved
  temporary pairing treatment, separate from the result (J01).

Target: 20 results, two blanks and one corrected typo in under sixty seconds once
familiar, all correct.

## Between rounds · Repeat

Preflight for round N shows only what changed: results missing, players withdrawn,
byes requested, a section finished. Post, print the packet, start the clock. The
Event tab is the home screen between rounds; the current section's results grid
is the home screen during one.

## End of day · Finish and leave with proof

**Goal:** prizes right, report produced, backup somewhere safe, nothing forgotten.

The Event tab switches to an end-of-day list (K04):

```
All results entered        Quad 3 has 1 missing → open
Sections complete 5 of 5
Prize classes              standings by class → print
Rulings pending 0
Rating report              preflight → export package
Backup                     copied to the secondary folder at 14:52
Submission                 not recorded → record reference
```

- Standings filtered by prize class make manual prize distribution a reading task,
  even before automated allocation exists (K17).
- Export produces the three DBFs and a manifest from one revision; exported,
  submitted and accepted remain distinct states (U01–U03, J05).
- The secondary backup folder has already received a copy at every posted round;
  the last copy is confirmed here. Continuing tomorrow on a different laptop from
  that folder is a rehearsed scenario, not a recovery adventure (K15).

Target: export preflight clean and backup confirmed within five minutes of the last
result.

## What this order changes in the build

1. Check-in, preflight and event-wide results are screens, not columns and counters.
2. Batch post-and-print is the default; per-section review is the exception.
3. Time is on screen. A TD should never need a separate clock to answer “when?”
4. The wall sheet is designed as the result-collection instrument.
5. The vocabulary is a TD's: post, wall sheet, pairing number, house player, bye.
6. Every rehearsal scenario in [TD duties](../research/notes/TD_DUTIES.md) maps to
   a moment above; anything that cannot be placed on this timeline is not a
   first-release priority.
