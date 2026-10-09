/// Whether an entered name plausibly belongs to the US Chess member found
/// for its ID. It exists to catch a wrong ID (somebody else entirely), so it
/// forgives nicknames, initials, word order and a single typo. When US Chess
/// gives a last name, the entered name must contain something close to it.
bool namesLookAlike(String entered, String official, {String? lastName}) {
  final mine = _words(entered);
  final theirs = _words(
    lastName == null || lastName.trim().isEmpty ? official : lastName,
  );
  if (mine.isEmpty || theirs.isEmpty) return true;
  // Particles are shared by unrelated people, so they are no evidence,
  // unless one side is nothing else (the surname Le).
  final a = _core(mine), b = _core(theirs);
  if (a.isNotEmpty && b.isNotEmpty) {
    return a.any((x) => b.any((y) => _close(x, y)));
  }
  return mine.any((x) => theirs.any((y) => _close(x, y)));
}

/// The last name in a `LAST, FIRST` rating-report name.
String? lastNameOf(String? reportName) {
  if (reportName == null || !reportName.contains(',')) return null;
  return reportName.split(',').first;
}

const _suffixes = {'jr', 'sr', 'ii', 'iii', 'iv'};

/// Name particles, as in "La Shawn Smith" and "Juan De La Cruz".
const _particles = {
  'da',
  'das',
  'de',
  'del',
  'della',
  'den',
  'der',
  'di',
  'do',
  'dos',
  'du',
  'la',
  'le',
  'st',
  'ter',
  'van',
  'von',
};

List<String> _words(String name) => name
    .toLowerCase()
    .split(RegExp(r"[^a-zÀ-ɏ']+"))
    .map((w) => w.replaceAll("'", ''))
    .where((w) => w.length > 1 && !_suffixes.contains(w))
    .toList();

List<String> _core(List<String> words) =>
    words.where((w) => !_particles.contains(w)).toList();

bool _close(String a, String b) {
  if (a == b) return true;
  final short = a.length < b.length ? a : b, long = a.length < b.length ? b : a;
  // "Alex" and "Alexander", "Rob" and "Robert".
  if (short.length >= 3 && long.startsWith(short)) return true;
  return short.length >= 4 && _withinOneEdit(short, long);
}

bool _withinOneEdit(String short, String long) {
  if (long.length - short.length > 1) return false;
  var i = 0, j = 0, edits = 0;
  while (i < short.length && j < long.length) {
    if (short[i] == long[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (short.length == long.length) i++;
    j++;
  }
  return edits + (long.length - j) + (short.length - i) <= 1;
}
