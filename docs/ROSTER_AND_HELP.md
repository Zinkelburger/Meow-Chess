# Website rosters, ratings and help

## Entry lists

**Refresh from URL** (named **Refresh from <saved URL>** after confirmation) reads a single HTML table with Name and Rating columns (USCF ID is optional) from an
HTTPS URL. Boylston accepts either an event URL (`/events/1563/october-quads`)
or an entry-list URL (`/tournament/entries/1563`); both resolve to the entry list.
Other sites use the supplied page directly, without discovering links or guessing
paths. Clubs can contribute URL rules and custom parsers through the
[club adapter registry](CLUB_ROSTER_ADAPTERS.md). JavaScript-rendered tables,
multiple candidate tables, redirects and login pages require a final readable URL
or CSV. No arbitrary page scripts are executed. Responses are bounded to 2 MiB
and requests time out.

Fetch creates a proposal, not an event change. New entries are checked; existing
name/rating differences are unchecked. Duplicate identities and name-only
collisions cannot be approved. Missing entries are retained and called out.
Source sections and byes remain in raw source rows for manual assignment, not
silent section moves or bye changes. A changed event revision invalidates a
proposal. Confirm saves accepted changes, URL, source rows and retrieval time in
one undoable event revision. Future updates reuse the saved URL. An empty table
or failed download cannot clear the event.

Website ratings are retained as reference values with provenance.
**Fetch ratings from USCF** is checked by default in the URL import panel;
uncheck it to skip. After confirming the roster, the optional USCF review runs
in the player table on the left, leaving the right-hand player editor available. A website update cannot replace an applied monthly supplement
rating. Refreshes do not regroup sections. Before pairing, remake quads explicitly
if the director wants to seed groups from updated ratings.

## US Chess

**Refresh ratings** fetches a member identity and dated rating supplement for each
USCF ID, sequentially with a delay and per-player results. Stop leaves completed
lookups available for review. Throttling/authentication stops the batch; ordinary
individual failures leave other successful observations usable. Confirm only the
selected changes, or choose **Keep current ratings** to discard the whole draft.
The review opens in the right-hand column; the table gains **USCF ID**,
**Entered**, **Rating on <supplement date>** (with a tick box and the change) and
**USCF name** columns beside USCF expires and the registration note. Valid
proposals start ticked, but no pairing rating changes before confirmation. A USCF
name that looks like a different person (the entered name shares no close word
with the US Chess last name) is flagged with an icon, listed under **Names to
check**, and starts unticked. Changes of more than 50 points in either direction
and unrated-to-rated changes are bold and shaded. Clicking a player opens their
editable card in place of the review, with that player's proposal under Rating
and **Back to rating review**; a rating typed there is kept and that row reads
"Your edit is kept." Missing IDs,
unrated members, provider failures, and skipped players have explanations and
recovery options on their rows. No-ID rosters make no lookup requests. Same-value
ratings can still be confirmed to record verification.

The refresh arrow beside an ID fetches one player. The card shows the official
name and all returned categories; choosing a rating offers a before/after
confirmation. Missing ratings remain unknown. Posted sections keep their pairing
ratings, and late results cannot override an edited event. Manual rating or ID
edits clear the old verified-rating attribution.

**Players → Refresh from USCF** fetches each member profile along with the rating
supplement, so membership expiry is saved for everyone found, unrated players included.
The **USCF expires** column displays the saved date; expired dates are red and
labelled **Expired**. Memberships expiring later this calendar month are yellow
and labelled **Expires this month**. Dates before the event's last day also
receive a warning.
Expiration is inclusive: a membership expiring on the event's last day is not
flagged as expired for that event. Provider status and the retrieval timestamp appear on
the player card and in the date tooltip. Missing dates are unknown, never inferred
to mean lifetime membership.

USCF refreshes and single-player rating lookups automatically save membership
observations separately from pairing ratings, whether or not rating changes are
confirmed. They work after
pairings are posted, survive reopening the event, and retain the previous value
on request failure. Editing a USCF ID clears its membership observation; manual
rating edits keep it. Membership refreshes do not determine tournament eligibility
or block pairings. Saved dates are observations as of the displayed check time;
use Refresh from USCF again to see renewals.

Event details → Data sources sets the default category across events on this
computer, using the system credential store. Monthly supplement is the available
source; latest/unofficial is visibly unavailable until its contract is verified.
The optional operator key selects API v2. With no key, public API v1 is tried.
Public access is an observed capability, not a provider guarantee. Keys never go
to entry-list websites and provider requests refuse redirects.

Live check on 2026-10-03: Boylston entry list 1563 yielded 24 valid entrants and the public v1
member/supplement endpoints returned dated October values without a key.
Authenticated v2 remains unverified. Published profile and supplement data are not
labelled live/unofficial. See [US Chess research](../research/notes/US_CHESS_API.md).

## Sections and help

Section navigation uses compact horizontal tabs and preserves per-section workspace state.
All sections stays pinned; there is no section search. New Section creates an empty
section immediately and opens its settings in the right-hand panel. Side games is
unchecked by default. Right-click a section, or use its visible action menu, to
rename, configure, combine, or delete an unplayed section. Before play, the Players
view offers Create sections when players are unassigned, including grouping by
rating into quads. Refresh from USCF sits beside Add player in the Players
toolbar, and Refresh from URL is under Player tools; posting lives in the Pairings
content header.

Player cards offer a destination and explicit confirmation. Before rounds are
posted, choose a destination player to exchange roster slots in one atomic swap.
Both quads remain four players. All sections also offers a two-selected-player
swap. Posted schedules cannot be changed with this command. Existing safe
same-progress section transition rules still apply after play.

The Help control opens offline searchable articles. The section action menu also
opens that section’s pairing algorithm article. The registry in
`lib/ui/help_panel.dart` holds titles, summaries and named prose sections and can
be extended without network services or routing changes. Articles cover quads,
Swiss, round robin, imports, ratings and registration/moves. Search includes body
text, so “extra Black” finds the quad explanation.

The quad schedule already matches Hoy’s description: round 1 is 1–4, 2–3;
round 2 is 3–1, 4–2 (White first). Each player has one of each color after two
rounds. Round 3 is 1 versus 2 and 3 versus 4, with two color choices derived from
the randomly generated section ID. Reopening or re-previewing does not redraw
them. Every player finishes with a 2:1 color split. The posted round note records
the lot. This is Meow-Chess’s implemented schedule, not a claim of parity with
every SwissSys configuration.

For failures, choose **Help → Export diagnostic log**. See [Diagnostic logs](DIAGNOSTICS.md) for file locations, recorded operations, and retention.
