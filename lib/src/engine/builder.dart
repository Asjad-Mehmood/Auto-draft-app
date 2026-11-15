// Turns survey points into a drawing. Points are taken in the order they were surveyed (the
// order in the file). Each line code with its number (RE1, RE2…) is its own line: a point
// coded RE1 joins the road edge 1 being drawn. Control words start, end, close or curve a line,
// or finish a rectangle from three corners. Point codes place their symbol. Every point gets a
// point marker and, as set, its level, number and code as text. Anything doubtful becomes a
// Problem, so the surveyor can check it before saving.
import 'dart:math' as math;

import 'code_parser.dart';
import 'codes.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'point.dart';

Drawing buildDrawing(List<SurveyPoint> points, CodeLibrary library, DraftOptions options) =>
    _Builder(points, library, options).build();

class _OpenVertex {
  _OpenVertex(this.v, this.id) : arcStart = false;
  final Vertex v;

  /// '' for a corner the app added (RECT)
  final String id;
  bool arcStart;
  bool arcEnd = false;
}

class _OpenLine {
  _OpenLine(this.ref);
  final FeatureRef ref;
  final List<_OpenVertex> verts = [];
  bool inArc = false;
}

class _Builder {
  _Builder(this.points, this.library, this.options);

  final List<SurveyPoint> points;
  final CodeLibrary library;
  final DraftOptions options;

  final lines = <DLine>[];
  final symbols = <DSymbol>[];
  final texts = <DText>[];
  final problems = <Problem>[];
  final _open = <String, _OpenLine>{};
  final _usedFeatures = <String, FeatureCode>{};
  final _unknown = <String, List<SurveyPoint>>{};
  final _stray = <SurveyPoint>[];
  final _remarks = <String, List<SurveyPoint>>{};

  Drawing build() {
    for (final p in points) {
      _point(p);
    }
    for (final key in _open.keys.toList()) {
      _finish(key);
    }
    _checks();
    return Drawing(
      points: points,
      lines: lines,
      symbols: symbols,
      texts: texts,
      layers: _layers(),
      problems: problems..sort((a, b) => a.severity.index.compareTo(b.severity.index)),
      options: options,
    );
  }

  Vertex _v(SurveyPoint p) => Vertex(p.e, p.n, p.z ?? 0);

  void _point(SurveyPoint p) {
    final parsed = parseCode(p.code, library);
    if (parsed.strayControls.isNotEmpty) _stray.add(p);
    for (final r in parsed.remarks) {
      (_remarks[r] ??= []).add(p);
    }
    var symbolPlaced = false;
    var levels = parsed.refs.isEmpty;
    for (final ref in parsed.refs) {
      _usedFeatures[ref.feature.code] = ref.feature;
      if (ref.feature.levels) levels = true;
      if (ref.feature.kind == CodeKind.point) {
        if (!symbolPlaced) {
          symbols.add(
            DSymbol(
              layer: ref.feature.layer,
              symbol: ref.feature.symbol,
              at: _v(p),
              pointId: p.id,
              feature: ref.feature,
            ),
          );
          symbolPlaced = true;
        }
      } else {
        _addToLine(ref, p);
      }
    }
    if (parsed.unknown.isNotEmpty) {
      (_unknown[parsed.unknown] ??= []).add(p);
      if (!symbolPlaced) {
        symbols.add(DSymbol(layer: Layers.unknown.name, symbol: 'AD_UNKNOWN', at: _v(p), pointId: p.id));
      }
      levels = true;
    }
    _labels(p, levels: levels);
  }

