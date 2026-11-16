// Recognising what a draughtsman drew, from the pieces a PDF keeps:
//
//  - a pattern hatch: many parallel lines, evenly spaced, whose ends sit on one outline
//  - a dimension: a line with an arrow at each end, a value beside it, extension lines to what it
//    measures
//  - a solid hatch: any other filled shape
//
// Paper millimetres throughout. What is recognised is taken out of the loose pieces.
import 'dart:math' as math;

import 'cad.dart';
import 'rebuild.dart';

class FoundHatch {
  FoundHatch(
    this.loops,
    this.rgb,
    this.layer, {
    this.pattern = 'SOLID',
    this.angle = 0,
    this.spacing = 0,
    this.patternScale = 1,
  });
  final List<List<V>> loops;
  final int rgb;
  final String? layer;

  /// SOLID, ANSI31, ANSI37 or _USER (one line family at [angle], [spacing] apart)
  final String pattern;
  final double angle, spacing, patternScale;
}

class FoundDimension {
  FoundDimension({
    required this.p1,
    required this.p2,
    required this.lineA,
    required this.lineB,
    required this.text,
    required this.rgb,
    required this.widthMm,
    required this.layer,
    required this.parts,
    required this.arrows,
  });

  /// what it measures (where the extension lines start)
  final V p1, p2;

  /// the dimension line's ends
  final V lineA, lineB;
  final TextItem text;
  final int rgb;
  final double widthMm;
  final String? layer;
  final List<Piece> parts;
  final List<List<V>> arrows;

  double get value => double.tryParse(text.text.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  double get paperLength {
    final ux = lineB.x - lineA.x, uy = lineB.y - lineA.y;
    final l = math.sqrt(ux * ux + uy * uy);
    return ((p2.x - p1.x) * ux + (p2.y - p1.y) * uy).abs() / l;
  }

  CadDimension build(CadStyle s, double f) {
    final ang = math.atan2(lineB.y - lineA.y, lineB.x - lineA.x);
    final measured = paperLength * f;
    final shown = value;
    // the value it prints, when it is the measurement: AutoCAD then keeps it up to date
    final matches = shown > 0 && (shown - measured).abs() <= 0.005 * measured + 0.006;
    final a = text.angle * math.pi / 180;
    final tx = text.x + math.cos(a) * text.advance / 2 - math.sin(a) * text.height / 2;
    final ty = text.y + math.sin(a) * text.advance / 2 + math.cos(a) * text.height / 2;
    final dimStyle = s.copyWith(aci: 256, lineType: 'BYLAYER', ltScale: 1, lineWeight: -1);
    return CadDimension(
      s,
      x1: p1.x * f,
      y1: p1.y * f,
      x2: p2.x * f,
      y2: p2.y * f,
      lineX: lineB.x * f,
      lineY: lineB.y * f,
      textX: tx * f,
      textY: ty * f,
      angle: ang * 180 / math.pi,
      text: matches ? '' : text.text,
      measured: measured,
      textHeight: text.height * f,
      arrowSize: _arrowLength(arrows.first) * f,
      block: [
        for (final p in parts)
          if (p.v.length == 2 && p.v[0].b == 0)
            CadLine(dimStyle, p.v[0].x * f, p.v[0].y * f, p.v[1].x * f, p.v[1].y * f)
          else
            CadPolyline(dimStyle, [for (final q in p.v) CadVertex(q.x * f, q.y * f, q.b)], closed: p.closed),
        for (final ar in arrows)
          CadHatch(dimStyle, [
            [for (final q in ar) CadVertex(q.x * f, q.y * f)],
          ]),
        CadText(dimStyle, text.text, text.x * f, text.y * f, text.height * f, text.angle, text.style),
      ],
    );
  }
}

double _arrowLength(List<V> tri) {
  final d = [tri[0].dist(tri[1]), tri[1].dist(tri[2]), tri[2].dist(tri[0])]..sort();
  return d[2];
}

class Recognised {
  Recognised(this.pieces, this.hatches, this.dimensions, this.texts);
  final List<Piece> pieces;
  final List<FoundHatch> hatches;
  final List<FoundDimension> dimensions;
  final List<TextItem> texts;

