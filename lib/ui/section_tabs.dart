import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/model.dart';
import '../domain/pairing.dart';
import 'player_actions.dart' show ContextMenuKeys, contextMenu;

/// What a section tab's menu asks the workspace to do.
enum SectionMenuAction {
  print,
  wallChart,
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
///
/// A tab's actions open from the menu button on the chosen tab, from
/// Shift+F10 or the Menu key on a focused tab, and from a right-click.
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

  /// A section tab's second line: players, then the latest round's state,
  /// marked FIDE when FIDE rates the section.
  static String progress(Section s) =>
      s.fideRated ? 'FIDE · ${_progress(s)}' : _progress(s);

  static String _progress(Section s) => s.sideGames
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
    final tab = Builder(
      builder: (context) => Container(
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
            // One node: the tab's name and whether it is the current tab,
            // not an unnamed "selected" wrapper around a separate button.
            MergeSemantics(
              child: Semantics(
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
                      // A very long name is cut short, so the tab and its
                      // menu button always fit in the strip together.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.textScalerOf(context).scale(200),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
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
            ),
            if (active)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _menuButton(colors, label, id, section),
              ),
          ],
        ),
      ),
    );
    return Builder(
      builder: (context) => ContextMenuKeys(
        onMenu: (position) => _openMenu(context, position, id, section),
        child: GestureDetector(
          // Its menu is on the tab's own button and keys; as a semantics
          // tap the right-click did nothing and hid the tab's name.
          excludeFromSemantics: true,
          onSecondaryTapDown: (details) =>
              _openMenu(context, details.globalPosition, id, section),
          child: tab,
        ),
      ),
    );
  }

  /// The chosen tab's menu button: the same menu as a right-click, for the
  /// mouse, Tab and Enter, and a screen reader.
  Widget _menuButton(
    ColorScheme colors,
    String label,
    String? id,
    Section? section,
  ) => Builder(
    builder: (context) {
      void open() {
        final box = context.findRenderObject()! as RenderBox;
        _openMenu(
          context,
          box.localToGlobal(Offset(0, box.size.height)),
          id,
          section,
        );
      }

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): open,
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): open,
        },
        child: Tooltip(
          message: 'Section actions',
          // The button names its section; the tooltip would say less.
          excludeFromSemantics: true,
          child: IconButton(
            key: ValueKey('section-menu-${id ?? 'all'}'),
            onPressed: open,
            icon: Icon(
              Icons.more_vert,
              size: 18,
              semanticLabel: '$label actions',
            ),
            color: colors.onSurfaceVariant,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    },
  );

  /// Opens the tab's menu at [position] and passes the choice on.
  Future<void> _openMenu(
    BuildContext context,
    Offset position,
    String? id,
    Section? section,
  ) async {
    final action = await contextMenu<SectionMenuAction>(context, position, [
      const PopupMenuItem(
        value: SectionMenuAction.print,
        child: Text('Print player list'),
      ),
      const PopupMenuItem(
        value: SectionMenuAction.preview,
        child: Text('Preview player list…'),
      ),
      const PopupMenuItem(
        value: SectionMenuAction.wallChart,
        child: Text('Print wall chart'),
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
    ]);
    if (!context.mounted || action == null) return;
    onMenu(context, action, id);
  }
}
