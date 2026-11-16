// Plays a page's content stream the way a PDF viewer would, but instead of painting pixels it keeps
// what was drawn: every path with its pen (colour, width, dashes) and fill, every piece of text with
// its position, size and angle, and the layer each sat on. Coordinates are page points (1/72 inch),
// y upwards, after every transformation.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'pdf_file.dart';

/// A point on the page, in points
class P2 {
  const P2(this.x, this.y);
  final double x, y;
  P2 operator +(P2 o) => P2(x + o.x, y + o.y);
  P2 operator -(P2 o) => P2(x - o.x, y - o.y);
  P2 operator *(double k) => P2(x * k, y * k);
  double get length => math.sqrt(x * x + y * y);
  double dist(P2 o) => (this - o).length;
  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// A straight piece ([c1], [c2] null) or a cubic Bézier curve
class Seg {
  const Seg(this.a, this.b, [this.c1, this.c2]);
  final P2 a, b;
  final P2? c1, c2;
  bool get curved => c1 != null;

  P2 at(double t) {
    if (!curved) return a + (b - a) * t;
    final u = 1 - t;
    return a * (u * u * u) + c1! * (3 * u * u * t) + c2! * (3 * u * t * t) + b * (t * t * t);
  }

  double get length {
    if (!curved) return a.dist(b);
    var l = 0.0;
    var p = a;
    for (var i = 1; i <= 16; i++) {
      final q = at(i / 16);
      l += p.dist(q);
      p = q;
    }
    return l;
  }
}

class SubPath {
  SubPath(this.segs, this.closed);
  final List<Seg> segs;
  bool closed;
  P2 get start => segs.first.a;
  P2 get end => segs.last.b;
}

/// One painted path
class PaintedPath {
  PaintedPath({
    required this.subs,
    required this.stroke,
    required this.fill,
    required this.evenOdd,
    required this.strokeRgb,
    required this.fillRgb,
    required this.width,
    required this.dash,
    required this.layer,
    required this.order,
  });
  final List<SubPath> subs;
  final bool stroke, fill, evenOdd;

  /// 0xRRGGBB
  final int strokeRgb, fillRgb;

  /// pen width and dash lengths in points (scaled by the transformation)
  final double width;
  final List<double> dash;
  final String? layer;
  final int order;
}

/// One piece of text as it was shown
class ShownText {
  ShownText({
    required this.text,
    required this.origin,
    required this.height,
    required this.angle,
    required this.advance,
    required this.rgb,
    required this.font,
    required this.capHeight,
    required this.invisible,
    required this.layer,
    required this.order,
  });
  final String text;

  /// where the baseline starts, in points
  final P2 origin;

  /// the font size on the page, in points
  final double height;

  /// radians, anticlockwise from the x axis
  final double angle;

  /// how far the text runs along its baseline, in points
  final double advance;
  final int rgb;
  final String font;

  /// capital-letter height as a share of the font size (0.7 when the font doesn't say)
  final double capHeight;

  /// written with render mode 3 (e.g. the hidden text of a scanned page)
  final bool invisible;
  final String? layer;
  final int order;
}

/// What a page holds
class PageContent {
  PageContent(this.width, this.height);
  final double width, height;
  final paths = <PaintedPath>[];
  final texts = <ShownText>[];

  /// rectangles covered by pictures (scans, photos), in points: x0, y0, x1, y1
  final images = <List<double>>[];
}

// ---------------------------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------------------------

class _Font {
  _Font({
    required this.name,
    required this.twoByte,
    required this.toUnicode,
    required this.widths,
    required this.defaultWidth,
    required this.capHeight,
  });
  final String name;
  final bool twoByte;
  final Map<int, String> toUnicode;
  final Map<int, double> widths; // per 1000 units
  final double defaultWidth;
  final double capHeight;