  /// the scale the dimensions say the drawing is at (their values against their length on paper)
  int? get suggestedScale {
    final ratios = [
      for (final d in dimensions)
        if (d.value > 0 && d.paperLength > 1) d.value / d.paperLength * 1000,
    ]..sort();
    if (ratios.isEmpty) return null;
    final mid = ratios[ratios.length ~/ 2];
    const common = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 1250, 2000, 2500, 5000, 10000];
    for (final c in common) {
      if ((mid - c).abs() <= 0.02 * c) return c;
    }
    return mid.round();
  }
}

double _area(List<V> loop) {
  var a = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final p = loop[i], q = loop[(i + 1) % loop.length];
    a += p.x * q.y - q.x * p.y;
  }
  return a / 2;
}

double _distToSeg(double px, double py, V a, V b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((px - a.x) * dx + (py - a.y) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final x = a.x + t * dx, y = a.y + t * dy;
  return math.sqrt((px - x) * (px - x) + (py - y) * (py - y));
}

/// How far a point is from a loop's edges (straight edges; arcs as their chords)
double _distToLoop(double x, double y, List<V> loop) {
  var best = double.infinity;
  for (var i = 0; i < loop.length; i++) {
    best = math.min(best, _distToSeg(x, y, loop[i], loop[(i + 1) % loop.length]));
  }
  return best;
}

Recognised recognise(
  List<Piece> pieces,
  List<({List<List<V>> loops, int rgb, String? layer, int order})> fills,
  List<TextItem> texts, {
  bool findDimensions = true,
  bool findHatches = true,
}) {
  final loose = List<Piece>.of(pieces);
  final hatches = <FoundHatch>[];
  final dims = <FoundDimension>[];
  final freeTexts = List<TextItem>.of(texts);
  final freeFills = List.of(fills);

  // ---------------------------------------------------------------- dimensions
  if (findDimensions) {
    // arrows: small filled triangles; tip = the corner opposite the shortest side
    final arrows = <({int fill, V tip, double dx, double dy, List<V> tri, double len})>[];
    for (var i = 0; i < freeFills.length; i++) {
      final fl = freeFills[i];
      if (fl.loops.length != 1) continue;
      var tri = fl.loops.first;
      if (tri.length == 4 && tri.first.dist(tri.last) < 1e-3) tri = tri.sublist(0, 3);
      if (tri.length != 3) continue;
      final area = _area(tri).abs();
      final sides = [tri[1].dist(tri[2]), tri[2].dist(tri[0]), tri[0].dist(tri[1])];
      final longest = sides.reduce(math.max);
      if (area > 12 || area < 0.01 || longest > 8) continue;
      final si = sides.indexOf(sides.reduce(math.min));
      final tip = tri[si];
      final b1 = tri[(si + 1) % 3], b2 = tri[(si + 2) % 3];
      final mx = (b1.x + b2.x) / 2, my = (b1.y + b2.y) / 2;
      final l = math.sqrt((tip.x - mx) * (tip.x - mx) + (tip.y - my) * (tip.y - my));
      if (l < 1.5 * sides[si]) continue; // not pointed enough to be an arrow
      arrows.add((fill: i, tip: tip, dx: (tip.x - mx) / l, dy: (tip.y - my) / l, tri: tri, len: l));
    }
    final usedFills = <int>{};
    final usedPieces = <Piece>{};
    final usedTexts = <TextItem>{};
    final numeric = RegExp(r'^[^\d]{0,3}\d[\d.,]*\s*(m|mm|cm|M)?$');
    for (final line in loose) {
      if (line.closed || line.v.length != 2 || line.v[0].b != 0 || line.pen.lineType != 'CONTINUOUS') continue;
      final a = line.v[0], b = line.v[1];
      final len = a.dist(b);
      if (len < 2) continue;
      final ux = (b.x - a.x) / len, uy = (b.y - a.y) / len;
      // an arrow at each end, pointing out along the line
      ({int fill, V tip, double dx, double dy, List<V> tri, double len})? atEnd(V p, double sx, double sy) {
        for (final ar in arrows) {
          if (usedFills.contains(ar.fill)) continue;
          if (ar.tip.dist(p) < 0.3 && ar.dx * sx + ar.dy * sy > 0.95) return ar;
        }
        return null;
      }

      final arA = atEnd(a, -ux, -uy), arB = atEnd(b, ux, uy);
      if (arA == null || arB == null) continue;
      // the value: text along the line, near its middle
      final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      TextItem? value;
      for (final t in freeTexts) {
        if (usedTexts.contains(t) || !numeric.hasMatch(t.text.trim())) continue;
        final ang = t.angle * math.pi / 180;
        final cx = t.x + math.cos(ang) * t.advance / 2 - math.sin(ang) * t.height / 2;
        final cy = t.y + math.sin(ang) * t.advance / 2 + math.cos(ang) * t.height / 2;
        final along = (cx - mx) * ux + (cy - my) * uy;
        final across = (-(cx - mx) * uy + (cy - my) * ux).abs();
        final parallel = (math.sin(ang - math.atan2(uy, ux))).abs() < 0.05;
        if (parallel && along.abs() < len / 2 && across < 2.5 * t.height + 1) {
          value = t;
          break;
        }
      }
      if (value == null) continue;
      // extension lines: across the dimension line at each end; their far ends are what is measured
      (Piece, V)? ext(V end) {
        for (final p in loose) {
          if (p == line || usedPieces.contains(p) || p.closed || p.v.length != 2 || p.v[0].b != 0) continue;
          final q0 = p.v[0], q1 = p.v[1];
          final l = q0.dist(q1);
          if (l < 0.5) continue;
          final vx = (q1.x - q0.x) / l, vy = (q1.y - q0.y) / l;
          if ((vx * ux + vy * uy).abs() > 0.05) continue; // not across
          if (_distToSeg(end.x, end.y, q0, q1) > 0.1) continue;
          // the end farther from the dimension line is the measured point
          final d0 = (-(q0.x - end.x) * uy + (q0.y - end.y) * ux).abs();
          final d1 = (-(q1.x - end.x) * uy + (q1.y - end.y) * ux).abs();
          return (p, d0 > d1 ? q0 : q1);
        }
        return null;
      }

      final eA = ext(a), eB = ext(b);
      final p1 = eA?.$2 ?? a, p2 = eB?.$2 ?? b;
      final parts = [line, if (eA != null) eA.$1, if (eB != null) eB.$1];
      dims.add(
        FoundDimension(
          p1: p1,
          p2: p2,
          lineA: a,
          lineB: b,
          text: value,
          rgb: line.pen.rgb,
          widthMm: line.pen.widthMm,
          layer: line.pen.layer,
          parts: parts,
          arrows: [arA.tri, arB.tri],
        ),
      );
      usedFills
        ..add(arA.fill)
        ..add(arB.fill);
      usedPieces.addAll(parts);
      usedTexts.add(value);
    }
    loose.removeWhere(usedPieces.contains);
    freeTexts.removeWhere(usedTexts.contains);
    final keep = [
      for (var i = 0; i < freeFills.length; i++)
        if (!usedFills.contains(i)) freeFills[i],
    ];
    freeFills
      ..clear()
      ..addAll(keep);
  }

  // ---------------------------------------------------------------- pattern hatches
  if (findHatches) {
    final lines = [
      for (final p in loose)
        if (!p.closed && p.v.length == 2 && p.v[0].b == 0 && p.pen.lineType == 'CONTINUOUS' && p.length > 0.5) p,
    ];
    // by pen and direction
    final groups = <String, List<({Piece p, double th, double rho})>>{};
    for (final p in lines) {
      var th = math.atan2(p.v[1].y - p.v[0].y, p.v[1].x - p.v[0].x);
      if (th < 0) th += math.pi;
      if (th >= math.pi - 0.002) th -= math.pi;
      final rho = -math.sin(th) * p.v[0].x + math.cos(th) * p.v[0].y;
      final k = '${p.pen.rgb}|${p.pen.widthMm.toStringAsFixed(2)}|${p.pen.layer}|${(th * 180 / math.pi / 0.5).round()}';
      groups.putIfAbsent(k, () => []).add((p: p, th: th, rho: rho));
    }
    final closedLoops = [
      for (final p in loose)
        if (p.closed) p,
    ];
    final families = <({List<Piece> lines, double angle, double spacing, Piece? boundary, int rgb, String? layer})>[];
    for (final g in groups.values) {
      if (g.length < 5) continue;
      g.sort((a, b) => a.rho.compareTo(b.rho));
      // runs of even spacing
      var run = [g.first];
      void finish() {
        if (run.length < 5) return;
        final steps = [for (var i = 1; i < run.length; i++) run[i].rho - run[i - 1].rho]..sort();
        final spacing = steps[steps.length ~/ 2];
        // the outline their ends sit on
        Piece? boundary;
        for (final loop in closedLoops) {
          var on = 0;
          for (final r in run) {
            if (_distToLoop(r.p.v[0].x, r.p.v[0].y, loop.v) < 0.15 &&
                _distToLoop(r.p.v[1].x, r.p.v[1].y, loop.v) < 0.15) {
              on++;
            }
          }
          if (on >= 0.8 * run.length) {
            boundary = loop;
            break;
          }
        }
        if (boundary == null) return;
        families.add((
          lines: [for (final r in run) r.p],
          angle: run.first.th * 180 / math.pi,
          spacing: spacing,
          boundary: boundary,
          rgb: run.first.p.pen.rgb,
          layer: run.first.p.pen.layer,
        ));
      }

      for (var i = 1; i < g.length; i++) {
        final step = g[i].rho - run.last.rho;
        final steps = [for (var k = 1; k < run.length; k++) run[k].rho - run[k - 1].rho];
        final typical = steps.isEmpty ? step : (steps..sort())[steps.length ~/ 2];
        if (step > 0.2 && (step - typical).abs() <= 0.08 * typical + 0.02) {
          run.add(g[i]);
        } else if (step.abs() <= 0.02) {
          continue; // the same line twice
        } else {
          finish();
          run = [g[i]];
        }
      }
      finish();
    }
    // two families in one outline, crossing: a cross hatch
    final usedLines = <Piece>{};
    final byBoundary = <Piece, List<int>>{};
    for (var i = 0; i < families.length; i++) {
      byBoundary.putIfAbsent(families[i].boundary!, () => []).add(i);
    }
    for (final e in byBoundary.entries) {
      final fs = [for (final i in e.value) families[i]];
      final first = fs.first;
      var pattern = '_USER';
      var angle = first.angle;
      final spacing = first.spacing;
      var scale = 1.0;
      final crossed =
          fs.length >= 2 &&
          ((fs[0].angle - fs[1].angle).abs() - 90).abs() < 1 &&
          (fs[0].spacing - fs[1].spacing).abs() < 0.05 * fs[0].spacing;
      if (crossed && fs.any((x) => (x.angle - 45).abs() < 1)) {
        pattern = 'ANSI37';
        angle = 0;
        scale = first.spacing / 3.175;
      } else if (!crossed && (angle - 45).abs() < 1) {
        pattern = 'ANSI31';
        angle = 0;
        scale = spacing / 3.175;
      } else if (crossed) {
        pattern = '_USER_DOUBLE';
        angle = fs.map((x) => x.angle).reduce(math.min);
      }
      hatches.add(
        FoundHatch(
          [e.key.v],
          first.rgb,
          first.layer,
          pattern: pattern,
          angle: angle,
          spacing: spacing,
          patternScale: scale,
        ),
      );
      for (final x in fs) {
        usedLines.addAll(x.lines);
      }
    }
    loose.removeWhere(usedLines.contains);
  }

  // ---------------------------------------------------------------- solid fills
  for (final fl in freeFills) {
    hatches.insert(0, FoundHatch(fl.loops, fl.rgb, fl.layer));
  }
  return Recognised(loose, hatches, dims, freeTexts);
}
