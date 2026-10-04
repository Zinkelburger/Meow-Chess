# US Chess ratings and identity API

## Name lookup implementation — October 3, 2026

The current v1 OpenAPI and live anonymous `GET /api/v1/members` were checked
again. `Fuzzy` accepts a full name; `Offset=0&Size=10` bounds the candidate list.
The app now exposes this search for player IDs and chief/assistant TD IDs.
The same documented query is used on v2 when an operator supplies a key; the
authenticated search is covered by contract tests, not a live keyed probe.
Exact-ID checks distinguish a 404 from service failures and suggest name matches
for missing records or a different official name. Candidate selection edits the
draft ID only; the operator still saves it, and pairing ratings do not change.
Late results and stale selection buttons are invalidated when the input changes.

## There is a real public specification

The [official Swagger UI](https://ratings-api.uschess.org/swagger/index.html)
links downloadable [v1 OpenAPI](https://ratings-api.uschess.org/swagger/v1/swagger.json)
and [v2 OpenAPI](https://ratings-api.uschess.org/swagger/v2/swagger.json). Both
documents were retrieved successfully without a token and archived locally.

The captured v2 contract has seven paths, all GET operations:

| Path under `/api/v2` | Intended use |
|---|---|
| `/members` | Search/filter members, including `Fuzzy`, rating source, state and pagination |
| `/members/{memberId}` | Member details and ratings |
| `/members/{memberId}/rating-supplements` | Published rating history |
| `/rating-supplement-files` | List available supplement downloads |
| `/rating-supplement-files/{filename}` | Download a supplement |
| `/affiliates` | Search affiliates |
| `/affiliates/{affiliateId}` | Affiliate details |

Authentication is the `X-Api-Key` header, issued through
[the ratings portal](https://ratings.uschess.org/portal). The August 20, 2026
[announcement](https://forum.uschess.org/t/api-2-0-is-now-available/61581)
describes members/TDs obtaining keys and usage monitoring. It is not a license to
embed a secret in an open-source desktop binary. Proposed policy: the operator
provides a key, stored in OS credential storage, with clear setup instructions.
Confirm allowed end-user key distribution and quotas with US Chess before release.

There is no tournament submission operation in the captured v2 contract. Plan
file export and a TD-controlled portal upload, not an invented write API.

## What was actually tested

No key was supplied, and no account settings were changed. Small read-only probes:

| Request | Observation on research date |
|---|---|
| Production v1 `/members/12641216` | HTTP 200, member/ratings JSON |
| Production v1 `/members/12641216/sections?RatingSource=R&Size=2` | HTTP 200, paginated section history with pre/post ratings |
| Production v2 `/members/12641216` | HTTP 401 without a key |
| User's `beta-ratings-api` v1 member URL | DNS resolution failure on this machine |

The existing Chess Auto Prep `uscf_member` MCP tool also succeeded. Its adapter
maps missing game counts to zero and reads `state` rather than the observed
`stateRep`; do not copy those assumptions into Meow-Chess. In the raw response,
established game counts were absent and `stateRep` was present.

The OpenAPI specifies authentication globally even though the tested v1 routes
allowed anonymous access. Keep the latter as a dated observation, not a guaranteed
fallback or a reason to bypass v2 access requirements. Save success/error examples
locally; future committed tests should use synthetic/redacted fixtures.

## Latest means something different from published

Store separate **published supplement**, **latest/unofficial**, **imported**, and
**TD-assigned** observations. Each needs federation, rating category, value,
provisional status, nullable game count, source, retrieval time, effective date
when supplied, and source event/supplement identifier. `lastChangedDate` on a
member profile must not be assumed to date every rating.

The v2 search contract includes `UseUnofficialRatings`; the announcement discussion
contains a contributor's August 21 report that it had no effect and returned
supplement ratings. This is a reported discrepancy, **not a bug independently
reproduced with a v2 token in this research**. The same thread reports missing
established game counts and other schema/behavior inconsistencies.

Our v1 member and first returned event's post-rating were also different. That
does not by itself tell us which is the latest usable rating. History ordering,
late/out-of-order event submissions, rerates and category filters matter.

Proposed UI wording when certainty is missing: “Published rating available; latest
rating unavailable/unverified.” Never display a fetched value as live solely
because the HTTP request happened now. Never use the maximum historical rating
as the latest rating. An event-history fallback must retain the event/date and be
labelled as a latest observed event result until its semantics are verified.

Before accepting this core feature, use a token to compare published vs unofficial
queries, supplement history, and current portal displays across established,
provisional, newly rated and recently rerated players. Ask US Chess to confirm
the supported endpoint, category filter, ordering and freshness contract.

## Validate a roster without silently identifying the wrong person

1. Preserve raw row, source filename/URL, import time and stable import-row ID.
2. Normalize ID as a string. Check expected syntax and duplicate use; do not infer
   identity from syntax. Distinguish a missing ID from an invalid one.
3. Look up exact IDs first. Compare names tolerantly for punctuation, accents,
   order and initials, while retaining the exact official response.
4. Return per-row findings: exact match; probable spelling difference; ID/name
   conflict; duplicate entry; expired membership; not found; request failed;
   unresolved rating category. Missing fields mean unknown, not false or zero.
5. For conflicts or missing IDs, use bounded name search (`Fuzzy`) or an authorized
   local supplement. Show multiple candidates with public discriminators and
   evidence. A one-digit ID difference is evidence for review, never auto-repair.
6. TD chooses the identity and which fields to apply. Show before/after names,
   IDs, ratings and membership state together. Bulk approval is for reviewed safe
   changes; unresolved identity matches cannot be hidden inside “Update all.”
7. Record the decision, original data and selected source. Re-importing the same
   registration must preserve confirmed corrections unless explicitly superseded.

Membership expiration is compared with the event's relevant date, not just today.
Club membership and US Chess membership are different fields. Do not infer identity
from email, gender, age or name alone. Avoid importing unnecessary contact or birth
data; redact it from diagnostics and public output.

## Client behavior

One configurable request queue; conservative rate, cache and per-ID deduplication;
cancel/resume; respect `Retry-After`; bounded retries for transient failures;
clear 401/403 setup state; 404 as not found; 429 as throttling; partial success
summaries. Numeric service quotas are not documented in this pass and must not be
invented. Unknown JSON enum values and nullable fields must fail gently.

Fetch observations into a review batch. A separate transaction applies selected
changes. A refresh that finishes after an entrant was edited or moved must not
overwrite the newer revision. Freeze pairing and eligibility rating snapshots
before pairing; refreshing the member cache later does not reseed an event.

Offline import of a supplement remains useful. The provider's supplement formats
and category labels need their own tests. Do not assume a `Q_*` DBF field means
Quick regardless of which provider file it came from.

Without a token we can design parsers, typed errors, queues, UI states and contract
fixtures. We cannot claim verified authenticated behavior, guaranteed live-rating
access, or provider approval.
