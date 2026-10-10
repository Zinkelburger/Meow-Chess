import 'model.dart';
import 'us_chess.dart';

/// FIDE rules that do not depend on a file format.
///
/// Sources, saved under `research/local` (see `research/notes/FIDE.md`):
/// - TRF-2026 (`fide-trf26-spec.txt`): player identity fields, ranking
///   methods (record 172).
/// - Rating Regulations B.02 (standard, 2024) and the rapid and blitz
///   regulations: rating categories by playing time for 60 moves.
/// - General handling rules for Swiss tournaments C.04.2: initial ranking.

/// FIDE titles in C.04.2 order (a higher title ranks first among equal
/// ratings). TRF 001 writes them as listed.
const fideTitles = ['GM', 'IM', 'WGM', 'FM', 'WIM', 'CM', 'WFM', 'WCM'];

/// The title order for initial ranking; untitled players rank last.
int fideTitleRank(String title) {
  final i = fideTitles.indexOf(title.trim().toUpperCase());
  return i < 0 ? fideTitles.length : i;
}

/// US Chess member records carry FIDE titles as single letters
/// (`fideTitle: "G"`); FIDE's own lists use the two- or three-letter form.
String fideTitleFromCode(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  return switch (c) {
    'G' || 'GM' => 'GM',
    'I' || 'M' || 'IM' => 'IM',
    'F' || 'FM' => 'FM',
    'C' || 'CM' => 'CM',
    'WG' || 'WGM' => 'WGM',
    'WI' || 'WM' || 'WIM' => 'WIM',
    'WF' || 'WFM' => 'WFM',
    'WC' || 'WCM' => 'WCM',
    _ => '',
  };
}

/// A FIDE ID: digits only, at most eleven (TRF 001 positions 58–68).
bool isFideId(String s) => RegExp(r'^[1-9]\d{0,10}$').hasMatch(s);

/// A three-letter FIDE federation code.
bool isFederationCode(String s) => RegExp(r'^[A-Z]{3}$').hasMatch(s);

/// `YYYY` or `YYYY-MM-DD`, the forms FIDE's lists and TRF accept.
bool isFideBirthDate(String s) {
  if (RegExp(r'^\d{4}$').hasMatch(s)) return true;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final parsed = DateTime.tryParse(s);
  return parsed != null && parsed.toIso8601String().startsWith(s);
}

/// The birth date as TRF 001 writes it (`YYYY/MM/DD`, or `YYYY/00/00` when
/// only the year is known).
String trfBirthDate(String birthDate) {
  if (RegExp(r'^\d{4}$').hasMatch(birthDate)) return '$birthDate/00/00';
  return birthDate.replaceAll('-', '/');
}

/// FIDE's three rating lists. A game is rated in the list its time control
/// falls in.
enum FideCategory {
  standard('Standard'),
  rapid('Rapid'),
  blitz('Blitz');

  const FideCategory(this.label);
  final String label;
}

/// B.02 and the rapid and blitz regulations: the category of a time
/// control by each player's time for 60 moves (base time plus 60 times the
/// increment; FIDE treats delay as increment). Null when FIDE rates no
/// game at this control (3 minutes or less).
FideCategory? fideCategory(TimeControl tc) {
  final total = tc.totalMinutes;
  if (total >= 60) return FideCategory.standard;
  if (total > 10) return FideCategory.rapid;
  if (total > 3) return FideCategory.blitz;
  return null;
}

/// The category for [section]'s time control, or null when it cannot be
/// parsed or FIDE rates none.
FideCategory? sectionFideCategory(Event event, Section section) {
  try {
    return fideCategory(TimeControl.parse(section.effectiveTimeControl(event)));
  } on TournamentException {
    return null;
  }
}

/// [player]'s published FIDE rating in [category]; zero when unrated.
int fideRating(Player player, FideCategory? category) => switch (category) {
  FideCategory.standard || null => player.fideStandard,
  FideCategory.rapid => player.fideRapid,
  FideCategory.blitz => player.fideBlitz,
};

/// TRF record 172 ranking methods: how the rating that sets pairing
/// numbers is chosen when players also hold a national rating.
const fideRankingMethods = {
  'FIDON': 'FIDE rating, then US Chess rating if none',
  'FIDE': 'FIDE rating only',
  'NIDOF': 'US Chess rating, then FIDE rating if none',
  'HBFN': 'Higher of FIDE and US Chess',
  'LBFN': 'Lower of FIDE and US Chess',
};

/// The section's ranking method: its own choice, else FIDE first with the
/// US Chess rating for players FIDE has not rated (dual-rated), or FIDE
/// only (FIDE-only sections).
String fideRankingMethod(Section section) =>
    fideRankingMethods.containsKey(section.fideRanking)
    ? section.fideRanking
    : section.unrated
    ? 'FIDE'
    : 'FIDON';

/// The rating that orders [player] for a FIDE-rated [section]'s pairing
/// numbers (C.04.2 with TRF record 172).
int fideRankingRating(Event event, Section section, Player player) {
  final fide = fideRating(player, sectionFideCategory(event, section));
  final national = player.effectivePairingRating;
  return switch (fideRankingMethod(section)) {
    'FIDE' => fide,
    'NIDOF' => national > 0 ? national : fide,
    'HBFN' => fide > national ? fide : national,
    'LBFN' =>
      fide == 0
          ? national
          : national == 0
          ? fide
          : (fide < national ? fide : national),
    _ => fide > 0 ? fide : national,
  };
}

