// Where every word of a generated PDF lands. The pdf package writes each
// word as its own text run, places it with `cm` transforms, and clips table
// cells with `re W n`; fonts carry their widths. Interpreting those few
// operators gives each word's box exactly, with no renderer.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class Box {
  const Box(this.left, this.bottom, this.right, this.top);
  final double left, bottom, right, top;
  Box intersect(Box o) => Box(
    max(left, o.left),
    max(bottom, o.bottom),
    min(right, o.right),
    min(top, o.top),
  );
  @override
  String toString() =>
      '[${left.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)} – '
      '${right.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}]';
}

/// One word as printed: its text, page, baseline, horizontal extent, size,
/// and the clip rectangle it was drawn in (null when unclipped).
class Run {
  Run(this.text, this.page, this.x0, this.x1, this.y, this.size, this.clip);
  final String text;
  final int page;
  final double x0, x1, y, size;
  final Box? clip;
  @override
  String toString() =>
      '"$text" p$page x ${x0.toStringAsFixed(1)}–${x1.toStringAsFixed(1)} '
      'y ${y.toStringAsFixed(1)}${clip == null ? '' : ' clip $clip'}';
}

class PdfPage {
  PdfPage(this.width, this.height, this.runs);
  final double width, height;
  final List<Run> runs;
}

/// Affine matrix [a b c d e f], as PDF writes it.
typedef _M = List<double>;
_M _mul(_M m, _M n) => [
  m[0] * n[0] + m[1] * n[2],
  m[0] * n[1] + m[1] * n[3],
  m[2] * n[0] + m[3] * n[2],
  m[2] * n[1] + m[3] * n[3],
  m[4] * n[0] + m[5] * n[2] + n[4],
  m[4] * n[1] + m[5] * n[3] + n[5],
];
const _M _identity = [1, 0, 0, 1, 0, 0];
(double, double) _apply(_M m, double x, double y) =>
    (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);

List<PdfPage> pdfPages(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final objects = <int, String>{
    for (final m in RegExp(
      r'(\d+) 0 obj\s*(.*?)endobj',
      dotAll: true,
    ).allMatches(raw))
      int.parse(m[1]!): m[2]!,
  };
  String stream(String body) {
    final m = RegExp(
      r'^(.*?)stream\r?\n(.*)\r?\nendstream',
      dotAll: true,
    ).firstMatch(body)!;
    final data = latin1.encode(m[2]!);
    return latin1.decode(
      m[1]!.contains('/FlateDecode') ? zlib.decode(data) : data,
    );
  }

  // An object reference stands for the object; widths arrays use them.
  String resolve(String text) => text.replaceAllMapped(
    RegExp(r'(\d+) 0 R'),
    (m) => objects[int.parse(m[1]!)]?.trim() ?? m[0]!,
  );
  final fontsById = <int, _Font>{};
  for (final MapEntry(key: id, value: body) in objects.entries) {
    if (!body.contains('/Type/Font') || body.contains('/Type/FontDescriptor')) {
      continue;
    }
    if (body.contains('/Subtype/Type0')) {
      // An embedded font: two-byte glyph codes, widths in /W, text through
      // the /ToUnicode map.
      final widths = <int, double>{};
      String? w;
      final at = body.indexOf('/W[');
      if (at >= 0) {
        var depth = 0, end = at + 2;
        do {
          if (body[end] == '[') depth++;
          if (body[end] == ']') depth--;
          end++;
        } while (depth > 0);
        w = body.substring(at + 3, end - 1);
      }
      if (w != null) {
        final tokens = RegExp(
          r'\[[^\]]*\]|[-\d.]+',
        ).allMatches(resolve(w)).map((m) => m[0]!).toList();
        for (var i = 0; i < tokens.length;) {
          final first = int.parse(tokens[i]);
          if (tokens[i + 1].startsWith('[')) {
            final list = tokens[i + 1]
                .substring(1, tokens[i + 1].length - 1)
                .trim()
                .split(RegExp(r'\s+'));
            for (final (k, v) in list.indexed) {
              widths[first + k] = double.parse(v);
            }
            i += 2;
          } else {
            for (var c = first; c <= int.parse(tokens[i + 1]); c++) {
              widths[c] = double.parse(tokens[i + 2]);
            }
            i += 3;
          }
        }
      }
      final unicode = <int, String>{};
      final map = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(body)?[1];
      if (map != null) {
        final cmap = stream(objects[int.parse(map)]!);
        String text(String hex) => String.fromCharCodes([
          for (var i = 0; i + 4 <= hex.length; i += 4)
            int.parse(hex.substring(i, i + 4), radix: 16),
        ]);
        for (final m
            in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(
              RegExp(
                r'beginbfchar(.*?)endbfchar',
                dotAll: true,
              ).allMatches(cmap).map((m) => m[1]!).join(),
            )) {
          unicode[int.parse(m[1]!, radix: 16)] = text(m[2]!);
        }
      }
      fontsById[id] = _Font.cid(
        widths,
        double.parse(RegExp(r'/DW (\d+)').firstMatch(body)?[1] ?? '1000'),
        unicode,
      );
    } else {
      final first = int.parse(
        RegExp(r'/FirstChar (\d+)').firstMatch(body)?[1] ?? '0',
      );
      final list = RegExp(r'/Widths\[([^\]]*)\]').firstMatch(body)?[1];
      fontsById[id] = _Font.simple(
        first,
        list == null
            ? const []
            : list.trim().split(RegExp(r'\s+')).map(double.parse).toList(),
      );
    }
  }
  final pages = <PdfPage>[];
  for (final body in objects.values) {
    if (!RegExp(r'/Type/Page[^s]').hasMatch(body)) continue;
    final box = RegExp(
      r'/MediaBox\[([^\]]*)\]',
    ).firstMatch(body)![1]!.trim().split(RegExp(r'\s+')).map(double.parse);
    final fonts = <String, int>{
      for (final m in RegExp(
        r'/(F\d+) (\d+) 0 R',
      ).allMatches(RegExp(r'/Font<<(.*?)>>').firstMatch(body)?[1] ?? ''))
        m[1]!: int.parse(m[2]!),
    };
    final contents = RegExp(r'(\d+) 0 R').allMatches(
      RegExp(r'/Contents\s*(\[[^\]]*\]|\d+ 0 R)').firstMatch(body)![1]!,
    );
    final runs = <Run>[];
    for (final c in contents) {
      _interpret(stream(objects[int.parse(c[1]!)]!), pages.length + 1, {
        for (final f in fonts.entries) f.key: fontsById[f.value]!,
      }, runs);
    }
    pages.add(PdfPage(box.elementAt(2), box.elementAt(3), runs));
  }
  return pages;
}

