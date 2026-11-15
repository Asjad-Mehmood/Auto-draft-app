import 'dart:io';

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/dxf.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/engine/point.dart';
import 'package:flutter_test/flutter_test.dart';

/// The group code / value pairs of a DXF file
List<(int, String)> _pairs(String dxf) {
  final lines = dxf.split('\r\n');
  return [for (var i = 0; i + 1 < lines.length; i += 2) (int.parse(lines[i].trim()), lines[i + 1])];
}

void main() {
  Drawing sample({DraftOptions options = const DraftOptions()}) {
    final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
    return buildDrawing(readPoints(t, guessColumns(t)).points, CodeLibrary.defaults(), options);
  }

  test('the sample survey draws without problems', () {
    final d = sample();
    expect(d.problems, isEmpty);
    expect(d.lines.length, 9); // RE1 RE2 CL DR1 FN1 WL1 GT1 BLD1 BLD2
    expect(d.symbols.length, 23);
    expect(d.lines.where((l) => l.closed).length, 2);
  });

  test('a well-formed R12 file: sections, tables, blocks and entities in order', () {
    final dxf = writeDxf(sample());
    final p = _pairs(dxf);
    expect(p.first, (0, 'SECTION'));
    expect(p.last, (0, 'EOF'));
    final sections = [
      for (var i = 0; i < p.length - 1; i++)
        if (p[i] == (0, 'SECTION')) p[i + 1].$2,
    ];
    expect(sections, ['HEADER', 'TABLES', 'BLOCKS', 'ENTITIES']);
    expect(p.where((x) => x == (0, 'SECTION')).length, p.where((x) => x == (0, 'ENDSEC')).length);
    expect(dxf, contains('AC1009'));
    // every POLYLINE ends with a SEQEND
    expect(p.where((x) => x == (0, 'POLYLINE')).length, p.where((x) => x == (0, 'SEQEND')).length);
    // only plain ASCII
    expect(dxf.runes.every((r) => r < 128), isTrue);
  });

  test('every layer and block that is used is defined', () {
    final d = sample();
    final p = _pairs(writeDxf(d));
    final layers = <String>{}, blocks = <String>{}, usedLayers = <String>{}, usedBlocks = <String>{};
    var section = '';
    for (var i = 0; i < p.length; i++) {
      if (p[i] == (0, 'SECTION')) section = p[i + 1].$2;
      if (p[i] == (0, 'LAYER')) layers.add(p[i + 1].$2);
      if (p[i] == (0, 'BLOCK')) blocks.add(p.skip(i).firstWhere((x) => x.$1 == 2).$2);
      if (section == 'ENTITIES' && p[i].$1 == 8) usedLayers.add(p[i].$2);
      if (section == 'ENTITIES' && p[i] == (0, 'INSERT')) usedBlocks.add(p.skip(i).firstWhere((x) => x.$1 == 2).$2);
    }
    expect(layers.containsAll(usedLayers), isTrue, reason: '${usedLayers.difference(layers)}');
    expect(blocks, usedBlocks);
  });

  test('numbers: real coordinates to 0.1 mm, always with a decimal point', () {
    final d = buildDrawing(
      const [SurveyPoint(id: '1', e: 436200.12345, n: 3487400, z: 214.6, code: 'TR')],
      CodeLibrary.defaults(),
      const DraftOptions(),
    );
    final dxf = writeDxf(d);
    expect(dxf, contains('436200.1235'));
    expect(dxf, contains('3487400.0'));
  });

  test('flat lines by default, 3D polylines with levels when asked', () {
    final flat = _pairs(writeDxf(sample()));
    final i = flat.indexOf((0, 'POLYLINE'), flat.indexOf((2, 'ENTITIES')));
    expect(flat.skip(i).firstWhere((x) => x.$1 == 70).$2, '0');
    final threeD = _pairs(writeDxf(sample(options: const DraftOptions(lines3d: true))));
    final j = threeD.indexOf((0, 'POLYLINE'), threeD.indexOf((2, 'ENTITIES')));
    expect(int.parse(threeD.skip(j).firstWhere((x) => x.$1 == 70).$2) & 8, 8);
  });

  test('text outside ASCII is escaped, line breaks removed', () {
    final d = buildDrawing(
      const [SurveyPoint(id: 'نقطہ\n1', e: 0, n: 0, z: 1, code: 'TR')],
      CodeLibrary.defaults(),
      const DraftOptions(pointNumbers: true),
    );
    final dxf = writeDxf(d);
    expect(dxf, contains(r'\U+0646'));
    expect(dxf.runes.every((r) => r < 128), isTrue);
  });

  test('an empty survey still makes a valid file', () {
    final dxf = writeDxf(buildDrawing(const [], CodeLibrary.defaults(), const DraftOptions()));
    expect(_pairs(dxf).last, (0, 'EOF'));
  });
}
