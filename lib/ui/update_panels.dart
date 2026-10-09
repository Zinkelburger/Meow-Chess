import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../application/tournament_controller.dart';
import '../application/failures.dart';
import '../application/diagnostics.dart';
import '../domain/model.dart';
import '../infrastructure/roster_import.dart';
import '../infrastructure/web_roster.dart';
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
        error = null;
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
    // A first fetch adds the roster; later fetches update it.
    final first = c.event!.players.isEmpty;
    return SidePanel(
      title: first ? 'Add from URL' : 'Refresh from URL',
      onClose: widget.onClose,
      footer: [
        if (r != null)
          FilledButton(
            onPressed: r.rows.every((row) => row.player == null) ? null : apply,
            child: Text('Confirm ${selected.length} changes & save source'),
          ),
      ],
      children: [
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
        OutlinedButton.icon(
          onPressed: busy ? null : fetch,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(
            busy
                ? 'Reading entry list…'
                : first
                ? 'Fetch players'
                : 'Fetch updates',
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('import-refresh-ratings'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Fetch ratings from USCF'),
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
