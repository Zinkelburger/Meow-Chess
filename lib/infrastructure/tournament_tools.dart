import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../application/failures.dart';
import '../application/tournament_controller_core.dart';
import '../domain/bye_policy.dart';
import '../domain/knockout.dart';
import '../domain/ladder.dart';
import '../domain/model.dart';
import '../domain/prizes.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/us_chess.dart';
import 'dbf_export.dart';
import 'publish_file.dart';
import 'reports.dart';
import 'sqlite_event_repository.dart';

Json _string([String? description]) => {
  'type': 'string',
  'description': ?description,
};
Json _integer(int minimum) => {'type': 'integer', 'minimum': minimum};
Json _object(Json properties, [List<String> required = const []]) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};
Json _array(Json items) => {'type': 'array', 'items': items};

/// Bughouse partnerships: pairs of player IDs; replaces the whole list.
final _partners = {
  ..._array(_array(_string())),
  'description':
      'Bughouse partnerships as pairs of player IDs; replaces the list. Only before round 1.',
};

/// Knockout bracket settings; `rounds` (the bracket as played) is kept.
final _bracket = {
  ..._object({
    'gamesPerMatch': _integer(1),
    'tiebreak': _enum(knockoutTiebreakLabels.keys),
    'seeds': _array(_string('Player ID')),
  }),
  'description':
      'Knockout: gamesPerMatch (1 or 2), tiebreak (none = director decides, rapid, blitz, armageddon), seeds (player IDs in seeding order; frozen at round 1). Games per match and seeds are fixed once round 1 is posted.',
};
Json _enum(Iterable<String> values) => {
  'type': 'string',
  'enum': values.toList(),
};
const _bool = {'type': 'boolean'};

final _metadata = <String, dynamic>{
  for (final key in [
    'name',
    'date',
    'endDate',
    'timeControl',
    'venue',
    'tdId',
    'assistantTdId',
    'otherTdIds',
    'affiliateId',
    'city',
    'state',
    'zip',
    'level',
    'notes',
  ])
    key: _string(),
  'practice': _bool,
  'useTiebreaks': _bool,
  // Chapter 10: reported through the online rating categories.
  'online': _bool,
  // Rule 34B: the posted order by method code; empty restores the US Chess
  // default (34E for a Swiss, 34F for a round robin or quad).
  'tiebreaks': {
    'type': 'array',
    'items': {
      'type': 'string',
      'enum': [for (final m in TiebreakMethod.values) m.code],
    },
  },
};
final _playerFields = <String, dynamic>{
  for (final key in [
    'name',
    'memberId',
    'state',
    'reportName',
    'club',
    'team',
    'notes',
    'ratingNote',
    'foreignFederation',
  ])
    key: _string(),
  'rating': {'type': 'integer', 'minimum': 0, 'maximum': 4000},
  // Rules 28E/28F: TD-assigned ratings (0 = use the published rating), the
  // stated cause (28E2), a disclosed foreign rating (28C2/28D1) and rule 36.
  'pairingRating': {'type': 'integer', 'minimum': 0, 'maximum': 4000},
  'prizeRating': {'type': 'integer', 'minimum': 0, 'maximum': 4000},
  'foreignRating': {'type': 'integer', 'minimum': 0, 'maximum': 4000},
  'computer': _bool,
  // Rule 20M3 / 35: a fixed board (0 = none). Rule 28S: the earlier entry
  // this re-entry replaces.
  'fixedBoard': _integer(0),
  'reentryOf': _string('Player ID of the earlier entry; empty for none.'),
  'checkedIn': _bool,
  'withdrawn': _bool,
};
final _swissFields = <String, dynamic>{
  'accelerated': {
    ..._enum(['', 'addedScore']),
    'description': 'Rule 28R1 accelerated pairings for rounds 1–2.',
  },
  'avoidTeammates': {
    ..._bool,
    'description': 'Rule 28N1: keep team-mates apart by the plus-two method.',
  },
  'unrated': {
    ..._bool,
    'description':
        'Leave the section out of the US Chess rating report (ladders, unrated events). Bughouse is always unrated.',
  },
  'variations': {
    ..._array(_enum(swissVariations)),
    'description':
        'Announced pairing variations by rule number (29E4a, 29E4b, 29E4d, 29E5h).',
  },
};
final _byeRules = _object({
  'lastHalfByeRound': _integer(0),
  'maxHalfByes': _integer(0),
  'deadlineMinutes': _integer(0),
  'irrevocableFromRound': _integer(0),
});
final _prizeTable = _object({
  'basedOn': _integer(0),
  'fundCents': _integer(0),
  'withdrawnEligible': _bool,
  'unratedCapCents': _integer(0),
  'list': _array(
    _object(
      {
        'id': _string(),
        'label': _string(),
        'kind': _enum(PrizeKind.values.map((k) => k.code)),
        'place': _integer(1),
        'min': _integer(0),
        'max': _integer(0),
        'points': _integer(0),
        'cents': _integer(0),
        'trophy': _bool,
        'guaranteed': _bool,
        'eligible': _array(_string('Player ID')),
      },
      ['id'],
    ),
  ),
});
final _gameFields = _object(
  {
    'white': _string('Player ID'),
    'black': _string('Player ID'),
    'board': _integer(1),
    'leg': {
      'type': 'integer',
      'enum': [1, 2],
    },
  },
  ['white', 'black', 'board'],
);
final _byeFields = _object(
  {
    'player': _string('Player ID'),
    'points': {'type': 'integer', 'minimum': 0, 'maximum': 4},
    'reason': _string(),
    'allocated': _bool,
  },
  ['player', 'points', 'reason'],
);

