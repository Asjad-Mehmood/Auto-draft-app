// Writes the drawing as a DXF file, AutoCAD Release 12 format (AC1009). R12 is the version every
// CAD program reads: AutoCAD and AutoCAD LT (2000 onwards), Civil 3D, BricsCAD, ZWCAD, DraftSight,
// LibreCAD, QGIS and Global Mapper. Drawing units are metres, at real (UTM) coordinates.
//
// What is in it: line types (paper sizes in mm, so $LTSCALE is the drawing scale / 1000), one
// layer per feature with its colour and line type, a block for each symbol, then the lines
// (POLYLINE), symbols (INSERT), point markers (POINT) and text (TEXT).
import 'drawing.dart';
import 'geometry.dart';
import 'sheet.dart';
import 'symbols.dart';

/// The line types: (name, description, pattern in mm on paper; dash > 0, gap < 0, dot 0)
const _lineTypes = <(String, String, List<double>)>[
  ('CONTINUOUS', 'Solid line', []),
  ('DASHED', 'Dashed __ __ __', [6, -3]),
  ('HIDDEN', 'Hidden _ _ _', [3, -1.5]),
  ('CENTER', 'Centre ____ _ ____', [12, -2, 2, -2]),
  ('DASHDOT', 'Dash dot __ . __ .', [6, -2, 0, -2]),
  ('DOT', 'Dot . . . .', [0, -1.5]),
];

