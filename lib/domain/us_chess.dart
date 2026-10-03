import 'model.dart';

/// US Chess reporting rules that do not depend on a file format.
///
/// Sources, saved under `research/local`:
/// - Official Rules of Chess, 7th edition, rule 5C (`uscf-rules-2026.txt`):
///   rating categories from total playing time.
/// - Rating report upload format 2C with the September 2025 character-field
///   correction (`uscf-fileformat.txt`): field contents and widths.

enum RatingCategory {
  regular('R', 'Regular'),
  dual('D', 'Dual (Regular and Quick)'),
  quick('Q', 'Quick'),
  blitz(null, 'Blitz');

  const RatingCategory(this.code, this.label);

  /// The rule 5C category letter. 2C defines none for Blitz; see
  /// [reportSystemCode] for what the report file carries.
  final String? code;

  /// The 2C `S_R_SYSTEM` value. US Chess derives the category from
  /// `S_TIMECTL`, not from this letter: SwissSys sends `R` for dual events and
  /// `D` for blitz, and both were rated by time control (Fall Equinox Swiss
  /// 202609190383 rated dual; Rated Friday Night Blitz 202604280273 rated
  /// blitz from `D`). 2C lists only R/D/Q, so Blitz uses the `D` that was
  /// accepted rather than an untested `B`.
  String get reportSystemCode => code ?? 'D';
  final String label;
}

/// A parsed time control: zero or more `moves/minutes` stages, then one sudden
/// death stage, then an optional delay or increment in seconds.
class TimeControl {
  const TimeControl._(this.stages, this.bonusKind, this.bonusSeconds);

  /// `(moves, minutes)`; the last stage is sudden death (`moves == null`).
  final List<(int?, int)> stages;

  /// `'d'` for delay, `'inc'` for increment, or null when none was stated.
  final String? bonusKind;
  final int bonusSeconds;

  static final _separator = RegExp(r'[\s,;]+');
  static final _moves = RegExp(r'(\d{1,3})\s*/\s*(\d{1,3})');
  static final _suddenDeath = RegExp(r'(?:GAME|SD|G)\s*/?\s*(\d{1,3})');
  static final _delay = RegExp(
    r'(?:DELAY|D)\s*/?\s*(\d{1,3})(?:\s*(?:SECONDS|SECOND|SECS|SEC|S))?',
  );
  static final _increment = RegExp(
    r'(?:(?:INCREMENT|INC)\s*/?\s*|\+\s*)(\d{1,3})(?:\s*(?:SECONDS|SECOND|SECS|SEC|S))?',
  );

  static const examples = 'G/60 d/5, G/90 inc/30 or 40/90, SD/30 d/5';

  /// Accepts the rulebook's notations (rule 5B2), such as `G/90 inc/30`,
  /// `G/90;+30`, `G/60;d5`, `Game/45` and `40/90, SD/30 d/5`.
  static TimeControl parse(String text) {
    final s = text.trim().toUpperCase();
    final stages = <(int?, int)>[];
    String? kind;
    var seconds = 0, at = 0;
    TournamentException invalid() => TournamentException(
      'Time control "${text.trim()}" is not in a form US Chess reports use. '
      'Enter it like $examples.',
    );
    bool boundary(int end) =>
        end == s.length ||
        _separator.matchAsPrefix(s, end) != null ||
        s[end] == '+';
    while (at < s.length) {
      final skip = _separator.matchAsPrefix(s, at);
      if (skip != null) {
        at = skip.end;
        continue;
      }
      final done = stages.isNotEmpty && stages.last.$1 == null;
      Match? m;
      if (!done &&
          (m = _moves.matchAsPrefix(s, at)) != null &&
          boundary(m!.end)) {
        stages.add((int.parse(m[1]!), int.parse(m[2]!)));
      } else if (!done &&
          (m = _suddenDeath.matchAsPrefix(s, at)) != null &&
          // SwissSys also writes the compact `G90d5`.
          (boundary(m!.end) || _delay.matchAsPrefix(s, m.end) != null)) {
        stages.add((null, int.parse(m[1]!)));
      } else if (done &&
          kind == null &&
          (m = _delay.matchAsPrefix(s, at)) != null &&
          boundary(m!.end)) {
        kind = 'd';
        seconds = int.parse(m[1]!);
      } else if (done &&
          kind == null &&
          (m = _increment.matchAsPrefix(s, at)) != null &&
          boundary(m!.end)) {
        kind = 'inc';
        seconds = int.parse(m[1]!);
      } else {
        throw invalid();
      }
      at = m.end;
    }
    if (stages.isEmpty ||
        stages.last.$1 != null ||
        stages.any((x) => x.$2 < 1 || (x.$1 ?? 1) < 1)) {
      throw invalid();
    }
    return TimeControl._(List.unmodifiable(stages), kind, seconds);
  }

  /// Rule 5C: minutes of every control plus the delay or increment seconds.
  int get totalMinutes =>
      stages.fold<int>(0, (n, x) => n + x.$2) + bonusSeconds;
  int get primaryMinutes => stages.first.$2;

