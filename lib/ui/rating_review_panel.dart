import 'package:flutter/material.dart';

import '../domain/model.dart';
import '../domain/rating_system.dart';
import 'membership_style.dart';
import 'player_format.dart';
import 'rating_refresh.dart';
import 'side_panel.dart';
import 'theme.dart';
import 'select.dart';

String _system(String category) =>
    RatingSystem.parse(category)?.label ?? category;

/// The proposed change for one row, such as `+150` or `from UNR`.
String? ratingChange(RatingRefresh draft, Player p) {
  final proposed = draft.proposed(p);
  if (proposed == null || proposed <= 0) return null;
  if (p.rating == 0) return 'from UNR';
  final delta = proposed - p.rating;
  return delta == 0 ? '±0' : '${delta > 0 ? '+' : ''}$delta';
}

/// "Rating on 2026-10-01", or the rating system when it is not Regular.
String proposedHeading(RatingRefresh draft) {
  final date = draft.supplementDate;
  final what = draft.category == 'R' ? 'Rating' : _system(draft.category);
  return date == null ? '$what at USCF' : '$what on $date';
}

/// The USCF rating review, docked at the right while the roster stays put.
/// Ticks live in the table; this panel holds the totals and the decision.
class RatingReviewPanel extends StatelessWidget {
  const RatingReviewPanel({
    required this.draft,
    required this.onClose,
    required this.onConfirm,
    required this.onOpenPlayer,
    required this.onAddId,
    super.key,
  });
  final RatingRefresh draft;
  final VoidCallback onClose, onConfirm;
  final ValueChanged<String> onOpenPlayer;

  /// Opens the player at their US Chess ID field.
  final ValueChanged<String> onAddId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final players = draft.controller.event!.players;
      final lookups = (draft.snapshot?.players ?? const <Player>[])
          .where((p) => p.memberId.trim().isNotEmpty)
          .length;
      final names = players.where(draft.nameMismatch).toList();
      final noIds = players.where(draft.missingId).toList();
      final approved = draft.approved.length;
      return KeyedSubtree(
        key: const ValueKey('rating-review'),
        child: SidePanel(
          title: 'Review USCF ratings',
          onClose: onClose,
          footer: [
            FilledButton(
              key: const ValueKey('confirm-ratings'),
              onPressed: draft.busy || approved == 0 ? null : onConfirm,
              child: Text(
                'Confirm $approved rating ${approved == 1 ? 'change' : 'changes'}',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('keep-ratings'),
              onPressed: draft.discard,
              child: const Text('Keep current ratings'),
            ),
          ],
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                draft.busy
                    ? 'Looking up USCF… ${draft.checkedCount} of $lookups checked'
                    : '${draft.foundCount} of ${players.length} players have USCF ratings.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (draft.notice case final notice?) ...[
              const SizedBox(height: 8),
              Text(notice),
            ],
            const SizedBox(height: 16),
            PlainSelect<String>(
              key: const ValueKey('rating-review-system'),
              value: draft.category,
              label: 'Rating system',
              options: [
                for (final s in RatingSystem.values)
                  SelectOption(s.code, s.label),
              ],
              onChanged: draft.busy ? null : draft.showCategory,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: draft.busy
                  ? [
                      OutlinedButton.icon(
                        onPressed: draft.stop,
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Stop lookup'),
                      ),
                    ]
                  : [
                      OutlinedButton(
                        onPressed: () => draft.selectAll(true),
                        child: const Text('Tick all'),
                      ),
                      OutlinedButton(
                        onPressed: () => draft.selectAll(false),
                        child: const Text('Untick all'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('rating-review-again'),
                        onPressed: () => draft.fetch(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Look up again'),
                      ),
                    ],
            ),
            if (noIds.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Heading('No USCF ID (${noIds.length})'),
              for (final p in noIds)
                _PlayerLink(
                  key: ValueKey('no-id-${p.id}'),
                  name: p.name,
                  onOpen: () => onAddId(p.id),
                ),
            ],
            if (names.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Heading('Names to check (${names.length})'),
              for (final p in names)
                _PlayerLink(
                  key: ValueKey('name-check-${p.id}'),
                  name: p.name,
                  detail:
                      'USCF: ${draft.observations[p.id]!.name} · ${p.memberId}',
                  onOpen: () => onOpenPlayer(p.id),
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// A list heading that needs the TD's attention: icon and words, not colour alone.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          color: attentionColor(Theme.of(context).colorScheme),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}

class _PlayerLink extends StatelessWidget {
  const _PlayerLink({
    required this.name,
    required this.onOpen,
    this.detail,
    super.key,
  });
  final String name;
  final String? detail;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (detail case final detail?)
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The review for one player, under the Rating field in their panel, so a
/// TD can edit a player mid-review without losing the draft.
class PlayerRatingReview extends StatelessWidget {
  const PlayerRatingReview({
    required this.draft,
    required this.player,
    required this.onBack,
    super.key,
  });
  final RatingRefresh draft;
  final Player player;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
      final p = draft.controller.event!.players
          .where((x) => x.id == player.id)
          .firstOrNull;
      if (p == null || !draft.active) return const SizedBox.shrink();
      final m = draft.observations[p.id];
      final problem = draft.problem(p);
      final proposed = draft.proposed(p);
      final change = ratingChange(draft, p);
      final included = problem == null && draft.selected.contains(p.id);
      return Container(
        key: const ValueKey('player-rating-review'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'USCF ${_system(draft.category).toLowerCase()} rating',
                if (m?.supplementDate case final date?) '$date supplement',
              ].join(' · '),
              style: muted.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 4),
            if (proposed != null && proposed > 0)
              Row(
                children: [
                  Text(
                    '${ratingText(p.rating)} → $proposed',
                    maxLines: 1,
                    // Only the Regular weight is bundled; a bolder request
                    // would be synthesized differently on each OS.
                    style: const TextStyle(
                      fontFamily: 'SourceCodePro',
                      fontSize: 15,
                    ),
                  ),
                  if (change != null && p.rating != 0) ...[
                    const SizedBox(width: 8),
                    Flexible(child: Text(change, style: muted)),
                  ],
                ],
              ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(problem, style: muted),
              )
            else
              // The visible label makes the whole line the target.
              InkWell(
                onTap: draft.busy ? null : () => draft.select(p, !included),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PlainCheckbox(
                        key: ValueKey('panel-approve-rating-${p.id}'),
                        label: 'Include ${p.name} in the rating update',
                        value: included,
                        onChanged: draft.busy
                            ? null
                            : (value) => draft.select(p, value == true),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Include in the rating update'),
                      ),
                    ],
                  ),
                ),
              ),
            if (m != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: draft.nameMismatch(p)
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: attentionColor(colors),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'USCF name is ${m.name}. Check the ID.',
                              style: TextStyle(
                                fontSize: 13,
                                color: attentionColor(colors),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text('USCF name: ${m.name}', style: muted),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('back-to-rating-review'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to rating review'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