/// Local tools share the GUI controller, repository, reports and domain rules.
/// One connection owns one event; close it before opening that file in the GUI.
class TournamentTools {
  TournamentTools(String directory)
    : root = Directory(directory).absolute..createSync(recursive: true);
  final Directory root;
  TournamentControllerCore? _controller;
  final _proposals = <String, PairingBatch>{};
  TournamentControllerCore get controller =>
      _controller ??
      (throw const TournamentException('Open or create an event first.'));
  Event get event =>
      controller.event ??
      (throw const TournamentException('This file has no event.'));

  static List<Json> get definitions {
    Json tool(
      String name,
      String description,
      Json properties, {
      List<String> required = const [],
      bool write = false,
    }) => {
      'name': name,
      'description': description,
      'inputSchema': _object(
        {...properties, if (write) 'expectedRevision': _integer(1)},
        [...required, if (write) 'expectedRevision'],
      ),
      'annotations': {
        'readOnlyHint': [
          'get_event',
          'standings',
          'prize_report',
          'propose_pairings',
          'rating_preflight',
        ].contains(name),
        'destructiveHint': write,
        'openWorldHint': false,
      },
    };
    return [
      tool(
        'create_event',
        'Create a new .meow event inside the configured data directory. Never overwrites. Dates are YYYY-MM-DD. Practice defaults to true.',
        {'path': _string(), ..._metadata},
        required: ['path', 'name', 'date'],
      ),
      tool(
        'open_event',
        'Open an existing .meow file inside the data directory. Close it in the GUI first.',
        {'path': _string()},
        required: ['path'],
      ),
      tool('close_event', 'Release the event file so the GUI can open it.', {}),
      tool(
        'get_event',
        'Read the complete event, IDs, current revision, rounds and results.',
        {},
      ),
      tool(
        'update_event',
        'Edit event and rating-report metadata. Practice is fixed when the event is created.',
        _metadata,
        write: true,
      ),
      tool(
        'add_players',
        'Register players atomically. IDs are returned; no silent duplicate skipping.',
        {
          'players': _array(_object(_playerFields, ['name'])),
        },
        required: ['players'],
        write: true,
      ),
      tool(
        'update_player',
        'Edit a player, including check-in, withdrawal, rating and report identity.',
        {'playerId': _string(), ..._playerFields},
        required: ['playerId'],
        write: true,
      ),
      tool(
        'create_section',
        'Create a section with explicitly selected unassigned players. Scores use integer half-points.',
        {
          'name': _string(),
          'players': _array(_string()),
          'format': _enum(Format.values.map((v) => v.name)),
          'plannedRounds': _integer(1),
          'boardStart': _integer(1),
          'doubleGames': _bool,
          'ratingCeiling': _integer(0),
          'timeControl': _string('Blank inherits the event default.'),
          'sideGames': _bool,
          'rrTable': _enum(['', crenshawTable]),
          'doubleCycle': _bool,
          'homeTeam': _string('Scheveningen: the team label of side A.'),
          ..._swissFields,
          'partners': _partners,
          'bracket': _bracket,
        },
        required: ['name', 'players', 'format', 'plannedRounds', 'boardStart'],
        write: true,
      ),
      tool(
        'update_section',
        'Edit a section\'s name, time control (blank inherits the event default), planned rounds, first board or prize table. Format changes are GUI-only.',
        {
          'sectionId': _string(),
          'name': _string(),
          'timeControl': _string('Blank inherits the event default.'),
          'plannedRounds': _integer(1),
          'boardStart': _integer(1),
          'rrTable': _enum(['', crenshawTable]),
          'doubleCycle': _bool,
          'homeTeam': _string('Scheveningen: the team label of side A.'),
          ..._swissFields,
          'byeRules': _byeRules,
          'partners': _partners,
          'bracket': _bracket,
          'prizes': {
            ..._prizeTable,
            'description':
                'Rules 32–33 prize table; replaces the whole table. Amounts are cents; points are half-points; class min/max are inclusive, under max is exclusive; eligible lists player IDs for junior/senior prizes.',
          },
        },
        required: ['sectionId'],
        write: true,
      ),
      tool(
        'advance_knockout',
        'Knockout: record the director\'s decision on a drawn match when the section plays no tie-break games. The chosen player advances from the match on that board; the reason is kept in the bracket and the history.',
        {
          'sectionId': _string(),
          'board': _integer(1),
          'playerId': _string('Player ID'),
          'reason': _string(),
        },
        required: ['sectionId', 'board', 'playerId'],
        write: true,
      ),
      tool(
        'pair_side_game',
        'Choose any two registered people and post an independent side game. Creates Side Games and separate entries as needed. Resolve main games first; no score carries over.',
        {'white': _string(), 'black': _string(), 'sectionId': _string()},
        required: ['white', 'black'],
        write: true,
      ),
      tool(
        'add_section_entry',
        'Enter an existing person separately in another unstarted section. Keeps identity; starts a separate score.',
        {'playerId': _string(), 'sectionId': _string()},
        required: ['playerId', 'sectionId'],
        write: true,
      ),
      tool(
        'draw_lots',
        'Rule 30A: assign a round-robin or quad section\'s pairing numbers by lot (seeded shuffle, recorded in history). Only before round 1.',
        {'sectionId': _string(), 'seed': _integer(0)},
        required: ['sectionId'],
        write: true,
      ),
      tool(
        'set_partners',
        'Set a bughouse section\'s partnerships (pairs of player IDs; replaces the list). Players left out sit out with a zero-point bye. Only before round 1.',
        {'sectionId': _string(), 'partners': _partners},
        required: ['sectionId', 'partners'],
        write: true,
      ),
      tool(
        'make_quads',
        'Group the entire roster by rating into quads and a bottom Swiss. Only before play.',
        {},
        write: true,
      ),
      tool(
        'make_holland',
        'Rule 30H/30I: split the unassigned roster (or the given players) by rating into Holland preliminary round robins (Prelim 1, …), balanced by snake seeding or, with unbalanced, the top-rated in Prelim 1. Only before play.',
        {
          'groups': _integer(2),
          'qualifiers': {
            ..._integer(1),
            'description': 'How many advance from each prelim (30H).',
          },
          'unbalanced': _bool,
          'players': _array(_string('Player ID')),
        },
        required: ['groups', 'qualifiers'],
        write: true,
      ),
      tool(
        'make_holland_final',
        'Create the Final round robin of a Holland group once every prelim has finished: the qualifiers by standings and tie-breaks enter it separately with a fresh score. A tie on every tie-break at the cut is broken by lot (seed).',
        {
          'group': _string('The holland.group of the prelims.'),
          'seed': _integer(0),
        },
        required: ['group'],
        write: true,
      ),
      tool(
        'move_players',
        'Move entries through the same transition rules as the GUI.',
        {
          'players': _array(_string()),
          'sectionId': _string(),
          'reason': _string(),
        },
        required: ['players', 'sectionId'],
        write: true,
      ),
      tool(
        'remove_players',
        'Remove entries that never played. Once their section is paired, withdraw them with update_player instead.',
        {'players': _array(_string())},
        required: ['players'],
        write: true,
      ),
      tool(
        'reserve_bye',
        'Reserve a future bye: points 0, 1, 2 mean zero, half, full point. Half-point byes follow the section byeRules (22C1–22C4); irrevocable declares the bye irrevocable (22C4), and a cancelled irrevocable bye scores a later win as a draw for prizes (22C5).',
        {
          'playerId': _string(),
          'round': _integer(1),
          'points': {'type': 'integer', 'minimum': 0, 'maximum': 2},
          'irrevocable': _bool,
        },
        required: ['playerId', 'round', 'points'],
        write: true,
      ),
      tool(
        'cancel_bye',
        'Cancel a reserved bye. An irrevocable declaration stays unless irrevocable is false (rule 22C5).',
        {'playerId': _string(), 'round': _integer(1), 'irrevocable': _bool},
        required: ['playerId', 'round'],
        write: true,
      ),
      tool(
        'hold_out_non_reporters',
        'Rules 29H3/29H4: for unreported games in the last posted round, score each as a double forfeit (doubleForfeit) or give both players half-point byes for the next round (halfPointByes), in one revision.',
        {
          'sectionId': _string(),
          'treatment': _enum(NonReporterTreatment.values.map((t) => t.name)),
        },
        required: ['sectionId', 'treatment'],
        write: true,
      ),
      tool(
        'log_ruling',
        'Rules 13I, 20K, 18G, 21H–21L: log a ruling, penalty, appeal or adjudication. Appeals are due within 30 minutes of the ruling (21H1); appeals to US Chess within ten days of the event (21L1).',
        {
          'kind': _enum(['ruling', 'penalty', 'appeal', 'adjudication']),
          'text': _string(),
          'round': _integer(0),
          'sectionId': _string(),
          'players': _array(_string('Player ID')),
          'decidedBy': _string(),
          'outcome': _string(),
        },
        required: ['kind', 'text'],
        write: true,
      ),
      tool(
        'propose_pairings',
        'Preview the next round. Returns a proposalId for post_pairings. No event changes.',
        {'sectionId': _string()},
      ),
      tool(
        'post_pairings',
        'Post a previously reviewed proposal. Stale proposals are rejected.',
        {'proposalId': _string()},
        required: ['proposalId'],
        write: true,
      ),
      tool(
        'post_manual_round',
        'Post a documented manual next round (for historical replay or TD-directed pairings). Every active section player needs games or an explicit bye; double games require reversed colors. Enter results separately.',
        {
          'sectionId': _string(),
          'reason': _string(),
          'games': _array(_gameFields),
          'byes': _array(_byeFields),
        },
        required: ['sectionId', 'reason', 'games', 'byes'],
        write: true,
      ),
      tool(
        'record_ladder_game',
        'Ladder: record one challenge game and reorder the ladder in the same change. Positions are the order of the section\'s players (first = #1). A player may challenge up to $ladderChallengeRange places above; a win (also by forfeit) takes the loser\'s place and everyone between moves down one; a draw or loss changes nothing. The result is from the challenger\'s side; the challenger has Black unless challengerWhite.',
        {
          'sectionId': _string(),
          'challenger': _string('Player ID'),
          'defender': _string('Player ID'),
          'result': _enum(ChallengeResult.values.map((r) => r.name)),
          'challengerWhite': _bool,
          'reason': _string('Optional note on the game.'),
        },
        required: ['sectionId', 'challenger', 'defender', 'result'],
        write: true,
      ),
      tool(
        'set_ladder_order',
        'Ladder: the director\'s reordering. List every player of the section exactly once, top first, with the reason.',
        {
          'sectionId': _string(),
          'players': _array(_string('Player ID')),
          'reason': _string(),
        },
        required: ['sectionId', 'players', 'reason'],
        write: true,
      ),
      tool(
        'start_round',
        'Mark the posted round started.',
        {'sectionId': _string()},
        required: ['sectionId'],
        write: true,
      ),
      tool(
        'record_result',
        'Record or correct a game. A correction affecting later rounds requires a reason.',
        {
          'gameId': _string(),
          'outcome': _enum(Outcome.values.map((v) => v.name)),
          'reason': _string(),
        },
        required: ['gameId', 'outcome'],
        write: true,
      ),
      tool(
        'standings',
        'Read points, ranks, tie-breaks and played counts. Points are integer half-points. Each section lists its posted tie-break order (rule 34) and each row carries the values in that order, with each value in its method\'s unit and as a number.',
        {},
      ),
      tool(
        'rating_preflight',
        'Read export blockers without changing anything.',
        {},
      ),
      tool(
        'prize_report',
        'Read the prize allocation (rules 32–33) for one section or all: paid amounts, who wins what, and the pooling arithmetic.',
        {'sectionId': _string()},
      ),
      tool(
        'export_event',
        'Write JSON, CSV, text crosstable, preflight and (when valid) the three DBFs into a NEW directory. Never submits results. Returns DBF blockers.',
        {
          'directory': _string(),
          'sectionId': _string(
            'Optional: export only this section as a separate package.',
          ),
        },
        required: ['directory'],
      ),
      tool(
        'backup_event',
        'Save an independent .meow copy to a new path.',
        {'path': _string()},
        required: ['path'],
      ),
      tool(
        'undo',
        'Undo the last change. Structural or multiple-result losses require acceptLosses=true.',
        {'acceptLosses': _bool},
        write: true,
      ),
      tool(
        'redo',
        'Redo a change. Structural or multiple-result losses require acceptLosses=true.',
        {'acceptLosses': _bool},
        write: true,
      ),
    ];
  }

