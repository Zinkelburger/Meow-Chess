import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/fide.dart';
import '../domain/model.dart';
import '../domain/us_chess.dart' show nameKey;

/// FIDE's monthly rating list, the only official bulk source of FIDE
/// ratings (no FIDE API exists). Source and layout:
/// `research/notes/FIDE.md` §1, `research/local/fide-download-lists.txt`.
///
/// The list is downloaded once a month (or a ZIP the TD already has is
/// chosen) and kept on this computer as a compact gzipped index of what a
/// TD needs: FIDE ID, name, federation, sex, title, the three ratings and
/// birth year. Lookups stream through the index on a background isolate,
/// so a club laptop never holds the 300 MB list in memory.

/// The combined standard, rapid and blitz list.
const fideListUrl = 'https://ratings.fide.com/download/players_list.zip';

/// One player as FIDE's list publishes them.
class FideListPlayer {
  const FideListPlayer({
    required this.id,
    required this.name,
    this.federation = '',
    this.sex = '',
    this.title = '',
    this.standard = 0,
    this.rapid = 0,
    this.blitz = 0,
    this.birthYear = '',
    this.arbiter = '',
    this.inactive = false,
  });
  final String id, name, federation, sex, title, birthYear;

  /// The arbiter title the list shows (`IA`, `FA` or `NA`), or empty.
  final String arbiter;

  /// FIDE lists the player as inactive (flag `i`): still rated, but has not
  /// played a rated game for a year.
  final bool inactive;
  final int standard, rapid, blitz;

  String toLine() => [
    id,
    name,
    federation,
    sex,
    title,
    standard,
    rapid,
    blitz,
    birthYear,
    arbiter,
    inactive ? 'i' : '',
  ].join('\t');

  static FideListPlayer? fromLine(String line) {
    final f = line.split('\t');
    if (f.length < 9) return null;
    return FideListPlayer(
      id: f[0],
      name: f[1],
      federation: f[2],
      sex: f[3],
      title: f[4],
      standard: int.tryParse(f[5]) ?? 0,
      rapid: int.tryParse(f[6]) ?? 0,
      blitz: int.tryParse(f[7]) ?? 0,
      birthYear: f[8],
      arbiter: f.length > 9 ? f[9] : '',
      inactive: f.length > 10 && f[10] == 'i',
    );
  }

