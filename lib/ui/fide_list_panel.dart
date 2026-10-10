import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/fide.dart';
import '../domain/model.dart';
import '../infrastructure/fide_rating_list.dart';
import 'side_panel.dart';
import 'membership_style.dart';
import 'panels.dart' show Dock;
import 'player_panel.dart' show PlayerPanel;
import 'theme.dart';

/// What a list record would change on [p], in words; empty when nothing.
List<String> fideChanges(Player p, FideListPlayer r, {required bool locked}) {
  String rating(int n) => n == 0 ? 'unrated' : '$n';
  return [
    if (!locked) ...[
      if (p.fideStandard != r.standard)
        'Standard ${rating(p.fideStandard)} → ${rating(r.standard)}',
      if (p.fideRapid != r.rapid)
        'Rapid ${rating(p.fideRapid)} → ${rating(r.rapid)}',
      if (p.fideBlitz != r.blitz)
        'Blitz ${rating(p.fideBlitz)} → ${rating(r.blitz)}',
      if (p.title != r.title) r.title.isEmpty ? 'No title' : 'Title ${r.title}',
    ],
    if (isFederationCode(r.federation) && p.federation != r.federation)
      'Federation ${r.federation}',
    if (r.sex.isNotEmpty && p.sex != r.sex)
      'Sex ${r.sex == 'm' ? 'male' : 'female'}',
    if (r.birthYear.isNotEmpty && !p.birthDate.startsWith(r.birthYear))
      'Born ${r.birthYear}',
  ];
}

/// [p] updated from [r]: everything when ratings may change, otherwise
/// only federation, sex and birth year.
Player applyFideRecord(
  Player p,
  FideListPlayer r, {
  required String month,
  required bool locked,
}) {
  final updated = r.applyTo(p, month: month);
  return locked
      ? p.copy(
          federation: updated.federation,
          sex: updated.sex,
          birthDate: updated.birthDate,
        )
      : updated;
}

/// Opens the FIDE ratings panel in the dock.
void showFideList(BuildContext context, TournamentController c) {
  final dock = Dock.maybeOf(context);
  dock?.show(
    'fide-list',
    ListenableBuilder(
      listenable: c,
      builder: (_, _) => FideListPanel(controller: c, onClose: dock.close),
    ),
  );
}

