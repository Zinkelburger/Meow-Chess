import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/fide_rating_list.dart';

/// Lines from FIDE's October 2026 lists (research/local/
/// fide-players-list-excerpt.txt), zipped as FIDE ships them.
String _zip(Directory dir, String txt) {
  final source = File('test/fixtures/fide/$txt');
  final archive = Archive()
    ..addFile(ArchiveFile.bytes(txt, source.readAsBytesSync()));
  final path = '${dir.path}/$txt.zip';
  File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  return path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fide-list-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('imports the combined list and finds players by ID', () async {
    final list = FideRatingList(Directory('${dir.path}/fide'));
    expect(await list.info(), isNull);
    final info = await list.importZip(
      _zip(dir, 'players_list_foa.txt'),
      published: DateTime.utc(2026, 10, 1),
    );
    expect(info.month, '2026-10');
    expect(info.label, 'October 2026');
    expect(info.players, 6);
    expect((await list.info())!.players, 6);

    final found = await list.lookup({'2016192', '3501418', '3101959', '1'});
    expect(found.keys, unorderedEquals(['2016192', '3501418', '3101959']));
    final hikaru = found['2016192']!;
    expect(hikaru.name, 'Nakamura, Hikaru');
    expect(hikaru.federation, 'USA');
    expect(hikaru.title, 'GM');
    expect(hikaru.sex, 'm');
    expect((hikaru.standard, hikaru.rapid, hikaru.blitz), (2792, 2738, 2800));
    expect(hikaru.birthYear, '1987');
    // A woman's title from the title column, sex F written as w.
    expect(found['3501418']!.title, 'WGM');
    expect(found['3501418']!.sex, 'w');
    // A line one character long (other titles overflow) still reads right.
    final cruz = found['3101959']!;
    expect((cruz.standard, cruz.rapid, cruz.blitz), (1938, 1956, 1927));
    expect(cruz.birthYear, '1982');
    // Arbiter titles from the other-titles column, overflow included.
    expect(cruz.arbiter, 'NA');
    expect(found['3501418']!.arbiter, 'IA');
    expect(hikaru.arbiter, '');
    expect(hikaru.inactive, isFalse);
  });

  test('searches by name in either order', () async {
    final list = FideRatingList(Directory('${dir.path}/fide'));
    await list.importZip(_zip(dir, 'players_list_foa.txt'));
    expect((await list.search('Hikaru Nakamura')).single.id, '2016192');
    expect((await list.search('carlsen')).single.id, '1503014');
    expect(await list.search('Nobody Here'), isEmpty);
  });

  test('a common name offers its strongest players, wherever they are '
      'in the list', () async {
    final lines = File(
      'test/fixtures/fide/players_list_foa.txt',
    ).readAsLinesSync();
    final header = lines.first;
    final template = lines[1].padRight(header.length);
    final name = header.indexOf('Name'), rating = header.indexOf('SRtng');
    String row(int i) {
      final id = '${9000000 + i}'.padRight(name);
      final who = 'Wang, Player$i'.padRight(header.indexOf('Fed') - name);
      final mid = template.substring(name + who.length, rating);
      final elo = '${1000 + i}'.padRight(6);
      return '$id$who$mid$elo${template.substring(rating + elo.length)}';
    }

    File('${dir.path}/wang.txt').writeAsStringSync(
      [header, for (var i = 0; i < 300; i++) row(i)].join('\r\n'),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'players_list_foa.txt',
          File('${dir.path}/wang.txt').readAsBytesSync(),
        ),
      );
    final zip = '${dir.path}/wang.zip';
    File(zip).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    final list = FideRatingList(Directory('${dir.path}/fide'));
    await list.importZip(zip);
    final found = await list.search('wang', limit: 3);
    expect(found.map((p) => p.standard), [1299, 1298, 1297]);
  });

  test('reads a single-type list by its month column', () async {
    final list = FideRatingList(Directory('${dir.path}/fide'));
    await list.importZip(_zip(dir, 'standard_rating_list.txt'));
    final carlsen = (await list.lookup({'1503014'}))['1503014']!;
    expect(carlsen.standard, 2823);
    expect(carlsen.rapid, 0);
  });

  test('a ZIP without a list is refused', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('readme.md', [1, 2, 3]));
    final path = '${dir.path}/other.zip';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    final list = FideRatingList(Directory('${dir.path}/fide'));
    await expectLater(
      list.importZip(path),
      throwsA(isA<TournamentException>()),
    );
    expect(await list.info(), isNull);
  });

  test('a list record fills a player and records where it came from', () {
    const r = FideListPlayer(
      id: '2016192',
      name: 'Nakamura, Hikaru',
      federation: 'USA',
      sex: 'm',
      title: 'GM',
      standard: 2792,
      rapid: 2738,
      blitz: 2800,
      birthYear: '1987',
    );
    final p = r.applyTo(
      Player(id: 'p', name: 'Hikaru Nakamura', birthDate: '1987-12-09'),
      month: '2026-10',
    );
    expect(p.fideId, '2016192');
    expect(p.fideStandard, 2792);
    expect(p.title, 'GM');
    expect(p.birthDate, '1987-12-09', reason: 'a fuller date is kept');
    expect(p.fideEvidence['list'], '2026-10');
  });
}
