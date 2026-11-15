// Contours from the TIN: each triangle a level passes through gives one short piece; the pieces join
// into lines (open at the TIN's edge, closed round a hill or hollow). Every 5th level is a major
// contour, labelled along its line, upright, about every 100 mm on paper.
import 'dart:math' as math;

import 'point.dart';
import 'tin.dart';

class Contour {
  const Contour(this.level, this.major, this.vertices, {this.closed = false});
  final double level;
  final bool major;
  final List<Vertex> vertices;
  final bool closed;
}

class ContourLabel {
  const ContourLabel(this.text, this.at, this.rotation);
  final String text;

  /// The middle of the text's baseline
  final Vertex at;

  /// Degrees, anticlockwise, kept between −90 and 90 so it reads upright
  final double rotation;
}

/// A round interval giving about 15 contours over [range] metres of height
double autoInterval(double range) {
  const nice = [0.1, 0.2, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
  final raw = range / 15;
  return nice.firstWhere((n) => n >= raw, orElse: () => nice.last);
}

List<Contour> traceContours(Tin tin, double interval, {int majorEvery = 5}) {
  if (tin.triangles.isEmpty || interval <= 0) return const [];
  final p = tin.points;
  var zmin = double.infinity, zmax = -double.infinity;
  for (final v in p) {
    zmin = math.min(zmin, v.z);
    zmax = math.max(zmax, v.z);
  }
  final first = (zmin / interval).ceil(), last = (zmax / interval).floor();
  if (last - first > 2000) return const []; // an interval far too small for the ground
  final out = <Contour>[];
  for (var k = first; k <= last; k++) {
    final level = k * interval;
    // the pieces, keyed by the edges they cross
    final pieces = <(int, int)>[];
    final at = <int, Vertex>{};
    int key(int a, int b) => a < b ? a * 1000003 + b : b * 1000003 + a;
    // a corner exactly at the level counts as above it, so every crossing is on an edge's inside
    bool above(int i) => p[i].z >= level;
    for (final (a, b, c) in tin.triangles) {
      final cut = <int>[];
      for (final (u, v) in [(a, b), (b, c), (c, a)]) {
        if (above(u) != above(v)) {
          final kk = key(u, v);
          at.putIfAbsent(kk, () {
            final t = (level - p[u].z) / (p[v].z - p[u].z);
            return Vertex(p[u].e + (p[v].e - p[u].e) * t, p[u].n + (p[v].n - p[u].n) * t, level);
          });
          cut.add(kk);
        }
      }
      if (cut.length == 2) pieces.add((cut[0], cut[1]));
    }
    // join the pieces end to end
    final ends = <int, List<int>>{};
    for (var i = 0; i < pieces.length; i++) {
      (ends[pieces[i].$1] ??= []).add(i);
      (ends[pieces[i].$2] ??= []).add(i);
    }
    final used = List<bool>.filled(pieces.length, false);
    final major = majorEvery > 0 && k % majorEvery == 0;
    // open lines start at an end used once (the TIN's edge); then the closed loops
    final starts = [
      for (final e in ends.entries)
        if (e.value.length == 1) e.key,
      for (final e in ends.entries)
        if (e.value.length != 1) e.key,
    ];
    for (final s in starts) {
      final firstPiece = ends[s]!.where((i) => !used[i]).firstOrNull;
      if (firstPiece == null) continue;
      final keys = <int>[s];
      var cur = s, piece = firstPiece;
      while (true) {
        used[piece] = true;
        final (x, y) = pieces[piece];
        cur = x == cur ? y : x;
        keys.add(cur);
        final nextPiece = ends[cur]!.where((i) => !used[i]).firstOrNull;
        if (nextPiece == null) break;
        piece = nextPiece;
      }
      final closed = keys.length > 2 && keys.first == keys.last;
      final verts = [for (final kk in closed ? keys.sublist(0, keys.length - 1) : keys) at[kk]!];
      if (verts.length >= 2) out.add(Contour(level, major, verts, closed: closed));
    }
  }
  return out;
}

/// Labels along the major contours: about every [spacing] metres, none on lines shorter than a
/// quarter of it
List<ContourLabel> labelContours(List<Contour> contours, double spacing, int decimals) {
  final out = <ContourLabel>[];
  for (final c in contours.where((c) => c.major)) {
    final v = c.closed ? [...c.vertices, c.vertices.first] : c.vertices;
    final seg = [
      for (var i = 1; i < v.length; i++) math.sqrt(math.pow(v[i].e - v[i - 1].e, 2) + math.pow(v[i].n - v[i - 1].n, 2)),
    ];
    final total = seg.fold<double>(0, (a, b) => a + b);
    if (total < spacing / 4) continue;
    final count = math.max(1, (total / spacing).floor());
    for (var j = 0; j < count; j++) {
      var want = total * (j + 0.5) / count;
      for (var i = 0; i < seg.length; i++) {
        if (want <= seg[i] || i == seg.length - 1) {
          final t = seg[i] == 0 ? 0.0 : (want / seg[i]).clamp(0.0, 1.0);
          final a = v[i], b = v[i + 1];
          var rot = math.atan2(b.n - a.n, b.e - a.e) * 180 / math.pi;
          if (rot > 90) rot -= 180;
          if (rot < -90) rot += 180;
          out.add(
            ContourLabel(
              c.level.toStringAsFixed(decimals),
              Vertex(a.e + (b.e - a.e) * t, a.n + (b.n - a.n) * t, c.level),
              rot,
            ),
          );
          break;
        }
        want -= seg[i];
      }
    }
  }
  return out;
}

/// How many decimals an interval needs: 0.25 → 2, 0.5 → 1, 2 → 0
int intervalDecimals(double interval) {
  for (var d = 0; d <= 3; d++) {
    final s = interval * math.pow(10, d);
    if ((s - s.round()).abs() < 1e-9) return d;
  }
  return 3;
}
