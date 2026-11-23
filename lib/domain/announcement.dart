import 'model.dart';

/// What a club's event page announces about the tournament, as far as it
/// could be read. A field the page did not state is zero, null or empty;
/// nothing here is trusted until the director has seen it in Set up.
class Announcement {
  const Announcement({
    this.rounds = 0,
    this.format,
    this.timeControl = '',
    this.playUpLimit = 0,
    this.mergeBelow = 0,
  });

  /// Announced number of rounds ("4SS" is 4); zero when not stated.
  final int rounds;

  /// Swiss for "SS", round robin for "RR"; null when not stated.
  final Format? format;

  /// As the page writes it ("G/60 d5"); empty when not stated.
  final String timeControl;

  /// "Players rated within 200 points of the lower section maximum may play
  /// up one section" is 200; zero when the page has no such rule.
  final int playUpLimit;

  /// "Sections with fewer than eight players may be merged" is 8; zero
  /// when the page has no such rule.
  final int mergeBelow;

  bool get isEmpty =>
      rounds == 0 &&
      format == null &&
      timeControl.isEmpty &&
      playUpLimit == 0 &&
      mergeBelow == 0;

  /// The format line as a director reads it: "4 rounds · G/60 d5".
  String get summary => [
    if (rounds > 0) '$rounds ${rounds == 1 ? 'round' : 'rounds'}',
    if (timeControl.isNotEmpty) timeControl,
  ].join(' · ');

  Json toJson() => {
    if (rounds > 0) 'rounds': rounds,
    if (format != null) 'format': format!.name,
    if (timeControl.isNotEmpty) 'timeControl': timeControl,
    if (playUpLimit > 0) 'playUpLimit': playUpLimit,
    if (mergeBelow > 0) 'mergeBelow': mergeBelow,
  };

  factory Announcement.fromJson(Map<dynamic, dynamic> j) => Announcement(
    rounds: (j['rounds'] ?? 0) as int,
    format: Format.values.where((f) => f.name == j['format']).firstOrNull,
    timeControl: (j['timeControl'] ?? '') as String,
    playUpLimit: (j['playUpLimit'] ?? 0) as int,
    mergeBelow: (j['mergeBelow'] ?? 0) as int,
  );

  /// The announcement saved with [event]'s roster source, or null.
  static Announcement? of(Event event) {
    final saved = event.rosterSource['announced'];
    if (saved is! Map) return null;
    final announcement = Announcement.fromJson(saved);
    return announcement.isEmpty ? null : announcement;
  }
}
