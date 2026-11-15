import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/geometry.dart';
import 'package:auto_draft/src/engine/point.dart';
import 'package:flutter_test/flutter_test.dart';

final _lib = CodeLibrary.defaults();

Drawing _draw(List<(double, double, String)> pts, {DraftOptions options = const DraftOptions()}) => buildDrawing(
  [
    for (var i = 0; i < pts.length; i++)
      SurveyPoint(id: '${i + 1}', e: pts[i].$1, n: pts[i].$2, z: 100, code: pts[i].$3, row: i + 2),
  ],
  _lib,
  options,
);

void main() {
  test('points with the same code and number make one line, in survey order', () {
    final d = _draw([(0, 0, 'RE1'), (10, 0, 'RE1'), (20, 0, 'RE1')]);
    expect(d.lines.single.vertices.map((v) => v.e), [0, 10, 20]);
    expect(d.lines.single.layer, 'ROAD_EDGE');
    expect(d.lines.single.closed, isFalse);
    expect(d.problems, isEmpty);
  });

  test('different numbers are different lines, even when mixed', () {
    final d = _draw([(0, 0, 'RE1'), (0, 7, 'RE2'), (10, 0, 'RE1'), (10, 7, 'RE2')]);
    expect(d.lines.length, 2);
    expect(d.lines.map((l) => l.number).toSet(), {1, 2});
    expect(d.lines.every((l) => l.vertices.length == 2), isTrue);
  });

  test('ST starts a new line; END ends one', () {
    final d = _draw([(0, 0, 'WL'), (10, 0, 'WL'), (50, 0, 'WL ST'), (60, 0, 'WL END'), (70, 0, 'WL'), (80, 0, 'WL')]);
    expect(d.lines.length, 3);
    expect(d.lines.map((l) => l.pointIds), [
      ['1', '2'],
      ['3', '4'],
      ['5', '6'],
    ]);
  });

  test('CLS closes the shape; a repeated first point is not doubled', () {
    final d = _draw([(0, 0, 'BLD1'), (10, 0, 'BLD1'), (10, 8, 'BLD1'), (0, 8, 'BLD1 CLS')]);
    expect(d.lines.single.closed, isTrue);
    expect(d.lines.single.vertices.length, 4);
    final e = _draw([(0, 0, 'BLD1'), (10, 0, 'BLD1'), (10, 8, 'BLD1'), (0, 0, 'BLD1 CLS')]);
    expect(e.lines.single.vertices.length, 3);
    expect(e.lines.single.closed, isTrue);
  });

  test('RECT adds the fourth corner and closes', () {
    final d = _draw([(0, 0, 'BLD2'), (12, 0, 'BLD2'), (12, 9, 'BLD2 RECT')]);
    final l = d.lines.single;
    expect(l.closed, isTrue);
    expect(l.vertices.length, 4);
    expect(l.vertices.last.e, closeTo(0, 1e-9));
    expect(l.vertices.last.n, closeTo(9, 1e-9));
    expect(l.pointIds, ['1', '2', '3']); // the added corner isn't a survey point
    expect(d.problems, isEmpty);
  });

  test('RECT on a corner that is not square says so', () {
    final d = _draw([(0, 0, 'BLD'), (12, 0, 'BLD'), (15, 9, 'BLD RECT')]);
    expect(d.problems.single.severity, Severity.info);
    expect(d.problems.single.title, contains('not square'));
  });

  test('RECT with too few corners adds nothing', () {
    final d = _draw([(0, 0, 'BLD'), (12, 0, 'BLD RECT')]);
    expect(d.problems.any((p) => p.title.contains('needs three corners')), isTrue);
  });

  test('ARC … EARC makes a smooth curve through the surveyed points', () {
    // a quarter circle of radius 10 round (0, 10), then straight on
    final d = _draw([
      (-10, 0, 'RE1'),
      (0, 0, 'RE1 ARC'),
      (7.0710678, 2.9289322, 'RE1'),
      (10, 10, 'RE1 EARC'),
      (10, 20, 'RE1'),
    ]);
    final v = d.lines.single.vertices;
    expect(v.length, greaterThan(20));
    expect(v.first, const Vertex(-10, 0, 100));
    expect(v.last, const Vertex(10, 20, 100));
    // every curve vertex lies on the circle
    for (final p in v.where((p) => p.e > 0.01 && p.n < 9.99)) {
      expect(dist(p, const Vertex(0, 10)), closeTo(10, 1e-6));
    }
    expect(d.problems, isEmpty);
  });

  test('a curve the other way round, and one longer than half a circle', () {
    final cw = curveThrough(const [Vertex(0, 0), Vertex(7.0710678, -2.9289322), Vertex(10, -10)]);
    for (final p in cw) {
      expect(dist(p, const Vertex(0, -10)), closeTo(10, 1e-6));
    }
    // three-quarters of a circle: from the bottom, through the right, to the left
    final big = curveThrough(const [Vertex(0, -10), Vertex(10, 0), Vertex(-10, 0)]);
    for (final p in big) {
      expect(dist(p, const Vertex(0, 0)), closeTo(10, 1e-6));
    }
    expect(big.any((p) => p.n > 9.9), isTrue); // it passes the top
  });

  test('a curve through more than three points passes through every one', () {
    const pts = [Vertex(0, 0), Vertex(10, 2), Vertex(20, 7), Vertex(28, 15), Vertex(32, 25)];
    final c = curveThrough(pts);
    for (final p in pts) {
      expect(c.any((v) => dist(v, p) < 1e-9), isTrue);
    }
  });

  test('EARC without ARC, and ARC without EARC, are reported', () {
    final a = _draw([(0, 0, 'RE'), (10, 0, 'RE EARC')]);
    expect(a.problems.single.title, contains('never started'));
    final b = _draw([(0, 0, 'RE ARC'), (10, 2, 'RE'), (20, 7, 'RE')]);
    expect(b.problems.single.title, contains('no end'));
    expect(b.lines.single.vertices.length, greaterThan(3));
  });

  test('point codes place their symbol on their layer', () {
    final d = _draw([(5, 5, 'TR'), (6, 6, 'MH'), (7, 7, 'EPL')]);
    expect(d.symbols.map((s) => s.symbol), ['AD_TREE', 'AD_MANHOLE', 'AD_ELEC_POLE']);
    expect(d.symbols.map((s) => s.layer), ['TREE', 'MANHOLE', 'ELECTRIC_POLE']);
    expect(d.lines, isEmpty);
  });

  test('a line with one point is reported, and the point still drawn', () {
    final d = _draw([(0, 0, 'FN1'), (5, 5, 'TR')]);
    expect(d.lines, isEmpty);
    expect(d.problems.single.title, contains('only one point'));
    expect(d.points.length, 2);
  });

  test('unknown codes are grouped into one problem and drawn as a square', () {
    final d = _draw([(0, 0, 'XYZ'), (1, 0, 'XYZ'), (2, 0, 'ABC')]);
    expect(d.symbols.every((s) => s.symbol == 'AD_UNKNOWN'), isTrue);
    expect(d.problems.where((p) => p.title.contains("isn't in the code list")).length, 2);
    expect(d.layers.any((l) => l.name == 'UNKNOWN_CODES'), isTrue);
  });

  test('a long jump in a line is reported', () {
    final d = _draw([(0, 0, 'DR'), (5, 0, 'DR'), (10, 0, 'DR'), (15, 0, 'DR'), (80, 0, 'DR'), (85, 0, 'DR')]);
    final p = d.problems.single;
    expect(p.title, contains('jumps 65.0 m'));
    expect(p.pointIds, ['4', '5']);
  });

  test('levels, numbers and codes as text, sized for the scale', () {
    final d = _draw([(0, 0, 'TR')], options: const DraftOptions(scale: 1000, pointNumbers: true, codes: true));
    expect(d.texts.map((t) => t.kind), [TextKind.level, TextKind.number, TextKind.code]);
    expect(d.texts.first.text, '100.000');
    expect(d.texts.first.height, closeTo(1.8, 1e-9)); // 1.8 mm at 1:1000
    final none = _draw([(0, 0, 'TR')], options: const DraftOptions(levels: false));
    expect(none.texts, isEmpty);
  });

  test('duplicate numbers, points in one place, and missing or zero levels', () {
    final d = buildDrawing(
      const [
        SurveyPoint(id: '1', e: 0, n: 0, z: 10, code: 'SP'),
        SurveyPoint(id: '1', e: 5, n: 0, z: 10, code: 'SP'),
        SurveyPoint(id: '3', e: 5, n: 0, z: 0, code: 'SP'),
        SurveyPoint(id: '4', e: 9, n: 0, code: 'SP'),
      ],
      _lib,
      const DraftOptions(),
    );
    final titles = d.problems.map((p) => p.title).join(' | ');
    expect(titles, contains('Point number 1 is used 2 times'));
    expect(titles, contains('1 place with more than one point'));
    expect(titles, contains('1 point without a level'));
    expect(titles, contains('1 point at level 0.000'));
    // warnings first
    expect(d.problems.first.severity, Severity.warning);
  });

  test('only the layers that are used, features first', () {
    final d = _draw([(0, 0, 'RE1'), (10, 0, 'RE1'), (5, 5, 'TR')]);
    expect(d.layers.map((l) => l.name), ['ROAD_EDGE', 'TREE', 'POINTS', 'LEVELS']);
  });

  test('3D lines keep the levels', () {
    final d = buildDrawing(
      const [SurveyPoint(id: '1', e: 0, n: 0, z: 10, code: 'TB'), SurveyPoint(id: '2', e: 10, n: 0, z: 12, code: 'TB')],
      _lib,
      const DraftOptions(lines3d: true),
    );
    expect(d.lines.single.vertices.map((v) => v.z), [10, 12]);
  });

  test('options survive a round trip and ignore bad values', () {
    const o = DraftOptions(scale: 1000, textMm: 2.5, pointNumbers: true, lines3d: true);
    final back = DraftOptions.fromJson(o.toJson());
    expect(back.scale, 1000);
    expect(back.textMm, 2.5);
    expect(back.pointNumbers, isTrue);
    expect(back.lines3d, isTrue);
    final bad = DraftOptions.fromJson({'scale': -5, 'textMm': 99, 'levelDecimals': 9});
    expect(bad.scale, 500);
    expect(bad.textMm, 1.8);
    expect(bad.levelDecimals, 3);
  });
}
