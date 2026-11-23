import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../application/tournament_controller.dart';
import '../application/failures.dart';
import '../application/diagnostics.dart';
import '../domain/announcement.dart';
import '../domain/model.dart';
import '../infrastructure/roster_import.dart';
import '../infrastructure/web_roster.dart';
import 'player_format.dart';
import 'side_panel.dart';
import 'theme.dart';

String rosterRefreshLabel(Event event) {
  final source = event.rosterSource['url'] as String?;
  return source == null || source.isEmpty
      ? 'Refresh from URL'
      : 'Refresh from $source';
}

/// Adds a club's entry list from its URL. One fetch, one button: new
/// entries are added, sections the list names are started, and only what
/// needs a decision is listed (a changed local player, a row that cannot
/// come in). Format and rounds are set afterwards, in Set up.
class WebRosterPanel extends StatefulWidget {
  const WebRosterPanel({
    required this.controller,
    required this.onClose,
    this.loader,
    this.announcementLoader,
    this.onImported,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final Future<List<ImportRow>> Function(String)? loader;

  /// Reads what the club's event page announces. With a test [loader] and
  /// none of its own, nothing is fetched.
  final Future<Announcement?> Function(String)? announcementLoader;
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
  bool showAll = false;
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
      final web = WebRoster(client);
      // The event page is a courtesy: it never holds the entry list up.
      final announced =
          (widget.announcementLoader ??
                  (widget.loader == null
                      ? web.fetchAnnouncement
                      : (_) async => null))(source)
              .catchError((Object _) => null);
      final rows = await (widget.loader ?? web.fetch)(source);
      final announcement = await announced;
      Diagnostics.record(
        'fetch website roster',
        'succeeded',
        context: {
          'rows': rows.length,
          'invalidRows': rows.where((r) => r.error != null).length,
          'announcement': announcement != null,
        },
      );
      if (!mounted) return;
      final proposal = RosterReview(
        snapshot,
        source,
        rows,
        announcement: announcement,
      );
      setState(() {
        review = proposal;
        showAll = false;
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

  /// The new entries and the local players being updated, among [selected].
  ({int added, int updated}) counts(RosterReview r) {
    var added = 0, updated = 0;
    for (final item in r.changes) {
      if (!selected.contains(item.key)) continue;
      item.existing == null ? added++ : updated++;
    }
    return (added: added, updated: updated);
  }

  static String players(int n) => '$n ${n == 1 ? 'player' : 'players'}';

  /// What the button will do, in its own words; null when there is nothing
  /// to add or update.
  String? actionLabel(RosterReview r) {
    final (:added, :updated) = counts(r);
    if (added > 0 && updated > 0) return 'Add $added and update $updated';
    if (added > 0) return 'Add ${players(added)}';
    if (updated > 0) return 'Update ${players(updated)}';
    return null;
  }

  void apply() {
    final r = review!;
    final (:added, :updated) = counts(r);
    Diagnostics.record(
      'import website roster',
      'started',
      context: {'selected': selected.length, 'revision': c.event!.revision},
    );
    try {
      final next = r.apply(c.event!, selected);
      c.change(
        added > 0 && updated > 0
            ? 'Add ${players(added)} and update $updated from the website'
            : added > 0
            ? 'Add ${players(added)} from the website'
            : updated > 0
            ? 'Update ${players(updated)} from the website'
            : 'Save the entry-list URL',
        next,
      );
      Diagnostics.record(
        'import website roster',
        'succeeded',
        context: {'selected': selected.length, 'revision': c.event!.revision},
      );
      setState(() {
        error = null;
        notice = [
          if (added > 0) 'Added ${players(added)}.',
          if (updated > 0) 'Updated ${players(updated)}.',
          if (added == 0 && updated == 0) 'Saved the URL for later refreshes.',
          'Nobody was removed.',
        ].join(' ');
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
            ? 'The import could not be completed. Close and reopen Meow-Chess, then fetch again. Error details are in Help → Export diagnostic log.'
            : '${plainMessage(e)} Details are in Help → Export diagnostic log.',
      );
    }
  }

  /// A local player whose section is paired takes only a changed note.
  bool noteOnly(RosterChange item) =>
      item.existing != null &&
      (c.event!.sectionOf(item.existing!.id)?.rounds.isNotEmpty ?? false);

  /// What the website now says differently about a local player.
  String difference(RosterChange item) {
    final old = item.existing!, now = item.incoming;
    return [
      if (old.name != now.name) 'Name ${old.name} → ${now.name}',
      if (old.rating != now.rating)
        noteOnly(item)
            ? 'Rating stays ${ratingText(old.rating)}: the section is paired'
            : old.ratingEvidence['supplementDate'] != null
            ? 'Rating stays ${ratingText(old.rating)}: verified with US Chess'
            : 'Rating ${ratingText(old.rating)} → ${ratingText(now.rating)}',
      if (old.registrationNote != now.registrationNote)
        'Note: ${now.registrationNote.isEmpty ? 'removed' : now.registrationNote}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final r = review;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    // A first fetch adds the roster; later fetches update it.
    final first = c.event!.players.isEmpty;
    final label = r == null ? null : actionLabel(r);
    final saved = r != null && c.event!.rosterSource['url'] == r.url;
    final readable = r != null && r.rows.any((row) => row.player != null);
    return SidePanel(
      title: first ? 'Add from URL' : 'Refresh from URL',
      onClose: widget.onClose,
      footer: [
        if (r != null && readable && (label != null || !saved)) ...[
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Check(
                checkKey: const ValueKey('import-refresh-ratings'),
                label: 'Fetch ratings from US Chess',
                value: refreshRatings,
                onChanged: (v) => setState(() => refreshRatings = v),
              ),
            ),
          FilledButton(
            key: const ValueKey('confirm-web-roster'),
            onPressed: apply,
            child: Text(label ?? 'Save this URL'),
          ),
        ],
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
        if (c.event!.rosterSource['fetchedAt'] case final String date)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Last added from this URL: $date', style: muted),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(notice!, key: const ValueKey('web-roster-notice')),
          ),
        if (r != null) ..._review(context, r, first, muted),
      ],
    );
  }

  List<Widget> _review(
    BuildContext context,
    RosterReview r,
    bool first,
    TextStyle muted,
  ) {
    final plan = r.sectionPlan(c.event!, selected);
    final fresh = [
      for (final item in r.changes)
        if (item.existing == null && item.problem == null) item,
    ];
    final changed = [
      for (final item in r.changes)
        if (item.existing != null && item.changed && item.problem == null) item,
    ];
    final blocked = [
      for (final item in r.changes)
        if (item.problem != null) item,
    ];
    final unreadable = r.rows.where((row) => row.error != null).toList();
    final announced = r.announcement;
    final sections = [
      for (final MapEntry(key: name, value: ids) in plan.creates.entries)
        '$name ${ids.length}',
    ].join(' · ');
    final joins = <String, int>{};
    for (final id in plan.joins.values) {
      joins[id] = (joins[id] ?? 0) + 1;
    }
    final joining = [
      for (final s in c.event!.sections)
        if (joins[s.id] case final n?) '${s.name} +$n',
    ].join(' · ');
    const tabular = [FontFeature.tabularFigures()];
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return [
      const Divider(height: 32),
      Text(
        fresh.isEmpty
            ? 'No new players'
            : first
            ? players(fresh.length)
            : '${fresh.length} new ${fresh.length == 1 ? 'player' : 'players'}',
        key: const ValueKey('web-roster-count'),
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontFeatures: tabular),
      ),
      if (sections.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            sections,
            key: const ValueKey('web-new-sections'),
            style: const TextStyle(fontFeatures: tabular),
          ),
        ),
      if (joining.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(joining, style: const TextStyle(fontFeatures: tabular)),
        ),
      if (plan.creates.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            announced != null && announced.summary.isNotEmpty
                ? 'Event page: ${announced.summary}'
                : 'Format and rounds come next, in Set up',
            key: const ValueKey('web-announced'),
            style: muted,
          ),
        ),
      if (unreadable.isNotEmpty) ...[
        heading('Left out'),
        for (final row in unreadable)
          Text('Row ${row.line}: ${row.error}', style: muted),
      ],
      if (blocked.isNotEmpty) ...[
        heading('Not added'),
        for (final item in blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: item.incoming.name),
                  TextSpan(text: '  ${item.problem}', style: muted),
                ],
              ),
            ),
          ),
      ],
      if (plan.skipped.isNotEmpty) ...[
        heading('Added without a section'),
        for (final MapEntry(key: id, value: why) in plan.skipped.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: r.changes
                        .where((x) => (x.existing?.id ?? x.incoming.id) == id)
                        .map((x) => x.incoming.name)
                        .firstOrNull,
                  ),
                  TextSpan(text: '  $why', style: muted),
                ],
              ),
            ),
          ),
      ],
      if (changed.isNotEmpty) ...[
        heading('Changed on the website'),
        for (final item in changed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Check(
              checkKey: ValueKey('web-change-${item.key}'),
              label: 'Update ${item.existing!.name}',
              detail: difference(item),
              value: selected.contains(item.key),
              // A paired section's player takes a changed note and
              // nothing else.
              onChanged:
                  noteOnly(item) &&
                      item.existing!.registrationNote ==
                          item.incoming.registrationNote
                  ? null
                  : (v) => setState(
                      () => v
                          ? selected.add(item.key)
                          : selected.remove(item.key),
                    ),
            ),
          ),
      ],
      if (r.missing.isNotEmpty) ...[
        heading('No longer on the website'),
        Text(
          '${r.missing.map((p) => p.name).join(', ')} · kept in this event',
          style: muted,
        ),
      ],
      if (fresh.isEmpty && changed.isEmpty && blocked.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('The roster matches the website.', style: muted),
        ),
      if (fresh.isNotEmpty) ...[
        const SizedBox(height: 12),
        DisclosureGroup(
          headerKey: const ValueKey('web-show-all'),
          title: 'All ${fresh.length} new entries',
          open: showAll,
          onToggle: () => setState(() => showAll = !showAll),
          children: [
            for (final item in fresh)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.incoming.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      [
                        ratingText(item.incoming.rating),
                        ?plan.createdFor(item.incoming.id),
                        if (plan.joins[item.incoming.id] case final id?)
                          c.event!.sections.firstWhere((s) => s.id == id).name,
                      ].join(' · '),
                      style: muted.copyWith(fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ];
  }
}

/// A flat checkbox with its label beside it and an optional second line.
/// A null [onChanged] shows it fixed.
class _Check extends StatelessWidget {
  const _Check({
    required this.checkKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });
  final Key checkKey;
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final change = onChanged;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlainCheckbox(
          key: checkKey,
          label: label,
          value: value,
          onChanged: change == null ? null : (v) => change(v ?? false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: change == null ? null : () => change(!value),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    if (detail case final text? when text.isNotEmpty)
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