final _token = RegExp(
  r'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|/[^\s/\[\]()<>]+|\[|\]|[-+]?(?:\d+\.?\d*|\.\d+)|[A-Za-z*\x27"]+',
);

/// A font's widths and, for an embedded font, how its codes read as text.
class _Font {
  _Font.simple(this.first, this.list)
    : cid = false,
      widths = const {},
      fallback = 600,
      unicode = const {};
  _Font.cid(this.widths, this.fallback, this.unicode)
    : cid = true,
      first = 0,
      list = const [];
  final bool cid;
  final int first;
  final List<double> list;
  final Map<int, double> widths;
  final double fallback;
  final Map<int, String> unicode;

  List<int> codes(List<int> bytes) => cid
      ? [
          for (var i = 0; i + 1 < bytes.length; i += 2)
            bytes[i] << 8 | bytes[i + 1],
        ]
      : bytes;
  double width(int code) => cid
      ? widths[code] ?? fallback
      : (code - first >= 0 && code - first < list.length
            ? list[code - first]
            : fallback);
  String text(int code) =>
      cid ? unicode[code] ?? '\uFFFD' : String.fromCharCode(code);
}

/// The bytes of a string operand, before any font gives them meaning.
class _Bytes {
  const _Bytes(this.bytes);
  final List<int> bytes;
}

String _unescape(String s) => s
    .substring(1, s.length - 1)
    .replaceAllMapped(
      RegExp(r'\\([0-7]{1,3}|.)'),
      (m) => switch (m[1]!) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        final o when RegExp(r'^[0-7]+$').hasMatch(o) => String.fromCharCode(
          int.parse(o, radix: 8),
        ),
        final c => c,
      },
    );

