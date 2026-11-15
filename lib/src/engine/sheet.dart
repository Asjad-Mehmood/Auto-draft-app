// The printed sheet around the survey: paper, frame, coordinate grid with labels, and a panel on the
// right with the legend (made from the codes used), north arrow, scale bar, notes and the title block.
//
// Everything is laid out in millimetres on paper and placed in the drawing at the survey's scale, so
// the DXF prints at scale from model space and the PDF is the same sheet. Plain Dart: the DXF writer,
// the PDF writer and the preview all draw from the [Sheet] this makes.
import 'dart:math' as math;

import 'codes.dart';
import 'drawing.dart';
import 'geometry.dart';
import 'point.dart';

/// ISO paper sizes, landscape (width × height in mm)
enum Paper {
  a4('A4', 297, 210),
  a3('A3', 420, 297),
  a2('A2', 594, 420),
  a1('A1', 841, 594),
  a0('A0', 1189, 841);

  const Paper(this.label, this.width, this.height);
  final String label;
  final double width, height;
}

/// What the title block says, and the paper. Remembered between surveys except the title and number.
class SheetInfo {
  const SheetInfo({
    this.firm = '',
    this.title = '',
    this.location = '',
    this.client = '',
    this.surveyedBy = '',
    this.drawnBy = 'Auto Draft',
    this.date = '',
    this.drawingNo = '',
    this.sheetNo = '1 of 1',
    this.notes = 'Coordinates in metres (UTM, WGS 84). Levels in metres.',
    this.paper,
    this.portrait = false,
    this.inDxf = true,
  });

  final String firm, title, location, client, surveyedBy, drawnBy, date, drawingNo, sheetNo, notes;

  /// null: the smallest paper the survey fits on at its scale
  final Paper? paper;
  final bool portrait;

  /// Draw the sheet in the DXF too (and on screen)
  final bool inDxf;

  SheetInfo copyWith({
    String? firm,
    String? title,
    String? location,
    String? client,
    String? surveyedBy,
    String? drawnBy,
    String? date,
    String? drawingNo,
    String? sheetNo,
    String? notes,
    Paper? Function()? paper,
    bool? portrait,
    bool? inDxf,
  }) => SheetInfo(
    firm: firm ?? this.firm,
    title: title ?? this.title,
    location: location ?? this.location,
    client: client ?? this.client,
    surveyedBy: surveyedBy ?? this.surveyedBy,
    drawnBy: drawnBy ?? this.drawnBy,
    date: date ?? this.date,
    drawingNo: drawingNo ?? this.drawingNo,
    sheetNo: sheetNo ?? this.sheetNo,
    notes: notes ?? this.notes,
    paper: paper == null ? this.paper : paper(),
    portrait: portrait ?? this.portrait,
    inDxf: inDxf ?? this.inDxf,
  );

  Map<String, Object> toJson() => {
    'firm': firm,
    'title': title,
    'location': location,
    'client': client,
    'surveyedBy': surveyedBy,
    'drawnBy': drawnBy,
    'date': date,
    'drawingNo': drawingNo,
    'sheetNo': sheetNo,
    'notes': notes,
    'paper': paper?.name ?? 'auto',
    'portrait': portrait,
    'inDxf': inDxf,
  };

  static SheetInfo fromJson(Object? j) {
    const d = SheetInfo();
    if (j is! Map) return d;
    String s(String k, String fallback) => j[k] is String ? j[k] as String : fallback;
    return SheetInfo(
      firm: s('firm', d.firm),
      title: s('title', d.title),
      location: s('location', d.location),
      client: s('client', d.client),
      surveyedBy: s('surveyedBy', d.surveyedBy),
      drawnBy: s('drawnBy', d.drawnBy),
      date: s('date', d.date),
      drawingNo: s('drawingNo', d.drawingNo),
      sheetNo: s('sheetNo', d.sheetNo),
      notes: s('notes', d.notes),
      paper: Paper.values.where((p) => p.name == j['paper']).firstOrNull,
      portrait: j['portrait'] == true,
      inDxf: j['inDxf'] != false,
    );
  }
}

enum SheetAlign { left, center, right }

/// What a sheet is drawn with, in drawing units (metres) at the survey's scale
sealed class SheetItem {
  const SheetItem(this.layer);
  final String layer;
}

class SheetPolyline extends SheetItem {
  const SheetPolyline(super.layer, this.points, {this.closed = false, this.color, this.lineType, this.weightMm = 0.18});
  final List<Vertex> points;
  final bool closed;