  /// [player] with this record's identity and ratings. Ratings, title,
  /// federation and sex follow the list; a birth date already recorded
  /// more precisely is kept.
  Player applyTo(Player player, {required String month}) => player.copy(
    fideId: id,
    fideStandard: standard,
    fideRapid: rapid,
    fideBlitz: blitz,
    title: title,
    federation: isFederationCode(federation) ? federation : null,
    sex: sex.isEmpty ? null : sex,
    birthDate:
        birthYear.isNotEmpty &&
            !player.birthDate.startsWith(birthYear) &&
            isFideBirthDate(birthYear)
        ? birthYear
        : null,
    fideEvidence: {
      'source': 'FIDE rating list',
      'list': month,
      'retrievedAt': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

/// What is installed: the list's month (`YYYY-MM`), when it was imported
/// and how many players it holds.
class FideListInfo {
  const FideListInfo(this.month, this.importedAt, this.players);
  final String month, importedAt;
  final int players;
  Json toJson() => {
    'month': month,
    'importedAt': importedAt,
    'players': players,
    'format': indexFormat,
  };

  /// Bumped when the index gains columns; an older index is imported again.
  static const indexFormat = 2;

  static FideListInfo? fromJson(Object? j) =>
      j is Map && j['format'] == indexFormat
      ? FideListInfo(
          '${j['month'] ?? ''}',
          '${j['importedAt'] ?? ''}',
          j['players'] is int ? j['players'] as int : 0,
        )
      : null;

  /// "October 2026".
  String get label {
    final parts = month.split('-');
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
    return m == null || m < 1 || m > 12 ? month : '${names[m - 1]} ${parts[0]}';
  }
}

class FideRatingList {
  FideRatingList([this._directory]);
  final Directory? _directory;

  Future<Directory> get directory async {
    if (_directory != null) return _directory;
    final configured = Platform.environment['MEOW_DATA_DIR'];
    final root = configured == null
        ? await getApplicationSupportDirectory()
        : Directory(configured);
    return Directory(p.join(root.path, 'fide'));
  }

  Future<File> get _index async =>
      File(p.join((await directory).path, 'players.tsv.gz'));
  Future<File> get _meta async =>
      File(p.join((await directory).path, 'list.json'));

  /// The installed list, or null when none has been imported.
  Future<FideListInfo?> info() async {
    final meta = await _meta, index = await _index;
    if (!await meta.exists() || !await index.exists()) return null;
    try {
      return FideListInfo.fromJson(jsonDecode(await meta.readAsString()));
    } on FormatException {
      return null;
    }
  }

  /// Downloads the current combined list from FIDE and imports it.
  /// [progress] reports bytes received and the total when known.
  Future<FideListInfo> download({
    http.Client? client,
    void Function(int received, int? total)? progress,
  }) async {
    final dir = await directory;
    await dir.create(recursive: true);
    final zip = File(p.join(dir.path, 'download.zip.partial'));
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.send(
        http.Request('GET', Uri.parse(fideListUrl)),
      );
      if (response.statusCode != 200) {
        throw TournamentException(
          'FIDE\'s rating list server answered ${response.statusCode}. Try again later, or choose a list ZIP you downloaded.',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = zip.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          progress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      DateTime? modified;
      try {
        modified = HttpDate.parse(response.headers['last-modified'] ?? '');
      } on FormatException {
        modified = null;
      } on HttpException {
        modified = null;
      }
      return await importZip(zip.path, published: modified);
    } on SocketException {
      throw const TournamentException(
        'Could not reach ratings.fide.com. Check the connection, or choose a list ZIP you downloaded.',
      );
    } on http.ClientException {
      throw const TournamentException(
        'The download from ratings.fide.com stopped. Try again, or choose a list ZIP you downloaded.',
      );
    } finally {
      if (own) c.close();
      if (await zip.exists()) await zip.delete();
    }
  }

  /// Imports a FIDE list ZIP (the combined list, or the standard, rapid or
  /// blitz list) into the local index, replacing the previous one.
  Future<FideListInfo> importZip(String path, {DateTime? published}) async {
    final dir = await directory;
    await dir.create(recursive: true);
    final index = await _index, meta = await _meta;
    final staging = '${index.path}.partial';
    final date = published ?? (await File(path).lastModified());
    final count = await Isolate.run(() => _buildIndex(path, staging));
    await File(staging).rename(index.path);
    final info = FideListInfo(
      '${date.year}-${date.month.toString().padLeft(2, '0')}',
      DateTime.now().toUtc().toIso8601String(),
      count,
    );
    await meta.writeAsString(jsonEncode(info.toJson()), flush: true);
    return info;
  }

  /// The listed players among [ids].
  Future<Map<String, FideListPlayer>> lookup(Set<String> ids) async {
    final index = await _index;
    if (!await index.exists() || ids.isEmpty) return const {};
    final path = index.path;
    return Isolate.run(() async {
      final found = <String, FideListPlayer>{};
      await for (final line in _lines(path)) {
        final tab = line.indexOf('\t');
        if (tab < 0 || !ids.contains(line.substring(0, tab))) continue;
        if (FideListPlayer.fromLine(line) case final p?) found[p.id] = p;
        if (found.length == ids.length) break;
      }
      return found;
    });
  }

  /// Players whose name matches [query] ("Last, First", "First Last" or a
  /// part of either), best matches first.
  Future<List<FideListPlayer>> search(String query, {int limit = 12}) async {
    final index = await _index;
    final words = nameKey(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (limit < 1 || !await index.exists() || words.isEmpty) return const [];
    final path = index.path;
    return Isolate.run(() async {
      // Every match is ranked, so a common name still offers its strongest
      // players however late they come in the list; only the best [limit]
      // are kept, strongest first.
      int rank(FideListPlayer p) => p.standard + p.rapid + p.blitz;
      final best = <FideListPlayer>[];
      await for (final line in _lines(path)) {
        final tab = line.indexOf('\t');
        if (tab < 0) continue;
        final end = line.indexOf('\t', tab + 1);
        final name = nameKey(line.substring(tab + 1, end < 0 ? null : end));
        if (!words.every(name.contains)) continue;
        final p = FideListPlayer.fromLine(line);
        if (p == null) continue;
        if (best.length == limit && rank(p) <= rank(best.last)) continue;
        final at = best.indexWhere((b) => rank(p) > rank(b));
        best.insert(at < 0 ? best.length : at, p);
        if (best.length > limit) best.removeLast();
      }
      return best;
    });
  }
}

Stream<String> _lines(String gz) => File(gz)
    .openRead()
    .transform(gzip.decoder)
    .transform(utf8.decoder)
    .transform(const LineSplitter());

/// Builds the gzipped index from a list ZIP. Returns the player count.
Future<int> _buildIndex(String zipPath, String outPath) async {
  final input = InputFileStream(zipPath);
  final txt = '$outPath.txt';
  try {
    final archive = ZipDecoder().decodeStream(input);
    final entry = archive.files
        .where((f) => f.isFile && f.name.toLowerCase().endsWith('.txt'))
        .firstOrNull;
    if (entry == null) {
      throw const TournamentException(
        'That ZIP holds no FIDE rating list (no .txt file). Choose players_list.zip from ratings.fide.com.',
      );
    }
    final output = OutputFileStream(txt);
    entry.writeContent(output);
    await output.close();
    final kind = entry.name.toLowerCase();
    final sink = File(outPath).openWrite();
    final encoder = gzip.encoder.startChunkedConversion(sink);
    var count = 0;
    _Columns? columns;
    await for (final line in File(
      txt,
    ).openRead().transform(latin1.decoder).transform(const LineSplitter())) {
      if (columns == null) {
        columns = _Columns.parse(line, kind);
        continue;
      }
      final player = columns.read(line);
      if (player == null) continue;
      encoder.add(utf8.encode('${player.toLine()}\n'));
      count++;
    }
    encoder.close();
    await sink.done;
    if (count == 0) {
      throw const TournamentException(
        'The FIDE list in that ZIP has no players.',
      );
    }
    return count;
  } finally {
    await input.close();
    final f = File(txt);
    if (await f.exists()) await f.delete();
  }
}

/// Field positions read from the list's header line (FIDE has changed the
/// layout before: legacy, FOA, single-type lists). Fields after the
/// "other titles" column are read from the line's end, because a long
/// title list can push them one character right.
class _Columns {
  _Columns(this.header, this.starts, this.kind);
  final String header, kind;
  final Map<String, int> starts;

  static _Columns parse(String header, String kind) {
    final starts = <String, int>{};
    for (final m in RegExp(r'\S+(?: Number)?').allMatches(header)) {
      starts[m[0]!] = m.start;
    }
    if (!starts.containsKey('ID Number') || !starts.containsKey('Name')) {
      throw const TournamentException(
        'That file is not a FIDE rating list: its header has no ID Number or Name column.',
      );
    }
    return _Columns(header, starts, kind);
  }

  /// The field that starts at [name], up to the next field.
  String _field(String line, String name, {bool fromEnd = false}) {
    final start = starts[name];
    if (start == null) return '';
    final next = starts.values
        .where((s) => s > start)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    var from = start, to = next ?? header.length;
    if (fromEnd) {
      final shift = line.length - header.length;
      from += shift;
      to += shift;
    }
    if (from >= line.length) return '';
    return line
        .substring(from.clamp(0, line.length), to.clamp(0, line.length))
        .trim();
  }

  /// The "other titles" column, which may run into the next column.
  List<String> _otherTitles(String line) {
    final start = starts['OTit'], foa = starts['FOA'];
    if (start == null || start >= line.length) return const [];
    final end = ((foa ?? start + 15) + line.length - header.length).clamp(
      start,
      line.length,
    );
    return line.substring(start, end).trim().split(',');
  }

  int _rating(String line, String name) =>
      int.tryParse(_field(line, name, fromEnd: true)) ?? 0;

  FideListPlayer? read(String line) {
    final id = _field(line, 'ID Number');
    if (!isFideId(id)) return null;
    final sex = _field(line, 'Sex').toUpperCase();
    final title = fideTitleFromCode(_field(line, 'Tit'));
    // Single-type lists head the rating column with the month (`OCT26`).
    final monthColumn = starts.keys
        .where((k) => RegExp(r'^[A-Z]{3}\d{2}$').hasMatch(k))
        .firstOrNull;
    int single(String type) => kind.contains(type) && monthColumn != null
        ? _rating(line, monthColumn)
        : 0;
    final standard = starts.containsKey('SRtng')
        ? _rating(line, 'SRtng')
        : single('standard');
    final rapid = starts.containsKey('RRtng')
        ? _rating(line, 'RRtng')
        : single('rapid');
    final blitz = starts.containsKey('BRtng')
        ? _rating(line, 'BRtng')
        : single('blitz');
    final year = _field(line, 'B-day', fromEnd: true);
    return FideListPlayer(
      id: id,
      name: _field(line, 'Name'),
      federation: _field(line, 'Fed'),
      sex: sex == 'M'
          ? 'm'
          : sex == 'F'
          ? 'w'
          : '',
      title: title.isNotEmpty ? title : fideTitleFromCode(_field(line, 'WTit')),
      standard: standard,
      rapid: rapid,
      blitz: blitz,
      birthYear: RegExp(r'^(19|20)\d\d$').hasMatch(year) ? year : '',
      arbiter:
          const [
            'IA',
            'FA',
            'NA',
          ].where(_otherTitles(line).contains).firstOrNull ??
          '',
      inactive: _field(line, 'Flag', fromEnd: true).contains('i'),
    );
  }
}