  String _path(String value) {
    if (value.trim().isEmpty) throw const TournamentException('Choose a path.');
    final path = p.normalize(p.join(root.path, value));
    final canonicalRoot = root.resolveSymbolicLinksSync();
    // Resolve existing parents too: a symlink cannot escape the selected root.
    var ancestor = path;
    final suffix = <String>[];
    while (true) {
      final type = FileSystemEntity.typeSync(ancestor, followLinks: false);
      if (type == FileSystemEntityType.link &&
          FileSystemEntity.typeSync(ancestor) ==
              FileSystemEntityType.notFound) {
        throw const TournamentException('Broken symbolic link in path.');
      }
      if (type.isDirectoryOrFile) break;
      suffix.insert(0, p.basename(ancestor));
      final parent = p.dirname(ancestor);
      if (parent == ancestor) throw const TournamentException('Invalid path.');
      ancestor = parent;
    }
    final canonical = p.joinAll([
      File(ancestor).resolveSymbolicLinksSync(),
      ...suffix,
    ]);
    if (!p.isWithin(canonicalRoot, canonical)) {
      throw const TournamentException(
        'Path must be inside the configured data directory.',
      );
    }
    return canonical;
  }

  /// Metadata is checked when it changes, so automation cannot store a value
  /// the rating report would later refuse without saying so.
  void _checkMetadata(Json args) {
    _checkControl(args['timeControl']);
    final atd = args['assistantTdId'] as String?;
    if (atd != null && atd.isNotEmpty && !isMemberId(atd)) {
      throw const TournamentException(
        'The assistant chief TD\'s US Chess ID has eight digits.',
      );
    }
    if (otherTdProblem(args['otherTdIds'] ?? '') case final problem?) {
      throw TournamentException(problem);
    }
    if (args['tiebreaks'] case final List codes) {
      if (tiebreakCodesProblem(List<String>.from(codes)) case final problem?) {
        throw TournamentException(problem);
      }
    }
  }