  void _addToLine(FeatureRef ref, SurveyPoint p) {
    final key = ref.key;
    final c = ref.controls;
    if (c.contains(Control.start) && (_open[key]?.verts.isNotEmpty ?? false)) _finish(key);
    final line = _open[key] ??= _OpenLine(ref);
    final ov = _OpenVertex(_v(p), p.id);
    line.verts.add(ov);
    if (c.contains(Control.endArc)) {
      if (line.inArc) {
        ov.arcEnd = true;
        line.inArc = false;
      } else {
        problems.add(
          Problem(
            Severity.warning,
            '${_name(ref)}: a curve ends at point ${p.id} but never started',
            'EARC (end of curve) was written, but no ARC before it on this line. The points are joined straight. '
                'Add ARC to the point where the curve starts.',
            pointIds: [p.id],
            at: _v(p),
          ),
        );
      }
    }
    // after EARC, so "EARC ARC" ends one curve and starts the next at the same point
    if (c.contains(Control.arc)) {
      ov.arcStart = true;
      line.inArc = true;
    }
    if (c.contains(Control.rect)) {
      if (line.verts.length >= 3) {
        final n = line.verts.length;
        final a = line.verts[n - 3].v, b = line.verts[n - 2].v, cc = line.verts[n - 1].v;
        final angle = cornerAngle(a, b, cc);
        if ((angle - 90).abs() > 5) {
          problems.add(
            Problem(
              Severity.info,
              '${_name(ref)}: the corner at point ${line.verts[n - 2].id} is ${angle.toStringAsFixed(1)}°, not square',
              'RECT adds the fourth corner as if the shape were a rectangle. Check the three corners were taken in order around the shape.',
              pointIds: [line.verts[n - 3].id, line.verts[n - 2].id, p.id],
              at: b,
            ),
          );
        }
        line.verts.add(_OpenVertex(fourthCorner(a, b, cc), ''));
        _finish(key, closed: true);
      } else {
        problems.add(
          Problem(
            Severity.warning,
            '${_name(ref)}: RECT at point ${p.id} needs three corners',
            'RECT goes on the third corner of a rectangle; this line has only ${line.verts.length} point(s) so far. '
                'Nothing was added.',
            pointIds: [p.id],
            at: _v(p),
          ),
        );
      }
      return;
    }
    if (c.contains(Control.close)) {
      _finish(key, closed: true);
    } else if (c.contains(Control.end)) {
      _finish(key);
    }
  }

  String _name(FeatureRef r) => '${r.feature.name} ${r.feature.code}${r.number == 0 ? '' : r.number}';

  void _finish(String key, {bool closed = false}) {
    final line = _open.remove(key);
    if (line == null || line.verts.isEmpty) return;
    final ids = [
      for (final v in line.verts)
        if (v.id.isNotEmpty) v.id,
    ];
    final name = _name(line.ref);
    if (line.verts.length < 2) {
      problems.add(
        Problem(
          Severity.warning,
          '$name has only one point (${ids.join(', ')})',
          'A line needs at least two points. Check the code of this point, or of the points that should join it. '
              'The point is still drawn, without a line.',
          pointIds: ids,
          at: line.verts.first.v,
        ),
      );
      return;
    }
    var verts = line.verts;
    // a closed shape whose last point repeats its first: no doubled corner
    if (closed && verts.length > 2 && dist(verts.first.v, verts.last.v) < 0.001) {
      verts = verts.sublist(0, verts.length - 1);
    }
    if (closed && verts.length < 3) {
      problems.add(
        Problem(
          Severity.warning,
          '$name is closed with only two points',
          'Closing a shape needs at least three corners. It is drawn as a line.',
          pointIds: ids,
          at: verts.first.v,
        ),
      );
      closed = false;
    }
    if (line.inArc) {
      problems.add(
        Problem(
          Severity.info,
          '$name: the curve has no end (EARC)',
          'A curve started (ARC) and the line ended before EARC, so the curve runs to the line\'s last point.',
          pointIds: ids,
          at: verts.last.v,
        ),
      );
    }
    _longJumps(name, verts);
    lines.add(
      DLine(
        layer: line.ref.feature.layer,
        feature: line.ref.feature,
        number: line.ref.number,
        vertices: _shape(verts),
        closed: closed,
        pointIds: ids,
      ),
    );
  }