  Iterable<(int, String)> codes(Uint8List b) sync* {
    if (twoByte) {
      for (var i = 0; i + 1 < b.length; i += 2) {
        final c = b[i] << 8 | b[i + 1];
        yield (c, toUnicode[c] ?? (c < 0x10000 && c >= 0x20 ? String.fromCharCode(c) : ''));
      }
    } else {
      for (final c in b) {
        yield (c, toUnicode[c] ?? _winAnsi(c));
      }
    }
  }

  double widthOf(int code) => (widths[code] ?? defaultWidth) / 1000;
}

const _win1252 = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, //
  0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
  0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
  0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
};

String _winAnsi(int c) {
  if (c < 0x20) return '';
  return String.fromCharCode(_win1252[c] ?? c);
}

/// Glyph names a Differences array uses, to their characters
String? _glyph(String name) {
  const named = {
    'space': ' ',
    'exclam': '!',
    'quotedbl': '"',
    'numbersign': '#',
    'dollar': r'$',
    'percent': '%',
    'ampersand': '&', //
    'quotesingle': "'", 'quoteright': '’', 'parenleft': '(', 'parenright': ')', 'asterisk': '*', 'plus': '+',
    'comma': ',', 'hyphen': '-', 'minus': '-', 'period': '.', 'slash': '/', 'zero': '0', 'one': '1', 'two': '2',
    'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'colon': ':',
    'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>', 'question': '?', 'at': '@', 'bracketleft': '[',
    'backslash': r'\', 'bracketright': ']', 'asciicircum': '^', 'underscore': '_', 'grave': '`', 'quoteleft': '‘',
    'braceleft': '{', 'bar': '|', 'braceright': '}', 'asciitilde': '~', 'degree': '°', 'plusminus': '±',
    'diameter': 'Ø', 'Oslash': 'Ø', 'oslash': 'ø', 'multiply': '×', 'mu': 'µ', 'twosuperior': '²', 'threesuperior': '³',
    'endash': '–', 'emdash': '—', 'bullet': '•',
  };
  if (named.containsKey(name)) return named[name];
  if (name.length == 1) return name;
  final u = RegExp(r'^uni([0-9A-Fa-f]{4})').firstMatch(name);
  if (u != null) return String.fromCharCode(int.parse(u.group(1)!, radix: 16));
  return null;
}

Map<int, String> _parseCMap(Uint8List data) {
  final out = <int, String>{};
  final s = latin1.decode(data);
  String hexText(String h) {
    final codes = <int>[];
    for (var i = 0; i + 3 < h.length + 0; i += 4) {
      codes.add(int.parse(h.substring(i, i + 4), radix: 16));
    }
    if (h.length == 2) codes.add(int.parse(h, radix: 16));
    return String.fromCharCodes(codes);
  }

  for (final m in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(s)) {
    for (final p in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(m.group(1)!)) {
      out[int.parse(p.group(1)!, radix: 16)] = hexText(p.group(2)!);
    }
  }
  for (final m in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(s)) {
    final body = m.group(1)!;
    for (final p in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])').allMatches(body)) {
      final lo = int.parse(p.group(1)!, radix: 16), hi = int.parse(p.group(2)!, radix: 16);
      if (hi - lo > 0xFFFF) continue;
      if (p.group(4) != null) {
        final start = hexText(p.group(4)!);
        if (start.isEmpty) continue;
        final last = start.codeUnitAt(start.length - 1);
        for (var c = lo; c <= hi; c++) {
          out[c] = start.substring(0, start.length - 1) + String.fromCharCode(last + (c - lo));
        }
      } else {
        final items = RegExp(r'<([0-9A-Fa-f]*)>').allMatches(p.group(5)!).toList();
        for (var i = 0; i < items.length && lo + i <= hi; i++) {
          out[lo + i] = hexText(items[i].group(1)!);
        }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// The interpreter
// ---------------------------------------------------------------------------------------------

class _Mat {
  const _Mat(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _Mat(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  /// this, then [o]
  _Mat then(_Mat o) => _Mat(
    a * o.a + b * o.c,
    a * o.b + b * o.d,
    c * o.a + d * o.c,
    c * o.b + d * o.d,
    e * o.a + f * o.c + o.e,
    e * o.b + f * o.d + o.f,
  );
  P2 apply(double x, double y) => P2(a * x + c * y + e, b * x + d * y + f);
  P2 vector(double x, double y) => P2(a * x + c * y, b * x + d * y);

  /// how much lengths grow (average of the two directions)
  double get scale => math.sqrt((a * d - b * c).abs());
}

class _GState {
  _Mat ctm = _Mat.identity;
  int strokeRgb = 0, fillRgb = 0;
  String strokeSpace = 'DeviceGray', fillSpace = 'DeviceGray';
  double width = 1;
  List<double> dash = const [];
  // text
  double charSpace = 0, wordSpace = 0, hScale = 1, leading = 0, rise = 0, size = 0;
  int render = 0;
  _Font? font;

  _GState copy() => _GState()
    ..ctm = ctm
    ..strokeRgb = strokeRgb
    ..fillRgb = fillRgb
    ..strokeSpace = strokeSpace
    ..fillSpace = fillSpace
    ..width = width
    ..dash = dash
    ..charSpace = charSpace
    ..wordSpace = wordSpace
    ..hScale = hScale
    ..leading = leading
    ..rise = rise
    ..size = size
    ..render = render
    ..font = font;
}

int _rgb(double r, double g, double b) {
  int c(double v) => (v.clamp(0, 1) * 255).round();
  return c(r) << 16 | c(g) << 8 | c(b);
}

int _cmyk(double c, double m, double y, double k) => _rgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));

/// Reads [page] and returns everything drawn on it
PageContent readPage(PdfPageInfo page) {
  final box = page.mediaBox;
  final rot = page.rotate;
  final w = box[2] - box[0], h = box[3] - box[1];
  final out = PageContent(rot == 90 || rot == 270 ? h : w, rot == 90 || rot == 270 ? w : h);
  // the page box to (0,0)…(width,height), turned as the viewer turns it
  var base = _Mat(1, 0, 0, 1, -box[0], -box[1]);
  base = switch (rot) {
    90 => base.then(_Mat(0, -1, 1, 0, 0, w)),
    180 => base.then(_Mat(-1, 0, 0, -1, w, h)),
    270 => base.then(_Mat(0, 1, -1, 0, h, 0)),
    _ => base,
  };
  _Interpreter(page.file, out).run(page.content, page.resources, base, null);
  return out;
}

class _Interpreter {
  _Interpreter(this.file, this.out);
  final PdfFile file;
  final PageContent out;
  int order = 0;
  final _fonts = <Object, _Font>{};
  int depth = 0;

  void run(Uint8List data, Map<String, Object?> res, _Mat ctm, String? layer, {_GState? start}) {
    if (depth > 12) return;
    depth++;
    var gs = (start?.copy() ?? _GState())..ctm = ctm;
    final stack = <_GState>[];
    final layers = <String?>[layer];
    String? currentLayer() => layers.lastWhere((l) => l != null, orElse: () => null);

    // the path being built (in page space)
    var subs = <SubPath>[];
    var cur = <Seg>[];
    P2? startPt, pt;
    // text
    var tm = _Mat.identity, tlm = _Mat.identity;

    void endSub({bool close = false}) {
      if (cur.isNotEmpty) {
        if (close && startPt != null && pt != null && startPt!.dist(pt!) > 1e-9) cur.add(Seg(pt!, startPt!));
        subs.add(SubPath(cur, close));
      } else if (close && subs.isNotEmpty) {
        subs.last.closed = true;
      }
      cur = <Seg>[];
    }

    void paint({required bool stroke, required bool fill, bool evenOdd = false, bool close = false}) {
      endSub(close: close);
      if (subs.isNotEmpty && (stroke || fill)) {
        out.paths.add(
          PaintedPath(
            subs: subs,
            stroke: stroke,
            fill: fill,
            evenOdd: evenOdd,
            strokeRgb: gs.strokeRgb,
            fillRgb: gs.fillRgb,
            width: gs.width * gs.ctm.scale,
            dash: [for (final d in gs.dash) d * gs.ctm.scale],
            layer: currentLayer(),
            order: order++,
          ),
        );
      }
      subs = <SubPath>[];
      cur = <Seg>[];
      startPt = null;
      pt = null;
    }

    void showText(Uint8List bytes, {List<Object?>? tj}) {
      final f = gs.font;
      if (f == null) return;
      // the text's origin and direction on the page
      final trm0 = _Mat(gs.size * gs.hScale, 0, 0, gs.size, 0, gs.rise).then(tm).then(gs.ctm);
      final start = trm0.apply(0, 0);
      final buf = StringBuffer();
      void advance(double tx) => tm = _Mat(1, 0, 0, 1, tx, 0).then(tm);
      var total = 0.0;
      void glyphs(Uint8List b) {
        for (final (code, s) in f.codes(b)) {
          buf.write(s);
          final tx =
              (f.widthOf(code) * gs.size + gs.charSpace + (!f.twoByte && code == 32 ? gs.wordSpace : 0)) * gs.hScale;
          advance(tx);
          total += tx;
        }
      }

      if (tj != null) {
        for (final item in tj) {
          if (item is PdfString) {
            glyphs(item.bytes);
          } else if (item is num) {
            final tx = -item / 1000 * gs.size * gs.hScale;
            // a big gap inside TJ is a space between words
            if (-item > 250 && buf.isNotEmpty && !buf.toString().endsWith(' ')) buf.write(' ');
            advance(tx);
            total += tx;
          }
        }
      } else {
        glyphs(bytes);
      }
      final text = buf.toString();
      if (text.trim().isEmpty) return;
      final up = trm0.vector(0, 1);
      final along = trm0.vector(1, 0);
      final dir = tm.then(gs.ctm);
      final adv = (total * dir.vector(1, 0).length).abs();
      out.texts.add(
        ShownText(
          text: text,
          origin: start,
          height: up.length,
          angle: math.atan2(along.y, along.x),
          advance: adv,
          rgb: gs.fillRgb,
          font: f.name,
          capHeight: f.capHeight,
          invisible: gs.render == 3 || gs.render == 7,
          layer: currentLayer(),
          order: order++,
        ),
      );
    }

    final lx = PdfLexer(data);
    final ops = <Object?>[];
    double n(int i) => (ops[i] as num?)?.toDouble() ?? 0;
    double nl(int k) => ops.length >= k ? n(ops.length - k) : 0;

    int colour(String space, List<double> v, {Object? patternName}) {
      final sp = space;
      if (sp == 'DeviceRGB' || sp == 'CalRGB' || sp == 'RGB3') return v.length >= 3 ? _rgb(v[0], v[1], v[2]) : 0;
      if (sp == 'DeviceCMYK' || sp == 'CMYK4') return v.length >= 4 ? _cmyk(v[0], v[1], v[2], v[3]) : 0;
      if (sp == 'Separation') return v.isEmpty ? 0 : _rgb(1 - v[0], 1 - v[0], 1 - v[0]);
      if (sp == 'Pattern') return 0x808080;
      if (v.length == 1) return _rgb(v[0], v[0], v[0]);
      if (v.length >= 4) return _cmyk(v[0], v[1], v[2], v[3]);
      if (v.length == 3) return _rgb(v[0], v[1], v[2]);
      return 0;
    }

    String spaceOf(Object? name) {
      if (name is! PdfName) return 'DeviceGray';
      final n0 = name.name;
      if (n0.startsWith('Device') || n0 == 'Pattern') return n0;
      final cs = file.resolve(file.dict(res['ColorSpace'])?[n0]);
      if (cs is List && cs.isNotEmpty) {
        final kind = (cs[0] as PdfName?)?.name ?? '';
        if (kind == 'ICCBased') {
          final s = file.resolve(cs[1]);
          final count = s is PdfStream ? (s.dict['N'] as num?)?.toInt() ?? 3 : 3;
          return count == 4
              ? 'CMYK4'
              : count == 1
              ? 'DeviceGray'
              : 'RGB3';
        }
        if (kind == 'CalRGB' || kind == 'Lab') return 'RGB3';
        if (kind == 'CalGray') return 'DeviceGray';
        if (kind == 'Separation' || kind == 'DeviceN') return 'Separation';
        if (kind == 'Pattern') return 'Pattern';
        if (kind == 'Indexed') return 'RGB3';
      }
      return 'DeviceGray';
    }

    while (true) {
      final t = lx.next();
      if (t == null && lx.atEnd) break;
      if (t is! PdfKeyword) {
        ops.add(t);
        continue;
      }
      final op = t.word;
      switch (op) {
        // ---- graphics state
        case 'q':
          stack.add(gs.copy());
        case 'Q':
          if (stack.isNotEmpty) gs = stack.removeLast();
        case 'cm':
          if (ops.length >= 6) gs.ctm = _Mat(nl(6), nl(5), nl(4), nl(3), nl(2), nl(1)).then(gs.ctm);
        case 'w':
          gs.width = nl(1);
        case 'd':
          if (ops.length >= 2 && ops[ops.length - 2] is List) {
            gs.dash = [for (final v in ops[ops.length - 2] as List) (file.resolve(v) as num?)?.toDouble() ?? 0];
          }
        case 'gs':
          final ext = file.dict(file.dict(res['ExtGState'])?[(ops.lastOrNull as PdfName?)?.name]);
          if (ext != null) {
            if (ext['LW'] is num) gs.width = (ext['LW'] as num).toDouble();
            final d = file.resolve(ext['D']);
            if (d is List && d.isNotEmpty && d[0] is List) {
              gs.dash = [for (final v in d[0] as List) (v as num).toDouble()];
            }
            final font = file.resolve(ext['Font']);
            if (font is List && font.length == 2) {
              gs.font = _font(font[0]);
              gs.size = (font[1] as num).toDouble();
            }
          }
        // ---- colour
        case 'g':
          gs.fillRgb = colour('DeviceGray', [nl(1)]);
          gs.fillSpace = 'DeviceGray';
        case 'G':
          gs.strokeRgb = colour('DeviceGray', [nl(1)]);
          gs.strokeSpace = 'DeviceGray';
        case 'rg':
          gs.fillRgb = colour('DeviceRGB', [nl(3), nl(2), nl(1)]);
          gs.fillSpace = 'DeviceRGB';
        case 'RG':
          gs.strokeRgb = colour('DeviceRGB', [nl(3), nl(2), nl(1)]);
          gs.strokeSpace = 'DeviceRGB';
        case 'k':
          gs.fillRgb = colour('DeviceCMYK', [nl(4), nl(3), nl(2), nl(1)]);
          gs.fillSpace = 'DeviceCMYK';
        case 'K':
          gs.strokeRgb = colour('DeviceCMYK', [nl(4), nl(3), nl(2), nl(1)]);
          gs.strokeSpace = 'DeviceCMYK';
        case 'cs':
          gs.fillSpace = spaceOf(ops.lastOrNull);
          gs.fillRgb = 0;
        case 'CS':
          gs.strokeSpace = spaceOf(ops.lastOrNull);
          gs.strokeRgb = 0;
        case 'sc' || 'scn':
          gs.fillRgb = colour(gs.fillSpace, [
            for (final o in ops)
              if (o is num) o.toDouble(),
          ]);
        case 'SC' || 'SCN':
          gs.strokeRgb = colour(gs.strokeSpace, [
            for (final o in ops)
              if (o is num) o.toDouble(),
          ]);
        // ---- path
        case 'm':
          endSub();
          pt = startPt = gs.ctm.apply(nl(2), nl(1));
        case 'l':
          final q = gs.ctm.apply(nl(2), nl(1));
          if (pt != null) cur.add(Seg(pt!, q));
          pt = q;
          startPt ??= q;
        case 'c':
          final c1 = gs.ctm.apply(nl(6), nl(5)), c2 = gs.ctm.apply(nl(4), nl(3)), q = gs.ctm.apply(nl(2), nl(1));
          if (pt != null) cur.add(Seg(pt!, q, c1, c2));
          pt = q;
        case 'v':
          final c2 = gs.ctm.apply(nl(4), nl(3)), q = gs.ctm.apply(nl(2), nl(1));
          if (pt != null) cur.add(Seg(pt!, q, pt!, c2));
          pt = q;
        case 'y':
          final c1 = gs.ctm.apply(nl(4), nl(3)), q = gs.ctm.apply(nl(2), nl(1));
          if (pt != null) cur.add(Seg(pt!, q, c1, q));
          pt = q;
        case 'h':
          endSub(close: true);
          pt = startPt;
        case 're':
          endSub();
          final x = nl(4), y = nl(3), rw = nl(2), rh = nl(1);
          final a = gs.ctm.apply(x, y),
              b = gs.ctm.apply(x + rw, y),
              c = gs.ctm.apply(x + rw, y + rh),
              d = gs.ctm.apply(x, y + rh);
          subs.add(SubPath([Seg(a, b), Seg(b, c), Seg(c, d), Seg(d, a)], true));
          pt = startPt = a;
        case 'S':
          paint(stroke: true, fill: false);
        case 's':
          paint(stroke: true, fill: false, close: true);
        case 'f' || 'F':
          paint(stroke: false, fill: true);
        case 'f*':
          paint(stroke: false, fill: true, evenOdd: true);
        case 'B':
          paint(stroke: true, fill: true);
        case 'B*':
          paint(stroke: true, fill: true, evenOdd: true);
        case 'b':
          paint(stroke: true, fill: true, close: true);
        case 'b*':
          paint(stroke: true, fill: true, evenOdd: true, close: true);
        case 'n':
          subs = <SubPath>[];
          cur = <Seg>[];
          startPt = pt = null;
        case 'W' || 'W*':
          break;
        // ---- text
        case 'BT':
          tm = tlm = _Mat.identity;
        case 'ET':
          break;
        case 'Tc':
          gs.charSpace = nl(1);
        case 'Tw':
          gs.wordSpace = nl(1);
        case 'Tz':
          gs.hScale = nl(1) / 100;
        case 'TL':
          gs.leading = nl(1);
        case 'Ts':
          gs.rise = nl(1);
        case 'Tr':
          gs.render = nl(1).toInt();
        case 'Tf':
          if (ops.length >= 2) {
            gs.font = _fontFromRes(res, ops[ops.length - 2]);
            gs.size = nl(1);
          }
        case 'Td':
          tlm = _Mat(1, 0, 0, 1, nl(2), nl(1)).then(tlm);
          tm = tlm;
        case 'TD':
          gs.leading = -nl(1);
          tlm = _Mat(1, 0, 0, 1, nl(2), nl(1)).then(tlm);
          tm = tlm;
        case 'Tm':
          tlm = tm = _Mat(nl(6), nl(5), nl(4), nl(3), nl(2), nl(1));
        case 'T*':
          tlm = _Mat(1, 0, 0, 1, 0, -gs.leading).then(tlm);
          tm = tlm;
        case 'Tj':
          if (ops.lastOrNull is PdfString) showText((ops.last as PdfString).bytes);
        case 'TJ':
          if (ops.lastOrNull is List) showText(Uint8List(0), tj: ops.last as List<Object?>);
        case "'":
          tlm = _Mat(1, 0, 0, 1, 0, -gs.leading).then(tlm);
          tm = tlm;
          if (ops.lastOrNull is PdfString) showText((ops.last as PdfString).bytes);
        case '"':
          if (ops.length >= 3) {
            gs.wordSpace = n(ops.length - 3);
            gs.charSpace = n(ops.length - 2);
          }
          tlm = _Mat(1, 0, 0, 1, 0, -gs.leading).then(tlm);
          tm = tlm;
          if (ops.lastOrNull is PdfString) showText((ops.last as PdfString).bytes);
        // ---- forms and pictures
        case 'Do':
          final name = (ops.lastOrNull as PdfName?)?.name;
          final xo = file.resolve(file.dict(res['XObject'])?[name]);
          if (xo is PdfStream) {
            final sub = (xo.dict['Subtype'] as PdfName?)?.name;
            if (sub == 'Form') {
              final m = file.resolve(xo.dict['Matrix']);
              var fm = gs.ctm;
              if (m is List && m.length == 6) {
                final v = [for (final x in m) (file.resolve(x) as num).toDouble()];
                fm = _Mat(v[0], v[1], v[2], v[3], v[4], v[5]).then(gs.ctm);
              }
              final r = file.dict(xo.dict['Resources']) ?? res;
              final formLayer = _ocName(file.resolve(xo.dict['OC']), res);
              // the form starts with the current pen and colours, and leaves them as they were
              run(decodeStream(xo, file), r, fm, formLayer ?? currentLayer(), start: gs);
            } else if (sub == 'Image') {
              final corners = [gs.ctm.apply(0, 0), gs.ctm.apply(1, 0), gs.ctm.apply(1, 1), gs.ctm.apply(0, 1)];
              out.images.add([
                corners.map((p) => p.x).reduce(math.min),
                corners.map((p) => p.y).reduce(math.min),
                corners.map((p) => p.x).reduce(math.max),
                corners.map((p) => p.y).reduce(math.max),
              ]);
            }
          }
        case 'BI':
          // an inline picture: skip its data up to EI
          final start = lx.pos;
          var p = start;
          while (p + 2 < data.length) {
            final ei = data[p] == 0x45 && data[p + 1] == 0x49;
            if (ei && isPdfWhite(data[p - 1]) && (p + 2 >= data.length || isPdfWhite(data[p + 2]))) {
              break;
            }
            p++;
          }
          lx.pos = p + 2;
          final corners = [gs.ctm.apply(0, 0), gs.ctm.apply(1, 1)];
          out.images.add([
            math.min(corners[0].x, corners[1].x),
            math.min(corners[0].y, corners[1].y),
            math.max(corners[0].x, corners[1].x),
            math.max(corners[0].y, corners[1].y),
          ]);
        // ---- layers (marked content)
        case 'BDC':
          if (ops.length >= 2 && ops[ops.length - 2] is PdfName && (ops[ops.length - 2] as PdfName).name == 'OC') {
            layers.add(_ocName(ops.last, res));
          } else {
            layers.add(null);
          }
        case 'BMC':
          layers.add(null);
        case 'EMC':
          if (layers.length > 1) layers.removeLast();
      }
      ops.clear();
    }
    depth--;
  }

  String? _ocName(Object? o, Map<String, Object?> res) {
    Object? v = o;
    if (v is PdfName) v = file.dict(res['Properties'])?[v.name];
    if (v is PdfRef) {
      final name = file.layerNames[v.num];
      if (name != null) return name;
      final d = file.dict(v);
      // a membership dictionary: its first group
      final g = file.resolve(d?['OCGs']);
      if (g is List && g.isNotEmpty && g.first is PdfRef) return file.layerNames[(g.first as PdfRef).num];
      if (g is PdfRef) return file.layerNames[g.num];
      final n = file.resolve(d?['Name']);
      if (n is PdfString) return n.text;
    }
    if (v is Map<String, Object?>) {
      final n = file.resolve(v['Name']);
      if (n is PdfString) return n.text;
    }
    return null;
  }

  _Font? _fontFromRes(Map<String, Object?> res, Object? name) {
    if (name is! PdfName) return null;
    return _font(file.dict(res['Font'])?[name.name]);
  }

  _Font? _font(Object? ref) {
    final key = ref is PdfRef ? ref : Object();
    if (_fonts[key] case final f?) return f;
    final d = file.dict(ref);
    if (d == null) return null;
    final sub = (d['Subtype'] as PdfName?)?.name ?? '';
    final baseName = (d['BaseFont'] as PdfName?)?.name ?? 'Font';
    final name = baseName.contains('+') ? baseName.substring(baseName.indexOf('+') + 1) : baseName;
    var toUni = <int, String>{};
    final tu = file.resolve(d['ToUnicode']);
    if (tu is PdfStream) toUni = _parseCMap(decodeStream(tu, file));
    final widths = <int, double>{};
    var dw = 500.0;
    var cap = 0.7;
    double capOf(Map<String, Object?>? fd) {
      final ch = (file.resolve(fd?['CapHeight']) as num?)?.toDouble();
      return ch != null && ch > 100 && ch < 1000 ? ch / 1000 : 0.7;
    }

    if (sub == 'Type0') {
      final desc = file.resolve(d['DescendantFonts']);
      final df = file.dict(desc is List && desc.isNotEmpty ? desc.first : desc);
      dw = (file.resolve(df?['DW']) as num?)?.toDouble() ?? 1000;
      cap = capOf(file.dict(df?['FontDescriptor']));
      final wa = file.resolve(df?['W']);
      if (wa is List) {
        var i = 0;
        while (i < wa.length) {
          final first = (file.resolve(wa[i]) as num?)?.toInt() ?? 0;
          final nx = file.resolve(i + 1 < wa.length ? wa[i + 1] : null);
          if (nx is List) {
            for (var k = 0; k < nx.length; k++) {
              widths[first + k] = (file.resolve(nx[k]) as num?)?.toDouble() ?? dw;
            }
            i += 2;
          } else {
            final last = (nx as num?)?.toInt() ?? first;
            final wv = (file.resolve(i + 2 < wa.length ? wa[i + 2] : null) as num?)?.toDouble() ?? dw;
            for (var c = first; c <= last && c - first < 65536; c++) {
              widths[c] = wv;
            }
            i += 3;
          }
        }
      }
      final f = _Font(name: name, twoByte: true, toUnicode: toUni, widths: widths, defaultWidth: dw, capHeight: cap);
      _fonts[key] = f;
      return f;
    }
    // a simple font: its encoding, then ToUnicode on top
    final enc = file.resolve(d['Encoding']);
    final simple = <int, String>{};
    if (enc is Map<String, Object?>) {
      final diffs = file.resolve(enc['Differences']);
      if (diffs is List) {
        var code = 0;
        for (final x in diffs) {
          final v = file.resolve(x);
          if (v is num) {
            code = v.toInt();
          } else if (v is PdfName) {
            final ch = _glyph(v.name);
            if (ch != null) simple[code] = ch;
            code++;
          }
        }
      }
    }
    final fc = (file.resolve(d['FirstChar']) as num?)?.toInt() ?? 0;
    final wa = file.resolve(d['Widths']);
    if (wa is List) {
      for (var i = 0; i < wa.length; i++) {
        widths[fc + i] = (file.resolve(wa[i]) as num?)?.toDouble() ?? 0;
      }
      dw = widths.isEmpty
          ? 500
          : widths.values.where((v) => v > 0).fold(0.0, (a, b) => a + b) /
                math.max(1, widths.values.where((v) => v > 0).length);
    } else if (name.startsWith('Courier')) {
      dw = 600;
    }
    cap = capOf(file.dict(d['FontDescriptor']));
    final f = _Font(
      name: name,
      twoByte: false,
      toUnicode: {...simple, ...toUni},
      widths: widths,
      defaultWidth: dw,
      capHeight: cap,
    );
    _fonts[key] = f;
    return f;
  }
}