  void _checkControl(String? control) {
    if (control != null && control.trim().isNotEmpty) {
      TimeControl.parse(control);
    }
  }

  void close() {
    _controller?.dispose();
    _controller = null;
    _proposals.clear();
  }

  Json _summary() => {
    'revision': event.revision,
    'name': event.name,
    'players': event.players.length,
    'sections': event.sections.length,
  };

  Future<Json> call(String name, Json args) async {
    final definition = definitions.where((d) => d['name'] == name).firstOrNull;
    if (definition == null) throw ArgumentError('Unknown tool: $name');
    _validate(args, definition['inputSchema'] as Json, 'arguments');
    if ((definition['inputSchema']['required'] as List).contains(
          'expectedRevision',
        ) &&
        args['expectedRevision'] != event.revision) {
      throw const TournamentException(
        'Stale revision. Read get_event and review the current state before retrying.',
      );
    }
    switch (name) {
      case 'create_event':
      case 'open_event':
        final path = _path(args['path']);
        if (p.extension(path) != '.meow') {
          throw const TournamentException('Use a .meow filename.');
        }
        if (name == 'create_event' &&
            FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
          throw const TournamentException(
            'That file already exists. Choose a new path.',
          );
        }
        if (name == 'open_event' && !File(path).existsSync()) {
          throw const TournamentException('That event file does not exist.');
        }
        if (_controller != null) {
          throw const TournamentException('Close the current event first.');
        }
        Event? initial;
        if (name == 'create_event') {
          initial = Event.fromJson({
            ...Event(
              id: 'pending',
              name: args['name'],
              date: args['date'],
              practice: true,
            ).toJson(),
            for (final key in _metadata.keys)
              if (args.containsKey(key)) key: args[key],
          });
          _checkMetadata(args);
          validateEvent(initial);
        }
        Directory(p.dirname(path)).createSync(recursive: true);
        final next = TournamentControllerCore(SqliteEventRepository(path));
        try {
          if (initial != null) {
            next.change(
              'Create event via automation',
              Event.fromJson({...initial.toJson(), 'id': next.newId()}),
            );
          }
          if (next.event == null) {
            throw const TournamentException('This file has no event.');
          }
          _controller = next;
        } catch (_) {
          next.dispose();
          // A failed create must not leave an empty file that blocks a retry.
          if (initial != null) {
            for (final suffix in ['', '-wal', '-shm', '-journal']) {
              try {
                final leftover = File('$path$suffix');
                if (leftover.existsSync()) leftover.deleteSync();
              } on FileSystemException {
                // Report the original failure rather than the cleanup.
              }
            }
          }
          rethrow;
        }
        return {'path': path, ...event.toJson()};
      case 'close_event':
        close();
        return {'closed': true};
      case 'get_event':
        return event.toJson();
      case 'update_event':
        if (event.practice && args['practice'] == false) {
          throw const TournamentException(
            'This event is a practice copy and stays one, so it cannot produce a rating report. Create a new event with practice set to false.',
          );
        }
        if (!event.practice && args['practice'] == true) {
          // Practice is permanent and undo cannot remove it, so a rated event
          // is never converted in place.
          throw const TournamentException(
            'A rated event cannot be turned into a practice copy, because that cannot be undone. Back it up and create a separate event with practice set to true.',
          );
        }
        _checkMetadata(args);
        controller.change(
          'Edit event via automation',
          Event.fromJson({
            ...event.toJson(),
            for (final key in _metadata.keys)
              if (args.containsKey(key)) key: args[key],
          }),
        );
      case 'add_players':
        final additions = (args['players'] as List)
            .map(
              (value) => Player.fromJson({
                ...Player(id: controller.newId(), name: value['name']).toJson(),
                ...value as Map,
              }),
            )
            .toList();
        if (additions.isEmpty) {
          throw const TournamentException('Provide at least one player.');
        }
        final ids = event.players
            .where((p) => isMemberId(p.memberId))
            .map((p) => p.memberId)
            .toSet();
        for (final player in additions) {
          if (isMemberId(player.memberId) && !ids.add(player.memberId)) {
            throw TournamentException(
              'Duplicate US Chess ID: ${player.memberId}.',
            );
          }
        }
        controller.change(
          'Register ${additions.length} players via automation',
          event.copy(players: [...event.players, ...additions]),
        );
        return {
          ..._summary(),
          'added': additions.map((p) => p.toJson()).toList(),
        };
      case 'update_player':
        final old = event.player(args['playerId']);
        controller.savePlayer(
          Player.fromJson({
            ...old.toJson(),
            for (final key in _playerFields.keys)
              if (args.containsKey(key)) key: args[key],
          }),
        );
      case 'create_section':
        final ids = List<String>.from(args['players']);
        for (final id in ids) {
          event.player(id);
          if (event.sectionOf(id) != null) {
            throw const TournamentException(
              'Player already has a section; use move_players.',
            );
          }
        }
        _checkControl(args['timeControl']);
        final section = Section(
          id: controller.newId(),
          name: args['name'],
          players: ids,
          format: Format.values.byName(args['format']),
          plannedRounds: args['plannedRounds'],
          boardStart: args['boardStart'],
          doubleGames: args['doubleGames'] ?? false,
          ratingCeiling: args['ratingCeiling'] ?? 0,
          timeControl: args['timeControl'] ?? '',
          sideGames: args['sideGames'] ?? false,
          rrTable: args['rrTable'] ?? '',
          doubleCycle: args['doubleCycle'] ?? false,
          homeTeam: args['homeTeam'] ?? '',
          accelerated: args['accelerated'] ?? '',
          avoidTeammates: args['avoidTeammates'] ?? false,
          // Bughouse is never US Chess rated.
          unrated:
              args['format'] == Format.bughouse.name ||
              (args['unrated'] ?? false),
          variations: Set<String>.from(args['variations'] ?? const []),
          partners: [
            for (final p in args['partners'] as List? ?? const [])
              List<String>.from(p),
          ],
          bracket: _bracketArg(args['bracket'], const {}),
        );
        if (section.format == Format.knockout) {
          if (knockoutSettingsProblem(section.bracket) case final problem?) {
            throw TournamentException(problem);
          }
        }
        if (doubleCycleProblem(section) case final problem?) {
          throw TournamentException(problem);
        }
        controller.change(
          'Create ${section.name}',
          event.copy(sections: [...event.sections, section]),
        );
        return {..._summary(), 'section': section.toJson()};
      case 'update_section':
        final current = _section(args['sectionId']);
        if (args['timeControl'] != current.timeControl) {
          _checkControl(args['timeControl']);
        }
        final rounds = args['plannedRounds'] ?? current.plannedRounds;
        if (rounds < current.rounds.length) {
          throw TournamentException(
            '${current.rounds.length} rounds are already posted, so the section needs at least that many.',
          );
        }
        final name = (args['name'] ?? current.name).trim();
        if (name.isEmpty) throw const TournamentException('Name the section.');
        final rrTable = args['rrTable'] ?? current.rrTable,
            doubleCycle = args['doubleCycle'] ?? current.doubleCycle,
            homeTeam = (args['homeTeam'] ?? current.homeTeam).trim();
        if (current.rounds.isNotEmpty &&
            (rrTable != current.rrTable ||
                doubleCycle != current.doubleCycle ||
                homeTeam != current.homeTeam ||
                args['partners'] != null)) {
          throw const TournamentException(
            'Pairing format cannot change after rounds are posted.',
          );
        }
        final bracket = _bracketArg(args['bracket'], current.bracket);
        if (args['bracket'] != null) {
          if (knockoutSettingsProblem(bracket) case final problem?) {
            throw TournamentException(problem);
          }
          if (current.rounds.isNotEmpty &&
              (bracket['gamesPerMatch'] != current.bracket['gamesPerMatch'] ||
                  jsonEncode(bracket['seeds']) !=
                      jsonEncode(current.bracket['seeds']))) {
            throw const TournamentException(
              'Games per match and seeding are fixed once round 1 is posted.',
            );
          }
        }
        if (doubleCycleProblem(
              current.copy(
                plannedRounds: rounds,
                rrTable: rrTable,
                doubleCycle: doubleCycle,
              ),
            )
            case final problem?) {
          throw TournamentException(problem);
        }
        final prizes = args['prizes'] == null
            ? null
            : PrizeTable.fromJson(
                Map<String, dynamic>.from(args['prizes'] as Map),
              ).toJson();
        final byeRules = args['byeRules'] == null
            ? null
            : ByePolicy.fromJson(
                Map<String, dynamic>.from(args['byeRules'] as Map),
              );
        if (byeRules != null &&
            (byeRules.lastHalfByeRound > rounds ||
                byeRules.irrevocableFromRound > rounds)) {
          throw TournamentException(
            'Bye policy rounds cannot exceed the $rounds planned rounds.',
          );
        }
        controller.change(
          'Edit section ${current.name} via automation',
          event.copy(
            sections: [
              for (final x in event.sections)
                x.id == current.id
                    ? x.copy(
                        name: name,
                        timeControl: (args['timeControl'] ?? x.timeControl)
                            .trim(),
                        plannedRounds: rounds,
                        boardStart: args['boardStart'] ?? x.boardStart,
                        rrTable: rrTable,
                        doubleCycle: doubleCycle,
                        homeTeam: homeTeam,
                        accelerated: args['accelerated'] ?? x.accelerated,
                        unrated: x.format == Format.bughouse
                            ? true
                            : args['unrated'] ?? x.unrated,
                        avoidTeammates:
                            args['avoidTeammates'] ?? x.avoidTeammates,
                        variations: args['variations'] == null
                            ? x.variations
                            : Set<String>.from(args['variations']),
                        prizes: prizes,
                        bracket: bracket,
                        doubleGames: x.format == Format.knockout
                            ? knockoutGamesPerMatch(x.copy(bracket: bracket)) ==
                                  2
                            : null,
                        byeRules: byeRules?.toJson() ?? x.byeRules,
                        partners: args['partners'] == null
                            ? x.partners
                            : [
                                for (final p in args['partners'] as List)
                                  List<String>.from(p),
                              ],
                      )
                    : x,
            ],
          ),
        );
        return {..._summary(), 'section': _section(current.id).toJson()};
      case 'advance_knockout':
        _section(args['sectionId']);
        controller.advanceKnockout(
          args['sectionId'],
          args['board'],
          args['playerId'],
          reason: args['reason'] ?? '',
        );
        return {
          ..._summary(),
          'bracket': knockoutBracketLines(event, _section(args['sectionId'])),
        };
      case 'pair_side_game':
        final section = controller.addSideGame(
          args['white'],
          args['black'],
          sectionId: args['sectionId'],
        );
        return {..._summary(), 'sectionId': section};
      case 'add_section_entry':
        final entry = controller.addSectionEntry(
          args['playerId'],
          args['sectionId'],
        );
        return {..._summary(), 'entry': entry.toJson()};
      case 'draw_lots':
        controller.drawLots(args['sectionId'], seed: args['seed']);
        return {..._summary(), 'section': _section(args['sectionId']).toJson()};
      case 'set_partners':
        controller.setPartners(args['sectionId'], [
          for (final p in args['partners'] as List) List<String>.from(p),
        ]);
        return {..._summary(), 'section': _section(args['sectionId']).toJson()};
      case 'make_quads':
        controller.applyQuads(controller.quadPreview(), event.revision);
        return {
          ..._summary(),
          'sections': event.sections.map((s) => s.toJson()).toList(),
        };
      case 'make_holland':
        final ids = controller.makeHolland(
          groups: args['groups'],
          qualifiers: args['qualifiers'],
          unbalanced: args['unbalanced'] ?? false,
          players: args['players'] == null
              ? null
              : List<String>.from(args['players']),
        );
        return {
          ..._summary(),
          'sections': [for (final id in ids) _section(id).toJson()],
        };
      case 'make_holland_final':
        final id = controller.makeHollandFinal(
          args['group'],
          seed: args['seed'],
        );
        return {..._summary(), 'section': _section(id).toJson()};
      case 'move_players':
        controller.movePlayers(
          List<String>.from(args['players']),
          args['sectionId'],
          reason: args['reason'] ?? '',
        );
      case 'remove_players':
        controller.removePlayers(List<String>.from(args['players']));
      case 'reserve_bye':
        controller.reserveBye(
          args['playerId'],
          args['round'],
          args['points'],
          irrevocable: args['irrevocable'],
        );
      case 'cancel_bye':
        controller.reserveBye(
          args['playerId'],
          args['round'],
          -1,
          irrevocable: args['irrevocable'],
        );
      case 'hold_out_non_reporters':
        final boards = controller.holdOutNonReporters(
          args['sectionId'],
          treatment: NonReporterTreatment.parse(args['treatment']),
        );
        return {..._summary(), 'boards': boards};
      case 'log_ruling':
        final id = controller.logRuling(
          kind: args['kind'],
          text: args['text'],
          round: args['round'] ?? 0,
          section: args['sectionId'] ?? '',
          players: List<String>.from(args['players'] ?? const []),
          decidedBy: args['decidedBy'] ?? '',
          outcome: args['outcome'] ?? '',
        );
        return {..._summary(), 'rulingId': id};
      case 'propose_pairings':
        if (args['sectionId'] != null) _section(args['sectionId']);
        final batch = await controller.propose(sectionId: args['sectionId']);
        final id = controller.newId();
        _proposals.clear();
        _proposals[id] = batch;
        return {
          'proposalId': id,
          'revision': batch.revision,
          'rounds': batch.rounds.map((k, v) => MapEntry(k, v.toJson())),
          'issues': batch.issues,
        };
      case 'post_pairings':
        final batch = _proposals[args['proposalId']];
        if (batch == null) {
          throw const TournamentException(
            'Unknown proposal. Generate a new one.',
          );
        }
        controller.post(batch);
        _proposals.clear();
      case 'post_manual_round':
        _postManual(args);
      case 'record_ladder_game':
        final challengerWhite = args['challengerWhite'] ?? false;
        final gameId = controller.recordLadderGame(
          args['sectionId'],
          args['challenger'],
          args['defender'],
          ChallengeResult.parse(
            args['result'],
          ).outcome(challengerWhite: challengerWhite),
          challengerWhite: challengerWhite,
          reason: args['reason'] ?? '',
        );
        return {
          ..._summary(),
          'gameId': gameId,
          'ladder': _section(args['sectionId']).players,
        };
      case 'set_ladder_order':
        controller.setLadderOrder(
          args['sectionId'],
          List<String>.from(args['players']),
          args['reason'],
        );
        return {..._summary(), 'ladder': _section(args['sectionId']).players};
      case 'start_round':
        controller.startRound(args['sectionId']);
      case 'record_result':
        controller.recordResult(
          args['gameId'],
          Outcome.values.byName(args['outcome']),
          reason: args['reason'] ?? '',
        );
      case 'prize_report':
        if (args['sectionId'] != null) _section(args['sectionId']);
        return {
          'revision': event.revision,
          'sections': [
            for (final s in event.sections)
              if (args['sectionId'] == null || s.id == args['sectionId'])
                {
                  'id': s.id,
                  'name': s.name,
                  'prizes': s.prizes,
                  ...allocatePrizes(event, s).toJson(),
                },
          ],
        };
      case 'standings':
        return {
          'revision': event.revision,
          'sections': [
            for (final s in event.sections)
              {
                'id': s.id,
                'name': s.name,
                'tiebreakOrder': [
                  for (final m in standingsTiebreaks(event, s))
                    {'code': m.code, 'label': m.label, 'rule': m.rule},
                ],
                'rows': [
                  for (final row in standings(event, s))
                    {
                      'playerId': row.player.id,
                      'name': row.player.name,
                      'points': row.points,
                      'rank': row.rank,
                      'tiebreaks': [
                        for (final t in row.tiebreaks)
                          {
                            'code': t.code,
                            'value': t.value,
                            'unit': t.method.unit.name,
                            'number': t.number,
                            'text': t.text,
                          },
                      ],
                      'played': row.played,
                    },
                ],
                if (s.format == Format.knockout) ...{
                  'placings': [
                    for (final (id, placing) in knockoutPlacings(event, s))
                      {'playerId': id, 'placing': placing},
                  ],
                  'bracket': knockoutBracketLines(event, s),
                },
              },
          ],
        };
      case 'rating_preflight':
        final all = ratingIssues(event);
        return {
          'revision': event.revision,
          'issues': [
            for (final i in all)
              if (i.blocking) i.message,
          ],
          'advice': [
            for (final i in all)
              if (!i.blocking) i.message,
          ],
        };
      case 'export_event':
        final selected = args['sectionId'] == null
            ? null
            : _section(args['sectionId']);
        // A separate section package carries only that section's moves.
        final snapshot = selected == null
            ? event
            : event.copy(
                sections: [selected],
                transitions: [
                  for (final t in event.transitions)
                    if (t['target'] == selected.id ||
                        (t['players'] as List).any(selected.players.contains))
                      t,
                ],
              );
        final directory = Directory(_path(args['directory']));
        if (FileSystemEntity.typeSync(directory.path) !=
            FileSystemEntityType.notFound) {
          throw const TournamentException(
            'Export directory already exists. Choose a new one.',
          );
        }
        final issues = ratingPreflight(snapshot);
        final dbfs = issues.isEmpty
            ? ratingPackage(snapshot)
            : <String, List<int>>{};
        final texts = {
          'event.json': const JsonEncoder.withIndent(
            '  ',
          ).convert(snapshot.toJson()),
          'standings.csv': standingsCsv(snapshot),
          'crosstable.txt': crosstable(snapshot),
          'preflight.json': jsonEncode({
            'issues': issues,
            'submitted': false,
            'sectionId': selected?.id,
            'sourceRevision': event.revision,
          }),
        };
        if (dbfs.isNotEmpty) {
          texts['manifest.json'] = const JsonEncoder.withIndent(
            '  ',
          ).convert(ratingManifest(snapshot, dbfs));
        }
        // Write into a hidden sibling and rename, so a failure part way never
        // leaves a half-written package under the requested name.
        createDirectoryDurably(p.dirname(directory.path));
        final staging = Directory(
          p.dirname(directory.path),
        ).createTempSync('.${p.basename(directory.path)}.partial-');
        try {
          for (final entry in texts.entries) {
            File(
              p.join(staging.path, entry.key),
            ).writeAsStringSync(entry.value, flush: true);
          }
          for (final entry in dbfs.entries) {
            File(
              p.join(staging.path, entry.key),
            ).writeAsBytesSync(entry.value, flush: true);
          }
          publishDirectory(staging.path, directory.path);
        } catch (_) {
          if (staging.existsSync()) staging.deleteSync(recursive: true);
          rethrow;
        }
        return {
          'directory': directory.path,
          'files': [...texts.keys, ...dbfs.keys],
          'dbfIssues': issues,
          'advice': [
            for (final issue in ratingIssues(snapshot))
              if (!issue.blocking) issue.message,
          ],
        };
      case 'backup_event':
        final path = _path(args['path']);
        if (p.extension(path) != '.meow') {
          throw const TournamentException('Use a .meow filename.');
        }
        controller.repository.backup(path);
        return {'path': path, ..._summary()};
      case 'undo':
        controller.undo(acceptLosses: args['acceptLosses'] ?? false);
      case 'redo':
        controller.redo(acceptLosses: args['acceptLosses'] ?? false);
    }
    return _summary();
  }