  /// Straight between points, smooth through curves (ARC … EARC)
  List<Vertex> _shape(List<_OpenVertex> verts) {
    final out = <Vertex>[];
    void add(Vertex v) {
      if (out.isEmpty || out.last != v) out.add(v);
    }

    var i = 0;
    while (i < verts.length) {
      if (verts[i].arcStart && i < verts.length - 1) {
        // the curve runs to its EARC, or to the line's last point
        var j = i + 1;
        while (j < verts.length - 1 && !verts[j].arcEnd) {
          j++;
        }
        curveThrough([for (var k = i; k <= j; k++) verts[k].v]).forEach(add);
        // the curve's last point may start another curve ("EARC ARC"), so look at it again
        i = verts[j].arcStart ? j : j + 1;
        continue;
      }
      add(verts[i].v);
      i++;
    }
    return out;
  }

  /// A piece far longer than the rest of its line usually means a point was taken out of order or
  /// a new line should have started (ST)
  void _longJumps(String name, List<_OpenVertex> verts) {
    if (verts.length < 4) return;
    final lens = [for (var i = 1; i < verts.length; i++) dist(verts[i - 1].v, verts[i].v)];
    final sorted = [...lens]..sort();
    final median = sorted[sorted.length ~/ 2];
    for (var i = 0; i < lens.length; i++) {
      if (lens[i] > math.max(10, 5 * median)) {
        final a = verts[i], b = verts[i + 1];
        problems.add(
          Problem(
            Severity.warning,
            '$name jumps ${lens[i].toStringAsFixed(1)} m between points ${a.id} and ${b.id}',
            'The other pieces of this line are about ${median.toStringAsFixed(1)} m. If the line shouldn\'t join here, '
                'write ST on point ${b.id} to start a new line, or give it another line number.',
            pointIds: [a.id, b.id],
            at: Vertex((a.v.e + b.v.e) / 2, (a.v.n + b.v.n) / 2),
          ),
        );
      }
    }
  }

  void _labels(SurveyPoint p, {required bool levels}) {
    final h = options.textHeight;
    final gap = options.symbolSize * 0.55;
    final x = p.e + gap;
    if (options.levels && levels && p.z != null) {
      texts.add(
        DText(
          layer: Layers.levels.name,
          kind: TextKind.level,
          text: p.z!.toStringAsFixed(options.levelDecimals),
          at: Vertex(x, p.n - h / 2, p.z!),
          height: h,
        ),
      );
    }
    if (options.pointNumbers) {
      texts.add(
        DText(
          layer: Layers.numbers.name,
          kind: TextKind.number,
          text: p.id,
          at: Vertex(x, p.n + h * 0.9, p.z ?? 0),
          height: h * 0.8,
        ),
      );
    }
    if (options.codes && p.code.trim().isNotEmpty) {
      texts.add(
        DText(
          layer: Layers.codes.name,
          kind: TextKind.code,
          text: p.code.trim(),
          at: Vertex(x, p.n - h * 1.9, p.z ?? 0),
          height: h * 0.8,
        ),
      );
    }
  }

