// Turns what a PDF page drew into a proper CAD drawing, the way a draughtsman would redraw it:
//
//  - pieces that meet end to end become one polyline (closed when they come back to the start)
//  - Bézier curves that follow a circle become arcs (bulges), whole circles become circles
//  - rows of short dashes along one line become one line with its standard line type (DASHED,
//    CENTER, PHANTOM, DOT, DASHDOT, DIVIDE, BORDER) and its line-type scale
//  - filled shapes become solid hatches; parallel lines filling an outline become a pattern hatch
//  - dimension lines with their arrows and value become real dimensions
//  - text becomes text: one TEXT per word or line, at its size and angle
//  - everything goes on a layer: the PDF's own layers when it has them, else one per colour and
//    line type; colours are AutoCAD's standard colours, lineweights the standard ones
//
// Work is in millimetres on paper; at the end everything is scaled to the drawing units.
import 'dart:math' as math;

import '../aci.dart';
import 'cad.dart';
import 'pdf_content.dart';
import 'recognise.dart';

class PdfDraftOptions {
  const PdfDraftOptions({this.scale, this.useLayers = true, this.findDimensions = true, this.findHatches = true});

  /// 1:scale, the drawing in metres; null: millimetres on paper, as printed
  final int? scale;

  /// use the PDF's own layers when it has them
  final bool useLayers;
  final bool findDimensions, findHatches;
}

const _mm = 25.4 / 72;

// ---------------------------------------------------------------------------------------------
// Pieces: polylines in paper millimetres, with their pen
// ---------------------------------------------------------------------------------------------

class Pen {
  const Pen(this.rgb, this.widthMm, this.layer, {this.lineType = 'CONTINUOUS', this.ltScale = 1});
  final int rgb;
  final double widthMm;
  final String? layer;
  final String lineType;

  /// line-type scale on paper
  final double ltScale;

  bool same(Pen o) =>
      rgb == o.rgb &&
      (widthMm - o.widthMm).abs() < 0.02 &&
      layer == o.layer &&
      lineType == o.lineType &&
      (ltScale - o.ltScale).abs() <= 0.08 * math.max(ltScale, o.ltScale);

  Pen withLineType(String lt, double scale) => Pen(rgb, widthMm, layer, lineType: lt, ltScale: scale);
}

class V {
  const V(this.x, this.y, [this.b = 0]);
  final double x, y;

