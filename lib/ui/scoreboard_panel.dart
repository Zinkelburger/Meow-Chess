import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import '../domain/model.dart';
import '../infrastructure/scoreboard.dart';
import 'controller_listener.dart';
import 'side_panel.dart';

/// The scoreboard's controls: start and stop it, where to open it, and
/// what it shows. Every choice applies at once; the board itself keeps
/// running when this panel closes.
class ScoreboardPanel extends StatefulWidget {
  const ScoreboardPanel({
    required this.scoreboard,
    required this.event,
    required this.onClose,
    this.onSettings,
    this.open = openInBrowser,
    super.key,
  });
  final Scoreboard scoreboard;

  /// The open event, read at each build for its sections.
  final Event Function() event;
  final VoidCallback onClose;

  /// Told after the director changes what the board shows, to save it.
  final VoidCallback? onSettings;

  /// Opens an address in the computer's browser; false when it could not.
  final Future<bool> Function(Uri) open;

  @override
  State<ScoreboardPanel> createState() => _ScoreboardPanelState();
}

class _ScoreboardPanelState extends State<ScoreboardPanel>
    with ListensToController<ScoreboardPanel> {
  @override
  Listenable controllerOf(ScoreboardPanel widget) => widget.scoreboard;
  Scoreboard get board => widget.scoreboard;
  late bool network = board.network;
  late final seconds = TextEditingController(text: '${board.settings.seconds}');
  bool busy = false;
  String? copied, notice;

  @override
  void dispose() {
    seconds.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      notice = null;
    });
    await action();
    if (mounted) setState(() => busy = false);
  }

  void change(ScoreboardSettings Function(ScoreboardSettings) edit) {
    board.settings = edit(board.settings);
    widget.onSettings?.call();
  }

  Future<void> copy(Uri address) async {
    await Clipboard.setData(ClipboardData(text: '$address'));
    if (mounted) setState(() => copied = '$address');
  }

  Future<void> openHere() async {
    final address = board.localAddress;
    if (address == null) return;
    final opened = await widget.open(address);
    if (!mounted) return;
    setState(
      () => notice = opened
          ? null
          : 'No browser opened. Copy the address into a browser instead.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final settings = board.settings;
    final running = board.running;
    final local = board.localAddress;
    final shared = board.networkAddresses;
    return SidePanel(
      key: const ValueKey('scoreboard-panel'),
      title: 'Scoreboard',
      onClose: widget.onClose,
      children: [
        Text(
          'A page that cycles through the pairings and standings, for a '
          'projector, a TV or phones. It follows the event as rounds are '
          'posted and results come in.',
          style: muted,
        ),
        const SizedBox(height: 12),
        Text(
          !running
              ? 'Off'
              : board.network
              ? 'On, for this computer and its network'
              : 'On, for this computer only',
          key: const ValueKey('scoreboard-status'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!running)
              FilledButton(
                key: const ValueKey('scoreboard-start'),
                onPressed: busy
                    ? null
                    : () => run(() => board.start(network: network)),
                child: const Text('Start scoreboard'),
              )
            else ...[
              FilledButton(
                key: const ValueKey('scoreboard-open'),
                onPressed: openHere,
                child: const Text('Open in browser'),
              ),
              OutlinedButton(
                key: const ValueKey('scoreboard-stop'),
                onPressed: busy ? null : () => run(board.stop),
                child: const Text('Stop'),
              ),
            ],
          ],
        ),
        if (board.problem ?? notice case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message, style: TextStyle(color: colors.error)),
          ),
        CheckboxListTile(
          key: const ValueKey('scoreboard-network'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Let TVs and phones on this network open it'),
          subtitle: const Text(
            'Anyone on the same Wi-Fi can read the board. They cannot '
            'change anything.',
          ),
          value: network,
          onChanged: busy
              ? null
              : (value) {
                  setState(() => network = value == true);
                  // A running board moves to its new audience at once.
                  if (running) run(() => board.start(network: network));
                },
        ),
        if (local != null) ...[
          const SizedBox(height: 4),
          _address(context, 'On this computer', local),
          Text(
            'Drag the browser window to the projector and press F11 for '
            'full screen.',
            style: muted,
          ),
        ],
        if (running && board.network && shared.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This computer is not on a network. Join the venue Wi-Fi, or '
              'turn on a phone hotspot, then stop and start the scoreboard.',
              style: muted,
            ),
          ),
        for (final address in shared) ...[
          const SizedBox(height: 12),
          _address(context, 'On TVs and phones', address),
          Center(
            child: Container(
              key: ValueKey('scoreboard-qr-$address'),
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Semantics(
                label: 'QR code for $address',
                child: CustomPaint(
                  size: const Size.square(168),
                  painter: _QrPainter('$address'),
                ),
              ),
            ),
          ),
        ],
        if (shared.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'If a phone cannot open it, the venue Wi-Fi may keep devices '
              'apart. A phone hotspot shared by the laptop and the TV works '
              'without it.',
              style: muted,
            ),
          ),
        const Divider(height: 32),
        Text('What it shows', style: Theme.of(context).textTheme.titleSmall),
        CheckboxListTile(
          key: const ValueKey('scoreboard-pairings'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Pairings and results'),
          value: settings.pairings,
          onChanged: (v) => change((s) => s.copy(pairings: v == true)),
        ),
        CheckboxListTile(
          key: const ValueKey('scoreboard-standings'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Standings'),
          value: settings.standings,
          onChanged: (v) => change((s) => s.copy(standings: v == true)),
        ),
        if (!settings.pairings && !settings.standings)
          Text(
            'Nothing is ticked, so the board is blank.',
            style: TextStyle(color: colors.error),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 200,
            child: TextField(
              key: const ValueKey('scoreboard-seconds'),
              controller: seconds,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Seconds on each screen',
                helperText:
                    '${ScoreboardSettings.minSeconds} to '
                    '${ScoreboardSettings.maxSeconds}',
              ),
              onChanged: (text) {
                final value = int.tryParse(text);
                if (value == null ||
                    value < ScoreboardSettings.minSeconds ||
                    value > ScoreboardSettings.maxSeconds) {
                  return;
                }
                change((s) => s.copy(seconds: value));
              },
            ),
          ),
        ),
        if (widget.event().sections.where((s) => !s.sideGames).length > 1) ...[
          const SizedBox(height: 12),
          Text('Sections', style: Theme.of(context).textTheme.titleSmall),
          for (final s in widget.event().sections.where((s) => !s.sideGames))
            CheckboxListTile(
              key: ValueKey('scoreboard-section-${s.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(s.name),
              value: !settings.hidden.contains(s.id),
              onChanged: (v) => change(
                (now) => now.copy(
                  hidden: v == true
                      ? ({...now.hidden}..remove(s.id))
                      : {...now.hidden, s.id},
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          'The board shows what is posted on the wall: names, boards, '
          'results, ratings and scores. IDs, notes and contact details '
          'never leave this computer.',
          style: muted,
        ),
      ],
    );
  }

  Widget _address(BuildContext context, String label, Uri address) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
              SelectableText(
                '$address',
                style: const TextStyle(fontFamily: 'SourceCodePro'),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: copied == '$address' ? 'Copied' : 'Copy address',
          icon: Icon(copied == '$address' ? Icons.check : Icons.copy, size: 18),
          onPressed: () => copy(address),
        ),
      ],
    );
  }
}

/// A QR code for [text], dark modules on the white box around it.
class _QrPainter extends CustomPainter {
  _QrPainter(this.text)
    : image = QrImage(
        QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
  final String text;
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (!image.isDark(row, col)) continue;
        // Overlap by a hair so no seam shows between modules.
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell + 0.25, cell + 0.25),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.text != text;
}
