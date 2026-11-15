// The ground surface as triangles (a TIN) for contours.
//
// 1. Delaunay triangulation of the points with levels (Bowyer–Watson, points taken left to right so
//    finished triangles drop out early), worked in local coordinates for precision.
// 2. Breaklines: each piece of a breakline (road edge, bank, drain…) is made an edge of the TIN by
//    flipping the edges that cross it, so contours bend at the line instead of cutting across.
// 3. The outside is trimmed: long, thin triangles on the edge (across open ground where nothing was
//    surveyed) are removed from the outside in, so no hole is cut inside.
import 'dart:math' as math;

import 'point.dart';

class Tin {
  Tin(this.points, this.triangles, {this.unrecovered = 0});

  final List<Vertex> points;

  /// Corner indices into [points], anticlockwise
  final List<(int, int, int)> triangles;

  /// Breakline pieces that couldn't be made edges (lines crossing each other)
  final int unrecovered;
}

double _orient(Vertex a, Vertex b, Vertex c) => (b.e - a.e) * (c.n - a.n) - (b.n - a.n) * (c.e - a.e);

/// [points] with levels; [breaklines] as pairs of indices into [points]; triangles with an edge longer
/// than [maxEdge] are trimmed from the outside (0: about 5 times the typical edge)
Tin buildTin(List<Vertex> points, {List<(int, int)> breaklines = const [], double maxEdge = 0}) {
  // one point per place (within 1 mm); breakline indices follow
  final keep = <String, int>{};
  final pts = <Vertex>[];
  final map = List<int>.filled(points.length, -1);
  for (var i = 0; i < points.length; i++) {
    final k = '${(points[i].e * 1000).round()}:${(points[i].n * 1000).round()}';
    map[i] = keep.putIfAbsent(k, () {
      pts.add(points[i]);
      return pts.length - 1;
    });
  }
  if (pts.length < 3) return Tin(pts, const []);

  // local coordinates
  final e0 = pts.map((p) => p.e).reduce(math.min), n0 = pts.map((p) => p.n).reduce(math.min);
  final local = [for (final p in pts) Vertex(p.e - e0, p.n - n0, p.z)];
  final tris = _delaunay(local);

  final mesh = _Mesh(local, tris);
  var unrecovered = 0;
  for (final (a, b) in breaklines) {
    final i = map[a], j = map[b];
    if (i < 0 || j < 0 || i == j) continue;
    if (!mesh.recover(i, j)) unrecovered++;
  }
  mesh.trim(maxEdge);
  return Tin(pts, mesh.triangles(), unrecovered: unrecovered);
}

List<(int, int, int)> _delaunay(List<Vertex> p) {
  final order = List<int>.generate(p.length, (i) => i)..sort((a, b) => p[a].e.compareTo(p[b].e));
  var minE = double.infinity, minN = double.infinity, maxE = -double.infinity, maxN = -double.infinity;
  for (final v in p) {
    minE = math.min(minE, v.e);
    minN = math.min(minN, v.n);
    maxE = math.max(maxE, v.e);
    maxN = math.max(maxN, v.n);
  }
  final d = math.max(maxE - minE, maxN - minN) * 20 + 1;
  final mx = (minE + maxE) / 2, my = (minN + maxN) / 2;
  // the super triangle's corners are indices n, n+1, n+2
  final all = [...p, Vertex(mx - d, my - d), Vertex(mx, my + d), Vertex(mx + d, my - d)];
  final n = p.length;

  final open = <_Tri>[_Tri.of(all, n, n + 1, n + 2)];
  final closed = <_Tri>[];
  for (final i in order) {
    final v = all[i];
    final edges = <(int, int)>[];
    for (var k = open.length - 1; k >= 0; k--) {
      final t = open[k];
      final dx = v.e - t.cx;
      // the circle lies wholly left of the point: no later point can fall in it
      if (dx > 0 && dx * dx > t.r2) {
        closed.add(t);
        open.removeAt(k);
        continue;
      }
      final dy = v.n - t.cy;
      if (dx * dx + dy * dy <= t.r2) {
        edges
          ..add((t.a, t.b))
          ..add((t.b, t.c))
          ..add((t.c, t.a));
        open.removeAt(k);
      }
    }
    // the hole's outline: the edges seen once
    final count = <int, int>{};
    int key(int x, int y) => x < y ? x * 1000003 + y : y * 1000003 + x;
    for (final (x, y) in edges) {
      count[key(x, y)] = (count[key(x, y)] ?? 0) + 1;
    }
    for (final (x, y) in edges) {
      if (count[key(x, y)] == 1) open.add(_Tri.of(all, x, y, i));
    }
  }
  return [
    for (final t in [...closed, ...open])
      if (t.a < n && t.b < n && t.c < n) _ccw(p, t.a, t.b, t.c),
  ];
}

(int, int, int) _ccw(List<Vertex> p, int a, int b, int c) => _orient(p[a], p[b], p[c]) >= 0 ? (a, b, c) : (a, c, b);

class _Tri {
  _Tri(this.a, this.b, this.c, this.cx, this.cy, this.r2);
  final int a, b, c;
  final double cx, cy, r2;