  /// The stored bracket with [arg]'s settings applied; `rounds` is kept.
  static Json _bracketArg(Object? arg, Json current) => arg == null
      ? current
      : {
          ...current,
          ...Map<String, dynamic>.from(arg as Map),
          if (current['rounds'] != null) 'rounds': current['rounds'],
        };

  Section _section(String id) =>
      event.sections.where((s) => s.id == id).firstOrNull ??
      (throw const TournamentException('Unknown section.'));

  void _postManual(Json args) {
    final s = _section(args['sectionId']);
    final reason = (args['reason'] as String).trim();
    if (reason.isEmpty) {
      throw const TournamentException('Explain the manual pairing.');
    }
    if (s.rounds.length >= s.plannedRounds ||
        s.rounds.any((r) => !r.complete)) {
      throw const TournamentException(
        'Complete the previous round and check the planned round count.',
      );
    }
    final games = (args['games'] as List)
        .map(
          (g) => Game(
            id: controller.newId(),
            white: g['white'],
            black: g['black'],
            board: g['board'],
            leg: g['leg'] ?? 1,
          ),
        )
        .toList();
    final byes = (args['byes'] as List)
        .map(
          (b) => ByeAward(
            b['player'],
            b['points'],
            b['reason'],
            allocated: b['allocated'] ?? false,
          ),
        )
        .toList();
    final participants = {
      ...games.expand((g) => [g.white, g.black]),
      ...byes.map((b) => b.player),
    };
    if (participants.any((id) => !s.players.contains(id)) ||
        s.players.any(
          (id) => !event.player(id).withdrawn && !participants.contains(id),
        )) {
      throw const TournamentException(
        'Include every active section player with a game or an explicit bye; use only section members.',
      );
    }
    for (final game in games) {
      if (!s.doubleGames && game.leg != 1) {
        throw const TournamentException('Single-game sections have one leg.');
      }
      if (s.doubleGames &&
          games
                  .where(
                    (g) =>
                        g.board == game.board &&
                        g.leg == 3 - game.leg &&
                        g.white == game.black &&
                        g.black == game.white,
                  )
                  .length !=
              1) {
        throw const TournamentException(
          'Double-game pairings require two legs on the same board with colors reversed.',
        );
      }
    }
    controller.post(
      PairingBatch(event.revision, {
        s.id: Round(
          number: s.rounds.length + 1,
          games: games,
          byes: byes,
          policy: 'td-manual',
          note: reason,
        ),
      }, {}),
    );
  }
}