  /// bulge of the piece to the next vertex
  final double b;
  V withB(double nb) => V(x, y, nb);
  double dist(V o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

class Piece {
  Piece(this.v, this.closed, this.pen, this.order);
  List<V> v;
  bool closed;
  Pen pen;
  final int order;
  bool used = false;

  bool get straightSingle => !closed && v.length == 2 && v[0].b == 0;
  bool get arcSingle => !closed && v.length == 2 && v[0].b != 0;
  double get length {
    var l = 0.0;
    for (var i = 0; i + 1 < v.length; i++) {
      l += _segLength(v[i], v[i + 1]);
    }
    return l;
  }

  Piece reversed() {
    final n = v.length;
    final out = <V>[];
    for (var i = n - 1; i >= 0; i--) {
      final b = i - 1 >= 0 ? -v[i - 1].b : 0.0;
      out.add(V(v[i].x, v[i].y, b));
    }
    return Piece(out, closed, pen, order);
  }
}

double _segLength(V a, V b) {
  final c = a.dist(b);
  if (a.b == 0) return c;
  final sweep = 4 * math.atan(a.b.abs());
  final r = c / (2 * math.sin(sweep / 2));
  return r * sweep;
}

/// Centre, radius and signed sweep of the bulged piece from [a] to [b]
({double cx, double cy, double r, double sweep}) arcOf(V a, V b) {
  final sweep = 4 * math.atan(a.b);
  final c = a.dist(b);
  final r = c / (2 * math.sin(sweep.abs() / 2));
  final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
  // distance from the chord's middle to the centre
  final h = math.sqrt(math.max(0, r * r - c * c / 4));
  final ux = (b.x - a.x) / c, uy = (b.y - a.y) / c;
  // the centre is to the left for an anticlockwise arc smaller than a half circle
  final s = (sweep > 0) == (sweep.abs() < math.pi) ? 1.0 : -1.0;
  return (cx: mx - uy * h * s, cy: my + ux * h * s, r: r, sweep: sweep);
}

/// A curve that follows a circle: its signed sweep in radians; null when it doesn't
double? _fitArc(Seg s) {
  final a = s.a, b = s.b, m = s.at(0.5);
  final d = 2 * (a.x * (m.y - b.y) + m.x * (b.y - a.y) + b.x * (a.y - m.y));
  if (d.abs() < 1e-9) return null;
  final a2 = a.x * a.x + a.y * a.y, m2 = m.x * m.x + m.y * m.y, b2 = b.x * b.x + b.y * b.y;
  final cx = (a2 * (m.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - m.y)) / d;
  final cy = (a2 * (b.x - m.x) + m2 * (a.x - b.x) + b2 * (m.x - a.x)) / d;
  final r = math.sqrt((a.x - cx) * (a.x - cx) + (a.y - cy) * (a.y - cy));
  if (r > 1e5 || r < 1e-4) return null;
  final tol = math.max(0.01, 0.002 * r);
  for (final t in const [0.1, 0.25, 0.75, 0.9]) {
    final q = s.at(t);
    if ((math.sqrt((q.x - cx) * (q.x - cx) + (q.y - cy) * (q.y - cy)) - r).abs() > tol) return null;
  }
  double ang(P2 p) => math.atan2(p.y - cy, p.x - cx);
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final ta = ang(a), tm = ang(m), tb = ang(b);
  final ccw = norm(tb - ta);
  if (norm(tm - ta) < ccw) return ccw;
  return -(2 * math.pi - ccw);
}

/// A subpath as vertices with bulges; curves that aren't arcs are followed with short pieces
List<V> _vertices(SubPath sp) {
  P2 mm(P2 p) => P2(p.x * _mm, p.y * _mm);
  final out = <V>[V(sp.start.x * _mm, sp.start.y * _mm)];
  for (final s0 in sp.segs) {
    final s = Seg(mm(s0.a), mm(s0.b), s0.c1 == null ? null : mm(s0.c1!), s0.c2 == null ? null : mm(s0.c2!));
    if (!s.curved || s.a.dist(s.c1!) + s.c1!.dist(s.c2!) + s.c2!.dist(s.b) - s.a.dist(s.b) < 1e-4) {
      if (s.a.dist(s.b) > 1e-6) out.add(V(s.b.x, s.b.y));
      continue;
    }
    final sweep = _fitArc(s);
    if (sweep != null) {
      out[out.length - 1] = out.last.withB(math.tan(sweep / 4));
      out.add(V(s.b.x, s.b.y));
    } else {
      for (var i = 1; i <= 8; i++) {
        final q = s.at(i / 8);
        out.add(V(q.x, q.y));
      }
    }
  }
  return _tidy(out, closed: sp.closed);
}

/// Joins arcs of one circle and drops in-between points of straight runs
List<V> _tidy(List<V> v0, {required bool closed}) {
  var v = List<V>.of(v0);
  if (closed && v.length > 2 && v.first.dist(v.last) < 1e-4) v = v.sublist(0, v.length - 1);
  var changed = true;
  while (changed && v.length > 2) {
    changed = false;
    final n = v.length;
    final limit = closed ? n : n - 1;
    for (var i = 1; i < limit; i++) {
      final prev = v[(i - 1) % n], cur = v[i % n], next = v[(i + 1) % n];
      if (!closed && i + 1 >= n) break;
      if (prev.b == 0 && cur.b == 0) {
        // straight, straight: drop the middle point when it lies on the line
        final dx = next.x - prev.x, dy = next.y - prev.y;
        final l = math.sqrt(dx * dx + dy * dy);
        if (l < 1e-9) continue;
        final off = ((cur.x - prev.x) * dy - (cur.y - prev.y) * dx).abs() / l;
        final along = ((cur.x - prev.x) * dx + (cur.y - prev.y) * dy) / (l * l);
        if (off < 0.01 && along > 0 && along < 1) {
          v.removeAt(i % n);
          changed = true;
          break;
        }
      } else if (prev.b != 0 && cur.b != 0) {
        final a1 = arcOf(prev, cur), a2 = arcOf(cur, next);
        final tol = math.max(0.02, 0.003 * a1.r);
        if ((a1.cx - a2.cx).abs() < tol &&
            (a1.cy - a2.cy).abs() < tol &&
            (a1.r - a2.r).abs() < tol &&
            (a1.sweep > 0) == (a2.sweep > 0)) {
          final total = a1.sweep + a2.sweep;
          if (total.abs() < 2 * math.pi - 0.05) {
            v[(i - 1) % n] = prev.withB(math.tan(total / 4));
            v.removeAt(i % n);
            changed = true;
            break;
          }
        }
      }
    }
  }
  return v;
}

// ---------------------------------------------------------------------------------------------
// Dashes → line types
// ---------------------------------------------------------------------------------------------

/// What line type a row of dashes is: its name and its period (one repeat, mm); null if none fits
(String, double)? classifyDashes(List<double> dashes, List<double> starts) {
  if (dashes.length < 3) return null;
  final maxD = dashes.reduce(math.max);
  if (maxD <= 0.35) {
    final steps = [for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1]]..sort();
    return ('DOT', steps[steps.length ~/ 2]);
  }
  final kinds = [for (final d in dashes) d <= math.max(0.35, 0.06 * maxD) ? 'D' : (d >= 0.55 * maxD ? 'L' : 'S')];
  // the groups that start at each long dash
  final groupStarts = <int>[];
  for (var i = 0; i < kinds.length; i++) {
    if (kinds[i] == 'L') groupStarts.add(i);
  }
  if (groupStarts.length < 2) {
    // all short and alike: a dashed line
    if (!kinds.contains('L') && !kinds.contains('D')) return null;
    return null;
  }
  final groups = <String>[];
  for (var g = 0; g + 1 < groupStarts.length; g++) {
    groups.add(kinds.sublist(groupStarts[g], groupStarts[g + 1]).join());
  }
  String majority(Iterable<String> xs) {
    final c = <String, int>{};
    for (final x in xs) {
      c[x] = (c[x] ?? 0) + 1;
    }
    return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  final unit = majority(groups);
  String? type = switch (unit) {
    'L' => 'DASHED',
    'LS' => 'CENTER',
    'LSS' => 'PHANTOM',
    'LD' => 'DASHDOT',
    'LDD' => 'DIVIDE',
    _ => null,
  };
  // BORDER: long, long, dot, which splits into "L" and "LD" in turn
  if (type == 'DASHED' && groups.contains('LD')) type = 'BORDER';
  if (type == 'DASHDOT' && groups.where((g) => g == 'L').length >= groups.length / 3) type = 'BORDER';
  if (type == null) return null;
  // the period: from one repeat's first long dash to the next
  final periodStarts = <double>[];
  for (var g = 0; g < groupStarts.length; g++) {
    final i = groupStarts[g];
    if (type == 'BORDER') {
      // a repeat starts at a long dash that follows a dot (or the first)
      if (i == 0 || kinds[i - 1] == 'D' || periodStarts.isEmpty) periodStarts.add(starts[i]);
    } else {
      periodStarts.add(starts[i]);
    }
  }
  if (periodStarts.length < 2) return null;
  final steps = [for (var i = 1; i < periodStarts.length; i++) periodStarts[i] - periodStarts[i - 1]]..sort();
  return (type, steps[steps.length ~/ 2]);
}

/// Rows of short straight pieces along one line, evenly spaced, become one line with a line type
List<Piece> _mergeDashes(List<Piece> pieces) {
  final out = <Piece>[];
  final cands = pieces.where((p) => p.straightSingle && p.pen.lineType == 'CONTINUOUS' && p.length < 60).toList();
  // by pen
  final byPen = <String, List<Piece>>{};
  for (final p in cands) {
    byPen.putIfAbsent('${p.pen.rgb}|${p.pen.widthMm.toStringAsFixed(2)}|${p.pen.layer}', () => []).add(p);
  }
  for (final group in byPen.values) {
    // by direction and offset
    final items = [
      for (final p in group)
        () {
          var dx = p.v[1].x - p.v[0].x, dy = p.v[1].y - p.v[0].y;
          var th = math.atan2(dy, dx);
          if (th < 0) th += math.pi;
          if (th >= math.pi - 1e-6) th -= math.pi;
          final ux = math.cos(th), uy = math.sin(th);
          final rho = -uy * p.v[0].x + ux * p.v[0].y;
          final ta = ux * p.v[0].x + uy * p.v[0].y, tb = ux * p.v[1].x + uy * p.v[1].y;
          dx = ux;
          dy = uy;
          return (p: p, th: th, rho: rho, t0: math.min(ta, tb), t1: math.max(ta, tb), ux: ux, uy: uy);
        }(),
    ]..sort((a, b) => a.th.compareTo(b.th));
    // cluster by angle, then by offset
    final lines = <List<({Piece p, double th, double rho, double t0, double t1, double ux, double uy})>>[];
    var cur = <({Piece p, double th, double rho, double t0, double t1, double ux, double uy})>[];
    for (final it in items) {
      if (cur.isNotEmpty && (it.th - cur.last.th).abs() > 0.004) {
        lines.add(cur);
        cur = [];
      }
      cur.add(it);
    }
    if (cur.isNotEmpty) lines.add(cur);
    for (final ang in lines) {
      ang.sort((a, b) => a.rho.compareTo(b.rho));
      final rows = <List<({Piece p, double th, double rho, double t0, double t1, double ux, double uy})>>[];
      var row = <({Piece p, double th, double rho, double t0, double t1, double ux, double uy})>[];
      for (final it in ang) {
        if (row.isNotEmpty && (it.rho - row.last.rho).abs() > 0.05) {
          rows.add(row);
          row = [];
        }
        row.add(it);
      }
      if (row.isNotEmpty) rows.add(row);
      for (final r in rows) {
        if (r.length < 3) continue;
        r.sort((a, b) => a.t0.compareTo(b.t0));
        // chains of evenly spaced dashes
        var chain = [r.first];
        void finish() {
          if (chain.length >= 3) {
            final dashes = [for (final c in chain) c.t1 - c.t0];
            final starts = [for (final c in chain) c.t0];
            // the ends may be cut short: classify on the inner dashes when there are enough
            final inner = chain.length >= 6;
            final kind = classifyDashes(
              inner ? dashes.sublist(1, dashes.length - 1) : dashes,
              inner ? starts.sublist(1, starts.length - 1) : starts,
            );
            final type =
                kind ??
                (dashes.every((d) => (d - dashes[1]).abs() < 0.2 * dashes[1] + 0.05)
                    ? ('DASHED', chain[1].t0 - chain[0].t0)
                    : null);
            if (type != null) {
              final first = chain.first, last = chain.last;
              final rho = first.rho;
              V at(double t) => V(first.ux * t - first.uy * rho, first.uy * t + first.ux * rho);
              final pen = first.p.pen.withLineType(type.$1, type.$2 / standardPeriod(type.$1));
              out.add(Piece([at(first.t0), at(last.t1)], false, pen, first.p.order));
              for (final c in chain) {
                c.p.used = true;
              }
            }
          }
        }

        for (var i = 1; i < r.length; i++) {
          final gap = r[i].t0 - chain.last.t1;
          final gaps = [for (var k = 1; k < chain.length; k++) chain[k].t0 - chain[k - 1].t1];
          final typical = gaps.isEmpty ? gap : (gaps.toList()..sort())[gaps.length ~/ 2];
          // a line type's gaps are never much longer than its dashes (dots aside): the arms of a
          // row of grid crosses aren't a dashed line
          final longest = math.max(chain.map((c) => c.t1 - c.t0).reduce(math.max), r[i].t1 - r[i].t0);
          final fits = longest <= 0.35 ? gap <= 10 : gap <= 1.25 * longest;
          final ok = gap > 0.05 && gap < 25 && fits && (gaps.isEmpty || (gap - typical).abs() <= 0.35 * typical + 0.1);
          if (ok) {
            chain.add(r[i]);
          } else {
            finish();
            chain = [r[i]];
          }
        }
        finish();
      }
    }
  }
  return out;
}

/// Short arcs of one circle, evenly spaced, become one arc (or circle) with a line type
List<Piece> _mergeArcDashes(List<Piece> pieces) {
  final out = <Piece>[];
  final cands = [
    for (final p in pieces)
      if (p.arcSingle && p.pen.lineType == 'CONTINUOUS' && !p.used) (p: p, a: arcOf(p.v[0], p.v[1])),
  ];
  cands.sort((x, y) => x.a.r.compareTo(y.a.r));
  final used = <int>{};
  for (var i = 0; i < cands.length; i++) {
    if (used.contains(i)) continue;
    final base = cands[i];
    final tol = math.max(0.05, 0.003 * base.a.r);
    final same = <int>[i];
    for (var j = i + 1; j < cands.length && cands[j].a.r - base.a.r <= tol; j++) {
      final c = cands[j];
      if (!used.contains(j) &&
          (c.a.cx - base.a.cx).abs() < tol &&
          (c.a.cy - base.a.cy).abs() < tol &&
          c.p.pen.same(base.p.pen)) {
        same.add(j);
      }
    }
    if (same.length < 3) continue;
    // each dash as an anticlockwise angle range
    final r = base.a.r, cx = base.a.cx, cy = base.a.cy;
    double norm(double x) {
      var v = x % (2 * math.pi);
      if (v < 0) v += 2 * math.pi;
      return v;
    }

    final dashes = [
      for (final k in same)
        () {
          final c = cands[k];
          final s = math.atan2(c.p.v[0].y - cy, c.p.v[0].x - cx);
          final e = math.atan2(c.p.v[1].y - cy, c.p.v[1].x - cx);
          final a0 = c.a.sweep > 0 ? norm(s) : norm(e);
          return (k: k, a0: a0, len: c.a.sweep.abs());
        }(),
    ]..sort((x, y) => x.a0.compareTo(y.a0));
    final lens = [for (final d in dashes) d.len * r];
    final starts = [for (final d in dashes) d.a0 * r];
    final gaps = [for (var k = 1; k < dashes.length; k++) (dashes[k].a0 - dashes[k - 1].a0 - dashes[k - 1].len) * r];
    if (gaps.isEmpty) continue;
    final sorted = [...gaps]..sort();
    final typical = sorted[sorted.length ~/ 2];
    if (typical <= 0.05 || gaps.any((g) => (g - typical).abs() > 0.35 * typical + 0.1 && g < 4 * typical)) continue;
    final longestArc = lens.reduce(math.max);
    if (longestArc <= 0.35 ? typical > 10 : typical > 1.25 * longestArc) continue;
    final kind =
        classifyDashes(lens, starts) ??
        (lens.every((d) => (d - lens[1]).abs() < 0.2 * lens[1] + 0.05) ? ('DASHED', starts[1] - starts[0]) : null);
    if (kind == null) continue;
    // a full circle when the dashes go all the way round
    final covered =
        dashes.fold(0.0, (a, d) => a + d.len) + gaps.where((g) => g < 4 * typical).fold(0.0, (a, g) => a + g / r);
    final pen = base.p.pen.withLineType(kind.$1, kind.$2 / standardPeriod(kind.$1));
    if (covered > 2 * math.pi - 2 * typical / r) {
      out.add(_circlePiece(cx, cy, r, pen, base.p.order));
    } else {
      // from the dash after the biggest gap all the way round to the dash before it
      var big = 0;
      for (var k = 1; k < gaps.length; k++) {
        if (gaps[k] > gaps[big]) big = k;
      }
      final wrapGap = 2 * math.pi - (dashes.last.a0 + dashes.last.len) + dashes.first.a0;
      double startA, endA;
      if (wrapGap * r >= gaps[big]) {
        startA = dashes.first.a0;
        endA = dashes.last.a0 + dashes.last.len;
      } else {
        startA = dashes[big + 1].a0;
        endA = dashes[big].a0 + dashes[big].len + 2 * math.pi;
      }
      final sweep = endA - startA;
      out.add(
        Piece(
          [
            V(cx + r * math.cos(startA), cy + r * math.sin(startA), math.tan(sweep / 4)),
            V(cx + r * math.cos(endA), cy + r * math.sin(endA)),
          ],
          false,
          pen,
          base.p.order,
        ),
      );
    }
    for (final k in same) {
      used.add(k);
      cands[k].p.used = true;
    }
  }
  return out;
}

/// Dashed lines stop where their last dash ends, short of the corner: where two with the same pen
/// end near each other and aren't in line, both are taken on to the corner
List<Piece> _meetAtCorners(List<Piece> lines) {
  final straight = [
    for (final p in lines)
      if (p.straightSingle) p,
  ];
  for (var i = 0; i < straight.length; i++) {
    for (var j = i + 1; j < straight.length; j++) {
      final a = straight[i], b = straight[j];
      if (!a.pen.same(b.pen)) continue;
      final reach = 1.2 * a.pen.ltScale * standardPeriod(a.pen.lineType);
      for (final ea in [0, 1]) {
        for (final eb in [0, 1]) {
          final pa = a.v[ea], pb = b.v[eb];
          if (pa.dist(pb) > reach) continue;
          // where the two lines cross
          final d1x = a.v[1].x - a.v[0].x, d1y = a.v[1].y - a.v[0].y;
          final d2x = b.v[1].x - b.v[0].x, d2y = b.v[1].y - b.v[0].y;
          final den = d1x * d2y - d1y * d2x;
          if (den.abs() < 1e-9 * (d1x * d1x + d1y * d1y + d2x * d2x + d2y * d2y)) continue;
          final t = ((b.v[0].x - a.v[0].x) * d2y - (b.v[0].y - a.v[0].y) * d2x) / den;
          final x = V(a.v[0].x + t * d1x, a.v[0].y + t * d1y);
          if (x.dist(pa) > reach || x.dist(pb) > reach) continue;
          a.v[ea] = x;
          b.v[eb] = x;
        }
      }
    }
  }
  return lines;
}

Piece _circlePiece(double cx, double cy, double r, Pen pen, int order) =>
    Piece([V(cx + r, cy, 1), V(cx - r, cy, 1)], true, pen, order);

// ---------------------------------------------------------------------------------------------
// Joining pieces end to end
// ---------------------------------------------------------------------------------------------

List<Piece> _join(List<Piece> pieces) {
  const tol = 0.05;
  final open = pieces.where((p) => !p.closed && p.v.length >= 2).toList();
  final done = pieces.where((p) => p.closed || p.v.length < 2).toList();
  // every end, on a grid
  final grid = <String, List<(int, bool)>>{};
  String key(double x, double y) => '${(x / tol).round()},${(y / tol).round()}';
  Iterable<(int, bool)> near(double x, double y) sync* {
    final kx = (x / tol).round(), ky = (y / tol).round();
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        yield* grid['${kx + i},${ky + j}'] ?? const [];
      }
    }
  }