/// [sheet]: the printed sheet (frame, grid, legend, title block) around the survey, when wanted
String writeDxf(Drawing d, {Sheet? sheet}) {
  final w = _Writer();
  final o = d.options;
  final db = d.bounds;
  final b = sheet == null || db == null
      ? db
      : Bounds(
          db.minE < sheet.origin.e ? db.minE : sheet.origin.e,
          db.minN < sheet.origin.n ? db.minN : sheet.origin.n,
          db.maxE > sheet.bounds.maxE ? db.maxE : sheet.bounds.maxE,
          db.maxN > sheet.bounds.maxN ? db.maxN : sheet.bounds.maxN,
          db.minZ,
          db.maxZ,
        );

  // ---- header
  w.section('HEADER');
  w.variable(r'$ACADVER', () => w.pair(1, 'AC1009'));
  w.variable(r'$INSBASE', () => w.point(0, 0, 0));
  if (b != null) {
    w.variable(r'$EXTMIN', () => w.point(b.minE, b.minN, b.minZ));
    w.variable(r'$EXTMAX', () => w.point(b.maxE, b.maxN, b.maxZ));
    w.variable(r'$LIMMIN', () => w.point2(b.minE, b.minN));
    w.variable(r'$LIMMAX', () => w.point2(b.maxE, b.maxN));
  }
  w.variable(r'$TEXTSIZE', () => w.pair(40, w.num(o.textHeight)));
  w.variable(r'$LTSCALE', () => w.pair(40, w.num(o.scale / 1000)));
  w.variable(r'$PDMODE', () => w.pair(70, '0'));
  w.variable(r'$PDSIZE', () => w.pair(40, '0.0'));
  w.endSection();

  // ---- tables
  w.section('TABLES');
  w.table('LTYPE', _lineTypes.length);
  for (final (name, desc, pattern) in _lineTypes) {
    w.pair(0, 'LTYPE');
    w.pair(2, name);
    w.pair(70, '0');
    w.pair(3, desc);
    w.pair(72, '65');
    w.pair(73, '${pattern.length}');
    w.pair(40, w.num(pattern.fold<double>(0, (t, x) => t + x.abs())));
    for (final x in pattern) {
      w.pair(49, w.num(x));
    }
  }
  w.endTable();

  final layers = [const Layer('0', 7), ...d.layers, if (sheet != null) ...SheetLayers.all];
  w.table('LAYER', layers.length);
  for (final l in layers) {
    w.pair(0, 'LAYER');
    w.pair(2, l.name);
    w.pair(70, '0');
    w.pair(62, '${l.color}');
    w.pair(6, l.lineType);
  }
  w.endTable();

  w.table('STYLE', 1);
  w.pair(0, 'STYLE');
  w.pair(2, 'STANDARD');
  w.pair(70, '0');
  w.pair(40, '0.0');
  w.pair(41, '1.0');
  w.pair(50, '0.0');
  w.pair(71, '0');
  w.pair(42, w.num(o.textHeight));
  w.pair(3, 'txt');
  w.pair(4, '');
  w.endTable();
  w.endSection();

  // ---- blocks: the symbols used, one unit wide, in BYBLOCK colour so they take their layer's
  final used = {
    for (final s in d.symbols) s.symbol,
    if (sheet != null)
      for (final i in sheet.items)
        if (i is SheetSymbol) i.symbol,
  };
  w.section('BLOCKS');
  for (final name in used) {
    final def = symbols[name] ?? symbols[unknownSymbol]!;
    w.pair(0, 'BLOCK');
    w.pair(8, '0');
    w.pair(2, name);
    w.pair(70, '0');
    w.point(0, 0, 0);
    w.pair(3, name);
    for (final part in def.parts) {
      switch (part) {
        case SLine(:final x1, :final y1, :final x2, :final y2):
          w.pair(0, 'LINE');
          w.pair(8, '0');
          w.pair(62, '0');
          w.point(x1, y1, 0);
          w.point(x2, y2, 0, 11);
        case SCircle(:final x, :final y, :final r):
          w.pair(0, 'CIRCLE');
          w.pair(8, '0');
          w.pair(62, '0');
          w.point(x, y, 0);
          w.pair(40, w.num(r));
        case SPoly(:final xy, :final closed):
          w.pair(0, 'POLYLINE');
          w.pair(8, '0');
          w.pair(62, '0');
          w.pair(66, '1');
          w.point(0, 0, 0);
          w.pair(70, closed ? '1' : '0');
          for (var i = 0; i + 1 < xy.length; i += 2) {
            w.pair(0, 'VERTEX');
            w.pair(8, '0');
            w.point(xy[i], xy[i + 1], 0);
          }
          w.pair(0, 'SEQEND');
          w.pair(8, '0');
      }
    }
    w.pair(0, 'ENDBLK');
    w.pair(8, '0');
  }
  w.endSection();

  // ---- entities
  w.section('ENTITIES');
  for (final l in d.lines) {
    w.pair(0, 'POLYLINE');
    w.pair(8, l.layer);
    w.pair(66, '1');
    if (o.lines3d) {
      w.point(0, 0, 0);
      w.pair(70, '${8 | (l.closed ? 1 : 0)}');
      for (final v in l.vertices) {
        w.pair(0, 'VERTEX');
        w.pair(8, l.layer);
        w.point(v.e, v.n, v.z);
        w.pair(70, '32');
      }
    } else {
      w.point(0, 0, 0);
      w.pair(70, l.closed ? '1' : '0');
      for (final v in l.vertices) {
        w.pair(0, 'VERTEX');
        w.pair(8, l.layer);
        w.point(v.e, v.n, 0);
      }
    }
    w.pair(0, 'SEQEND');
    w.pair(8, l.layer);
  }
  for (final s in d.symbols) {
    w.pair(0, 'INSERT');
    w.pair(8, s.layer);
    w.pair(2, s.symbol);
    w.point(s.at.e, s.at.n, o.lines3d ? s.at.z : 0);
    w.pair(41, w.num(o.symbolSize));
    w.pair(42, w.num(o.symbolSize));
    w.pair(43, w.num(o.symbolSize));
  }
  for (final p in d.points) {
    w.pair(0, 'POINT');
    w.pair(8, Layers.points.name);
    w.point(p.e, p.n, p.z ?? 0);
  }
  for (final t in d.texts) {
    w.pair(0, 'TEXT');
    w.pair(8, t.layer);
    w.point(t.at.e, t.at.n, o.lines3d ? t.at.z : 0);
    w.pair(40, w.num(t.height));
    w.pair(1, _text(t.text));
  }
  if (sheet != null) _sheet(w, sheet);
  w.endSection();
  w.pair(0, 'EOF');
  return w.toString();
}

