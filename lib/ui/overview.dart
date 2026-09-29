import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import 'theme.dart';

class EventOverview extends StatelessWidget {
  const EventOverview({
    required this.controller,
    required this.onPlayers,
    required this.onCheckIn,
    required this.onQuads,
    required this.onPost,
    required this.onResults,
    required this.onReports,
    required this.onSection,
    required this.onSettings,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onPlayers,
      onCheckIn,
      onQuads,
      onPost,
      onResults,
      onReports,
      onSettings;
  final void Function(String) onSection;
  @override
  Widget build(BuildContext context) {
    final e = controller.event!, c = Theme.of(context).colorScheme;
    final checked = e.players.where((p) => p.checkedIn && !p.withdrawn).length;
    final missing = e.games.where((g) => !g.outcome.resolved).length;
    final active = e.sections.where((s) => s.players.isNotEmpty).toList();
    final backup = controller.repository.readPreference('lastBackup');
    Widget stat(String value, String label, IconData icon) => SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: c.primary),
                  const Spacer(),
                  Text(
                    label,
                    style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR TOURNAMENT, UNDER CONTROL',
                    style: TextStyle(
                      color: c.primary,
                      fontSize: 12,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e.name,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${e.date}  ·  ${e.timeControl}${e.venue.isEmpty ? '' : '  ·  ${e.venue}'}',
                    style: TextStyle(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.pets_outlined, size: 42, color: c.primary),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            stat(
              '$checked / ${e.players.length}',
              'CHECKED IN',
              Icons.how_to_reg,
            ),
            stat('${active.length}', 'SECTIONS', Icons.dashboard_outlined),
            stat('$missing', 'RESULTS TO COLLECT', Icons.edit_note),
            stat(
              '${active.where((s) => s.finished).length} / ${active.length}',
              'SECTIONS FINISHED',
              Icons.flag_outlined,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onPost,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Post ready sections'),
            ),
            OutlinedButton.icon(
              onPressed: onCheckIn,
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Check in'),
            ),
            OutlinedButton.icon(
              onPressed: onQuads,
              icon: const Icon(Icons.grid_view),
              label: const Text('Make quads'),
            ),
            TextButton.icon(
              onPressed: onReports,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print packet & reports'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, constraints) {
            final checklist = Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next at the desk',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    _task(
                      context,
                      'Players at the door',
                      '${e.players.length - checked} not checked in',
                      Icons.people_outline,
                      onCheckIn,
                    ),
                    _task(
                      context,
                      'Identity review',
                      '${e.players.where((p) => p.memberId.isEmpty).length} IDs missing · entered IDs are unverified',
                      Icons.badge_outlined,
                      onPlayers,
                    ),
                    _task(
                      context,
                      'Sections',
                      active.isEmpty
                          ? 'Create quads or a section'
                          : '${active.length} sections · tap a section to work',
                      Icons.dashboard_outlined,
                      onQuads,
                    ),
                    _task(
                      context,
                      'Results',
                      missing == 0
                          ? 'No outstanding games'
                          : '$missing games need a result',
                      Icons.edit_note,
                      onResults,
                    ),
                    _task(
                      context,
                      'Rating report',
                      'Review metadata and export requirements',
                      Icons.fact_check_outlined,
                      onReports,
                    ),
                    _task(
                      context,
                      'Secondary backup',
                      backup == null
                          ? 'Choose a backup folder in event settings'
                          : 'Last verified copy: revision ${backup.split('|').first} · local revision ${e.revision}',
                      Icons.save_outlined,
                      onSettings,
                    ),
                  ],
                ),
              ),
            );
            final sections = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Around the room',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Your sections will appear here. Start with the roster, then make quads or create a Swiss section.',
                    ),
                  ),
                for (final s in active)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(s.name),
                      subtitle: Text(
                        '${s.players.length} players · ${s.format.name} · Round ${s.rounds.length} of ${s.plannedRounds}',
                      ),
                      trailing: StatusPill(
                        s.finished
                            ? 'Finished'
                            : s.rounds.isEmpty
                            ? 'Ready'
                            : s.rounds.last.complete
                            ? 'Round complete'
                            : 'In progress',
                        good: s.finished,
                      ),
                      onTap: () => onSection(s.id),
                    ),
                  ),
              ],
            );
            return constraints.maxWidth > 950
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: checklist),
                      const SizedBox(width: 20),
                      Expanded(child: sections),
                    ],
                  )
                : Column(
                    children: [checklist, const SizedBox(height: 20), sections],
                  );
          },
        ),
        const SizedBox(height: 24),
        ExpansionTile(
          title: const Text('Announced conditions & private handover'),
          children: [
            ListTile(title: Text(e.policy)),
            if (e.notes.isNotEmpty)
              ListTile(
                title: Text(e.notes),
                leading: const Icon(Icons.lock_outline),
              ),
            TextButton(
              onPressed: onSettings,
              child: const Text('Edit conditions and handover'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _task(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback action,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: action,
  );
}