  for (var i = 0; i < open.length; i++) {
    final p = open[i];
    grid.putIfAbsent(key(p.v.first.x, p.v.first.y), () => []).add((i, false));
    grid.putIfAbsent(key(p.v.last.x, p.v.last.y), () => []).add((i, true));
  }
  V endOf(int i, bool atEnd) => atEnd ? open[i].v.last : open[i].v.first;
  // the one other end that meets this one, when exactly two ends meet there and they share a pen
  (int, bool)? partner(int i, bool atEnd) {
    final e = endOf(i, atEnd);
    final there = [
      for (final c in near(e.x, e.y))
        if (endOf(c.$1, c.$2).dist(e) <= tol) c,
    ];
    if (there.length != 2) return null;
    final other = there.firstWhere((c) => !(c.$1 == i && c.$2 == atEnd), orElse: () => (-1, false));
    if (other.$1 < 0 || other.$1 == i && open[i].v.length <= 2) return null;
    if (!open[other.$1].pen.same(open[i].pen)) return null;
    return other;
  }

  final visited = List.filled(open.length, false);
  final out = <Piece>[...done];
  for (var s = 0; s < open.length; s++) {
    if (visited[s]) continue;
    // walk back to the start of the chain
    var startI = s;
    var startAtEnd = false; // we enter the piece at its start
    final seen = <int>{s};
    while (true) {
      final pr = partner(startI, startAtEnd);
      if (pr == null || seen.contains(pr.$1)) break;
      seen.add(pr.$1);
      startI = pr.$1;
      startAtEnd = !pr.$2;
    }
    // then forwards, gathering
    var verts = <V>[];
    var i = startI;
    var reversed = startAtEnd;
    var closed = false;
    final chainSeen = <int>{};
    while (true) {
      visited[i] = true;
      chainSeen.add(i);
      final p = reversed ? open[i].reversed() : open[i];
      if (verts.isEmpty) {
        verts = List.of(p.v);
      } else {
        verts.removeLast();
        verts.addAll(p.v);
      }
      final exitAtEnd = !reversed;
      final pr = partner(i, exitAtEnd);
      if (pr == null) break;
      if (pr.$1 == startI && pr.$2 == startAtEnd) {
        closed = true;
        break;
      }
      if (chainSeen.contains(pr.$1) || visited[pr.$1]) break;
      i = pr.$1;
      reversed = pr.$2;
    }
    if (closed && verts.length > 1) {
      // the last point is the first again
      final last = verts.removeLast();
      verts[verts.length - 1] = verts.last;
      if (verts.first.dist(last) > tol) verts.add(last);
    }
    out.add(Piece(_tidy(verts, closed: closed), closed, open[startI].pen, open[startI].order));
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// The page
// ---------------------------------------------------------------------------------------------

const _colourNames = {
  1: 'RED',
  2: 'YELLOW',
  3: 'GREEN',
  4: 'CYAN',
  5: 'BLUE',
  6: 'MAGENTA',
  7: 'WHITE',
  8: 'GREY',
  9: 'LIGHTGREY',
};

/// The AutoCAD colour for a PDF colour: the standard one when it is one, else the nearest
int aciOf(int rgb) {
  final r = rgb >> 16 & 0xFF, g = rgb >> 8 & 0xFF, b = rgb & 0xFF;
  if (r == g && g == b && (r < 24 || r > 240)) return 7;
  var best = 7;
  var bestD = 1 << 30;
  for (var i = 1; i <= 255; i++) {
    final (cr, cg, cb) = aciRgb(i);
    final d = (cr - r) * (cr - r) * 3 + (cg - g) * (cg - g) * 4 + (cb - b) * (cb - b) * 2;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// RED, GREEN … for the standard colours; for the others their hue and number (GREEN-94)
String colourName(int aci) {
  final named = _colourNames[aci];
  if (named != null) return named;
  final (r, g, b) = aciRgb(aci);
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  if (mx - mn < 30) return 'GREY-$aci';
  double h;
  if (mx == r) {
    h = 60 * (((g - b) / (mx - mn)) % 6);
  } else if (mx == g) {
    h = 60 * ((b - r) / (mx - mn) + 2);
  } else {
    h = 60 * ((r - g) / (mx - mn) + 4);
  }
  final hue = switch (h) {
    < 15 => 'RED',
    < 45 => 'ORANGE',
    < 70 => 'YELLOW',
    < 160 => 'GREEN',
    < 200 => 'CYAN',
    < 260 => 'BLUE',
    < 330 => 'MAGENTA',
    _ => 'RED',
  };
  return '$hue-$aci';
}

/// A layer name AutoCAD accepts
String layerName(String s) {
  final t = s.replaceAll(RegExp(r'[<>/\\":;?*|=`,]'), '_').trim();
  return t.isEmpty ? 'LAYER' : (t.length > 200 ? t.substring(0, 200) : t);
}

class PageDraft {
  PageDraft(this.drawing, this.pieces, {this.suggestedScale});
  final CadDrawing drawing;

  /// the scale the page's dimensions say it is at (1:n), when it has dimensions with values
  final int? suggestedScale;

  /// how many strokes, fills and texts the page had
  final ({int strokes, int fills, int texts, int images}) pieces;
}

/// Redraws [page] as a CAD drawing
PageDraft draftPage(PageContent page, PdfDraftOptions o) {
  final f = o.scale == null ? 1.0 : o.scale! / 1000; // paper mm → drawing units
  final cad = CadDrawing(units: o.scale == null ? 'mm' : 'm', scale: o.scale ?? 1);
  final pageW = page.width * _mm, pageH = page.height * _mm;
  final hasLayers = o.useLayers && page.paths.any((p) => p.layer != null);

  // ---- strokes and fills
  final pieces = <Piece>[];
  final fills = <({List<List<V>> loops, int rgb, String? layer, int order})>[];
  var strokes = 0, fillCount = 0;
  for (final p in page.paths) {
    if (p.stroke) {
      strokes++;
      var pen = Pen(p.strokeRgb, p.width * _mm, p.layer);
      final dash = [for (final d in p.dash) d * _mm];
      if (dash.isNotEmpty && dash.any((d) => d > 0.01)) {
        // a dash pattern from the PDF itself
        final starts = <double>[];
        final lens = <double>[];
        var pos = 0.0;
        for (var k = 0; k < 8 * dash.length; k++) {
          if (k.isEven) {
            starts.add(pos);
            lens.add(dash[k % dash.length]);
          }
          pos += dash[k % dash.length];
        }
        final kind =
            classifyDashes(lens, starts) ?? ('DASHED', dash.fold(0.0, (a, b) => a + b) * (dash.length.isOdd ? 2 : 1));
        pen = pen.withLineType(kind.$1, kind.$2 / standardPeriod(kind.$1));
      }
      for (final sp in p.subs) {
        final v = _vertices(sp);
        if (v.length < 2 && !(v.length == 1 && sp.segs.isNotEmpty)) continue;
        // a single point drawn as a zero-length line (a dot)
        final pts = v.length == 1 ? [v.first, v.first] : v;
        // a closed path whose two halves are arcs of one circle: a circle
        pieces.add(Piece(pts, sp.closed && pts.length > 2, pen, p.order));
      }
    }
    if (p.fill) {
      fillCount++;
      final r = p.fillRgb >> 16 & 0xFF, g = p.fillRgb >> 8 & 0xFF, b = p.fillRgb & 0xFF;
      if (r > 245 && g > 245 && b > 245) continue; // white: a mask or the paper
      final loops = [
        for (final sp in p.subs) _vertices(sp),
      ].where((l) => l.length >= 3 || l.length == 2 && l[0].b != 0).toList();
      if (loops.isEmpty) continue;
      // the whole page filled: a background, not part of the drawing
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (final l in loops) {
        for (final q in l) {
          minX = math.min(minX, q.x);
          maxX = math.max(maxX, q.x);
          minY = math.min(minY, q.y);
          maxY = math.max(maxY, q.y);
        }
      }
      if (maxX - minX > 0.9 * pageW && maxY - minY > 0.9 * pageH) continue;
      fills.add((loops: loops, rgb: p.fillRgb, layer: p.layer, order: p.order));
    }
  }

  // ---- dashes into line types, then pieces joined end to end
  final dashed = _meetAtCorners([..._mergeDashes(pieces), ..._mergeArcDashes(pieces)]);
  final rest = [
    for (final p in pieces)
      if (!p.used) p,
  ];
  final joined = _join([...rest, ...dashed]);

  // ---- text: runs on one baseline joined into words and lines
  final texts = _joinText([
    for (final t in page.texts)
      if (!t.invisible) t,
  ]);
  final hidden = page.texts.where((t) => t.invisible).length;

  // ---- dimensions and pattern hatches (recognise.dart)
  final found = recognise(joined, fills, texts, findDimensions: o.findDimensions, findHatches: o.findHatches);

  // ---- layers
  String layerFor(String kind, int aci, String lineType, String? pdfLayer) {
    if (hasLayers && pdfLayer != null) return layerName(pdfLayer);
    return switch (kind) {
      'text' => 'TEXT',
      'hatch' => 'HATCH',
      'dim' => 'DIMENSIONS',
      _ => lineType == 'CONTINUOUS' ? 'LINES-${colourName(aci)}' : 'LINES-${colourName(aci)}-$lineType',
    };
  }

  // what each layer mostly holds, so it can carry the colour, line type and lineweight
  final tally = <String, Map<String, int>>{};
  void count(String layer, String what) {
    final m = tally.putIfAbsent(layer, () => {});
    m[what] = (m[what] ?? 0) + 1;
  }

  final staged = <(String, int, String, double, int, CadEntity Function(CadStyle))>[];
  void stage(
    String kind,
    int rgb,
    String lineType,
    double ltScale,
    double widthMm,
    String? pdfLayer,
    CadEntity Function(CadStyle) make,
  ) {
    final aci = aciOf(rgb);
    final lw = nearestLineWeight(widthMm);
    final layer = layerFor(kind, aci, lineType, pdfLayer);
    count(layer, 'c$aci');
    count(layer, 'l$lineType');
    count(layer, 'w$lw');
    staged.add((layer, aci, lineType, ltScale, lw, make));
  }

  // solid fills first, so lines and text sit on top of them
  for (final h in found.hatches) {
    stage('hatch', h.rgb, 'CONTINUOUS', 1, 0, h.layer, (s) {
      return CadHatch(
        s,
        [
          for (final l in h.loops) [for (final q in l) CadVertex(q.x * f, q.y * f, q.b)],
        ],
        pattern: h.pattern,
        angle: h.angle,
        spacing: h.spacing * f,
        patternScale: h.patternScale * f,
      );
    });
  }
  for (final d in found.dimensions) {
    stage('dim', d.rgb, 'CONTINUOUS', 1, d.widthMm, d.layer, (s) => d.build(s, f));
  }
  for (final p in found.pieces) {
    stage(
      'line',
      p.pen.rgb,
      p.pen.lineType,
      p.pen.lineType == 'CONTINUOUS' ? 1 : p.pen.ltScale * f,
      p.pen.widthMm,
      p.pen.layer,
      (s) => _entity(p, s, f),
    );
  }
  for (final t in found.texts) {
    final style = cad.textStyles.keys.firstWhere(
      (k) => k == t.style,
      orElse: () {
        cad.textStyles[t.style] = t.fontFile;
        return t.style;
      },
    );
    stage(
      'text',
      t.rgb,
      'CONTINUOUS',
      1,
      0,
      t.layer,
      (s) => CadText(s, t.text, t.x * f, t.y * f, t.height * f, t.angle, style),
    );
  }

  // each layer takes what most of its objects are; objects that differ say so themselves
  for (final e in tally.entries) {
    String top(String prefix) {
      final xs = e.value.entries.where((x) => x.key.startsWith(prefix)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return xs.first.key.substring(1);
    }

    final l = cad.layer(e.key);
    l.aci = int.parse(top('c'));
    l.lineType = top('l');
    l.lineWeight = int.parse(top('w'));
  }
  for (final (layer, aci, lineType, ltScale, lw, make) in staged) {
    final l = cad.layers[layer]!;
    cad.entities.add(
      make(
        CadStyle(
          layer: layer,
          aci: aci == l.aci ? 256 : aci,
          lineType: lineType == l.lineType ? 'BYLAYER' : lineType,
          ltScale: (ltScale - 1).abs() < 1e-3 ? 1 : ltScale,
          lineWeight: lw == l.lineWeight ? -1 : lw,
        ),
      ),
    );
  }

  // ---- notes for the person
  final imageArea = page.images.fold(0.0, (a, r) => a + (r[2] - r[0]) * (r[3] - r[1])) * _mm * _mm;
  if (imageArea > 0.3 * pageW * pageH) {
    cad.notes.add(
      strokes < 20
          ? 'This page is a scanned picture, not a CAD drawing: it has no lines to draft. Use a PDF printed from CAD.'
          : 'Part of this page is a picture (a scan or photo): only its lines and text are drafted.',
    );
  }
  if (hidden > 0) cad.notes.add('$hidden pieces of hidden text (from text recognition on a scan) were left out.');
  final tiny = found.pieces.where((p) => p.length < 1.5 && p.v.length <= 3).length;
  if (tiny > 200 && texts.length < 5) {
    cad.notes.add('The text on this page seems to be drawn as lines (AutoCAD SHX fonts), so it stays as lines.');
  }
  return PageDraft(cad, (
    strokes: strokes,
    fills: fillCount,
    texts: page.texts.length,
    images: page.images.length,
  ), suggestedScale: found.suggestedScale);
}

CadEntity _entity(Piece p, CadStyle s, double f) {
  final v = p.v;
  // a circle: closed, every piece an arc of one circle, all the way round
  if (p.closed && v.every((q) => q.b != 0)) {
    final arcs = [for (var i = 0; i < v.length; i++) arcOf(v[i], v[(i + 1) % v.length])];
    final a0 = arcs.first;
    final tol = math.max(0.02, 0.003 * a0.r);
    final total = arcs.fold(0.0, (a, x) => a + x.sweep);
    if (arcs.every((a) => (a.cx - a0.cx).abs() < tol && (a.cy - a0.cy).abs() < tol && (a.r - a0.r).abs() < tol) &&
        (total.abs() - 2 * math.pi).abs() < 0.05) {
      return CadCircle(s, a0.cx * f, a0.cy * f, a0.r * f);
    }
  }
  if (!p.closed && v.length == 2) {
    if (v[0].b == 0) return CadLine(s, v[0].x * f, v[0].y * f, v[1].x * f, v[1].y * f);
    final a = arcOf(v[0], v[1]);
    var start = math.atan2(v[0].y - a.cy, v[0].x - a.cx) * 180 / math.pi;
    var end = math.atan2(v[1].y - a.cy, v[1].x - a.cx) * 180 / math.pi;
    if (a.sweep < 0) (start, end) = (end, start);
    return CadArc(s, a.cx * f, a.cy * f, a.r * f, start, end);
  }
  return CadPolyline(s, [for (final q in v) CadVertex(q.x * f, q.y * f, q.b)], closed: p.closed);
}

// ---------------------------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------------------------

class TextItem {
  TextItem(this.text, this.x, this.y, this.height, this.angle, this.rgb, this.layer, this.font, this.order);
  String text;

  /// baseline start, paper mm
  final double x, y;

  /// capital height, paper mm
  final double height;

  /// degrees
  final double angle;
  final int rgb;
  final String? layer;
  final String font;
  final int order;
  double advance = 0;

  bool get bold => RegExp('bold|black|heavy', caseSensitive: false).hasMatch(font);
  String get family {
    final f = font.toLowerCase();
    if (f.contains('times')) return 'Times';
    if (f.contains('courier')) return 'Courier';
    if (f.contains('helvetica') || f.contains('arial')) return 'Arial';
    final base = font.split(RegExp(r'[-,]')).first.replaceAll(RegExp(r'(MT|PS)$'), '');
    return base.isEmpty ? 'Arial' : base;
  }

  String get style => bold ? '$family Bold' : family;
  String get fontFile {
    const files = {
      'Arial': ('arial.ttf', 'arialbd.ttf'),
      'Times': ('times.ttf', 'timesbd.ttf'),
      'Courier': ('cour.ttf', 'courbd.ttf'),
    };
    final pair = files[family];
    if (pair != null) return bold ? pair.$2 : pair.$1;
    return '${family.toLowerCase()}.ttf';
  }
}

/// Standard fonts don't carry their capital height: AutoCAD's text height is the capitals' height
double _capOf(String font, double given) {
  final f = font.toLowerCase();
  if (f.contains('courier')) return 0.571;
  if (f.contains('times')) return 0.662;
  if (f.contains('helvetica') || f.contains('arial')) return 0.716;
  return given;
}

List<TextItem> _joinText(List<ShownText> shown) {
  final items = [
    for (final t in shown)
      TextItem(
        t.text,
        t.origin.x * _mm,
        t.origin.y * _mm,
        t.height * _capOf(t.font, t.capHeight) * _mm,
        t.angle * 180 / math.pi,
        t.rgb,
        t.layer,
        t.font,
        t.order,
      )..advance = t.advance * _mm,
  ]..sort((a, b) => a.order.compareTo(b.order));
  final out = <TextItem>[];
  for (final t in items) {
    if (out.isNotEmpty) {
      final p = out.last;
      final a = p.angle * math.pi / 180;
      final ex = p.x + math.cos(a) * p.advance, ey = p.y + math.sin(a) * p.advance;
      final dx = t.x - ex, dy = t.y - ey;
      final along = dx * math.cos(a) + dy * math.sin(a);
      final across = -dx * math.sin(a) + dy * math.cos(a);
      if ((t.height - p.height).abs() < 0.05 * p.height &&
          (t.angle - p.angle).abs() < 0.5 &&
          t.rgb == p.rgb &&
          t.layer == p.layer &&
          t.font == p.font &&
          across.abs() < 0.2 * p.height &&
          along > -0.3 * p.height &&
          along < 0.9 * p.height) {
        p.text += (along > 0.25 * p.height && !p.text.endsWith(' ') && !t.text.startsWith(' ')) ? ' ${t.text}' : t.text;
        p.advance += along + t.advance;
        continue;
      }
    }
    out.add(t);
  }
  for (final t in out) {
    t.text = t.text.trim();
  }
  return out.where((t) => t.text.isNotEmpty).toList();
}
