import 'dart:io';
import 'dart:math' as math;

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/contours.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/dxf.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/engine/point.dart';
import 'package:auto_draft/src/engine/tin.dart';
import 'package:flutter_test/flutter_test.dart';

List<Vertex> _grid(int n, double step, double Function(double, double) z) => [
  for (var i = 0; i < n; i++)
    for (var j = 0; j < n; j++) Vertex(436000 + i * step, 3487000 + j * step, z(i * step, j * step)),
];

bool _hasEdge(Tin t, int a, int b) => t.triangles.any((tr) {
  final s = {tr.$1, tr.$2, tr.$3};
  return s.contains(a) && s.contains(b);
});

void main() {
  test('a grid: two triangles a square, all anticlockwise', () {
    final t = buildTin(_grid(5, 10, (x, y) => 100));
    expect(t.triangles.length, 32);
    for (final (a, b, c) in t.triangles) {
      final p = t.points;
      final o = (p[b].e - p[a].e) * (p[c].n - p[a].n) - (p[b].n - p[a].n) * (p[c].e - p[a].e);
      expect(o, greaterThan(0));
    }
  });

  test('Delaunay: no point inside another triangle\'s circle', () {
    final r = math.Random(7);
    final pts = [
      for (var i = 0; i < 300; i++) Vertex(436000 + r.nextDouble() * 500, 3487000 + r.nextDouble() * 400, 200),
    ];
    final t = buildTin(pts, maxEdge: 1e9);
    final p = t.points;
    for (final (a, b, c) in t.triangles.take(150)) {
      final ax = p[a].e - 436000, ay = p[a].n - 3487000, bx = p[b].e - 436000, by = p[b].n - 3487000;
      final cx = p[c].e - 436000, cy = p[c].n - 3487000;
      for (var k = 0; k < p.length; k++) {
        if (k == a || k == b || k == c) continue;
        final dx = p[k].e - 436000, dy = p[k].n - 3487000;
        // the in-circle determinant: positive means inside (anticlockwise triangle)
        final m = [
          [ax - dx, ay - dy, (ax - dx) * (ax - dx) + (ay - dy) * (ay - dy)],
          [bx - dx, by - dy, (bx - dx) * (bx - dx) + (by - dy) * (by - dy)],
          [cx - dx, cy - dy, (cx - dx) * (cx - dx) + (cy - dy) * (cy - dy)],
        ];
        final det =
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
            m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
            m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        expect(det, lessThan(1e-3), reason: 'point $k in the circle of ($a, $b, $c)');
      }
    }
  });

  test('a breakline becomes an edge', () {
    // a long thin diamond: Delaunay joins the near pair, the breakline asks for the far pair
    const pts = [
      Vertex(0, 0, 10),
      Vertex(100, 0, 10),
      Vertex(50, 8, 12),
      Vertex(50, -8, 12),
      Vertex(50, 40, 11),
      Vertex(50, -40, 11),
    ];
    final plain = buildTin(pts, maxEdge: 1e9);
    expect(_hasEdge(plain, 0, 1), isFalse);
    final t = buildTin(pts, breaklines: [(0, 1)], maxEdge: 1e9);
    expect(_hasEdge(t, 0, 1), isTrue);
    expect(t.unrecovered, 0);
  });

  test('a point on a breakline splits it, without a warning', () {
    const pts = [Vertex(0, 0, 10), Vertex(50, 0, 10), Vertex(100, 0, 10), Vertex(50, 30, 12), Vertex(50, -30, 12)];
    final t = buildTin(pts, breaklines: [(0, 2)], maxEdge: 1e9);
    expect(t.unrecovered, 0);
    expect(_hasEdge(t, 0, 1) && _hasEdge(t, 1, 2), isTrue);
  });

  test('long triangles on the outside are trimmed, not the inside', () {
    final pts = [..._grid(4, 10, (x, y) => 100), const Vertex(436300, 3487015, 100)];
    final all = buildTin(pts, maxEdge: 1e9).triangles.length;
    final trimmed = buildTin(pts).triangles.length;
    expect(trimmed, 18); // the grid's own 3 x 3 x 2
    expect(all, greaterThan(trimmed));
  });

  test('a sloping plane: straight contours at every interval', () {
    // rises 1 m every 10 m eastward: 100 … 104
    final t = buildTin(_grid(5, 10, (x, y) => 100 + x / 10));
    final c = traceContours(t, 0.5, majorEvery: 2);
    // (none at exactly the lowest level: that would run along the surface's edge)
    expect(c.map((x) => x.level).toSet(), {100.5, 101.0, 101.5, 102.0, 102.5, 103.0, 103.5, 104.0});
    for (final line in c.where((x) => x.level > 100 && x.level < 104)) {
      expect(line.closed, isFalse);
      for (final v in line.vertices) {
        expect(v.e - 436000, closeTo((line.level - 100) * 10, 1e-6));
      }
      expect(line.major, line.level % 1 == 0);
    }
  });

  test('a hill: closed contours round the top', () {
    final t = buildTin(_grid(21, 5, (x, y) => 120 - math.sqrt(math.pow(x - 50, 2) + math.pow(y - 50, 2)) / 5));
    final c = traceContours(t, 1);
    final rings = c.where((x) => x.closed).toList();
    expect(rings, isNotEmpty);
    expect(rings.map((x) => x.level), contains(119.0));
  });

  test('labels: upright, along the major contours', () {
    final t = buildTin(_grid(11, 10, (x, y) => 100 + y / 10));
    final c = traceContours(t, 1, majorEvery: 5);
    final labels = labelContours(c, 30, 0);
    expect(labels, isNotEmpty);
    expect(labels.map((l) => l.text).toSet(), {'100', '105', '110'}.intersection(labels.map((l) => l.text).toSet()));
    for (final l in labels) {
      expect(l.rotation, inInclusiveRange(-90, 90));
    }
  });

  test('intervals: chosen for the ground, and their decimals', () {
    expect(autoInterval(1.5), 0.1);
    expect(autoInterval(4), 0.5);
    expect(autoInterval(40), 5);
    expect(intervalDecimals(0.25), 2);
    expect(intervalDecimals(0.5), 1);
    expect(intervalDecimals(2), 0);
  });

  test('the sample survey: buildings left out, contours drawn and labelled, into the DXF', () {
    final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
    final pts = readPoints(t, guessColumns(t)).points;
    final d = buildDrawing(pts, CodeLibrary.defaults(), const DraftOptions(contours: true, showTin: true));
    expect(d.tin, isNotNull);
    expect(d.contours, isNotEmpty);
    expect(d.contourInterval, 0.1);
    expect(d.problems, isEmpty);
    // the building corners (214.750 / 214.780) are roofs here: not in the surface
    expect(d.tin!.points.any((v) => v.z > 214.7), isFalse);
    expect(d.layers.map((l) => l.name), containsAll(['CONTOUR_MINOR', 'CONTOUR_MAJOR', 'CONTOUR_LABELS', 'TIN']));
    expect(d.texts.where((x) => x.kind == TextKind.contour), isNotEmpty);
    final dxf = writeDxf(d);
    expect(dxf, contains('3DFACE'));
    expect(dxf, contains('CONTOUR_MAJOR'));
    // without contours, none of it
    final plain = buildDrawing(pts, CodeLibrary.defaults(), const DraftOptions());
    expect(plain.tin, isNull);
    expect(writeDxf(plain), isNot(contains('CONTOUR')));
  });

  test('too few points with levels says so', () {
    final d = buildDrawing(
      const [SurveyPoint(id: '1', e: 0, n: 0, z: 1, code: 'SP'), SurveyPoint(id: '2', e: 5, n: 0, z: 2, code: 'SP')],
      CodeLibrary.defaults(),
      const DraftOptions(contours: true),
    );
    expect(d.problems.single.title, 'No contours: too few points with levels');
  });

  test('3000 points in good time', () {
    final r = math.Random(3);
    final pts = [
      for (var i = 0; i < 3000; i++) Vertex(r.nextDouble() * 1000, r.nextDouble() * 1000, 100 + r.nextDouble() * 20),
    ];
    final sw = Stopwatch()..start();
    final t = buildTin(pts);
    final c = traceContours(t, 1);
    sw.stop();
    expect(t.triangles.length, greaterThan(5000));
    expect(c, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(8000));
  });

  test('a code list saved before contours keeps the standard breaklines', () {
    final old = FeatureCode.fromJson({
      'code': 'RE',
      'name': 'Road edge',
      'kind': 'line',
      'layer': 'ROAD_EDGE',
      'color': 1,
    })!;
    expect(old.breakline, isTrue);
    final roof = FeatureCode.fromJson({'code': 'BLD', 'name': 'Building', 'kind': 'line', 'layer': 'BUILDING'})!;
    expect(roof.surface, isFalse);
    final mine = FeatureCode.fromJson({'code': 'XX', 'name': 'Mine', 'kind': 'line', 'layer': 'X', 'breakline': true})!;
    expect(mine.breakline, isTrue);
  });
}
