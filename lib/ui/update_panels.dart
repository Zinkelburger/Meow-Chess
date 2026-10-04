import '../application/member_lookup.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../application/tournament_controller.dart';
import '../application/failures.dart';
import '../application/diagnostics.dart';
import '../application/member_lookup_batch.dart';
import '../domain/model.dart';
import '../domain/rating_update.dart';
import '../domain/membership.dart';
import 'membership_style.dart';
import '../infrastructure/roster_import.dart';
import '../infrastructure/web_roster.dart';
import '../domain/member_observation.dart';
import '../infrastructure/member_directory.dart';
import 'side_panel.dart';

String rosterRefreshLabel(Event event) {
  final source = event.rosterSource['url'] as String?;
  return source == null || source.isEmpty
      ? 'Refresh from URL'
      : 'Refresh from $source';
}

class WebRosterPanel extends StatefulWidget {
  const WebRosterPanel({
    required this.controller,
    required this.onClose,
    this.loader,
    this.onImported,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final Future<List<ImportRow>> Function(String)? loader;
  final ValueChanged<bool>? onImported;
  @override
  State<WebRosterPanel> createState() => _WebRosterPanelState();
}

class _WebRosterPanelState extends State<WebRosterPanel> {
  final url = TextEditingController();
  final selected = <String>{};
  RosterReview? review;
  String? error, notice;
  bool busy = false;
  bool refreshRatings = true;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    url.text =
        c.event!.rosterSource['url'] as String? ??
        c.workspaceState.read('roster-url') ??
        '';
    url.addListener(remember);
  }

  void remember() => c.workspaceState.write('roster-url', url.text);
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  Future<void> fetch() async {
    if (busy) return;
    final snapshot = c.event!, source = url.text.trim();
    setState(() {
      busy = true;
      error = null;
      notice = null;
      review = null;
    });
    final client = http.Client();
    Diagnostics.record(
      'fetch website roster',
      'started',
      context: {'url': Diagnostics.sourceUrl(source)},
    );
    try {
      final rows = await (widget.loader ?? WebRoster(client).fetch)(source);
      Diagnostics.record(
        'fetch website roster',
        'succeeded',
        context: {
          'rows': rows.length,
          'invalidRows': rows.where((r) => r.error != null).length,
        },
      );
      if (!mounted) return;
      final proposal = RosterReview(snapshot, source, rows);
      setState(() {
        review = proposal;
        selected.clear();
        selected.addAll([
          for (final item in proposal.changes)
            if (item.existing == null && item.problem == null) item.key,
        ]);
      });
    } catch (e, stack) {
      Diagnostics.record(
        'fetch website roster',
        'failed',
        error: e,
        stack: stack,
      );
      if (mounted) {
        setState(() {
          review = null;
          error = e is TypeError
              ? 'The entry list could not be read. Close and reopen Meow-Chess, then fetch again. You can also import a CSV. Your roster is unchanged.'
              : '${plainMessage(e)} Retry the entry-list URL or import a CSV. Your roster is unchanged.';
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  void apply() {
    Diagnostics.record(
      'import website roster',
      'started',
      context: {'selected': selected.length, 'revision': c.event!.revision},
    );
    try {
      final next = review!.apply(c.event!, selected);
      c.change('Review website roster: ${selected.length} changes', next);
      Diagnostics.record(
        'import website roster',
        'succeeded',
        context: {'selected': selected.length, 'revision': c.event!.revision},
      );
      setState(() {
        notice =
            'Saved locally. ${selected.length} changes applied. Nobody removed. Undo is available in History.';
        review = null;
      });
      widget.onImported?.call(refreshRatings);
    } catch (e, stack) {
      Diagnostics.record(
        'import website roster',
        'failed',
        error: e,
        stack: stack,
      );
      setState(
        () => error = e is TypeError
            ? 'The import could not be completed. Close and reopen Meow-Chess, then fetch and confirm again. Error details are in Help → Export diagnostic log.'
            : '${plainMessage(e)} Details are in Help → Export diagnostic log.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = review;
    return SidePanel(
      title: 'Refresh from URL',
      onClose: widget.onClose,
      footer: [
        if (r != null)
          FilledButton(
            onPressed: r.rows.every((row) => row.player == null) ? null : apply,
            child: Text('Confirm ${selected.length} changes & save source'),
          ),
      ],
      children: [
        const Text(
          'Read a registration table from a web link, then confirm the changes to this event.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('roster-url'),
          controller: url,
          autofocus: true,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Event or entry-list URL',
          ),
          onChanged: (_) => setState(() => review = null),
          onSubmitted: (_) => fetch(),
        ),
        const SizedBox(height: 8),
        const Text(
          'Boylston: paste an event or entry-list link. Other clubs: paste the page with a Name and Rating table (USCF IDs are optional).',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : fetch,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(busy ? 'Reading entry list…' : 'Fetch updates'),
        ),
        CheckboxListTile(
          key: const ValueKey('import-refresh-ratings'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Refresh ratings from USCF'),
          subtitle: const Text(
            'Review proposed ratings after import. Players without IDs are skipped.',
          ),
          value: refreshRatings,
          onChanged: busy
              ? null
              : (value) => setState(() => refreshRatings = value == true),
        ),
        if (c.event!.rosterSource['fetchedAt'] case final String date)
          Text('Last confirmed: $date'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(notice!),
          ),
        if (r != null) ...[
          const Divider(height: 32),
          Text(
            'Confirm these updates',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${r.changes.where((x) => x.existing == null && x.problem == null).length} new · ${r.changes.where((x) => x.existing != null && x.changed).length} changed · ${r.missing.length} missing',
          ),
          const SizedBox(height: 8),
          for (final row in r.rows.where((row) => row.error != null))
            Text('Row ${row.line}: ${row.error}. Skipped.'),
          for (final p in r.missing)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(p.name),
              subtitle: const Text(
                'Missing from website — kept in this event.',
              ),
            ),
          for (final item in r.changes)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(item.key),
              onChanged:
                  item.problem != null ||
                      !item.changed ||
                      (item.existing != null &&
                          item.existing!.registrationNote ==
                              item.incoming.registrationNote &&
                          (c.event!
                                  .sectionOf(item.existing!.id)
                                  ?.rounds
                                  .isNotEmpty ??
                              false))
                  ? null
                  : (value) => setState(() {
                      value == true
                          ? selected.add(item.key)
                          : selected.remove(item.key);
                    }),
              title: Text(
                '${item.existing == null
                    ? 'Add'
                    : item.changed
                    ? 'Review'
                    : 'Keep'} ${item.incoming.name}',
              ),
              subtitle: Text(
                item.problem ??
                    '${item.incoming.memberId.isEmpty ? 'No USCF ID' : item.incoming.memberId}\n${item.existing == null ? '' : 'Local: ${item.existing!.name}, ${item.existing!.rating}\n'}Website rating: ${item.incoming.rating == 0 ? 'UNR' : item.incoming.rating}\nWebsite note: ${item.incoming.registrationNote.isEmpty ? '—' : item.incoming.registrationNote}${item.existing != null && item.existing!.registrationNote != item.incoming.registrationNote ? '\nLocal note: ${item.existing!.registrationNote.isEmpty ? '—' : item.existing!.registrationNote}' : ''}${item.existing?.ratingEvidence['supplementDate'] != null ? '\nVerified supplement rating will be kept.' : ''}${item.existing != null && (c.event!.sectionOf(item.existing!.id)?.rounds.isNotEmpty ?? false) ? '\nPosted section: only the website note can be updated.' : ''}',
              ),
            ),
        ],
      ],
    );
  }
}

class RatingsRefreshPanel extends StatefulWidget {
  const RatingsRefreshPanel({
    required this.controller,
    required this.onClose,
    this.lookup = fetchMember,
    this.membershipOnly = false,
    super.key,
  });
  const RatingsRefreshPanel.membership({
    required this.controller,
    required this.onClose,
    this.lookup = fetchMembership,
    super.key,
  }) : membershipOnly = true;
  final bool membershipOnly;
  final TournamentController controller;
  final VoidCallback onClose;
  final MemberLookup lookup;
  @override
  State<RatingsRefreshPanel> createState() => _RatingsRefreshPanelState();
}

class _RatingsRefreshPanelState extends State<RatingsRefreshPanel> {
  final observations = <String, MemberObservation>{};
  final failures = <String, String>{};
  final selected = <String>{};
  Event? snapshot;
  String category = 'R';
  bool busy = false, cancelled = false;
  String? notice;
  TournamentController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    loadCategory();
  }

  Future<void> loadCategory() async {
    final value = await readRatingCategory();
    if (mounted && snapshot == null) setState(() => category = value);
  }

  Future<void> fetch() async {
    final event = c.event!;
    setState(() {
      snapshot = event;
      observations.clear();
      failures.clear();
      selected.clear();
      busy = true;
      cancelled = false;
      notice = null;
    });
    try {
      final outcome = await const MemberLookupBatch().run(
        event.players,
        lookup: (id) => widget.lookup(id),
        isCurrent: () =>
            mounted &&
            !cancelled &&
            c.event?.id == snapshot?.id &&
            c.event?.revision == snapshot?.revision,
        onMissingId: (player) => setState(
          () => failures[player.id] =
              'No USCF ID — enter one on the player card.',
        ),
        onFound: (player, found) {
          c.recordMembership(event.id, player.id, found.toJson());
          setState(() {
            snapshot = c.event!;
            observations[player.id] = found;
          });
        },
        onFailure: (player, error, _) =>
            setState(() => failures[player.id] = plainMessage(error)),
      );
      if (!mounted) return;
      if (outcome == MemberBatchOutcome.providerStopped) {
        notice =
            'Provider stopped the batch. Completed lookups are available below; retry later.';
      } else if (outcome == MemberBatchOutcome.cancelled && !cancelled) {
        notice = 'The event changed. Fetch again to check the current roster.';
      }
    } catch (error) {
      if (mounted) notice = plainMessage(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    cancelled = true;
    super.dispose();
  }

  void apply() {
    try {
      if (c.event!.revision != snapshot!.revision) {
        throw const TournamentException(
          'The event changed. Fetch and review ratings again.',
        );
      }
      c.applyReviewedRatings(
        snapshot: snapshot!,
        observations: observations,
        playerIds: selected,
        category: category,
      );
      setState(() {
        notice =
            'Saved ${selected.length} supplement ratings locally. Section assignments are unchanged.';
        snapshot = null;
        selected.clear();
      });
    } catch (e) {
      setState(() => notice = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => SidePanel(
    title: widget.membershipOnly
        ? 'Check USCF memberships'
        : 'Refresh US Chess ratings',
    onClose: widget.onClose,
    children: [
      Text(
        widget.membershipOnly
            ? 'Fetch membership expiration dates directly from US Chess for every player in this event. Successful checks are saved automatically, including for unrated players and posted sections.'
            : 'Fetch dated monthly supplements for every USCF ID. Membership expiration dates are saved automatically. Review the official name and old → new rating, then tick the rating changes you approve.',
      ),
      const SizedBox(height: 12),
      if (!widget.membershipOnly)
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: category,
          key: ValueKey('refresh-category-$category'),
          decoration: const InputDecoration(labelText: 'Rating category'),
          items: const [
            DropdownMenuItem(value: 'R', child: Text('Regular')),
            DropdownMenuItem(value: 'Q', child: Text('Quick')),
            DropdownMenuItem(value: 'B', child: Text('Blitz')),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                  category = v!;
                  selected.clear();
                }),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy ? null : fetch,
            child: Text(
              busy
                  ? 'Fetched ${observations.length + failures.length} of ${snapshot!.players.length}…'
                  : widget.membershipOnly
                  ? 'Fetch memberships'
                  : 'Fetch monthly supplements',
            ),
          ),
          if (busy)
            TextButton(
              onPressed: () => setState(() {
                cancelled = true;
                notice = 'Stopped. Completed lookups are available for review.';
              }),
              child: const Text('Stop'),
            ),
        ],
      ),
      if (notice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(notice!),
        ),
      if (snapshot != null) ...[
        const SizedBox(height: 12),
        if (!widget.membershipOnly)
          const Text(
            'Posted sections keep their pairing ratings. Missing ratings never replace a number with zero.',
          ),
        for (final p in snapshot!.players)
          if (observations[p.id] case final m?)
            if (widget.membershipOnly)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${p.name} · ${MembershipSummary(p, eventDate: snapshot!.lastDate).label}',
                  style: TextStyle(
                    color: membershipColor(
                      Theme.of(context).colorScheme,
                      MembershipSummary(p, eventDate: snapshot!.lastDate),
                    ),
                  ),
                ),
                subtitle: Text(
                  'USCF ${m.id}: ${m.name}\n${MembershipSummary(p, eventDate: snapshot!.lastDate).detail}',
                ),
              )
            else
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(p.id),
                onChanged:
                    busy ||
                        ratingUpdateProblem(
                              current: c.event!,
                              snapshot: snapshot!,
                              player: c.event!.player(p.id),
                              observation: m,
                              category: category,
                            ) !=
                            null
                    ? null
                    : (value) => setState(() {
                        value == true
                            ? selected.add(p.id)
                            : selected.remove(p.id);
                      }),
                title: Text(
                  '${p.name}: ${p.rating} → ${m.ratings[category] ?? 'unavailable'}',
                ),
                subtitle: Text(
                  'USCF ${m.id}: ${m.name}\nMembership expiration: ${m.expiration ?? 'unavailable'} · ${m.status ?? 'unknown'}\nSupplement ${m.supplementDate ?? 'date unavailable'}${(snapshot!.sectionOf(p.id)?.rounds.isNotEmpty ?? false) ? '\nPairings posted — rating kept.' : ''}',
                ),
              )
          else if (failures[p.id] case final error?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name),
              subtitle: Text(error),
            ),
        if (!widget.membershipOnly)
          FilledButton(
            onPressed: busy || selected.isEmpty ? null : apply,
            child: Text('Confirm ${selected.length} rating changes'),
          ),
      ],
    ],
  );
}