void _interpret(
  String content,
  int page,
  Map<String, _Font> fonts,
  List<Run> out,
) {
  var ctm = _identity, tm = _identity, tlm = _identity;
  Box? clip;
  Box? pendingClip;
  final stack = <(_M, Box?)>[];
  String? font;
  var size = 0.0, spacing = 0.0;
  final operands = <Object>[];
  List<Object>? array;
  void show(List<Object> parts) {
    var advance = 0.0;
    final text = StringBuffer();
    final f = fonts[font] ?? _Font.simple(0, const []);
    for (final p in parts) {
      if (p is _Bytes) {
        for (final code in f.codes(p.bytes)) {
          advance += f.width(code) / 1000 * size + spacing;
          text.write(f.text(code));
        }
      } else if (p is double) {
        advance -= p / 1000 * size;
      }
    }
    final m = _mul(tm, ctm);
    final (x0, y) = _apply(m, 0, 0);
    final (x1, _) = _apply(m, advance, 0);
    final word = text.toString();
    if (word.trim().isNotEmpty) {
      out.add(Run(word, page, min(x0, x1), max(x0, x1), y, size * m[3], clip));
    }
    tm = _mul([1, 0, 0, 1, advance, 0], tm);
  }

  for (final m in _token.allMatches(content)) {
    final t = m[0]!;
    if (t == '[') {
      array = [];
      continue;
    }
    if (t == ']') {
      operands.add(array!);
      array = null;
      continue;
    }
    final value = t.startsWith('(')
        ? _Bytes(latin1.encode(_unescape(t)))
        : t.startsWith('<')
        ? _Bytes([
            for (
              var hex = t.replaceAll(RegExp(r'[<>\s]'), ''), i = 0;
              i + 2 <= hex.length;
              i += 2
            )
              int.parse(hex.substring(i, i + 2), radix: 16),
          ])
        : t.startsWith('/')
        ? t
        : double.tryParse(t);
    if (value != null) {
      (array ?? operands).add(value);
      continue;
    }
    double n(int i) => operands[operands.length - i] as double;
    switch (t) {
      case 'q':
        stack.add((ctm, clip));
      case 'Q':
        (ctm, clip) = stack.removeLast();
      case 'cm':
        ctm = _mul([n(6), n(5), n(4), n(3), n(2), n(1)], ctm);
      case 're':
        final (ax, ay) = _apply(ctm, n(4), n(3));
        final (bx, by) = _apply(ctm, n(4) + n(2), n(3) + n(1));
        pendingClip = Box(min(ax, bx), min(ay, by), max(ax, bx), max(ay, by));
      case 'W':
        if (pendingClip != null) {
          clip = clip == null ? pendingClip : clip.intersect(pendingClip);
        }
      case 'BT':
        tm = tlm = _identity;
      case 'Tf':
        font = (operands[operands.length - 2] as String).substring(1);
        size = n(1);
      case 'Tc':
        spacing = n(1);
      case 'Td' || 'TD':
        tlm = _mul([1, 0, 0, 1, n(2), n(1)], tlm);
        tm = tlm;
      case 'Tm':
        tlm = tm = [n(6), n(5), n(4), n(3), n(2), n(1)];
      case 'TJ':
        show(operands.last as List<Object>);
      case 'Tj':
        show([operands.last]);
    }
    operands.clear();
  }
}

/// The ways printed words go wrong: off the page, cut off by their cell, or
/// printed over each other. Each entry says which word and where.
List<String> layoutProblems(List<PdfPage> pages) {
  const slack = 0.5;
  final problems = <String>[];
  for (final p in pages) {
    for (final r in p.runs) {
      if (r.x0 < -slack ||
          r.x1 > p.width + slack ||
          r.y < -slack ||
          r.y > p.height + slack) {
        problems.add('off the page: $r');
      }
      final c = r.clip;
      if (c != null &&
          (r.x0 < c.left - slack ||
              r.x1 > c.right + slack ||
              r.y < c.bottom - r.size * 0.25 ||
              r.y > c.top)) {
        problems.add('cut off by its cell: $r');
      }
    }
    final lines = <int, List<Run>>{};
    for (final r in p.runs) {
      (lines[(r.y * 2).round()] ??= []).add(r);
    }
    for (final line in lines.values) {
      line.sort((a, b) => a.x0.compareTo(b.x0));
      for (var i = 1; i < line.length; i++) {
        final a = line[i - 1], b = line[i];
        if (b.x0 < a.x1 - slack) problems.add('overlapping: $a and $b');
      }
    }
  }
  return problems;
}