  void _checks() {
    for (final e in _unknown.entries) {
      final pts = e.value;
      problems.add(
        Problem(
          Severity.warning,
          'Code ${e.key} isn\'t in the code list (${_count(pts.length, 'point')})',
          'These points are drawn with a small square on layer ${Layers.unknown.name}. Add ${e.key} to the code list, '
              'or correct the code: ${_ids(pts)}.',
          pointIds: [for (final p in pts) p.id],
          at: _v(pts.first),
          kind: ProblemKind.unknownCode,
          subject: e.key,
        ),
      );
    }
    if (_stray.isNotEmpty) {
      problems.add(
        Problem(
          Severity.warning,
          'A control word comes before the code (${_count(_stray.length, 'point')})',
          'Write the code first and the control word after it, for example "RE1 ST", not "ST RE1": ${_ids(_stray)}.',
          pointIds: [for (final p in _stray) p.id],
          at: _v(_stray.first),
        ),
      );
    }
    for (final e in _remarks.entries) {
      final pts = e.value;
      problems.add(
        Problem(
          Severity.info,
          '"${e.key}" was read as a remark (${_count(pts.length, 'point')})',
          'It is neither a code in the list nor a control word, so it doesn\'t change the drawing: ${_ids(pts)}.',
          pointIds: [for (final p in pts) p.id],
          at: _v(pts.first),
          kind: ProblemKind.remark,
          subject: e.key,
        ),
      );
    }
    // the same point number twice
    final byId = <String, List<SurveyPoint>>{};
    for (final p in points) {
      (byId[p.id] ??= []).add(p);
    }
    for (final e in byId.entries.where((e) => e.value.length > 1)) {
      problems.add(
        Problem(
          Severity.warning,
          'Point number ${e.key} is used ${e.value.length} times',
          'Rows ${e.value.map((p) => p.row).join(', ')} have the same number. Both are drawn; check one isn\'t a mistake.',
          pointIds: [e.key],
          at: _v(e.value.first),
        ),
      );
    }
    // two points in the same place (within 1 mm)
    final byPlace = <String, List<SurveyPoint>>{};
    for (final p in points) {
      (byPlace['${(p.e * 1000).round()}:${(p.n * 1000).round()}'] ??= []).add(p);
    }
    final doubles = byPlace.values.where((v) => v.length > 1).toList();
    if (doubles.isNotEmpty) {
      problems.add(
        Problem(
          Severity.info,
          '${_count(doubles.length, 'place')} with more than one point',
          'Points at the same spot: ${doubles.take(8).map((g) => g.map((p) => p.id).join(' = ')).join('; ')}'
              '${doubles.length > 8 ? '…' : ''}. Often fine (a point taken twice), but check the codes.',
          pointIds: [for (final g in doubles) ...g.map((p) => p.id)],
          at: _v(doubles.first.first),
        ),
      );
    }
    final noLevel = points.where((p) => p.z == null).toList();
    if (noLevel.isNotEmpty) {
      problems.add(
        Problem(
          Severity.info,
          '${_count(noLevel.length, 'point')} without a level',
          'They are drawn at level 0 and get no level text: ${_ids(noLevel)}.',
          pointIds: [for (final p in noLevel) p.id],
          at: _v(noLevel.first),
        ),
      );
    }
    final zero = points.where((p) => p.z == 0).toList();
    if (zero.isNotEmpty && zero.length < points.length) {
      problems.add(
        Problem(
          Severity.warning,
          '${_count(zero.length, 'point')} at level 0.000',
          'Usually a level that wasn\'t recorded: ${_ids(zero)}.',
          pointIds: [for (final p in zero) p.id],
          at: _v(zero.first),
        ),
      );
    }
  }

  String _count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';

  String _ids(List<SurveyPoint> pts) =>
      pts.take(12).map((p) => p.id).join(', ') + (pts.length > 12 ? ' and ${pts.length - 12} more' : '');

  List<Layer> _layers() {
    final out = <String, Layer>{};
    final features = _usedFeatures.values.toList()..sort((a, b) => a.layer.compareTo(b.layer));
    for (final f in features) {
      out.putIfAbsent(f.layer, () => Layer(f.layer, f.color, f.lineType, f.name));
    }
    out[Layers.points.name] = Layers.points;
    if (texts.any((t) => t.kind == TextKind.level)) out[Layers.levels.name] = Layers.levels;
    if (texts.any((t) => t.kind == TextKind.number)) out[Layers.numbers.name] = Layers.numbers;
    if (texts.any((t) => t.kind == TextKind.code)) out[Layers.codes.name] = Layers.codes;
    if (_unknown.isNotEmpty) out[Layers.unknown.name] = Layers.unknown;
    return out.values.toList();
  }
}
