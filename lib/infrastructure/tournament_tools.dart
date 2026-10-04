import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../application/failures.dart';
import '../application/tournament_controller_core.dart';
import '../domain/model.dart';
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
  ])
    key: _string(),
  'rating': {'type': 'integer', 'minimum': 0, 'maximum': 4000},
  'checkedIn': _bool,
  'withdrawn': _bool,
};
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
        'Edit event and rating-report metadata.',
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
        },
        required: ['name', 'players', 'format', 'plannedRounds', 'boardStart'],
        write: true,
      ),
      tool(
        'update_section',
        'Edit a section\'s name, time control (blank inherits the event default), planned rounds or first board. Format changes are GUI-only.',
        {
          'sectionId': _string(),
          'name': _string(),
          'timeControl': _string('Blank inherits the event default.'),
          'plannedRounds': _integer(1),
          'boardStart': _integer(1),
        },
        required: ['sectionId'],
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
        'make_quads',
        'Group the entire roster by rating into quads and a bottom Swiss. Only before play.',
        {},
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
        'reserve_bye',
        'Reserve a future bye: points 0, 1, 2 mean zero, half, full point.',
        {
          'playerId': _string(),
          'round': _integer(1),
          'points': {'type': 'integer', 'minimum': 0, 'maximum': 2},
        },
        required: ['playerId', 'round', 'points'],
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
        'Read points, ranks, tie-breaks and played counts. Points are integer half-points; Sonneborn-Berger is in quarter-points.',
        {},
      ),
      tool(
        'rating_preflight',
        'Read export blockers without changing anything.',
        {},
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
            .where((p) => p.memberId.isNotEmpty)
            .map((p) => p.memberId)
            .toSet();
        for (final player in additions) {
          if (player.memberId.isNotEmpty && !ids.add(player.memberId)) {
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
        );
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
                      )
                    : x,
            ],
          ),
        );
        return {..._summary(), 'section': _section(current.id).toJson()};
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
      case 'make_quads':
        controller.applyQuads(controller.quadPreview(), event.revision);
        return {
          ..._summary(),
          'sections': event.sections.map((s) => s.toJson()).toList(),
        };
      case 'move_players':
        controller.movePlayers(
          List<String>.from(args['players']),
          args['sectionId'],
          reason: args['reason'] ?? '',
        );
      case 'reserve_bye':
        controller.reserveBye(args['playerId'], args['round'], args['points']);
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
      case 'start_round':
        controller.startRound(args['sectionId']);
      case 'record_result':
        controller.recordResult(
          args['gameId'],
          Outcome.values.byName(args['outcome']),
          reason: args['reason'] ?? '',
        );
      case 'standings':
        return {
          'revision': event.revision,
          'sections': [
            for (final s in event.sections)
              {
                'id': s.id,
                'name': s.name,
                'rows': [
                  for (final row in standings(event, s))
                    {
                      'playerId': row.player.id,
                      'name': row.player.name,
                      'points': row.points,
                      'rank': row.rank,
                      'buchholz': row.buchholz,
                      'sonneborn': row.sonneborn,
                      'played': row.played,
                    },
                ],
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