  /// A colour or line type of its own (legend samples); null: the layer's
  final int? color;
  final String? lineType;

  /// Pen width on paper (PDF and preview; DXF R12 has no line weights)
  final double weightMm;
}

class SheetText extends SheetItem {
  const SheetText(
    super.layer,
    this.text,
    this.at,
    this.height, {
    this.align = SheetAlign.left,
    this.rotation = 0,
    this.bold = false,
  });
  final String text;

  /// The baseline point: its left end, middle or right end as [align] says
  final Vertex at;
  final double height;
  final SheetAlign align;

  /// Degrees, anticlockwise
  final double rotation;
  final bool bold;
}

/// A filled triangle or quadrilateral (corners in order round it)
class SheetSolid extends SheetItem {
  const SheetSolid(super.layer, this.corners);
  final List<Vertex> corners;
}

class SheetSymbol extends SheetItem {
  const SheetSymbol(super.layer, this.symbol, this.at, this.size, {this.color});
  final String symbol;
  final Vertex at;
  final double size;
  final int? color;
}

abstract final class SheetLayers {
  static const frame = Layer('SHEET_FRAME', 7, 'CONTINUOUS', 'Sheet frame and title block');
  static const grid = Layer('SHEET_GRID', 8, 'CONTINUOUS', 'Coordinate grid');
  static const text = Layer('SHEET_TEXT', 7, 'CONTINUOUS', 'Sheet text');
  static const legend = Layer('SHEET_LEGEND', 7, 'CONTINUOUS', 'Legend');
  static const all = [frame, grid, text, legend];
}

class Sheet {
  Sheet({
    required this.paper,
    required this.portrait,
    required this.origin,
    required this.scale,
    required this.items,
    required this.area,
    required this.fits,
    required this.advice,
    required this.gridInterval,
  });

  final Paper paper;
  final bool portrait;

  /// The paper's lower-left corner in the drawing
  final Vertex origin;
  final int scale;
  final List<SheetItem> items;

  /// The drawing area (inside the frame, left of the panel), in the drawing
  final Bounds area;

  /// The whole survey is inside the drawing area
  final bool fits;

  /// When it doesn't fit: what would ("Choose A1, or the scale 1:1000")
  final String advice;
  final double gridInterval;

  double get widthMm => portrait ? paper.height : paper.width;
  double get heightMm => portrait ? paper.width : paper.height;

  /// Metres in the drawing per millimetre on paper
  double get f => scale / 1000;

  double get width => widthMm * f;
  double get height => heightMm * f;

  Bounds get bounds => Bounds(origin.e, origin.n, origin.e + width, origin.n + height, 0, 0);

  String get label => '${paper.label} ${portrait ? 'portrait' : 'landscape'} at 1:$scale';
}

// ------------------------------------------------------------------ layout

const _margin = 10.0, _binding = 20.0;

/// The panel on the right: wide enough for the title block, narrower on small paper
double _panelWidth(double w) => (w * 0.22).clamp(95.0, 180.0);

/// The drawing area of a paper, in mm: (left, bottom, right, top)
(double, double, double, double) _areaMm(double w, double h) {
  final right = w - _margin - _panelWidth(w);
  return (_binding + 9, _margin + 9, right - 4, h - _margin - 4);
}

bool _fitsOn(Bounds b, double w, double h, double f) {
  final (l, bo, r, t) = _areaMm(w, h);
  return b.width / f <= r - l && b.height / f <= t - bo;
}

const _standardScales = [100, 200, 250, 500, 1000, 1250, 2000, 2500, 5000, 10000];