extension on FileSystemEntityType {
  bool get isDirectoryOrFile =>
      this == FileSystemEntityType.directory ||
      this == FileSystemEntityType.file ||
      this == FileSystemEntityType.link;
}

void _validate(dynamic value, Json schema, String at) {
  void fail(String detail) => throw TournamentException('$at: $detail');
  final type = schema['type'];
  if (type == 'object') {
    if (value is! Map<String, dynamic>) fail('expected an object');
    final map = value as Json;
    final properties = schema['properties'] as Json;
    for (final required in schema['required'] as List) {
      if (!map.containsKey(required)) fail('missing $required');
    }
    for (final key in map.keys) {
      if (!properties.containsKey(key)) fail('unknown field $key');
      _validate(map[key], properties[key] as Json, '$at.$key');
    }
  } else if (type == 'array') {
    if (value is! List) fail('expected an array');
    for (final (i, element) in (value as List).indexed) {
      _validate(element, schema['items'] as Json, '$at[$i]');
    }
  } else {
    if ((type == 'string' && value is! String) ||
        (type == 'integer' && value is! int) ||
        (type == 'boolean' && value is! bool)) {
      fail('expected $type');
    }
    if (schema.containsKey('enum') &&
        !(schema['enum'] as List).contains(value)) {
      fail('invalid choice');
    }
    if (value is int &&
        ((schema['minimum'] != null && value < schema['minimum']) ||
            (schema['maximum'] != null && value > schema['maximum']))) {
      fail('out of range');
    }
  }
}

/// Tool failures stay in tools/call content, not JSON-RPC protocol errors.
Json toolFailure(Object error) => {
  'isError': true,
  'content': [
    {'type': 'text', 'text': plainMessage(error)},
  ],
};
