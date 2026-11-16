// Writes a drawing rebuilt from a PDF as a DXF in AutoCAD 2000 format (AC1015), which every
// AutoCAD since 2000, AutoCAD LT, Civil 3D, BricsCAD, ZWCAD and DraftSight open. 2000 rather than
// R12 because it has what a redrawn plan needs: hatches, lightweight polylines with arcs,
// lineweights and real dimensions.
//
// Layout: header, the classes AutoCAD expects, the tables (line types, layers, text styles, the
// dimension style, block records), blocks (model and paper space, one block per dimension), the
// objects, then the entities in drawing order: hatches under lines under text.
import 'dart:math' as math;

import 'cad.dart';

class _W {
  final b = StringBuffer();
  int _next = 0x40;
  String handle() => (_next++).toRadixString(16).toUpperCase();
  void pair(int code, Object value) {
    b
      ..write(code.toString().padLeft(3))
      ..write('\r\n')
      ..write(value is double ? _num(value) : value)
      ..write('\r\n');
  }

  static String _num(double v) {
    if (v.isNaN || v.isInfinite) return '0.0';
    final s = v.toStringAsFixed(6);
    var t = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '') : s;
    if (t.endsWith('.')) t = '${t}0';
    return t == '-0.0' ? '0.0' : t;
  }
}

/// Text for DXF: characters past ASCII as \U+XXXX (the file is ANSI_1252)
String _dxfText(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r == 10 || r == 13) {
      out.write(' ');
    } else if (r < 128) {
      out.writeCharCode(r);
    } else {
      out.write('\\U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
    }
  }
  return out.toString();
}

