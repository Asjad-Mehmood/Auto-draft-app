import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/dxf.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/engine/pdf.dart';
import 'package:auto_draft/src/engine/point.dart';
import 'package:auto_draft/src/engine/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

Drawing _sample([int scale = 500]) {
  final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
  return buildDrawing(readPoints(t, guessColumns(t)).points, CodeLibrary.defaults(), DraftOptions(scale: scale));
}

Iterable<String> _texts(Sheet s) => s.items.whereType<SheetText>().map((t) => t.text);

void main() {
  test('the smallest paper that fits', () {
    final a = buildSheet(_sample(), const SheetInfo());
    expect(a.paper, Paper.a3);
    expect(a.portrait, isFalse);
    expect(a.fits, isTrue);
    expect(a.label, 'A3 landscape at 1:500');
    final b = buildSheet(_sample(1000), const SheetInfo());
    expect(b.paper, Paper.a4);
    expect(b.fits, isTrue);
  });

  test('a paper that is too small says what would fit', () {
    final s = buildSheet(_sample(), const SheetInfo(paper: Paper.a4));
    expect(s.paper, Paper.a4);
    expect(s.fits, isFalse);
    expect(s.advice, 'To fit it, choose A3, or the scale 1:1000.');
  });

  test('the survey sits inside the drawing area, centred', () {
    final d = _sample();
    final s = buildSheet(d, const SheetInfo());
    final b = d.bounds!;
    expect(b.minE, greaterThanOrEqualTo(s.area.minE));
    expect(b.maxE, lessThanOrEqualTo(s.area.maxE));
    expect(b.minN, greaterThanOrEqualTo(s.area.minN));
    expect(b.maxN, lessThanOrEqualTo(s.area.maxN));
    expect((b.minE + b.maxE) / 2, closeTo((s.area.minE + s.area.maxE) / 2, 1e-6));
    // the paper is 420 x 297 mm at 1:500
    expect(s.width, closeTo(210, 1e-9));
    expect(s.height, closeTo(148.5, 1e-9));
  });

  test('everything on the sheet is on the paper', () {
    for (final paper in [Paper.a4, Paper.a3, Paper.a1]) {
      for (final portrait in [false, true]) {
        final s = buildSheet(
          _sample(),
          SheetInfo(paper: paper, portrait: portrait, firm: 'Al-Noor Surveys', title: 'Plot 42'),
        );
        final p = s.bounds;
        bool on(double e, double n) =>
            e >= p.minE - 1e-6 && e <= p.maxE + 1e-6 && n >= p.minN - 1e-6 && n <= p.maxN + 1e-6;
        for (final i in s.items) {
          final pts = switch (i) {
            SheetPolyline(:final points) => points,
            SheetText(:final at) => [at],
            SheetSolid(:final corners) => corners,
            SheetSymbol(:final at) => [at],
          };
          for (final v in pts) {
            expect(on(v.e, v.n), isTrue, reason: '$paper portrait=$portrait $i at $v');
          }
        }
      }
    }
  });

  test('grid every 50 m at 1:500, every 100 m at 1:1000, with labels', () {
    final s = buildSheet(_sample(), const SheetInfo());
    expect(s.gridInterval, 50);
    expect(_texts(s), containsAll(['E 436250', 'N 3487400']));
    expect(buildSheet(_sample(1000), const SheetInfo()).gridInterval, 100);
  });

  test('the title block, legend, scale bar and north arrow', () {
    final s = buildSheet(
      _sample(),
      const SheetInfo(
        firm: 'Al-Noor Surveys',
        title: 'Topographic survey of plot 42',
        surveyedBy: 'Asif',
        date: '15-11-2026',
        drawingNo: 'AD-042',
      ),
    );
    final t = _texts(s).toList();
    expect(
      t,
      containsAll([
        'Al-Noor Surveys',
        'Topographic survey of plot 42',
        'Asif',
        '15-11-2026',
        'AD-042',
        '1:500  (A3)',
        'LEGEND',
        'N',
      ]),
    );
    expect(t, containsAll(['SCALE 1:500', '0', '12.5', '25 m']));
    // one legend row per code used (9 line codes… as drawn) and the level sample
    for (final name in ['Road edge', 'Building', 'Wall', 'Gate', 'Tree', 'Manhole', 'Electric pole', 'Level (m)']) {
      expect(t, contains(name));
    }
    expect(s.items.whereType<SheetSolid>().length, greaterThanOrEqualTo(3)); // bar segments and the arrow
  });

  test('a long legend is cut short with a count', () {
    final lib = CodeLibrary.defaults();
    final codes = lib.all.where((c) => c.kind == CodeKind.point).toList();
    final pts = [
      for (var i = 0; i < codes.length; i++)
        SurveyPoint(id: '$i', e: 1000.0 + i * 5, n: 2000, z: 10, code: codes[i].code),
    ];
    final d = buildDrawing(pts, lib, const DraftOptions());
    final s = buildSheet(d, const SheetInfo(paper: Paper.a4, portrait: true));
    final more = _texts(s).where((t) => t.startsWith('…and '));
    expect(more.length, lessThanOrEqualTo(1));
  });

  test('sheet info round-trips, and auto paper is kept', () {
    const i = SheetInfo(firm: 'F', title: 'T', paper: Paper.a1, portrait: true, inDxf: false);
    final back = SheetInfo.fromJson(jsonDecode(jsonEncode(i.toJson())));
    expect(back.firm, 'F');
    expect(back.paper, Paper.a1);
    expect(back.portrait, isTrue);
    expect(back.inDxf, isFalse);
    expect(SheetInfo.fromJson(const SheetInfo().toJson()).paper, isNull);
  });

  test('the DXF has the sheet: its layers, aligned and turned text, solids', () {
    final d = _sample();
    final dxf = writeDxf(d, sheet: buildSheet(d, const SheetInfo(firm: 'Al-Noor Surveys')));
    for (final l in SheetLayers.all) {
      expect(dxf, contains('\r\n${l.name}\r\n'));
    }
    expect(dxf, contains('SOLID'));
    expect(dxf, contains(' 72\r\n1\r\n')); // centred text
    expect(dxf, contains(' 50\r\n90.0\r\n')); // the N labels, turned
    expect(dxf, contains('Al-Noor Surveys'));
    expect(writeDxf(d), isNot(contains('SHEET_FRAME')));
  });

  test('the PDF is one page of the paper, at scale', () async {
    final d = _sample();
    ByteData font(String f) => ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());
    final bytes = await writePdf(
      d,
      buildSheet(d, const SheetInfo(title: 'Plot 42')),
      PdfFonts(font('Inter_400Regular.ttf'), font('Inter_700Bold.ttf')),
      title: 'Plot 42',
    );
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF'));
    expect(RegExp(r'/MediaBox ?\[0 0 1190\.55\d* 841\.88\d*\]').hasMatch(text), isTrue, reason: 'A3 in points');
    expect(RegExp(r'/Type ?/Page(?!s)').allMatches(text).length, 1);
  });
}
