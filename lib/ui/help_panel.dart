import 'dart:convert';
import '../infrastructure/artifact_save.dart';
import 'package:flutter/material.dart';
import '../infrastructure/diagnostic_log.dart';
import '../application/diagnostics.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import 'side_panel.dart';

class HelpArticle {
  const HelpArticle(this.id, this.title, this.summary, this.sections);
  final String id, title, summary;
  final List<(String, String)> sections;

  /// Every word of [query] appears somewhere in the article, in any order.
  bool matches(String query) {
    final text =
        '$title $summary ${sections.map((s) => '${s.$1} ${s.$2}').join(' ')}'
            .toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(text.contains);
  }
}

/// Offline, searchable articles. Add an entry here to extend Help.
const helpArticles = [
  HelpArticle(
    'quads',
    'How quads are paired',
    'Four players, three rounds, one game against each opponent.',
    [
      (
        'Making the groups',
        'Make quads sorts active players by their pairing rating, highest first, and groups nearby ratings together. Equal ratings are ordered by name, then entry ID. If the total is not divisible by four, the last five, six or seven players form a Bottom Swiss. Review ratings and section assignments before posting.',
      ),
      (
        'The three-round schedule',
        'Within each quad, players are numbered 1–4 in section order. White is listed first:\n\nRound 1: 1–4 and 2–3\nRound 2: 3–1 and 4–2\nRound 3: 1 versus 2 and 3 versus 4; colors by lot.\n\nEvery player has one White and one Black after rounds 1 and 2. Scores do not change the remaining opponents.',
      ),
      (
        'Why did I get an extra Black?',
        'Three games cannot split evenly between two colors. In the last round, each pairing gets its colors by lot. Everyone finishes with either two Whites and one Black, or one White and two Blacks. A repeated color in round 3 is normal; it is not a penalty for a result or rating.',
      ),
      (
        'When is the color lot decided?',
        'Meow-Chess derives the two final-round color choices from the randomly generated section ID. The choice is stable: previewing again, reopening the event or posting a round does not redraw it. Each posted quad round records the color lot in its notes.',
      ),
      (
        'Edit opponents and colors',
        'Choose Edit quad pairings beside New section, then select the quad. Each round shows White and Black on both boards. Choose a player to exchange places in that round, or choose Flip colors. When changing opponents, adjust the other unplayed round too so everyone meets once. Save pairings updates posted games, future pairings and printed sheets together. Reprint sheets already handed out. Rounds with results, a start marker or pairing assumptions are locked; other rounds remain editable. Undo restores the previous schedule.',
      ),
      (
        'Changing a quad',
        'Before posting, open a player, choose Move… and the destination section, and optionally choose a player to swap with. Confirm the move or swap. A swap keeps both quads at four players. A quad that has a different number of players at its first pairing runs as a small Swiss. Once rounds are posted, a roster swap cannot rewrite them.',
      ),
      (
        'Related reading',
        'SwissSys documents rating-order, random and manual lot numbers for round robins. This article describes Meow-Chess’s quad schedule.\n\nSwissSys: Lot Numbers — Round Robin Tournaments\nhttps://docs.chessroster.com/swisssys/app-docs/user-guide/tournaments/lot-numbers-round-robin-tournaments/',
      ),
    ],
  ),
  HelpArticle(
    'swiss',
    'How Swiss pairings work',
    'Players meet opponents with similar scores, without playing everyone.',
    [
      (
        'A new round each time',
        'Meow-Chess orders available players by score and then pairing rating, and searches for pairings within or near those score groups. It avoids repeat opponents and respects explicit do-not-pair requests. It tries to balance colors first, then alternate them.',
      ),
      (
        'Odd numbers and missing results',
        'An odd field needs an allocated bye. The app tries to avoid giving a player a second allocated bye. Resolve missing results, or record a director-approved temporary pairing treatment, before posting the next round.',
      ),
      (
        'Requested byes and withdrawals',
        'Right-click a player and choose Byes…, or open the player. Under Byes, choose the round in the ½ pt, 0 pt or 1 pt row; choose it again to clear. A player leaving after a later round can take zero-point byes for the rounds they will miss. Withdraw, at the top of the player’s card, takes effect from the next unpaired round; Reinstate brings them back.',
      ),
    ],
  ),
  HelpArticle(
    'fide',
    'FIDE-rated sections',
    'Rate a section by FIDE, alone or with US Chess, and make its FIDE report.',
    [
      (
        'Choose how a section is rated',
        'Open the section\'s settings and set Rated by: US Chess, US Chess and FIDE, FIDE only, or Not rated. FIDE rates Swiss, round-robin and quad sections, and registers each section as its own tournament. The time control decides FIDE\'s list: standard from 60 minutes per player for 60 moves, rapid above 10 and under 60, blitz above 3 up to 10. A delay counts as an increment.',
      ),
      (
        'How a FIDE Swiss is paired',
        'A FIDE-rated Swiss is paired by the FIDE Dutch system (C.04.3, the rules in force since 1 February 2026) using BBP Pairings, the engine SwissSys uses for its FIDE pairings. Pairing numbers come from FIDE ratings, then title, then name; in a dual-rated section a player FIDE has not rated is ranked by their US Chess rating (Pairing rules → Pairing numbers by). Requested byes and do-not-pair requests carry over. The choice is made before round 1, because it changes the pairing system.',
      ),
      (
        'Acceleration and the bye\'s value',
        'Pairing rules offers the Baku acceleration (C.04.7), FIDE\'s only one: the top half of the field, rounded up to an even number, pairs with a virtual point in the first rounds and half a point in the next, so leaders meet sooner. The same group holds after late entries. Pairing-allocated bye scores sets what the odd player out receives: a win (the default), a draw or nothing. Both are announced before round 1 and fixed once the section is paired.',
      ),
      (
        'Unusual results, adjourned games and byes',
        'Correct a result offers ½–0, 0–½ and a played 0–0 in sections US Chess does not rate, and marks a game that lasted less than one move: its result stands, FIDE does not rate it. An adjourned game (Still playing) counts as a draw for the next pairing only; enter its result before pairing the round after. A full-point bye is allowed but FIDE deprecates it, and the player panel says so. Do-not-pair requests from round 3 on are noted in the pairing explanation.',
      ),
      (
        'FIDE identity',
        'Each player in a FIDE-rated section needs a FIDE ID; the player panel\'s FIDE group holds it with the standard, rapid and blitz ratings, title, federation, birth date and sex. Checking a player with US Chess offers the FIDE ID US Chess has on file. Player tools → FIDE ratings downloads FIDE\'s monthly rating list (or uses a list ZIP you already have) and fills ratings, titles, federations and birth years by FIDE ID, reviewed before they apply. Find on the FIDE list in a player\'s FIDE group searches it by name.',
      ),
      (
        'Tie-breaks',
        'FIDE-rated sections rank ties by FIDE tie-breaks (C.07, 2026). C.07 sets no default, so Meow-Chess starts from Buchholz Cut-1, Buchholz, Sonneborn–Berger, direct encounter and wins for a Swiss, and direct encounter, wins, Sonneborn–Berger and Koya for a round robin. Change the order in Event details → Standings → Tie-breaks before round 1. Byes, forfeits and withdrawals count as Article 16 says.',
      ),
      (
        'The FIDE report',
        'Export shows the FIDE rating report below the US Chess one, with what still needs fixing. Generate TRF files writes one TRF-2026 file per FIDE-rated section, the format FIDE\'s rating server reads. Event details → FIDE holds the chief arbiter, deputies and federation. In the United States, US Chess takes FIDE-rated events only as the file of a FIDE-endorsed pairing program, not as TRF. Meow-Chess is not endorsed. SwissSys, for one, can open a TRF file.',
      ),
      (
        'Import a TRF file',
        'Import FIDE report, on the start screen, makes a new event from a TRF file (TRF26, TRF16 or TRF06, as other pairing programs write them): players with their FIDE data, every round with its games, forfeits and byes, the tie-break order, the bye\'s value and the Baku acceleration. Absences announced for later rounds become requested byes, so a tournament begun elsewhere can be paired on here. Anything the file holds that Meow-Chess cannot keep is listed in the event\'s notes.',
      ),
      (
        'Check a tournament, or simulate one',
        'The FIDE tools run from a terminal. meow_chess -check FILE.trf rebuilds the tournament in a TRF, pairs every round again with the FIDE Dutch engine, ranks the standings by the file\'s tie-breaks and lists every difference (--inputs DIR also saves what the engine read for each round). meow_chess -generate --output FILE simulates FIDE Swiss tournaments with results drawn from the FIDE rating table, with options for byes, forfeits, withdrawals, late entries, the Baku acceleration and the bye\'s value. meow_chess -pair FILE pairs the next round of a TRF. meow_chess -help lists every option.',
      ),
    ],
  ),
  HelpArticle(
    'round-robin',
    'How round robins work',
    'A fixed schedule lets every player meet every other player.',
    [
      (
        'Opponents and rounds',
        'Meow-Chess uses a circle schedule for ordinary round robins. With an even number of players there are n−1 rounds; with an odd number there are n rounds and each player sits out once. Quads have their own three-round schedule.',
      ),
      (
        'Why scores do not change opponents',
        'The roster determines the schedule. Winning or losing does not change whom you play next. Moving players or granting an absence after posting can invalidate that schedule, so the app blocks unsafe changes.',
      ),
    ],
  ),
  HelpArticle(
    'website',
    'Import and update a website roster',
    'Keep a local event from a registration link, with changes reviewed first.',
    [
      (
        'First import',
        'On an empty event, choose Players → Add from URL; later, choose Player tools → Refresh from URL. Paste an HTTPS URL and choose Fetch players (or Fetch updates). Boylston accepts either an event page or its entry-list URL. For other clubs, paste the page containing one HTML player table with Name and Rating columns (USCF ID is optional); the generic importer reads that page without finding links to other pages. Review the rows, then confirm changes and save the source. Fetch ratings from USCF is checked by default; uncheck it to skip the optional rating review.',
      ),
      (
        'Updating later',
        'Open Refresh from the saved URL again. The saved URL is already filled in. New players are selected; changes to existing players need your explicit selection. Missing players stay in the event. Duplicate IDs and ambiguous names need manual resolution. Empty pages and failed requests do not replace the roster.',
      ),
      (
        'What the website can tell us',
        'After import, review proposed USCF ratings in the panel at the right and the player table. Changes over 50 points and unrated-to-rated changes are highlighted, and a USCF name that looks like a different person is flagged and left unticked. Confirm ticked ratings or choose Keep current ratings. Click a player to edit them; the review stays open. Missing IDs or published ratings leave current values intact. Website section and bye columns are retained in the source record; assign sections and requested byes explicitly in Meow-Chess.',
      ),
    ],
  ),
  HelpArticle(
    'ratings',
    'Refresh and verify US Chess ratings',
    'Review USCF rating changes before applying them.',
    [
      (
        'Find or correct a US Chess ID',
        'Beside a player’s US Chess ID, choose Find by name to search official member records. Check ID warns if the record is missing or the official name differs, and searches for possible corrections. Compare the name, state and rating, select Use, then Save or Add. Ratings stay unchanged. In Event details, type a chief or assistant TD’s name and choose Find by name to select their ID. Service failures mean unverified, not an invalid ID.',
      ),
      (
        'Refresh one or everyone',
        'Use Players → Refresh from USCF for the whole event, or the refresh arrow beside a player’s US Chess ID for one person. Check the returned official name, ID, category and supplement date. Confirm the rating changes you want in the player table, or keep current ratings. A failed lookup leaves local values intact.',
      ),
      (
        'Check USCF membership expiration',
        'Open a player card to see the saved USCF membership expiration date. Choose Players → Refresh from USCF to check everyone directly with US Chess, including unrated players and players in posted sections. Expiration dates save automatically, even if you keep current ratings. Expired dates appear in red with an Expired label. Memberships expiring later this calendar month appear in yellow with Expires this month. Dates before the event ends also receive a warning. Open the player card for provider status and the check time. No date means unknown, not lifetime membership. Failed checks keep the previous observation; changing an ID clears it.',
      ),
      (
        'Monthly versus latest',
        'Refresh uses the newest dated monthly supplement. Event details → Data sources holds the global default category and optional API key.',
      ),
      (
        'Between-round rating estimates',
        'In Players, open Player tools and enable Show rating estimates. Est. regular shows an approximate regular rating and change from completed played games. These optional estimates do not change pairing ratings or exports.',
      ),
      (
        'After pairing',
        'Refresh can display observations, but posted sections retain their pairing ratings. Refreshing never moves players between quads. Before play, remake quads explicitly if you want to regroup by updated ratings.',
      ),
    ],
  ),
  HelpArticle(
    'players',
    'Register, move and remove players',
    'Add a walk-up, change sections, or take out an entry that never played.',
    [
      (
        'Register a player',
        'On Players, choose Add player. Enter the name, rating (or UNR) and optional eight-digit US Chess ID. Choose the section and Add. This registers the player locally; it does not register them on an external website or collect a payment.',
      ),
      (
        'Move a player',
        'Open a player’s card, choose Move… and pick the destination section, then confirm. To move several players, tick them and choose a section under Move to section, or right-click one of the ticked players. Shift-click ticks every row between two players; the box on a section’s header row ticks the whole section. Before play, a move of ticked players happens at once and the panel offers Undo. A Swiss only needs a move. When a quad or round robin is involved and neither section is paired, you can instead exchange places with a player there so both stay full, or tick the two players and choose Swap sections.',
      ),
      (
        'Remove a player',
        'Until a player’s section is paired, Remove from event takes them out entirely, as if they never registered. It is on the player’s card and in the right-click menu, works on ticked players, and Delete on a focused row does the same. Undo brings them back. Once their section is paired the same button reads Withdraw, so their games stay in the record; unpairing the section makes Remove available again.',
      ),
      (
        'After rounds are posted',
        'Moves are restricted to preserve games, scores and schedules. Finish current games first; sections must have compatible round progress. A partial move out of a played quad or round robin is blocked. Accepted transitions require a reason and retain original game attribution.',
      ),
    ],
  ),
];

