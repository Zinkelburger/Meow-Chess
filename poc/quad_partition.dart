// Planning experiment only. Not an application or production pairing engine.
// Checks the proposed group-size policy and the four possible final-round
// color choices for the US Chess 30G quad schedule. No files/network/data stores.

List<int> groupSizes(int entrants) {
  if (entrants < 4) {
    throw ArgumentError.value(entrants, 'entrants', 'TD choice');
  }
  final remainder = entrants % 4;
  if (remainder == 0) return List.filled(entrants ~/ 4, 4);
  final swissSize = 4 + remainder;
  return [...List.filled((entrants - swissSize) ~/ 4, 4), swissSize];
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  var checked = 0;
  for (var count = 4; count <= 500; count++) {
    final sizes = groupSizes(count);
    require(sizes.fold(0, (sum, size) => sum + size) == count, 'Lost entrant');
    require(sizes.every((size) => size >= 4 && size <= 7), 'Invalid section');
    require(
      sizes.take(sizes.length - 1).every((s) => s == 4),
      'Non-final Swiss',
    );
    require(sizes.where((s) => s != 4).length <= 1, 'Multiple bottom sections');
    require(
      sizes.last == (count % 4 == 0 ? 4 : 4 + count % 4),
      'Wrong remainder',
    );
    checked++;
  }
  for (var count = 0; count < 4; count++) {
    var rejected = false;
    try {
      groupSizes(count);
    } on ArgumentError {
      rejected = true;
    }
    require(rejected, 'Tiny fields require a TD decision');
  }

  // Record each toss outcome in a real event; no runtime randomness here.
  for (var toss = 0; toss < 4; toss++) {
    final rounds = <List<(int, int)>>[
      [(1, 4), (2, 3)],
      [(3, 1), (4, 2)],
      [toss & 1 == 0 ? (1, 2) : (2, 1), toss & 2 == 0 ? (3, 4) : (4, 3)],
    ];
    final pairs = <String>{};
    final whiteCount = List.filled(5, 0);
    for (final round in rounds) {
      final scheduled = <int>{};
      for (final (white, black) in round) {
        require(scheduled.add(white) && scheduled.add(black), 'Double booking');
        whiteCount[white]++;
        final low = white < black ? white : black;
        final high = white > black ? white : black;
        require(pairs.add('$low-$high'), 'Repeat opponent');
      }
      require(scheduled.length == 4, 'Missing player in round');
    }
    require(pairs.length == 6, 'Incomplete quad');
    require(
      whiteCount.skip(1).every((n) => n == 1 || n == 2),
      'Color imbalance',
    );
  }
  print(
    'PASS: $checked field sizes; 4 tiny-field rejections; 4 color choices.',
  );
  for (final count in [5, 6, 7, 9, 10, 11, 20, 21, 22, 23, 24]) {
    print('$count entrants: ${groupSizes(count).join(' + ')}');
  }
}
