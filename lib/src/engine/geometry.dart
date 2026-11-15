// The geometry behind the drawing: curves through surveyed points, the fourth corner of a
// rectangle, and the box around everything.
import 'dart:math' as math;

import 'point.dart';

double dist(Vertex a, Vertex b) => math.sqrt(math.pow(a.e - b.e, 2) + math.pow(a.n - b.n, 2));

/// The fourth corner of a rectangle from three corners in order (a, b, c): d = a + c − b
Vertex fourthCorner(Vertex a, Vertex b, Vertex c) => Vertex(a.e + c.e - b.e, a.n + c.n - b.n, a.z + c.z - b.z);

/// The angle at b, in degrees, between b→a and b→c
double cornerAngle(Vertex a, Vertex b, Vertex c) {
  final a1 = math.atan2(a.n - b.n, a.e - b.e), a2 = math.atan2(c.n - b.n, c.e - b.e);
  var d = (a1 - a2).abs() * 180 / math.pi;
  if (d > 180) d = 360 - d;
  return d;
}

/// A smooth line through the surveyed points of a curve. Three points: the circle through them.
/// More: a centripetal Catmull-Rom spline, which passes through every point without overshooting.
/// Levels change evenly along the curve between surveyed points.
List<Vertex> curveThrough(List<Vertex> pts) {
  if (pts.length < 3) return List.of(pts);
  if (pts.length == 3) {
    final arc = _arcThrough(pts[0], pts[1], pts[2]);
    if (arc != null) return arc;
  }
  return _catmullRom(pts);
}

/// The circular arc from a through b to c, as short straight pieces of at most 3° each; null when
/// the three points are (nearly) in a line
List<Vertex>? _arcThrough(Vertex a, Vertex b, Vertex c) {
  final d = 2 * (a.e * (b.n - c.n) + b.e * (c.n - a.n) + c.e * (a.n - b.n));
  final span = dist(a, c);
  if (span == 0 || d.abs() < 1e-9 * span * span) return null;
  final a2 = a.e * a.e + a.n * a.n, b2 = b.e * b.e + b.n * b.n, c2 = c.e * c.e + c.n * c.n;
  final ux = (a2 * (b.n - c.n) + b2 * (c.n - a.n) + c2 * (a.n - b.n)) / d;
  final uy = (a2 * (c.e - b.e) + b2 * (a.e - c.e) + c2 * (b.e - a.e)) / d;
  final r = math.sqrt(math.pow(a.e - ux, 2) + math.pow(a.n - uy, 2));
  if (r > 1e6) return null; // practically straight
  double ang(Vertex v) => math.atan2(v.n - uy, v.e - ux);
  final t0 = ang(a), t1 = ang(b), t2 = ang(c);
  // a → b → c turning left goes round the circle anticlockwise, and the other way round
  final ccw = (b.e - a.e) * (c.n - b.n) - (b.n - a.n) * (c.e - b.e) > 0;
  double around(double from, double to) {
    var s = (to - from) % (2 * math.pi); // 0 … 2π, anticlockwise
    if (s < 0) s += 2 * math.pi;
    return ccw ? s : s - 2 * math.pi; // clockwise: −2π … 0
  }

  final ab = around(t0, t1), total = around(t0, t2);
  final steps = math.max(4, (total.abs() / (3 * math.pi / 180)).ceil());
  final abShare = ab.abs() / total.abs();
  return [
    for (var i = 0; i <= steps; i++)
      () {
        final f = i / steps;
        final t = t0 + total * f;
        // the level: a to b over the first part, b to c over the rest
        final z = f <= abShare
            ? a.z + (b.z - a.z) * (abShare == 0 ? 0 : f / abShare)
            : b.z + (c.z - b.z) * ((f - abShare) / (1 - abShare));
        if (i == 0) return a;
        if (i == steps) return c;
        return Vertex(ux + r * math.cos(t), uy + r * math.sin(t), z);
      }(),
  ];
}

List<Vertex> _catmullRom(List<Vertex> p) {
  const pieces = 10;
  final out = <Vertex>[p.first];
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = i == 0 ? _mirror(p[1], p[0]) : p[i - 1];
    final p1 = p[i], p2 = p[i + 1];
    final p3 = i + 2 < p.length ? p[i + 2] : _mirror(p[i], p[i + 1]);
    double knot(Vertex a, Vertex b) => math.max(math.sqrt(dist(a, b)), 1e-6);
    final t1 = knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3);
    for (var s = 1; s <= pieces; s++) {
      if (s == pieces) {
        out.add(p2);
        break;
      }
      final t = t1 + (t2 - t1) * s / pieces;
      double lerp(double a, double b, double ta, double tb) => (tb - t) / (tb - ta) * a + (t - ta) / (tb - ta) * b;
      double comp(double Function(Vertex) f) {
        final a1 = lerp(f(p0), f(p1), 0, t1), a2 = lerp(f(p1), f(p2), t1, t2), a3 = lerp(f(p2), f(p3), t2, t3);
        final b1 = lerp(a1, a2, 0, t2), b2 = lerp(a2, a3, t1, t3);
        return lerp(b1, b2, t1, t2);
      }

      final z = p1.z + (p2.z - p1.z) * s / pieces;
      out.add(Vertex(comp((v) => v.e), comp((v) => v.n), z));
    }
  }
  return out;
}

Vertex _mirror(Vertex about, Vertex v) => Vertex(2 * v.e - about.e, 2 * v.n - about.n, v.z);

class Bounds {
  const Bounds(this.minE, this.minN, this.maxE, this.maxN, this.minZ, this.maxZ);
  final double minE, minN, maxE, maxN, minZ, maxZ;
  double get width => maxE - minE;
  double get height => maxN - minN;

  static Bounds? of(Iterable<Vertex> vs) {
    double? a, b, c, d, e, f;
    for (final v in vs) {
      a = a == null ? v.e : math.min(a, v.e);
      b = b == null ? v.n : math.min(b, v.n);
      c = c == null ? v.e : math.max(c, v.e);
      d = d == null ? v.n : math.max(d, v.n);
      e = e == null ? v.z : math.min(e, v.z);
      f = f == null ? v.z : math.max(f, v.z);
    }
    return a == null ? null : Bounds(a, b!, c!, d!, e!, f!);
  }
}