  /// Rule 5C categories, or null when the time control is not ratable.
  RatingCategory? get category {
    final total = totalMinutes, primary = primaryMinutes;
    if (total > 10 && primary < 5) return null;
    if (total > 65) return RatingCategory.regular;
    if (total >= 30) return RatingCategory.dual;
    if (total > 10) return RatingCategory.quick;
    if (total >= 5 && primary >= 3) return RatingCategory.blitz;
    return null;
  }

  /// The 2C `S_TIMECTL` form: `Game/nnn` for sudden death (as the format
  /// asks), other stages as in its `40/90, SD/30` example, and the rulebook's
  /// `d/5` or `inc/30` for delay and increment.
  String get reportText {
    final base = stages.length == 1
        ? 'Game/${stages.single.$2}'
        : [
            for (final (moves, minutes) in stages)
              moves == null ? 'SD/$minutes' : '$moves/$minutes',
          ].join(', ');
    return bonusKind == null ? base : '$base $bonusKind/$bonusSeconds';
  }

  /// The spelling US Chess itself stores for every rated section (`G/60;d5`,
  /// `G/90;+30`, `40/90,SD/30;d5`; `;d0` when there is no delay). Written to
  /// `S_TIMECTL` so the rating system reads its own canonical form back.
  String get uscfText {
    final base = stages.length == 1
        ? 'G/${stages.single.$2}'
        : [
            for (final (moves, minutes) in stages)
              moves == null ? 'SD/$minutes' : '$moves/$minutes',
          ].join(',');
    return '$base;${bonusKind == 'inc' ? '+' : 'd'}$bonusSeconds';
  }
}

const _fold = {
  'ÀÁÂÃÄÅĀĂĄǍ': 'A',
  'àáâãäåāăąǎª': 'a',
  'ÇĆĈĊČ': 'C',
  'çćĉċč': 'c',
  'ĎĐÐ': 'D',
  'ďđð': 'd',
  'ÈÉÊËĒĔĖĘĚ': 'E',
  'èéêëēĕėęě': 'e',
  'ĜĞĠĢ': 'G',
  'ĝğġģ': 'g',
  'ĤĦ': 'H',
  'ĥħ': 'h',
  'ÌÍÎÏĨĪĬĮİǏ': 'I',
  'ìíîïĩīĭįıǐ': 'i',
  'Ĵ': 'J',
  'ĵ': 'j',
  'Ķ': 'K',
  'ķ': 'k',
  'ĹĻĽĿŁ': 'L',
  'ĺļľŀł': 'l',
  'ÑŃŅŇ': 'N',
  'ñńņňŉ': 'n',
  'ÒÓÔÕÖØŌŎŐǑ': 'O',
  'òóôõöøōŏőǒº': 'o',
  'ŔŖŘ': 'R',
  'ŕŗř': 'r',
  'ŚŜŞŠȘ': 'S',
  'śŝşšș': 's',
  'ŢŤŦȚ': 'T',
  'ţťŧț': 't',
  'ÙÚÛÜŨŪŬŮŰŲǓ': 'U',
  'ùúûüũūŭůűųǔ': 'u',
  'Ŵ': 'W',
  'ŵ': 'w',
  'ÝŸŶ': 'Y',
  'ýÿŷ': 'y',
  'ŹŻŽ': 'Z',
  'źżž': 'z',
  'Æ': 'AE',
  'æ': 'ae',
  'Œ': 'OE',
  'œ': 'oe',
  'ß': 'ss',
  'Þ': 'TH',
  'þ': 'th',
  'Ĳ': 'IJ',
  'ĳ': 'ij',
  '‘’ʼ´`“”„«»': "'",
  '‐‑‒–—−': '-',
  '½': '1/2',
  '…': '...',
  '\u00a0\u2002\u2003\u2009\u202f': ' ',
};
final _foldMap = {
  for (final e in _fold.entries)
    for (final c in e.key.runes) c: e.value,
};

/// Plain ASCII for a report field: accented Latin letters lose their accents,
/// typographic punctuation becomes its ASCII form and runs of whitespace
/// collapse. Null when a character has no ASCII spelling.
String? reportText(String text) {
  final out = StringBuffer();
  for (final c in text.runes) {
    if (c >= 0x300 && c <= 0x36f) continue; // Combining accents.
    final mapped = _foldMap[c];
    if (mapped != null) {
      out.write(mapped);
    } else if (c == 9 || c == 10 || c == 13) {
      out.write(' ');
    } else if (c >= 32 && c <= 126) {
      out.writeCharCode(c);
    } else {
      return null;
    }
  }
  return out.toString().replaceAll(RegExp(r' +'), ' ').trim();
}

/// Characters kept out of free-text report fields. The DBF format can hold
/// them, but they have no use in names and are the ones most likely to be
/// mishandled by quoting or markup downstream.
final _unsafe = RegExp(r'["\\|`~^<>{}\[\]*]');
String? unsafeCharacter(String text) => _unsafe.firstMatch(text)?[0];