/// C.04.2: initial ranking by rating, then title, then name.
int compareFideRanking(Event event, Section section, Player a, Player b) {
  final ra = fideRankingRating(event, section, a),
      rb = fideRankingRating(event, section, b);
  if (ra != rb) return rb.compareTo(ra);
  final ta = fideTitleRank(a.title), tb = fideTitleRank(b.title);
  if (ta != tb) return ta.compareTo(tb);
  final byName = compareNames(a.name, b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}

/// The section's players in FIDE pairing-number order. Before round 1 this
/// is C.04.2's initial ranking; once round 1 is posted the order recorded
/// then ([Section.fideOrder]) holds, and a late entry is placed before the
/// first player it outranks.
List<Player> fidePairingOrder(Event event, Section section) {
  final players = [for (final id in section.players) event.player(id)];
  int byRank(Player a, Player b) => compareFideRanking(event, section, a, b);
  if (section.rounds.isEmpty || section.fideOrder.isEmpty) {
    return players..sort(byRank);
  }
  final here = section.players.toSet();
  final order = [
    for (final id in section.fideOrder)
      if (here.contains(id)) event.player(id),
  ];
  final fixed = order.map((p) => p.id).toSet();
  final late = players.where((p) => !fixed.contains(p.id)).toList()
    ..sort(byRank);
  for (final p in late) {
    final at = order.indexWhere((q) => byRank(p, q) < 0);
    order.insert(at < 0 ? order.length : at, p);
  }
  return order;
}

/// Whether new Swiss, round-robin and quad sections start FIDE rated (FIDE
/// only), as FIDE's checklist asks of an endorsed program's FIDE mode
/// (VCL.01). Meow-Chess is a US Chess program first, so this is off; it is
/// the one switch to turn on for a FIDE-first build.
const fideModeDefault = false;

/// The formats FIDE rates here: each section is its own tournament.
const fideFormats = {Format.swiss, Format.roundRobin, Format.quad};

/// Why [after] cannot replace [before] once [before] has rounds: in a Swiss
/// FIDE rating chooses the pairing system, and the acceleration and the
/// pairing-allocated bye's value are announced before round 1 (C.04.2
/// 1.1, C.04.1 3). Null when the change is allowed.
String? fideSettingsChangeProblem(Section before, Section after) {
  if (before.rounds.isEmpty) return null;
  if (before.format == Format.swiss && after.fideRated != before.fideRated) {
    return 'FIDE rating changes the pairing system, so it is chosen before round 1.';
  }
  if (after.accelerated == 'baku' || before.accelerated == 'baku') {
    if (after.accelerated != before.accelerated) {
      return 'The Baku acceleration is announced before round 1 and cannot change once the section is paired.';
    }
  }
  if (after.pabPoints != before.pabPoints) {
    return 'The pairing-allocated bye’s value is announced before round 1 and cannot change once the section is paired.';
  }
  return null;
}

/// How a section is rated, as the director chooses it.
enum RatedBy {
  usChess('US Chess'),
  dual('US Chess + FIDE'),
  fide('FIDE'),
  none('Unrated');

  const RatedBy(this.label);
  final String label;

  static RatedBy of(Section s) =>
      s.fideRated ? (s.unrated ? fide : dual) : (s.unrated ? none : usChess);

  bool get usChessRated => this == usChess || this == dual;
  bool get fideRated => this == dual || this == fide;
}

/// Whether any section of [event] is FIDE rated, which brings FIDE identity
/// fields into the player panel and the FIDE report into Reports.
bool hasFideSection(Event event) => event.sections.any((s) => s.fideRated);

/// The name as FIDE lists it, `Lastname, Firstname`.
String fideName(Player p) {
  final report = playerReportName(p);
  if (report != null && report.contains(',')) {
    // US Chess report names are upper case; FIDE prefers the list's case.
    final parts = report.split(',');
    String title(String s) => s
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map(
          (w) => w.length <= 1
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
    return '${title(parts.first)}, ${title(parts.skip(1).join(','))}';
  }
  final words = p.name.trim().split(RegExp(r'\s+'));
  if (words.length < 2) return p.name.trim();
  return '${words.last}, ${words.take(words.length - 1).join(' ')}';
}

/// Problems with [p]'s FIDE fields that the stored model refuses.
String? fideFieldsProblem(Player p) {
  if (p.fideId.isNotEmpty && !isFideId(p.fideId)) {
    return 'A FIDE ID is digits only, up to eleven.';
  }
  for (final r in [p.fideStandard, p.fideRapid, p.fideBlitz]) {
    if (r < 0 || r > 3500) return 'FIDE ratings must be between 0 and 3500.';
  }
  if (p.title.isNotEmpty && !fideTitles.contains(p.title)) {
    return 'FIDE titles are ${fideTitles.join(', ')}.';
  }
  if (p.federation.isNotEmpty && !isFederationCode(p.federation)) {
    return 'A FIDE federation is three capital letters, such as USA.';
  }
  if (p.birthDate.isNotEmpty && !isFideBirthDate(p.birthDate)) {
    return 'Write the birth date as YYYY or YYYY-MM-DD.';
  }
  if (p.sex.isNotEmpty && p.sex != 'm' && p.sex != 'w') {
    return 'Sex is recorded as m or w, as FIDE lists it.';
  }
  return null;
}