Sheet buildSheet(Drawing d, SheetInfo info) {
  final scale = d.options.scale;
  final f = scale / 1000;
  final b = d.bounds ?? const Bounds(0, 0, 1, 1, 0, 0);

  // the paper: as chosen, or the smallest it fits on (landscape first)
  Paper paper;
  var portrait = info.portrait;
  if (info.paper != null) {
    paper = info.paper!;
  } else {
    paper = Paper.a0;
    var found = false;
    for (final p in Paper.values) {
      for (final por in [false, true]) {
        if (!found && _fitsOn(b, por ? p.height : p.width, por ? p.width : p.height, f)) {
          paper = p;
          portrait = por;
          found = true;
        }
      }
    }
    if (!found) portrait = false;
  }
  final w = portrait ? paper.height : paper.width, h = portrait ? paper.width : paper.height;
  final fits = _fitsOn(b, w, h, f);
  var advice = '';
  if (!fits) {
    final bigger = Paper.values
        .where((p) => p.index > paper.index && (_fitsOn(b, p.width, p.height, f) || _fitsOn(b, p.height, p.width, f)))
        .firstOrNull;
    final scaleUp = _standardScales.where((s) => s > scale && _fitsOn(b, w, h, s / 1000)).firstOrNull;
    advice = [if (bigger != null) 'choose ${bigger.label}', if (scaleUp != null) 'the scale 1:$scaleUp'].join(', or ');
    advice = advice.isEmpty
        ? 'The survey is larger than the sheet.'
        : 'To fit it, ${advice[0].toLowerCase()}${advice.substring(1)}.';
  }

  // the survey's centre at the drawing area's centre
  final (al, ab, ar, at) = _areaMm(w, h);
  final cx = (b.minE + b.maxE) / 2, cy = (b.minN + b.maxN) / 2;
  final origin = Vertex(cx - (al + ar) / 2 * f, cy - (ab + at) / 2 * f);
  Vertex p(double x, double y) => Vertex(origin.e + x * f, origin.n + y * f);

  final items = <SheetItem>[];
  void line(
    String layer,
    List<(double, double)> pts, {
    bool closed = false,
    double weight = 0.18,
    int? color,
    String? lineType,
  }) => items.add(
    SheetPolyline(
      layer,
      [for (final (x, y) in pts) p(x, y)],
      closed: closed,
      weightMm: weight,
      color: color,
      lineType: lineType,
    ),
  );
  void text(
    String s,
    double x,
    double y,
    double hMm, {
    SheetAlign align = SheetAlign.left,
    double rot = 0,
    bool bold = false,
    String layer = 'SHEET_TEXT',
  }) {
    if (s.trim().isEmpty) return;
    items.add(SheetText(layer, s, p(x, y), hMm * f, align: align, rotation: rot, bold: bold));
  }

  void box(double l, double bo, double r, double t, {double weight = 0.18, String layer = 'SHEET_FRAME'}) =>
      line(layer, [(l, bo), (r, bo), (r, t), (l, t)], closed: true, weight: weight);

  // frame and panel
  final fl = _binding, fb = _margin, fr = w - _margin, ft = h - _margin;
  final panel = fr - _panelWidth(w);
  box(fl, fb, fr, ft, weight: 0.5);
  line('SHEET_FRAME', [(panel, fb), (panel, ft)], weight: 0.35);
  box(fl + 1.5, fb + 1.5, panel, ft - 1.5, weight: 0.13);

  // the coordinate grid: crosses inside the area, values along its edges
  final interval = _gridInterval(f);
  final areaB = Bounds(origin.e + al * f, origin.n + ab * f, origin.e + ar * f, origin.n + at * f, 0, 0);
  final arm = 2.0 * f;
  for (var e = (areaB.minE / interval).ceil() * interval; e <= areaB.maxE; e += interval) {
    for (var n = (areaB.minN / interval).ceil() * interval; n <= areaB.maxN; n += interval) {
      items.add(SheetPolyline('SHEET_GRID', [Vertex(e - arm, n), Vertex(e + arm, n)], weightMm: 0.13));
      items.add(SheetPolyline('SHEET_GRID', [Vertex(e, n - arm), Vertex(e, n + arm)], weightMm: 0.13));
    }
    final x = (e - origin.e) / f;
    line('SHEET_GRID', [(x, fb + 1.5), (x, fb + 4.5)], weight: 0.13);
    line('SHEET_GRID', [(x, ft - 1.5), (x, ft - 4.5)], weight: 0.13);
    text('E ${_coord(e)}', x, fb + 5.5, 1.8, align: SheetAlign.center, layer: 'SHEET_GRID');
  }
  for (var n = (areaB.minN / interval).ceil() * interval; n <= areaB.maxN; n += interval) {
    final y = (n - origin.n) / f;
    line('SHEET_GRID', [(fl + 1.5, y), (fl + 4.5, y)], weight: 0.13);
    line('SHEET_GRID', [(panel, y), (panel - 3, y)], weight: 0.13);
    text('N ${_coord(n)}', fl + 7.2, y, 1.8, align: SheetAlign.center, rot: 90, layer: 'SHEET_GRID');
  }

  // ---------------------------------------------------------- the panel, from the bottom up
  final pl = panel + 4, pr = fr - 4, pw = pr - pl;

  // title block
  var y = fb;
  final tb = <double>[]; // the row lines
  const rowH = 8.0;
  final cells = [
    ('Drawing no.', info.drawingNo, 'Sheet', info.sheetNo),
    ('Drawn by', info.drawnBy, 'Scale', '1:$scale  (${paper.label})'),
    ('Surveyed by', info.surveyedBy, 'Date', info.date),
  ];
  text('Drawn with Auto Draft · www.exceltokml.com', (panel + fr) / 2, y + 1.6, 1.4, align: SheetAlign.center);
  y += 4;
  tb.add(y);
  final mid = panel + (fr - panel) / 2;
  for (final (l1, v1, l2, v2) in cells) {
    text(l1.toUpperCase(), panel + 2, y + rowH - 2.6, 1.5);
    text(v1, panel + 2, y + 1.8, 2.4);
    text(l2.toUpperCase(), mid + 2, y + rowH - 2.6, 1.5);
    text(v2, mid + 2, y + 1.8, 2.4);
    line('SHEET_FRAME', [(mid, y), (mid, y + rowH)]);
    y += rowH;
    tb.add(y);
  }
  // client and location
  if (info.client.isNotEmpty || info.location.isNotEmpty) {
    text('CLIENT', panel + 2, y + rowH - 2.6, 1.5);
    text(info.client, panel + 2, y + 1.8, 2.4);
    text('LOCATION', mid + 2, y + rowH - 2.6, 1.5);
    text(_fit(info.location, (fr - mid - 4) / (2.4 * 0.62)), mid + 2, y + 1.8, 2.4);
    line('SHEET_FRAME', [(mid, y), (mid, y + rowH)]);
    y += rowH;
    tb.add(y);
  }
  // the drawing's title, two lines at most
  final titleLines = _wrap(info.title.isEmpty ? 'Topographic survey' : info.title, pw / (4.0 * 0.62)).take(2).toList();
  final titleH = 6.0 + titleLines.length * 6.4;
  for (var i = 0; i < titleLines.length; i++) {
    text(titleLines[i], (panel + fr) / 2, y + titleH - 7.0 - i * 6.4, 4.0, align: SheetAlign.center, bold: true);
  }
  y += titleH;
  tb.add(y);
  // the firm
  final firmH = info.firm.isEmpty ? 0.0 : 12.0;
  if (firmH > 0) {
    text(_fit(info.firm, pw / (4.5 * 0.62)), (panel + fr) / 2, y + 4, 4.5, align: SheetAlign.center, bold: true);
    y += firmH;
    tb.add(y);
  }
  for (final ly in tb) {
    line('SHEET_FRAME', [(panel, ly), (fr, ly)], weight: ly == tb.last ? 0.35 : 0.18);
  }

  // notes
  final noteLines = _wrap(info.notes, pw / (1.9 * 0.62)).take(4).toList();
  if (noteLines.isNotEmpty) {
    y += 3;
    for (final l in noteLines.reversed) {
      text(l, pl, y, 1.9);
      y += 3.0;
    }
    text('NOTES', pl, y + 0.6, 2.0, bold: true);
    y += 4.5;
  }

  // scale bar
  y += 4;
  final barM = _barLength(pw - 12, f);
  final barMm = barM / f;
  final bx = pl + (pw - barMm) / 2;
  const segs = 4;
  for (var i = 0; i < segs; i++) {
    final x0 = bx + barMm * i / segs, x1 = bx + barMm * (i + 1) / segs;
    if (i.isEven) {
      items.add(SheetSolid('SHEET_FRAME', [p(x0, y + 4), p(x1, y + 4), p(x1, y + 6), p(x0, y + 6)]));
    }
    box(x0, y + 4, x1, y + 6, weight: 0.13);
  }
  text('0', bx, y, 1.8, align: SheetAlign.center);
  text(_num(barM / 2), bx + barMm / 2, y, 1.8, align: SheetAlign.center);
  text('${_num(barM)} m', bx + barMm, y, 1.8, align: SheetAlign.center);
  text('SCALE 1:$scale', pl + pw / 2, y + 8.5, 2.4, align: SheetAlign.center, bold: true);
  y += 14;

  // north arrow (the grid is to UTM north)
  final nx = pl + pw / 2;
  const na = 16.0;
  items.add(SheetSolid('SHEET_FRAME', [p(nx, y + na), p(nx, y + 3), p(nx - 4.5, y)]));
  line('SHEET_FRAME', [(nx, y + na), (nx + 4.5, y), (nx, y + 3), (nx - 4.5, y)], closed: true, weight: 0.25);
  text('N', nx, y + na + 2, 4.0, align: SheetAlign.center, bold: true);
  y += na + 9;
  line('SHEET_FRAME', [(panel, y), (fr, y)]);

  // legend: from the top down to what is left
  final top = ft - 4;
  text('LEGEND', pl, top - 4, 3.0, bold: true);
  final entries = _legend(d);
  const rowL = 6.0;
  final room = ((top - 9) - (y + 2)) ~/ rowL;
  final cols = entries.length > room && pw > 110 ? 2 : 1;
  final perCol = math.max(1, room);
  final colW = pw / cols;
  final shown = room <= 0 ? 0 : math.min(entries.length, perCol * cols);
  for (var i = 0; i < shown; i++) {
    final e = entries[i];
    final cx0 = pl + (i ~/ perCol) * colW;
    final cy0 = top - 9 - (i % perCol) * rowL - 2;
    final last = i == shown - 1 && shown < entries.length;
    if (last) {
      text('…and ${entries.length - shown + 1} more', cx0, cy0 - 0.8, 2.0);
      break;
    }
    switch (e) {
      case _LegendLine(:final code):
        line('SHEET_LEGEND', [(cx0, cy0), (cx0 + 12, cy0)], color: code.color, lineType: code.lineType, weight: 0.3);
      case _LegendSymbol(:final code):
        items.add(SheetSymbol('SHEET_LEGEND', code.symbol, p(cx0 + 6, cy0), 3.2 * f, color: code.color));
      case _LegendText(:final sample):
        text(sample, cx0 + 6, cy0 - 0.8, 1.8, align: SheetAlign.center, layer: 'SHEET_LEGEND');
    }
    text(_fit(e.name, (colW - 17) / (2.1 * 0.62)), cx0 + 15, cy0 - 0.8, 2.1, layer: 'SHEET_LEGEND');
  }

  return Sheet(
    paper: paper,
    portrait: portrait,
    origin: origin,
    scale: scale,
    items: items,
    area: areaB,
    fits: fits,
    advice: advice,
    gridInterval: interval,
  );
}

