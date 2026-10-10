import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../domain/model.dart';
import '../domain/pairing.dart';
import 'player_actions.dart' show contextMenu;

/// What a section tab's right-click menu asks the workspace to do.
enum SectionMenuAction {
  print,
  preview,
  settings,
  sideGame,
  combine,
  help,
  delete,
}

/// The strip of section tabs under the page row: All sections, then each
/// section with its progress, then New section (and Edit quad pairings when
/// a quad keeps a fixed schedule). The tabs scroll sideways with the wheel.
class SectionTabs extends StatelessWidget {
  const SectionTabs({
    required this.event,
    required this.sectionId,
    required this.scroll,
    required this.tabKey,
    required this.onPick,
    required this.onMenu,
    required this.onNewSection,
    required this.onEditQuadPairings,
    super.key,
  });
  final Event event;

  /// The section shown; all sections when it is null or no longer exists.
  final String? sectionId;
  final ScrollController scroll;

  /// A lasting key for the tab of a section id (`all` for All sections), so
  /// the workspace can scroll the chosen tab into view.
  final GlobalKey Function(String id) tabKey;
  final ValueChanged<String?> onPick;

  /// A choice from a tab's menu. [context] is the tab's, for printing.
  final void Function(
    BuildContext context,
    SectionMenuAction action,
    String? id,
  )
  onMenu;
  final VoidCallback onNewSection, onEditQuadPairings;

  @override
  Widget build(BuildContext context) {
    final e = event, colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('section-tabs'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          _sectionLink(
            colors,
            'All sections',
            null,
            '${e.players.length} players',
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent && scroll.hasClients) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {
                      scroll.jumpTo(
                        (scroll.offset +
                                event.scrollDelta.dy +
                                event.scrollDelta.dx)
                            .clamp(0, scroll.position.maxScrollExtent),
                      );
                    },
                  );
                }
              },
              child: Scrollbar(
                controller: scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in e.sections)
                        _sectionLink(colors, s.name, s.id, progress(s)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const ValueKey('new-section'),
            onPressed: onNewSection,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New section'),
          ),
          if (e.sections.any(hasFixedQuadSchedule)) ...[
            const SizedBox(width: 8),
            if (MediaQuery.sizeOf(context).width /
                    MediaQuery.textScalerOf(context).scale(1) <
                1100)
              IconButton(
                key: const ValueKey('edit-quad-pairings'),
                tooltip: 'Edit quad pairings',
                onPressed: onEditQuadPairings,
                icon: const Icon(Icons.edit_outlined, size: 18),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('edit-quad-pairings'),
                onPressed: onEditQuadPairings,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit quad pairings'),
              ),
          ],
        ],
      ),
    );
  }

  /// A section tab's second line: players, then the latest round's state.
  static String progress(Section s) => s.sideGames
      ? '${s.players.length} players · Side games'
      : s.rounds.isEmpty
      ? '${s.players.length} players'
      : 'Round ${s.rounds.length} · ${s.rounds.last.complete ? 'Complete' : '${s.rounds.last.games.where((g) => !g.outcome.resolved).length} missing'}';

  Widget _sectionLink(
    ColorScheme colors,
    String label,
    String? id,
    String subtitle,
  ) {
    final active =
        sectionId == id ||
        (id == null && !event.sections.any((s) => s.id == sectionId));
    final section = event.sections.where((s) => s.id == id).firstOrNull;
    final tab = Container(
      key: tabKey(id ?? 'all'),
      decoration: BoxDecoration(
        color: active ? colors.surface : null,
        border: Border(
          bottom: BorderSide(
            color: active ? colors.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            selected: active,
            child: TextButton(
              key: ValueKey('section-chip-${id ?? 'all'}'),
              onPressed: () => onPick(id),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: const RoundedRectangleBorder(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Builder(
      builder: (context) => GestureDetector(
        onSecondaryTapDown: (details) async {
          final action = await contextMenu<SectionMenuAction>(
            context,
            details.globalPosition,
            [
              const PopupMenuItem(
                value: SectionMenuAction.print,
                child: Text('Print player list'),
              ),
              const PopupMenuItem(
                value: SectionMenuAction.preview,
                child: Text('Preview player list…'),
              ),
              if (section != null) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: SectionMenuAction.settings,
                  child: Text('Rename / section settings…'),
                ),
                if (section.sideGames)
                  const PopupMenuItem(
                    value: SectionMenuAction.sideGame,
                    child: Text('Pair a side game…'),
                  ),
                const PopupMenuItem(
                  value: SectionMenuAction.combine,
                  child: Text('Combine sections…'),
                ),
                const PopupMenuItem(
                  value: SectionMenuAction.help,
                  child: Text('How these pairings work'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: SectionMenuAction.delete,
                  enabled: section.rounds.isEmpty,
                  child: Text(
                    section.rounds.isEmpty
                        ? 'Delete section'
                        : 'Delete unavailable after pairings',
                  ),
                ),
              ],
            ],
          );
          if (!context.mounted || action == null) return;
          onMenu(context, action, id);
        },
        child: tab,
      ),
    );
  }
}