/// FIDE ratings for the event: the monthly FIDE list on this computer, and
/// the changes it brings for every player with a FIDE ID, reviewed before
/// they apply as one undoable step.
class FideListPanel extends StatefulWidget {
  const FideListPanel({
    required this.controller,
    required this.onClose,
    this.list,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final FideRatingList? list;

  @override
  State<FideListPanel> createState() => _FideListPanelState();
}

class _FideListPanelState extends State<FideListPanel> {
  late final FideRatingList list = widget.list ?? FideRatingList();
  FideListInfo? info;
  bool loading = true, checking = false;

  /// Set while downloading or importing: what the panel says it is doing.
  String? busy;
  String? error, notice;

  /// The last check: records by FIDE ID, and which rows are ticked.
  Map<String, FideListPlayer>? found;
  final ticked = <String>{};

  TournamentController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    list.info().then((value) {
      if (mounted) {
        setState(() {
          info = value;
          loading = false;
        });
      }
    });
  }

  Future<void> run(String doing, Future<FideListInfo> Function() action) async {
    setState(() {
      busy = doing;
      error = null;
      notice = null;
    });
    try {
      final installed = await action();
      if (!mounted) return;
      setState(() {
        info = installed;
        found = null;
      });
      await check();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = cancelled
              ? 'Download cancelled. Nothing changed.'
              : plainMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  /// The client of a download in progress; closing it cancels.
  http.Client? downloading;
  bool cancelled = false;

  void cancelDownload() {
    cancelled = true;
    downloading?.close();
  }

  Future<void> download() async {
    final client = downloading = http.Client();
    cancelled = false;
    try {
      await runDownload(client);
    } finally {
      client.close();
      downloading = null;
    }
  }

  Future<void> runDownload(http.Client client) => run(
    'Downloading the FIDE list…',
    () => list.download(
      client: client,
      progress: (received, total) {
        if (!mounted) return;
        final mb = (received / 1e6).toStringAsFixed(0);
        setState(
          () => busy = received == total
              ? 'Preparing the list (about 20 seconds)…'
              : total == null
              ? 'Downloading the FIDE list… $mb MB'
              : 'Downloading the FIDE list… $mb of ${(total / 1e6).toStringAsFixed(0)} MB',
        );
      },
    ),
  );

  Future<void> choose() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'FIDE rating list', extensions: ['zip']),
      ],
    );
    if (file == null) return;
    await run(
      'Preparing the list (about 20 seconds)…',
      () => list.importZip(file.path),
    );
  }

  List<Player> get withIds => [
    for (final p in c.event!.players)
      if (isFideId(p.fideId)) p,
  ];

  /// Compares the event with the list. After an apply, [keepNotice] keeps
  /// the confirmation on screen.
  /// The event's FIDE arbiters with a FIDE ID: (role, ID).
  List<(String, String)> get officials {
    return [
      for (final (role, official) in c.event!.fide.officials)
        if (isFideId(official.id)) (role, official.id),
    ];
  }

  Future<void> check({bool keepNotice = false}) async {
    if (info == null) return;
    setState(() {
      checking = true;
      error = null;
      if (!keepNotice) notice = null;
    });
    try {
      final records = await list.lookup({
        for (final p in withIds) p.fideId,
        for (final (_, id) in officials) id,
      });
      if (!mounted) return;
      setState(() {
        found = records;
        ticked
          ..clear()
          ..addAll([
            for (final p in withIds)
              if (records[p.fideId] case final r?
                  when fideChanges(
                    p,
                    r,
                    locked: fideRatingsLocked(c.event!, p),
                  ).isNotEmpty)
                p.id,
          ]);
      });
    } catch (e) {
      if (mounted) setState(() => error = plainMessage(e));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  /// Opens [p]'s panel at the FIDE ID, in place of this one.
  void showPlayer(Player p) {
    final dock = Dock.maybeOf(context);
    dock?.show(
      ('fide-player', p.id),
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => c.event!.players.any((x) => x.id == p.id)
            ? PlayerPanel(
                key: ValueKey('fide-player-${p.id}'),
                controller: c,
                player: c.event!.player(p.id),
                focusField: 'fideId',
                onClose: dock.close,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  void apply() {
    final records = found, month = info?.month;
    if (records == null || month == null) return;
    final e = c.event!;
    final updates = <String, Player>{};
    for (final p in e.players) {
      if (!ticked.contains(p.id)) continue;
      final r = records[p.fideId];
      if (r == null) continue;
      updates[p.id] = applyFideRecord(
        p,
        r,
        month: month,
        locked: fideRatingsLocked(e, p),
      );
    }
    if (updates.isEmpty) return;
    try {
      c.change(
        'Update ${updates.length} ${updates.length == 1 ? 'player' : 'players'} from the ${info!.label} FIDE list',
        e.copy(players: [for (final p in e.players) updates[p.id] ?? p]),
      );
      setState(() {
        notice =
            'Updated ${updates.length} ${updates.length == 1 ? 'player' : 'players'}. Undo reverses it.';
        ticked.clear();
      });
      check(keepNotice: true);
    } catch (err) {
      setState(() => error = plainMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final e = c.event!;
    final installed = info;
    final records = found;
    final withId = withIds;
    final noId = [
      for (final s in e.sections.where((s) => s.fideRated))
        for (final id in s.players)
          if (!isFideId(e.player(id).fideId)) e.player(id),
    ];
    final rows = records == null
        ? const <(Player, FideListPlayer, List<String>, bool)>[]
        : [
            for (final p in withId)
              if (records[p.fideId] case final r?)
                (
                  p,
                  r,
                  fideChanges(p, r, locked: fideRatingsLocked(e, p)),
                  fideRatingsLocked(e, p),
                ),
          ].where((x) => x.$3.isNotEmpty).toList();
    final missing = records == null
        ? const <Player>[]
        : [
            for (final p in withId)
              if (!records.containsKey(p.fideId)) p,
          ];
    final sources = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        installed == null
            ? FilledButton(
                key: const ValueKey('fide-list-download'),
                onPressed: busy == null ? download : null,
                child: const Text('Download from FIDE (45 MB)'),
              )
            : OutlinedButton(
                key: const ValueKey('fide-list-download'),
                onPressed: busy == null ? download : null,
                child: const Text('Download again'),
              ),
        OutlinedButton(
          key: const ValueKey('fide-list-choose'),
          onPressed: busy == null ? choose : null,
          child: const Text('Choose list ZIP…'),
        ),
      ],
    );
    return SidePanel(
      key: const ValueKey('fide-list-panel'),
      title: 'FIDE ratings',
      onClose: widget.onClose,
      footer: [
        if (rows.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('fide-list-apply'),
              onPressed: ticked.isEmpty ? null : apply,
              child: Text(
                'Apply ${ticked.length} ${ticked.length == 1 ? 'update' : 'updates'}',
              ),
            ),
          ),
      ],
      children: [
        if (loading)
          Text('Looking for a FIDE list on this computer…', style: muted)
        else if (installed == null) ...[
          Text(
            'FIDE publishes its ratings once a month as one list. Meow-Chess keeps a copy on this computer and fills FIDE ratings, titles, federations and birth years by FIDE ID.',
            style: muted,
          ),
          const SizedBox(height: 12),
          sources,
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Already downloaded? Choose players_list.zip from ratings.fide.com.',
              style: muted,
            ),
          ),
        ] else ...[
          Text(
            '${installed.label} list',
            key: const ValueKey('fide-list-month'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${_thousands(installed.players)} players · FIDE publishes a new list on the 1st of each month.',
            style: muted,
          ),
          if (installed.month.compareTo(
                e.date.length >= 7 ? e.date.substring(0, 7) : installed.month,
              ) <
              0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Older than this event: download again for the ratings FIDE publishes for ${e.date.substring(0, 7)}.',
                key: const ValueKey('fide-list-stale'),
                style: TextStyle(fontSize: 13, color: attentionColor(colors)),
              ),
            ),
          const SizedBox(height: 8),
          sources,
        ],
        if (busy != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(busy!, key: const ValueKey('fide-list-busy')),
            ),
          ),
        if (busy != null &&
            downloading != null &&
            !busy!.startsWith('Preparing'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('fide-list-cancel'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: cancelDownload,
              child: const Text('Cancel download'),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        if (installed != null && busy == null) ...[
          const SizedBox(height: 20),
          Text('This event', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (checking)
            Text('Checking ${withId.length} FIDE IDs…', style: muted)
          else if (records == null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('fide-list-check'),
                onPressed: withId.isEmpty ? null : check,
                child: Text(
                  'Check ${withId.length} ${withId.length == 1 ? 'player' : 'players'} with a FIDE ID',
                ),
              ),
            )
          else ...[
            Text(
              rows.isEmpty
                  ? 'All ${withId.length - missing.length} listed players match the ${installed.label} list.'
                  : '${rows.length} of ${withId.length} players differ from the ${installed.label} list.',
              key: const ValueKey('fide-list-summary'),
              style: muted,
            ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(notice!, style: muted),
              ),
            const SizedBox(height: 8),
            for (final (p, r, changes, locked) in rows)
              _ChangeRow(
                key: ValueKey('fide-change-${p.id}'),
                player: p,
                record: r,
                changes: changes,
                locked: locked,
                ticked: ticked.contains(p.id),
                onChanged: (on) =>
                    setState(() => on ? ticked.add(p.id) : ticked.remove(p.id)),
              ),
          ],
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Not on the list: ${missing.map((p) => '${p.name} (${p.fideId})').join(', ')}. Check the IDs in their player panels.',
                style: TextStyle(fontSize: 13, color: attentionColor(colors)),
              ),
            ),
          if (records != null)
            for (final (role, id) in officials)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: switch (records[id]) {
                  final r? when r.arbiter.isNotEmpty => Text(
                    '$role: ${r.name}, ${r.arbiter} on the list.',
                    style: muted,
                  ),
                  final r => Text(
                    r == null
                        ? '$role: FIDE ID $id is not on the list. FIDE needs a licensed arbiter; check the ID.'
                        : '$role: ${r.name} has no arbiter title (IA, FA or NA) on the list. FIDE needs a licensed arbiter.',
                    style: TextStyle(
                      fontSize: 13,
                      color: attentionColor(colors),
                    ),
                  ),
                },
              ),
          if (records != null &&
              withId.any((p) => records[p.fideId]?.inactive ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Inactive on the FIDE list (still rated, no rated game for a year): ${withId.where((p) => records[p.fideId]?.inactive ?? false).map((p) => p.name).join(', ')}.',
                style: muted,
              ),
            ),
          if (noId.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No FIDE ID yet in FIDE-rated sections:',
                style: muted,
              ),
            ),
            Wrap(
              children: [
                for (final p in noId)
                  TextButton(
                    key: ValueKey('fide-noid-${p.id}'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => showPlayer(p),
                    child: Text(p.name),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.player,
    required this.record,
    required this.changes,
    required this.locked,
    required this.ticked,
    required this.onChanged,
    super.key,
  });
  final Player player;
  final FideListPlayer record;
  final List<String> changes;
  final bool locked, ticked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    return InkWell(
      onTap: () => onChanged(!ticked),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlainCheckbox(
              label: 'Update ${player.name}',
              value: ticked,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (record.name.isNotEmpty &&
                      fideName(player).toLowerCase() !=
                          record.name.toLowerCase())
                    Text('FIDE lists ${record.name}', style: muted),
                  Text(changes.join(' · '), style: muted),
                  if (locked)
                    Text(
                      'Paired: ratings and title stay for this event.',
                      style: muted,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// In a player's FIDE group: find them on the installed FIDE list by name
/// (no FIDE ID yet) or refresh them by ID, and apply a match in one step.
class FideListFinder extends StatefulWidget {
  const FideListFinder({
    required this.controller,
    required this.playerId,
    this.list,
    this.name,
    this.fideId,
    super.key,
  });
  final TournamentController controller;
  final String playerId;
  final FideRatingList? list;

  /// The name and FIDE ID as typed in the panel; the saved player's when
  /// absent.
  final String Function()? name, fideId;

  @override
  State<FideListFinder> createState() => _FideListFinderState();
}

class _FideListFinderState extends State<FideListFinder> {
  late final FideRatingList list = widget.list ?? FideRatingList();
  FideListInfo? info;
  bool searching = false, searched = false;
  List<FideListPlayer> matches = const [];
  String? error;

  TournamentController get c => widget.controller;
  Player get player => c.event!.player(widget.playerId);

  @override
  void initState() {
    super.initState();
    list.info().then((value) {
      if (mounted) setState(() => info = value);
    });
  }

  @override
  void didUpdateWidget(FideListFinder old) {
    super.didUpdateWidget(old);
    if (old.playerId != widget.playerId) {
      setState(() {
        matches = const [];
        searched = false;
        error = null;
      });
    }
  }

  String get typedId => (widget.fideId?.call() ?? player.fideId).trim();
  String get typedName => (widget.name?.call() ?? player.name).trim();

  Future<void> find() async {
    final id = typedId, name = typedName;
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final result = isFideId(id)
          ? [
              ...(await list.lookup({id})).values,
            ]
          : await list.search(name);
      if (mounted) {
        setState(() {
          matches = result;
          searched = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = plainMessage(e));
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void use(FideListPlayer r) {
    final e = c.event!;
    try {
      c.savePlayer(
        applyFideRecord(
          player,
          r,
          month: info?.month ?? '',
          locked: fideRatingsLocked(e, player),
        ),
      );
      setState(() {
        matches = const [];
        searched = false;
      });
    } catch (err) {
      setState(() => error = plainMessage(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final installed = info;
    final byId = isFideId(typedId);
    if (installed == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('No FIDE rating list on this computer.', style: muted),
            TextButton(
              key: const ValueKey('panel-fide-list'),
              onPressed: () => showFideList(context, c),
              child: const Text('FIDE ratings…'),
            ),
          ],
        ),
      );
    }
    String describe(FideListPlayer r) => [
      if (r.title.isNotEmpty) r.title,
      r.federation,
      if (r.standard > 0) 'Standard ${r.standard}',
      if (r.rapid > 0) 'Rapid ${r.rapid}',
      if (r.blitz > 0) 'Blitz ${r.blitz}',
      if (r.birthYear.isNotEmpty) 'born ${r.birthYear}',
      if (r.inactive) 'inactive',
      r.id,
    ].where((x) => x.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('panel-fide-find'),
            onPressed: searching ? null : find,
            icon: const Icon(Icons.search, size: 18),
            label: Text(
              searching
                  ? 'Searching the ${installed.label} list…'
                  : byId
                  ? 'Update from the ${installed.label} list'
                  : 'Find on the FIDE list',
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!, style: TextStyle(color: colors.error)),
            ),
          if (searched && matches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                byId
                    ? 'FIDE ID $typedId is not on the ${installed.label} list.'
                    : 'No one named $typedName is on the ${installed.label} list. Check the spelling, or enter the FIDE ID.',
                style: muted,
              ),
            ),
          for (final r in matches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(describe(r), style: muted),
                      ],
                    ),
                  ),
                  TextButton(
                    key: ValueKey('fide-match-${r.id}'),
                    onPressed: () => use(r),
                    child: Text(
                      'Use',
                      semanticsLabel: 'Use ${r.name}, FIDE ID ${r.id}',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