sealed class _Legend {
  const _Legend(this.name);
  final String name;
}

class _LegendLine extends _Legend {
  _LegendLine(this.code) : super(code.name);
  final FeatureCode code;
}

class _LegendSymbol extends _Legend {
  _LegendSymbol(this.code) : super(code.name);
  final FeatureCode code;
}

class _LegendText extends _Legend {
  const _LegendText(this.sample, super.name);
  final String sample;
}

/// One entry per code used: lines first, then point symbols, then the level text
List<_Legend> _legend(Drawing d) {
  final lines = <String, FeatureCode>{}, pts = <String, FeatureCode>{};
  for (final l in d.lines) {
    lines.putIfAbsent(l.feature.code, () => l.feature);
  }
  for (final s in d.symbols) {
    if (s.feature != null) pts.putIfAbsent(s.feature!.code, () => s.feature!);
  }
  int byName(FeatureCode a, FeatureCode b) => a.name.compareTo(b.name);
  return [
    for (final c in lines.values.toList()..sort(byName)) _LegendLine(c),
    for (final c in pts.values.toList()..sort(byName)) _LegendSymbol(c),
    if (d.texts.any((t) => t.kind == TextKind.level))
      _LegendText((214.35).toStringAsFixed(d.options.levelDecimals), 'Level (m)'),
  ];
}

/// The grid spacing: a round number of metres about 100 mm apart on paper
double _gridInterval(double f) {
  const nice = <double>[1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000];
  for (final n in nice) {
    if (n / f >= 70) return n;
  }
  return nice.last;
}

/// A round scale bar length that fits [mm] on paper
double _barLength(double mm, double f) {
  const nice = <double>[1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000];
  var best = nice.first;
  for (final n in nice) {
    if (n / f <= mm) best = n;
  }
  return best;
}

String _coord(double v) => v.round().toString();

String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

/// Shortens a line to about [chars] characters
String _fit(String s, double chars) {
  final n = chars.floor();
  return s.length <= n ? s : '${s.substring(0, math.max(1, n - 1))}…';
}

/// Breaks text into lines of about [chars] characters, at spaces
List<String> _wrap(String s, double chars) {
  final n = math.max(8, chars.floor());
  final out = <String>[];
  for (final para in s.split('\n')) {
    var line = '';
    for (final w in para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      if (line.isEmpty) {
        line = w;
      } else if (line.length + 1 + w.length <= n) {
        line = '$line $w';
      } else {
        out.add(line);
        line = w;
      }
    }
    if (line.isNotEmpty) out.add(line);
  }
  return out;
}