String writeDxf2000(CadDrawing d) {
  final w = _W();
  // fixed handles for the structure
  const hLayerTable = '1',
      hLtypeTable = '2',
      hAppTable = '3',
      hDimTable = '4',
      hStyleTable = '5',
      hUcsTable = '6',
      hViewTable = '7',
      hVportTable = '8',
      hBlockTable = '9';
  const hRoot = 'A', hGroups = 'B', hLayouts = 'C', hMline = 'D', hPlotStyles = 'E', hPlaceholder = 'F';
  const hModelRec = '10', hModelBlock = '11', hModelEnd = '12', hModelLayout = '13';
  const hPaperRec = '14', hPaperBlock = '15', hPaperEnd = '16', hPaperLayout = '17';
  const hMlineStd = '18', hVport = '19', hDimStd = '1A', hDimPdf = '1B', hApp = '1C';
  // dimensions: one anonymous block each
  final dims = d.entities.whereType<CadDimension>().toList();
  final dimBlocks = [
    for (var i = 0; i < dims.length; i++) (name: '*D${i + 1}', rec: w.handle(), begin: w.handle(), end: w.handle()),
  ];

  final b = d.bounds ?? (minX: 0.0, minY: 0.0, maxX: 420.0, maxY: 297.0);
  final metres = d.units == 'm';
  final dimTxt = dims.isEmpty ? 2.5 : dims.first.textHeight;
  final dimAsz = dims.isEmpty ? 2.5 : dims.first.arrowSize;
  final dimDec = () {
    for (final x in dims) {
      final m = RegExp(r'\.(\d+)').firstMatch(x.text);
      if (m != null) return m.group(1)!.length;
    }
    return metres ? 2 : 0;
  }();

  // ---------------------------------------------------------------- header
  w.pair(0, 'SECTION');
  w.pair(2, 'HEADER');
  void v(String name, void Function() body) {
    w.pair(9, name);
    body();
  }

  v(r'$ACADVER', () => w.pair(1, 'AC1015'));
  v(r'$DWGCODEPAGE', () => w.pair(3, 'ANSI_1252'));
  v(r'$INSBASE', () => [w.pair(10, 0.0), w.pair(20, 0.0), w.pair(30, 0.0)]);
  v(r'$EXTMIN', () => [w.pair(10, b.minX), w.pair(20, b.minY), w.pair(30, 0.0)]);
  v(r'$EXTMAX', () => [w.pair(10, b.maxX), w.pair(20, b.maxY), w.pair(30, 0.0)]);
  v(r'$LIMMIN', () => [w.pair(10, b.minX), w.pair(20, b.minY)]);
  v(r'$LIMMAX', () => [w.pair(10, b.maxX), w.pair(20, b.maxY)]);
  v(r'$LTSCALE', () => w.pair(40, 1.0));
  v(r'$PSLTSCALE', () => w.pair(70, 0));
  v(r'$LUNITS', () => w.pair(70, 2));
  v(r'$LUPREC', () => w.pair(70, metres ? 3 : 2));
  v(r'$INSUNITS', () => w.pair(70, metres ? 6 : 4));
  v(r'$MEASUREMENT', () => w.pair(70, 1));
  v(r'$LWDISPLAY', () => w.pair(290, 1));
  v(r'$TEXTSTYLE', () => w.pair(7, 'Standard'));
  v(r'$CLAYER', () => w.pair(8, '0'));
  v(r'$DIMSTYLE', () => w.pair(2, dims.isEmpty ? 'Standard' : 'PDF'));
  v(r'$HANDSEED', () => w.pair(5, 'FFFFF'));
  w.pair(0, 'ENDSEC');

  // ---------------------------------------------------------------- classes
  w.pair(0, 'SECTION');
  w.pair(2, 'CLASSES');
  for (final (dxf, cpp) in const [
    ('ACDBDICTIONARYWDFLT', 'AcDbDictionaryWithDefault'),
    ('ACDBPLACEHOLDER', 'AcDbPlaceHolder'),
    ('LAYOUT', 'AcDbLayout'),
  ]) {
    w.pair(0, 'CLASS');
    w.pair(1, dxf);
    w.pair(2, cpp);
    w.pair(3, 'ObjectDBX Classes');
    w.pair(90, 0);
    w.pair(280, 0);
    w.pair(281, 0);
  }
  w.pair(0, 'ENDSEC');

  // ---------------------------------------------------------------- tables
  w.pair(0, 'SECTION');
  w.pair(2, 'TABLES');
  void table(String name, String h, int count, [void Function()? extra]) {
    w.pair(0, 'TABLE');
    w.pair(2, name);
    w.pair(5, h);
    w.pair(330, '0');
    w.pair(100, 'AcDbSymbolTable');
    w.pair(70, count);
    extra?.call();
  }

  void record(String type, String h, String owner, String sub) {
    w.pair(0, type);
    w.pair(type == 'DIMSTYLE' ? 105 : 5, h);
    w.pair(330, owner);
    w.pair(100, 'AcDbSymbolTableRecord');
    w.pair(100, sub);
  }

  // VPORT: the view on opening, the whole drawing
  table('VPORT', hVportTable, 1);
  record('VPORT', hVport, hVportTable, 'AcDbViewportTableRecord');
  w.pair(2, '*Active');
  w.pair(70, 0);
  for (final (c, val) in [(10, 0.0), (20, 0.0), (11, 1.0), (21, 1.0)]) {
    w.pair(c, val);
  }
  w.pair(12, (b.minX + b.maxX) / 2);
  w.pair(22, (b.minY + b.maxY) / 2);
  for (final (c, val) in [
    (13, 0.0),
    (23, 0.0),
    (14, 1.0),
    (24, 1.0),
    (15, 0.0),
    (25, 0.0),
    (16, 0.0),
    (26, 0.0),
    (36, 1.0),
    (17, 0.0),
    (27, 0.0),
    (37, 0.0),
  ]) {
    w.pair(c, val);
  }
  w.pair(40, math.max(b.maxY - b.minY, (b.maxX - b.minX) / 1.6) * 1.1);
  w.pair(41, 1.6);
  w.pair(42, 50.0);
  for (final (c, val) in [(43, 0.0), (44, 0.0), (50, 0.0), (51, 0.0)]) {
    w.pair(c, val);
  }
  for (final (c, val) in [(71, 0), (72, 1000), (73, 1), (74, 3), (75, 0), (76, 0), (77, 0), (78, 0)]) {
    w.pair(c, val);
  }
  w.pair(0, 'ENDTAB');

  // LTYPE
  final usedLts = {
    for (final l in d.layers.values) l.lineType.toUpperCase(),
    for (final e in d.entities)
      if (e.style.lineType != 'BYLAYER') e.style.lineType.toUpperCase(),
  }..remove('CONTINUOUS');
  table('LTYPE', hLtypeTable, 3 + usedLts.length);
  for (final name in ['ByBlock', 'ByLayer', 'Continuous']) {
    record('LTYPE', w.handle(), hLtypeTable, 'AcDbLinetypeTableRecord');
    w.pair(2, name);
    w.pair(70, 0);
    w.pair(3, name == 'Continuous' ? 'Solid line' : '');
    w.pair(72, 65);
    w.pair(73, 0);
    w.pair(40, 0.0);
  }
  for (final name in usedLts) {
    final (String desc, List<double> pattern) = standardLineTypes[name] ?? ('', const <double>[]);
    record('LTYPE', w.handle(), hLtypeTable, 'AcDbLinetypeTableRecord');
    w.pair(2, name);
    w.pair(70, 0);
    w.pair(3, desc);
    w.pair(72, 65);
    w.pair(73, pattern.length);
    w.pair(40, pattern.fold<double>(0.0, (a, x) => a + x.abs()));
    for (final p in pattern) {
      w.pair(49, p);
      w.pair(74, 0);
    }
  }
  w.pair(0, 'ENDTAB');

  String lt(String n) => n.toUpperCase() == 'CONTINUOUS' ? 'Continuous' : n.toUpperCase();

  // LAYER
  final layers = [CadLayer('0'), ...d.layers.values.where((l) => l.name != '0')];
  if (dims.isNotEmpty && !layers.any((l) => l.name == 'Defpoints')) layers.add(CadLayer('Defpoints'));
  table('LAYER', hLayerTable, layers.length);
  for (final l in layers) {
    record('LAYER', w.handle(), hLayerTable, 'AcDbLayerTableRecord');
    w.pair(2, l.name);
    w.pair(70, 0);
    w.pair(62, l.aci);
    w.pair(6, lt(l.lineType));
    if (l.name == 'Defpoints') w.pair(290, 0);
    w.pair(370, l.lineWeight);
    w.pair(390, hPlaceholder);
  }
  w.pair(0, 'ENDTAB');

  // STYLE
  table('STYLE', hStyleTable, d.textStyles.length);
  for (final e in d.textStyles.entries) {
    record('STYLE', w.handle(), hStyleTable, 'AcDbTextStyleTableRecord');
    w.pair(2, e.key);
    w.pair(70, 0);
    w.pair(40, 0.0);
    w.pair(41, 1.0);
    w.pair(50, 0.0);
    w.pair(71, 0);
    w.pair(42, 2.5);
    w.pair(3, e.value);
    w.pair(4, '');
  }
  w.pair(0, 'ENDTAB');

  table('VIEW', hViewTable, 0);
  w.pair(0, 'ENDTAB');
  table('UCS', hUcsTable, 0);
  w.pair(0, 'ENDTAB');
  table('APPID', hAppTable, 1);
  record('APPID', hApp, hAppTable, 'AcDbRegAppTableRecord');
  w.pair(2, 'ACAD');
  w.pair(70, 0);
  w.pair(0, 'ENDTAB');

  // DIMSTYLE: Standard, and PDF with the sizes the drawing's dimensions use
  table('DIMSTYLE', hDimTable, dims.isEmpty ? 1 : 2, () => w.pair(100, 'AcDbDimStyleTable'));
  void dimStyle(String h, String name, double txt, double asz, int dec) {
    record('DIMSTYLE', h, hDimTable, 'AcDbDimStyleTableRecord');
    w.pair(2, name);
    w.pair(70, 0);
    w.pair(40, 1.0); // DIMSCALE
    w.pair(41, asz); // DIMASZ
    w.pair(42, txt * 0.25); // DIMEXO
    w.pair(44, txt * 0.5); // DIMEXE
    w.pair(140, txt); // DIMTXT
    w.pair(147, txt * 0.25); // DIMGAP
    w.pair(77, 1); // DIMTAD: text above the line
    w.pair(73, 0); // DIMTIH
    w.pair(74, 0); // DIMTOH
    w.pair(271, dec); // DIMDEC
    w.pair(277, 2); // DIMLUNIT: decimal
    w.pair(278, 46); // DIMDSEP '.'
  }

  dimStyle(hDimStd, 'Standard', 2.5, 2.5, 4);
  if (dims.isNotEmpty) dimStyle(hDimPdf, 'PDF', dimTxt, dimAsz, dimDec);
  w.pair(0, 'ENDTAB');

  // BLOCK_RECORD
  table('BLOCK_RECORD', hBlockTable, 2 + dimBlocks.length);
  record('BLOCK_RECORD', hModelRec, hBlockTable, 'AcDbBlockTableRecord');
  w.pair(2, '*Model_Space');
  w.pair(340, hModelLayout);
  record('BLOCK_RECORD', hPaperRec, hBlockTable, 'AcDbBlockTableRecord');
  w.pair(2, '*Paper_Space');
  w.pair(340, hPaperLayout);
  for (final db in dimBlocks) {
    record('BLOCK_RECORD', db.rec, hBlockTable, 'AcDbBlockTableRecord');
    w.pair(2, db.name);
    w.pair(340, '0');
  }
  w.pair(0, 'ENDTAB');
  w.pair(0, 'ENDSEC');

  // ---------------------------------------------------------------- entities (also inside blocks)
  void common(String type, CadStyle s, String owner, String sub) {
    w.pair(0, type);
    w.pair(5, w.handle());
    w.pair(330, owner);
    w.pair(100, 'AcDbEntity');
    w.pair(8, s.layer);
    if (s.lineType != 'BYLAYER') w.pair(6, lt(s.lineType));
    if (s.aci != 256) w.pair(62, s.aci);
    if (s.lineWeight != -1) w.pair(370, s.lineWeight);
    if ((s.ltScale - 1).abs() > 1e-6) w.pair(48, s.ltScale);
    w.pair(100, sub);
  }

  void loopVertices(List<CadVertex> loop) {
    final bulged = loop.any((q) => q.bulge != 0);
    w.pair(92, 2); // a polyline boundary
    w.pair(72, bulged ? 1 : 0);
    w.pair(73, 1);
    w.pair(93, loop.length);
    for (final q in loop) {
      w.pair(10, q.x);
      w.pair(20, q.y);
      if (bulged) w.pair(42, q.bulge);
    }
    w.pair(97, 0);
  }

  void entity(CadEntity e, String owner, int dimIndex) {
    switch (e) {
      case CadLine():
        common('LINE', e.style, owner, 'AcDbLine');
        w
          ..pair(10, e.x1)
          ..pair(20, e.y1)
          ..pair(30, 0.0)
          ..pair(11, e.x2)
          ..pair(21, e.y2)
          ..pair(31, 0.0);
      case CadPolyline():
        common('LWPOLYLINE', e.style, owner, 'AcDbPolyline');
        w.pair(90, e.vertices.length);
        w.pair(70, e.closed ? 1 : 0);
        w.pair(43, 0.0);
        for (final q in e.vertices) {
          w.pair(10, q.x);
          w.pair(20, q.y);
          if (q.bulge != 0) w.pair(42, q.bulge);
        }
      case CadCircle():
        common('CIRCLE', e.style, owner, 'AcDbCircle');
        w
          ..pair(10, e.cx)
          ..pair(20, e.cy)
          ..pair(30, 0.0)
          ..pair(40, e.r);
      case CadArc():
        common('ARC', e.style, owner, 'AcDbCircle');
        w
          ..pair(10, e.cx)
          ..pair(20, e.cy)
          ..pair(30, 0.0)
          ..pair(40, e.r)
          ..pair(100, 'AcDbArc')
          ..pair(50, e.start)
          ..pair(51, e.end);
      case CadText():
        common('TEXT', e.style, owner, 'AcDbText');
        w
          ..pair(10, e.x)
          ..pair(20, e.y)
          ..pair(30, 0.0)
          ..pair(40, e.height)
          ..pair(1, _dxfText(e.text));
        if (e.angle.abs() > 1e-6) w.pair(50, e.angle);
        w.pair(7, e.textStyle);
        w.pair(100, 'AcDbText');
      case CadHatch():
        common('HATCH', e.style, owner, 'AcDbHatch');
        w
          ..pair(10, 0.0)
          ..pair(20, 0.0)
          ..pair(30, 0.0)
          ..pair(210, 0.0)
          ..pair(220, 0.0)
          ..pair(230, 1.0);
        final user = e.pattern.startsWith('_USER');
        w.pair(2, user ? '_USER' : e.pattern);
        w.pair(70, e.solid ? 1 : 0);
        w.pair(71, 0);
        w.pair(91, e.loops.length);
        for (final l in e.loops) {
          loopVertices(l);
        }
        w.pair(75, 0);
        w.pair(76, user ? 0 : 1);
        if (!e.solid) {
          // the pattern's lines: (angle, spacing) in drawing units
          final lines = switch (e.pattern) {
            'ANSI31' => [(45.0 + e.angle, 3.175 * e.patternScale)],
            'ANSI37' => [(45.0 + e.angle, 3.175 * e.patternScale), (135.0 + e.angle, 3.175 * e.patternScale)],
            '_USER_DOUBLE' => [(e.angle, e.spacing), (e.angle + 90, e.spacing)],
            _ => [(e.angle, e.spacing)],
          };
          w.pair(52, e.angle);
          w.pair(41, user ? e.spacing : e.patternScale);
          w.pair(77, e.pattern == '_USER_DOUBLE' ? 1 : 0);
          w.pair(78, lines.length);
          for (final (ang, sp) in lines) {
            final a = ang * math.pi / 180;
            w.pair(53, ang);
            w.pair(43, 0.0);
            w.pair(44, 0.0);
            w.pair(45, -math.sin(a) * sp);
            w.pair(46, math.cos(a) * sp);
            w.pair(79, 0);
          }
        }
        w.pair(98, 0);
      case CadDimension():
        common('DIMENSION', e.style, owner, 'AcDbDimension');
        w.pair(2, dimBlocks[dimIndex].name);
        w
          ..pair(10, e.lineX)
          ..pair(20, e.lineY)
          ..pair(30, 0.0)
          ..pair(11, e.textX)
          ..pair(21, e.textY)
          ..pair(31, 0.0)
          ..pair(70, 1 | 32)
          ..pair(1, _dxfText(e.text))
          ..pair(42, e.measured)
          ..pair(3, 'PDF')
          ..pair(100, 'AcDbAlignedDimension')
          ..pair(13, e.x1)
          ..pair(23, e.y1)
          ..pair(33, 0.0)
          ..pair(14, e.x2)
          ..pair(24, e.y2)
          ..pair(34, 0.0);
    }
  }

  // ---------------------------------------------------------------- blocks
  w.pair(0, 'SECTION');
  w.pair(2, 'BLOCKS');
  void block(
    String name,
    String rec,
    String begin,
    String end, {
    bool anonymous = false,
    List<CadEntity> body = const [],
    String layer = '0',
  }) {
    w.pair(0, 'BLOCK');
    w.pair(5, begin);
    w.pair(330, rec);
    w.pair(100, 'AcDbEntity');
    if (name == '*Paper_Space') w.pair(67, 1);
    w.pair(8, layer);
    w.pair(100, 'AcDbBlockBegin');
    w.pair(2, name);
    w.pair(70, anonymous ? 1 : 0);
    w.pair(10, 0.0);
    w.pair(20, 0.0);
    w.pair(30, 0.0);
    w.pair(3, name);
    w.pair(1, '');
    for (final e in body) {
      entity(e, rec, -1);
    }
    w.pair(0, 'ENDBLK');
    w.pair(5, end);
    w.pair(330, rec);
    w.pair(100, 'AcDbEntity');
    if (name == '*Paper_Space') w.pair(67, 1);
    w.pair(8, layer);
    w.pair(100, 'AcDbBlockEnd');
  }

  block('*Model_Space', hModelRec, hModelBlock, hModelEnd);
  block('*Paper_Space', hPaperRec, hPaperBlock, hPaperEnd);
  for (var i = 0; i < dims.length; i++) {
    final db = dimBlocks[i];
    block(db.name, db.rec, db.begin, db.end, anonymous: true, body: dims[i].block, layer: dims[i].style.layer);
  }
  w.pair(0, 'ENDSEC');

  // ---------------------------------------------------------------- entities
  w.pair(0, 'SECTION');
  w.pair(2, 'ENTITIES');
  int rank(CadEntity e) => switch (e) {
    CadHatch(:final solid) => solid ? 0 : 1,
    CadText() => 4,
    CadDimension() => 3,
    _ => 2,
  };
  final ordered = List.of(d.entities)..sort((a, b) => rank(a).compareTo(rank(b)));
  for (final e in ordered) {
    entity(e, hModelRec, e is CadDimension ? dims.indexOf(e) : -1);
  }
  w.pair(0, 'ENDSEC');

  // ---------------------------------------------------------------- objects
  w.pair(0, 'SECTION');
  w.pair(2, 'OBJECTS');
  void dict(String h, String owner, Map<String, String> entries, {String type = 'DICTIONARY'}) {
    w.pair(0, type);
    w.pair(5, h);
    w.pair(330, owner);
    w.pair(100, 'AcDbDictionary');
    w.pair(281, 1);
    for (final e in entries.entries) {
      w.pair(3, e.key);
      w.pair(350, e.value);
    }
  }

  dict(hRoot, '0', {
    'ACAD_GROUP': hGroups,
    'ACAD_LAYOUT': hLayouts,
    'ACAD_MLINESTYLE': hMline,
    'ACAD_PLOTSTYLENAME': hPlotStyles,
  });
  dict(hGroups, hRoot, {});
  dict(hLayouts, hRoot, {'Model': hModelLayout, 'Layout1': hPaperLayout});
  dict(hMline, hRoot, {'Standard': hMlineStd});
  dict(hPlotStyles, hRoot, {'Normal': hPlaceholder}, type: 'ACDBDICTIONARYWDFLT');
  w.pair(100, 'AcDbDictionaryWithDefault');
  w.pair(340, hPlaceholder);
  w.pair(0, 'ACDBPLACEHOLDER');
  w.pair(5, hPlaceholder);
  w.pair(330, hPlotStyles);
  // the standard multiline style
  w.pair(0, 'MLINESTYLE');
  w.pair(5, hMlineStd);
  w.pair(330, hMline);
  w.pair(100, 'AcDbMlineStyle');
  w.pair(2, 'Standard');
  w.pair(70, 0);
  w.pair(3, '');
  w.pair(62, 256);
  w.pair(51, 90.0);
  w.pair(52, 90.0);
  w.pair(71, 2);
  w.pair(49, 0.5);
  w.pair(62, 256);
  w.pair(6, 'BYLAYER');
  w.pair(49, -0.5);
  w.pair(62, 256);
  w.pair(6, 'BYLAYER');
  // the two layouts
  void layout(String h, String name, int tab, String rec) {
    w.pair(0, 'LAYOUT');
    w.pair(5, h);
    w.pair(330, hLayouts);
    w.pair(100, 'AcDbPlotSettings');
    w.pair(1, '');
    w.pair(4, 'A3');
    w.pair(6, '');
    for (final (c, val) in [
      (40, 7.5),
      (41, 20.0),
      (42, 7.5),
      (43, 20.0),
      (44, 420.0),
      (45, 297.0),
      (46, 0.0),
      (47, 0.0),
      (48, 0.0),
      (49, 0.0),
      (140, 0.0),
      (141, 0.0),
      (142, 1.0),
      (143, 1.0),
    ]) {
      w.pair(c, val);
    }
    w.pair(70, name == 'Model' ? 1024 : 0);
    for (final (c, val) in [(72, 1), (73, 0), (74, 5)]) {
      w.pair(c, val);
    }
    w.pair(7, '');
    for (final (c, val) in [(75, 16), (76, 0), (77, 2), (78, 300)]) {
      w.pair(c, val);
    }
    w.pair(147, 1.0);
    w.pair(148, 0.0);
    w.pair(149, 0.0);
    w.pair(100, 'AcDbLayout');
    w.pair(1, name);
    w.pair(70, 1);
    w.pair(71, tab);
    for (final (c, val) in [(10, 0.0), (20, 0.0), (11, 420.0), (21, 297.0), (12, 0.0), (22, 0.0), (32, 0.0)]) {
      w.pair(c, val);
    }
    for (final (c, val) in [(14, 1e20), (24, 1e20), (34, 1e20), (15, -1e20), (25, -1e20), (35, -1e20)]) {
      w.pair(c, val.toStringAsExponential(0).replaceFirst('e+', 'e+'));
    }
    for (final (c, val) in [
      (146, 0.0),
      (13, 0.0),
      (23, 0.0),
      (33, 0.0),
      (16, 1.0),
      (26, 0.0),
      (36, 0.0),
      (17, 0.0),
      (27, 1.0),
      (37, 0.0),
    ]) {
      w.pair(c, val);
    }
    w.pair(76, 1);
    w.pair(330, rec);
  }

  layout(hModelLayout, 'Model', 0, hModelRec);
  layout(hPaperLayout, 'Layout1', 1, hPaperRec);
  w.pair(0, 'ENDSEC');
  w.pair(0, 'EOF');
  // the next free handle, now that every one is given
  return w.b.toString().replaceFirst('  5\r\nFFFFF\r\n', '  5\r\n${w.handle()}\r\n');
}