class HelpPanel extends StatefulWidget {
  const HelpPanel({
    required this.controller,
    required this.onClose,
    this.articleId,
    super.key,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final String? articleId;
  @override
  State<HelpPanel> createState() => _HelpPanelState();
}

class _HelpPanelState extends State<HelpPanel> {
  final search = TextEditingController();
  String? active, logNotice;
  @override
  void initState() {
    super.initState();
    active =
        widget.articleId ??
        widget.controller.workspaceState.read('help-article');
    search.text = widget.controller.workspaceState.read('help-search') ?? '';
  }

  @override
  void didUpdateWidget(HelpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.articleId != oldWidget.articleId) active = widget.articleId;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> exportLog() async {
    try {
      final log = DiagnosticLog.current;
      if (log == null) {
        setState(
          () => logNotice =
              'No file log is configured in this session. Diagnostics are available in the developer console.',
        );
        return;
      }
      final path = await saveArtifact(
        'meow-chess-diagnostics.log',
        utf8.encode(log.read()),
      );
      if (path == null) return;
      if (mounted) {
        setState(() => logNotice = 'Diagnostic log saved to $path');
      }
    } catch (e, stack) {
      Diagnostics.record(
        'export diagnostic log',
        'failed',
        error: e,
        stack: stack,
      );
      if (mounted) setState(() => logNotice = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = helpArticles.where((a) => a.id == active).firstOrNull;
    final matches = helpArticles
        .where((a) => a.matches(search.text.trim()))
        .toList();
    return SidePanel(
      title: 'Help',
      onClose: widget.onClose,
      children: [
        OutlinedButton.icon(
          onPressed: exportLog,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Export diagnostic log'),
        ),
        if (DiagnosticLog.current case final log?)
          SelectableText(
            'Log file: ${log.file.path}',
            style: const TextStyle(fontSize: 12),
          ),
        if (logNotice != null) Text(logNotice!),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('help-search'),
          controller: search,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Search help',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            widget.controller.workspaceState.write('help-search', value);
            widget.controller.workspaceState.write('help-article', '');
            setState(() => active = null);
          },
        ),
        const SizedBox(height: 16),
        if (article == null) ...[
          if (matches.isEmpty)
            const Text('No article yet. Try “quads”, “ratings” or “players”.'),
          for (final item in matches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(item.summary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                widget.controller.workspaceState.write('help-article', item.id);
                setState(() => active = item.id);
              },
            ),
        ] else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                widget.controller.workspaceState.write('help-article', '');
                setState(() => active = null);
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('All articles'),
            ),
          ),
          const SizedBox(height: 8),
          Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(article.summary),
          for (final (heading, text) in article.sections) ...[
            const SizedBox(height: 24),
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(text, style: const TextStyle(height: 1.5)),
          ],
        ],
      ],
    );
  }
}