void _sheet(_Writer w, Sheet sheet) {
  for (final item in sheet.items) {
    switch (item) {
      case SheetPolyline(:final layer, :final points, :final closed, :final color, :final lineType):
        w.pair(0, 'POLYLINE');
        w.pair(8, layer);
        if (color != null) w.pair(62, '$color');
        if (lineType != null) w.pair(6, lineType);
        w.pair(66, '1');
        w.point(0, 0, 0);
        w.pair(70, closed ? '1' : '0');
        for (final v in points) {
          w.pair(0, 'VERTEX');
          w.pair(8, layer);
          w.point(v.e, v.n, 0);
        }
        w.pair(0, 'SEQEND');
        w.pair(8, layer);
      case SheetText(:final layer, :final text, :final at, :final height, :final align, :final rotation):
        w.pair(0, 'TEXT');
        w.pair(8, layer);
        w.point(at.e, at.n, 0);
        w.pair(40, w.num(height));
        w.pair(1, _text(text));
        if (rotation != 0) w.pair(50, w.num(rotation));
        if (align != SheetAlign.left) {
          w.pair(72, align == SheetAlign.center ? '1' : '2');
          w.point(at.e, at.n, 0, 11);
        }
      case SheetSolid(:final layer, :final corners):
        // R12 SOLID takes its corners as 1, 2, 4, 3; a triangle repeats its last
        final c = corners;
        final third = c.length > 3 ? c[3] : c[2];
        w.pair(0, 'SOLID');
        w.pair(8, layer);
        w.point(c[0].e, c[0].n, 0);
        w.point(c[1].e, c[1].n, 0, 11);
        w.point(third.e, third.n, 0, 12);
        w.point(c[2].e, c[2].n, 0, 13);
      case SheetSymbol(:final layer, :final symbol, :final at, :final size, :final color):
        w.pair(0, 'INSERT');
        w.pair(8, layer);
        if (color != null) w.pair(62, '$color');
        w.pair(2, symbol);
        w.point(at.e, at.n, 0);
        w.pair(41, w.num(size));
        w.pair(42, w.num(size));
        w.pair(43, w.num(size));
    }
  }
}

/// DXF R12 text is plain: no line breaks, and characters outside Latin-1 as \U+XXXX
String _text(String s) {
  final b = StringBuffer();
  for (final r in s.replaceAll(RegExp(r'[\r\n]+'), ' ').runes) {
    b.write(r < 0x80 ? String.fromCharCode(r) : '\\U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
  }
  return b.toString();
}

class _Writer {
  final _b = StringBuffer();

  void pair(int code, String value) {
    _b
      ..write(code.toString().padLeft(3))
      ..write('\r\n')
      ..write(value)
      ..write('\r\n');
  }

  /// Up to 4 decimals (0.1 mm), no trailing zeros, always with a decimal point
  String num(double v) {
    if (v.isNaN || v.isInfinite) return '0.0';
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s += '0';
    if (s == '-0.0') s = '0.0';
    return s;
  }

  void point(double x, double y, double z, [int base = 10]) {
    pair(base, num(x));
    pair(base + 10, num(y));
    pair(base + 20, num(z));
  }

  void point2(double x, double y) {
    pair(10, num(x));
    pair(20, num(y));
  }

  void section(String name) {
    pair(0, 'SECTION');
    pair(2, name);
  }

  void endSection() => pair(0, 'ENDSEC');

  void table(String name, int count) {
    pair(0, 'TABLE');
    pair(2, name);
    pair(70, '$count');
  }

  void endTable() => pair(0, 'ENDTAB');

  void variable(String name, void Function() value) {
    pair(9, name);
    value();
  }

  @override
  String toString() => _b.toString();
}