  static _Tri of(List<Vertex> p, int a, int b, int c) {
    final A = p[a], B = p[b], C = p[c];
    final d = 2 * (A.e * (B.n - C.n) + B.e * (C.n - A.n) + C.e * (A.n - B.n));
    if (d.abs() < 1e-12) {
      // in a line: a circle so large every later point falls in it
      return _Tri(a, b, c, A.e, A.n, double.maxFinite);
    }
    final a2 = A.e * A.e + A.n * A.n, b2 = B.e * B.e + B.n * B.n, c2 = C.e * C.e + C.n * C.n;
    final ux = (a2 * (B.n - C.n) + b2 * (C.n - A.n) + c2 * (A.n - B.n)) / d;
    final uy = (a2 * (C.e - B.e) + b2 * (A.e - C.e) + c2 * (B.e - A.e)) / d;
    final r2 = (A.e - ux) * (A.e - ux) + (A.n - uy) * (A.n - uy);
    return _Tri(a, b, c, ux, uy, r2);
  }
}

/// Triangles with their edges, for flipping and trimming
class _Mesh {
  _Mesh(this.p, List<(int, int, int)> tris) {
    for (final t in tris) {
      _add(t);
    }
  }

  final List<Vertex> p;
  final _tris = <int, (int, int, int)>{};
  final _edges = <int, List<int>>{};
  var _next = 0;

  static int _key(int x, int y) => x < y ? x * 1000003 + y : y * 1000003 + x;

  void _add((int, int, int) t) {
    final id = _next++;
    _tris[id] = t;
    final (a, b, c) = t;
    for (final k in [_key(a, b), _key(b, c), _key(c, a)]) {
      (_edges[k] ??= []).add(id);
    }
  }

  void _remove(int id) {
    final (a, b, c) = _tris.remove(id)!;
    for (final k in [_key(a, b), _key(b, c), _key(c, a)]) {
      _edges[k]?.remove(id);
      if (_edges[k]?.isEmpty ?? false) _edges.remove(k);
    }
  }

  bool hasEdge(int a, int b) => _edges.containsKey(_key(a, b));

  /// Flips the edges crossing a–b until a–b is an edge; false when that can't be done
  bool recover(int a, int b, [int depth = 0]) {
    if (hasEdge(a, b)) return true;
    final pa = p[a], pb = p[b];
    // a point lying on the piece (a manhole on a centre line): the piece is two edges, through it
    final len2 = math.pow(pb.e - pa.e, 2) + math.pow(pb.n - pa.n, 2);
    if (depth < 50) {
      for (var m = 0; m < p.length; m++) {
        if (m == a || m == b) continue;
        final pm = p[m];
        final t = ((pm.e - pa.e) * (pb.e - pa.e) + (pm.n - pa.n) * (pb.n - pa.n)) / len2;
        if (t <= 1e-9 || t >= 1 - 1e-9) continue;
        if (_orient(pa, pb, pm).abs() / math.sqrt(len2) < 1e-4) {
          return recover(a, m, depth + 1) & recover(m, b, depth + 1);
        }
      }
    }
    bool crosses(int x, int y) {
      if (x == a || x == b || y == a || y == b) return false;
      final px = p[x], py = p[y];
      final d1 = _orient(pa, pb, px), d2 = _orient(pa, pb, py);
      final d3 = _orient(px, py, pa), d4 = _orient(px, py, pb);
      return d1 * d2 < 0 && d3 * d4 < 0;
    }

    for (var round = 0; round < 2000; round++) {
      final crossing = <(int, int)>[];
      for (final t in _tris.values) {
        final (x, y, z) = t;
        for (final (u, v) in [(x, y), (y, z), (z, x)]) {
          if (u < v && crosses(u, v)) crossing.add((u, v));
          if (v < u && crosses(v, u)) crossing.add((v, u));
        }
      }
      if (crossing.isEmpty) return hasEdge(a, b);
      var flipped = false;
      for (final (u, v) in crossing.toSet()) {
        if (_flip(u, v)) flipped = true;
      }
      if (!flipped) return false;
    }
    return hasEdge(a, b);
  }

  /// Turns edge u–v of the two triangles beside it into the other diagonal, when their quadrilateral
  /// is convex
  bool _flip(int u, int v) {
    final ids = _edges[_key(u, v)];
    if (ids == null || ids.length != 2) return false;
    final t1 = _tris[ids[0]]!, t2 = _tris[ids[1]]!;
    int other((int, int, int) t) => [t.$1, t.$2, t.$3].firstWhere((x) => x != u && x != v);
    final w1 = other(t1), w2 = other(t2);
    // convex: u and v on opposite sides of w1–w2
    if (_orient(p[w1], p[w2], p[u]) * _orient(p[w1], p[w2], p[v]) >= 0) return false;
    _remove(ids[1]);
    _remove(ids[0]);
    _add(_ccw(p, w1, w2, u));
    _add(_ccw(p, w1, w2, v));
    return true;
  }

  /// Removes long triangles on the outside, from the outside in
  void trim(double maxEdge) {
    if (_tris.isEmpty) return;
    double len(int x, int y) => math.sqrt(math.pow(p[x].e - p[y].e, 2) + math.pow(p[x].n - p[y].n, 2));
    var limit = maxEdge;
    if (limit <= 0) {
      final lens = <double>[
        for (final t in _tris.values) ...[len(t.$1, t.$2), len(t.$2, t.$3), len(t.$3, t.$1)],
      ]..sort();
      limit = lens[lens.length ~/ 2] * 5;
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in _tris.keys.toList()) {
        final t = _tris[id];
        if (t == null) continue;
        final (a, b, c) = t;
        final edges = [(a, b), (b, c), (c, a)];
        final outer = edges.where((e) => (_edges[_key(e.$1, e.$2)]?.length ?? 0) < 2);
        if (outer.any((e) => len(e.$1, e.$2) > limit)) {
          _remove(id);
          changed = true;
        }
      }
    }
  }

  List<(int, int, int)> triangles() => _tris.values.toList();
}
