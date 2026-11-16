import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:auto_draft/src/engine/pdf_in/pdf_drafting.dart';
import 'package:auto_draft/src/engine/pdf_in/rebuild.dart' show classifyDashes;
import 'package:auto_draft/src/screens/pdf_draft_screen.dart' show draftJob;
import 'package:flutter_test/flutter_test.dart';

/// A small PDF written by hand: [content] is the page's drawing, [layers] its optional content groups
Uint8List _pdf(String content, {List<String> layers = const []}) {
  final objs = <String>[];
  final layerRefs = [for (var i = 0; i < layers.length; i++) '${5 + i} 0 R'];
  final props = [for (var i = 0; i < layers.length; i++) '/L$i ${5 + i} 0 R'].join(' ');
  objs.add(
    '<< /Type /Catalog /Pages 2 0 R ${layers.isEmpty ? '' : '/OCProperties << /OCGs [${layerRefs.join(' ')}] /D << /ON [${layerRefs.join(' ')}] >> >>'} >>',
  );
  objs.add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  objs.add(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Contents 4 0 R '
    '/Resources << /Font << /F1 ${5 + layers.length} 0 R >> /Properties << $props >> >> >>',
  );
  objs.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  for (final l in layers) {
    objs.add('<< /Type /OCG /Name ($l) >>');
  }
  objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  final b = StringBuffer('%PDF-1.5\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(b.length);
    b.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = b.length;
  b.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

void main() {
  final plot = File('test/fixtures/pdf/cad-plot.pdf').readAsBytesSync();
  final expected = jsonDecode(File('test/fixtures/pdf/cad-plot.json').readAsStringSync()) as Map<String, dynamic>;

  group('a plot printed from CAD (test/fixtures/pdf/cad-plot.pdf)', () {
    late CadDrawing d;
    late PageDraft draft;
    setUpAll(() {
      draft = PdfDrawingFile.open(plot).draft(0, autoScale: true);
      d = draft.drawing;
    });

    test('its scale comes from its dimension: 1:200, in metres', () {
      expect(draft.suggestedScale, expected['scale']);
      expect(d.units, 'm');
      expect(d.scale, 200);
    });

    test('the dimension is a real dimension that measures 20 m', () {
      final dims = d.entities.whereType<CadDimension>().toList();
      expect(dims, hasLength(1));
      expect(dims.single.measured, closeTo(20, 0.02));
      // the printed value matches, so AutoCAD shows (and keeps up to date) the measurement
      expect(dims.single.text, '');
      expect(dims.single.style.layer, 'DIMENSIONS');
      expect(dims.single.block.whereType<CadHatch>(), hasLength(2)); // its two arrows
    });

    test('the trees are circles and the road curve is an arc', () {
      final circles = d.entities.whereType<CadCircle>().toList();
      expect(circles, hasLength(3));
      for (final c in circles) {
        expect(c.r, closeTo(1.5, 0.005));
      }
      final arc = d.entities.whereType<CadArc>().single;
      expect(arc.r, closeTo(15, 0.01));
      // at (30, 5) on the plan: 60 mm + 30 m × 5 mm/m across the paper, 100 mm + 5 m × 5 mm/m up it
      expect(arc.cx, closeTo((60 + 30 * 5) * 0.2, 0.02));
      expect(arc.cy, closeTo((100 + 5 * 5) * 0.2, 0.02));
    });

    test('dashes become line types: the centre line CENTER, the boundary DASHED and closed', () {
      final center = d.entities.where((e) => d.layers[e.style.layer]!.lineType == 'CENTER').toList();
      expect(center, hasLength(1));
      expect(center.single, isA<CadLine>());
      final boundary = d.entities.where((e) => d.layers[e.style.layer]!.lineType == 'DASHED').toList();
      expect(boundary, hasLength(1));
      final pl = boundary.single as CadPolyline;
      expect(pl.closed, isTrue);
      expect(pl.vertices, hasLength(4));
      // 53 m by 43 m
      final xs = pl.vertices.map((v) => v.x), ys = pl.vertices.map((v) => v.y);
      expect(xs.reduce(math.max) - xs.reduce(math.min), closeTo(53, 0.05));
      expect(ys.reduce(math.max) - ys.reduce(math.min), closeTo(43, 0.05));
    });

    test('the building is one closed polyline of six corners', () {
      final pl = d.entities.whereType<CadPolyline>().where((p) => p.style.layer == 'LINES-WHITE').single;
      expect(pl.closed, isTrue);
      expect(pl.vertices, hasLength(6));
    });

    test('the fills are hatches: SOLID for the pad, ANSI31 for the garden', () {
      final hatches = d.entities.whereType<CadHatch>().toList();
      expect(hatches.map((h) => h.pattern), containsAll(['SOLID', 'ANSI31']));
      final ansi = hatches.firstWhere((h) => h.pattern == 'ANSI31');
      // 3.175 mm apart on paper: the pattern's own spacing, at 1:200
      expect(ansi.patternScale, closeTo(0.2, 0.01));
      // none of its lines is left loose
      expect(d.entities.whereType<CadLine>().length, lessThan(5));
    });

    test('text is text, at its size and angle', () {
      final texts = {for (final t in d.entities.whereType<CadText>()) t.text: t};
      for (final e in expected['texts'] as List) {
        final t = texts[e['text']]!;
        expect(t.height, closeTo((e['height_mm'] as num) * 0.2, 0.02), reason: '${e['text']}');
        expect(t.angle, closeTo((e['angle'] as num).toDouble(), 0.2));
      }
      expect(texts['BUILDING']!.textStyle, 'Arial Bold');
    });

    test('every object is on a layer with a standard colour and line type', () {
      for (final e in d.entities) {
        final l = d.layers[e.style.layer];
        expect(l, isNotNull);
        expect(l!.aci, inInclusiveRange(1, 255));
        expect(standardLineTypes.keys, contains(l.lineType));
      }
      expect(d.layers.keys, containsAll(['LINES-RED', 'LINES-MAGENTA-DASHED', 'TEXT', 'HATCH', 'DIMENSIONS']));
    });

    test('without the scale it is drawn in millimetres, as printed', () {
      final mm = PdfDrawingFile.open(plot).draft(0).drawing;
      expect(mm.units, 'mm');
      expect(mm.entities.whereType<CadCircle>().first.r, closeTo(7.5, 0.02)); // 1.5 m at 1:200
    });

    test('the DXF is AutoCAD 2000 with the hatches, the dimension and the line types', () {
      final dxf = pdfDrawingToDxf(d);
      expect(dxf, contains('AC1015'));
      for (final s in [
        'HATCH',
        'DIMENSION',
        'LWPOLYLINE',
        'CIRCLE',
        'ARC',
        'TEXT',
        'ANSI31',
        'CENTER',
        'DASHED',
        '*D1',
        r'$INSUNITS',
      ]) {
        expect(dxf, contains(s), reason: s);
      }
    });
  });

  group('the PDF reader', () {
    test("a PDF's own layers are kept, with their names", () {
      const content = '''
/OC /L0 BDC 1 0 0 RG 1 w 100 100 m 300 100 l S EMC
/OC /L1 BDC 0 0 1 RG 100 200 m 300 200 l 300 300 l S EMC
/OC /L1 BDC BT /F1 12 Tf 100 400 Td (Hello) Tj ET EMC''';
      final d = PdfDrawingFile.open(_pdf(content, layers: ['C-ROAD-EDGE', 'C-BLDG'])).draft(0).drawing;
      expect(d.layers.keys, containsAll(['C-ROAD-EDGE', 'C-BLDG']));
      expect(d.entities.whereType<CadLine>().single.style.layer, 'C-ROAD-EDGE');
      expect(d.entities.whereType<CadPolyline>().single.style.layer, 'C-BLDG');
      expect(d.entities.whereType<CadText>().single.style.layer, 'C-BLDG');
      expect(d.layers['C-ROAD-EDGE']!.aci, 1);
      expect(d.layers['C-BLDG']!.aci, 5);
    });

    test('a dash pattern set in the PDF itself becomes a line type', () {
      final d = PdfDrawingFile.open(_pdf('[36 18] 0 d 0 0 0 RG 100 100 m 500 100 l S')).draft(0).drawing;
      final line = d.entities.whereType<CadLine>().single;
      expect(d.layers[line.style.layer]!.lineType, 'DASHED');
    });

    test('pieces that meet end to end become one polyline', () {
      const content =
          '0 0 0 RG 100 100 m 200 100 l S 200 100 m 200 200 l S 200 200 m 100 200 l S 100 200 m 100 100 l S';
      final d = PdfDrawingFile.open(_pdf(content)).draft(0).drawing;
      final pl = d.entities.whereType<CadPolyline>().single;
      expect(pl.closed, isTrue);
      expect(pl.vertices, hasLength(4));
    });

    test('a scanned page says so', () {
      // a picture covering the page, and nothing drawn
      const content = 'q 842 0 0 595 0 0 cm BI /W 1 /H 1 /BPC 8 /CS /G ID \x80 EI Q';
      final d = PdfDrawingFile.open(_pdf(content)).draft(0).drawing;
      expect(d.notes.single, contains('scanned'));
    });

    test('something that is not a PDF is refused clearly', () {
      expect(
        () => PdfDrawingFile.open(Uint8List.fromList(utf8.encode('Point,E,N\n1,2,3'))),
        throwsA(isA<PdfReadError>()),
      );
    });
  });

  group('the sample drawing (tool/make_sample_plan_pdf.py)', () {
    final sample = File('test/fixtures/pdf/sample-site-plan.pdf').readAsBytesSync();

    test('it drafts in a background isolate, as the app does it', () async {
      // the job must be sendable: a job that carried the screen with it failed on the Mac with
      // "object is unsendable"
      final r = await Isolate.run(draftJob(sample, 0, 0, true));
      expect(r.pageCount, 2);
      expect(r.pdfLayers, 17);
      expect(r.drawing.scale, 250);
    });

    test('the site plan: its layers, scale, dimensions, circles and line types', () {
      final d = PdfDrawingFile.open(sample).draft(0, autoScale: true).drawing;
      expect(d.scale, 250);
      expect(d.layers.keys, containsAll(['C-PROP-BNDY', 'C-ROAD-CNTR', 'A-BLDG', 'L-TREE', 'G-ANNO-DIMS']));
      final dims = [for (final x in d.entities.whereType<CadDimension>()) double.parse(x.measured.toStringAsFixed(2))]
        ..sort();
      expect(dims, [4.24, 10.0, 16.0, 20.0, 22.0, 22.0, 24.0, 44.0, 86.0]);
      // 7 trees (canopy and trunk) and 3 manholes
      expect(d.entities.whereType<CadCircle>(), hasLength(17));
      // the centre line round the curve is one CENTER polyline, arc and all
      final cl = d.entities.where((e) => e.style.layer == 'C-ROAD-CNTR').toList();
      expect(d.layers['C-ROAD-CNTR']!.lineType, 'CENTER');
      expect(cl.whereType<CadPolyline>().single.vertices.any((v) => v.bulge != 0), isTrue);
      expect(cl.whereType<CadArc>(), isEmpty);
      expect(d.layers['C-PROP-BNDY']!.lineType, 'PHANTOM');
      final hatches = d.entities.whereType<CadHatch>().map((h) => h.pattern).toList();
      expect(hatches.where((p) => p == 'ANSI31'), hasLength(2));
      expect(hatches, contains('ANSI37'));
    });

    test('the cross section: 1:50, both pattern hatches ANSI31 at their angles', () {
      final d = PdfDrawingFile.open(sample).draft(1, autoScale: true).drawing;
      expect(d.scale, 50);
      final dims = [for (final x in d.entities.whereType<CadDimension>()) double.parse(x.measured.toStringAsFixed(2))]
        ..sort();
      expect(dims, [2.15, 2.15, 7.3]);
      final ansi =
          d.entities.whereType<CadHatch>().where((h) => h.pattern == 'ANSI31').map((h) => h.angle.round()).toList()
            ..sort();
      expect(ansi, [0, 90]);
    });
  });

  group('dashes to line types', () {
    (String, double)? kind(List<double> pattern, {int repeats = 6}) {
      final dashes = <double>[], starts = <double>[];
      var pos = 0.0;
      for (var r = 0; r < repeats; r++) {
        for (var i = 0; i < pattern.length; i += 2) {
          starts.add(pos);
          dashes.add(pattern[i]);
          pos += pattern[i] + pattern[i + 1];
        }
      }
      return classifyDashes(dashes, starts);
    }

    test('each standard pattern is recognised, at any size', () {
      for (final scale in [0.5, 1.0, 3.0]) {
        List<double> s(List<double> p) => [for (final x in p) x * scale];
        expect(kind(s([12.7, 6.35]))?.$1, 'DASHED');
        expect(kind(s([31.75, 6.35, 6.35, 6.35]))?.$1, 'CENTER');
        expect(kind(s([31.75, 6.35, 6.35, 6.35, 6.35, 6.35]))?.$1, 'PHANTOM');
        expect(kind(s([12.7, 6.35, 0, 6.35]))?.$1, 'DASHDOT');
        expect(kind(s([12.7, 6.35, 0, 6.35, 0, 6.35]))?.$1, 'DIVIDE');
        expect(kind(s([12.7, 6.35, 12.7, 6.35, 0, 6.35]))?.$1, 'BORDER');
        expect(kind([0, 6.35 * scale])?.$1, 'DOT');
      }
    });

    test('the period gives the line-type scale', () {
      final (type, period) = kind([31.75 * 2, 6.35 * 2, 6.35 * 2, 6.35 * 2])!;
      expect(type, 'CENTER');
      expect(period / standardPeriod('CENTER'), closeTo(2, 0.01));
    });
  });
}