final _nameCharacters = RegExp(r"^[A-Z0-9 ,.'-]+$");
const _suffixes = {'JR', 'SR', 'II', 'III', 'IV'};
const _particles = {
  'DA',
  'DAS',
  'DE',
  'DEL',
  'DELLA',
  'DEN',
  'DER',
  'DI',
  'DO',
  'DOS',
  'DU',
  'LA',
  'LE',
  'ST',
  'TER',
  'VAN',
  'VON',
};

/// The 2C `D_NAME` form, `LAST, FIRST` in capitals ("SMITH, JOHN"), from a
/// player's name as entered. A name that already has a comma is taken as
/// `Last, First`. Null when the name has no ASCII spelling.
String? reportName(String name) {
  final text = reportText(name)?.toUpperCase();
  if (text == null || text.isEmpty) return null;
  String clean(String s) => s.replaceAll(RegExp(r'\s*,\s*'), ', ').trim();
  bool suffix(String s) => _suffixes.contains(s.replaceAll('.', '').trim());
  final comma = text.indexOf(',');
  if (comma >= 0 && !suffix(text.substring(comma + 1))) {
    if (text.substring(comma + 1).trim().isEmpty) {
      return text.substring(0, comma).trim();
    }
    return clean(
      '${text.substring(0, comma).trim()}, ${text.substring(comma + 1).trim()}',
    );
  }
  final words = text.replaceAll(',', ' ').split(' ')
    ..removeWhere((w) => w.isEmpty);
  final end = words.length > 2 && suffix(words.last)
      ? words.length - 1
      : words.length;
  if (end == 1) return words.join(' ');
  var start = end - 1;
  while (start > 1 &&
      _particles.contains(words[start - 1].replaceAll('.', ''))) {
    start--;
  }
  return [
    '${words.sublist(start, end).join(' ')}, ${words.sublist(0, start).join(' ')}',
    ...words.sublist(end),
  ].join(' ');
}

/// The problem with a `D_NAME` value, or null when it can be reported.
String? reportNameProblem(String? value) {
  if (value == null || value.isEmpty) return 'has no plain-letter spelling';
  if (value.length > 30) {
    return 'is ${value.length} characters on the rating report; US Chess allows 30';
  }
  if (!_nameCharacters.hasMatch(value)) {
    return 'may only use letters, digits, spaces and , . \' - on the rating report';
  }
  return null;
}

/// USPS codes for where a rated event can be held in the USA (H_STATE).
const usStates = {
  'AL',
  'AK',
  'AZ',
  'AR',
  'CA',
  'CO',
  'CT',
  'DE',
  'DC',
  'FL',
  'GA',
  'HI',
  'ID',
  'IL',
  'IN',
  'IA',
  'KS',
  'KY',
  'LA',
  'ME',
  'MD',
  'MA',
  'MI',
  'MN',
  'MS',
  'MO',
  'MT',
  'NE',
  'NV',
  'NH',
  'NJ',
  'NM',
  'NY',
  'NC',
  'ND',
  'OH',
  'OK',
  'OR',
  'PA',
  'RI',
  'SC',
  'SD',
  'TN',
  'TX',
  'UT',
  'VT',
  'VA',
  'WA',
  'WV',
  'WI',
  'WY',
  'PR',
  'VI',
  'GU',
  'AS',
  'MP',
  'AA',
  'AE',
  'AP',
};

/// A player's two-letter state. Any two letters are accepted because
/// US Chess membership records may carry codes outside [usStates].
bool isStateCode(String s) => RegExp(r'^[A-Z]{2}$').hasMatch(s);

/// Eight digits; `00000000` is the 2C placeholder for "ID unavailable".
bool isMemberId(String s) => RegExp(r'^\d{8}$').hasMatch(s) && s != '00000000';

/// Why [value] cannot be the comma-separated `H_OTHER_TD` list, or null.
String? otherTdProblem(String value) {
  if (value.trim().isEmpty) return null;
  final ids = otherTdList(value);
  if (ids.any((id) => !isMemberId(id))) {
    return 'Other TDs must be eight-digit US Chess IDs separated by commas.';
  }
  if (ids.join(',').length > 255) {
    return 'The other TDs list is longer than the report allows (255 characters).';
  }
  return null;
}

List<String> otherTdList(String value) => [
  for (final id in value.split(RegExp(r'[\s,;]+')))
    if (id.isNotEmpty) id,
];

/// US Chess affiliate IDs are the letter A and seven digits, e.g. A6051416.
bool isAffiliateId(String s) => RegExp(r'^A\d{7}$').hasMatch(s);

bool isZipCode(String s) =>
    RegExp(r'^\d{5}(-\d{4})?$').hasMatch(s) && !s.startsWith('00000');

/// 2C `S_SCH_LVL` values.
const sectionLevels = {
  'N': 'Not scholastic',
  'S': 'Scholastic',
  'P': 'Primary (Pre-K to grade 3 only)',
  'J': 'In-school JTP (Pre-K to grade 12 only)',
};

/// The `D_NAME` value for [p]: the TD's report name in capitals when given,
/// otherwise [reportName] of the player's name.
String? playerReportName(Player p) => p.reportName.trim().isNotEmpty
    ? reportText(p.reportName)?.toUpperCase()
    : reportName(p.name);
