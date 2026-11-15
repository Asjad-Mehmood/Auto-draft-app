import 'dart:io';

import 'package:auto_draft/src/engine/builder.dart';
import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/drawing.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/engine/instruments.dart';
import 'package:auto_draft/src/engine/kml.dart';
import 'package:auto_draft/src/engine/point.dart';
import 'package:auto_draft/src/engine/utm.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sample survey's points, the truth the instrument files were made from
final _truth = () {
  final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
  return {for (final p in readPoints(t, guessColumns(t)).points) p.id: p};
}();

List<SurveyPoint> _read(String file) {
  final r = readInstrument(file, File('test/fixtures/$file').readAsStringSync())!;
  return readPoints(r.table, const ColumnMap()).points;
}

void _matches(List<SurveyPoint> pts, {double tol = 0.001, double de = 0, double dn = 0, int count = 12}) {
  expect(pts.length, count);
  for (final p in pts) {
    final t = _truth[p.id]!;
    expect(p.e + de, closeTo(t.e, tol), reason: 'E of ${p.id}');
    expect(p.n + dn, closeTo(t.n, tol), reason: 'N of ${p.id}');
    expect(p.z, closeTo(t.z!, tol), reason: 'Z of ${p.id}');
  }
}

void main() {
  test('Leica GSI-16 coordinates and codes, ST in its own word', () {
    final r = readInstrument('sample-16.gsi', File('test/fixtures/sample-16.gsi').readAsStringSync())!;
    expect(r.format, 'Leica GSI-16');
    expect(r.notes.single, '12 points with coordinates');
    final pts = readPoints(r.table, const ColumnMap()).points;
    _matches(pts, tol: 1e-4);
    expect(pts[0].code, 'TBM');
    expect(pts[1].code, 'RE1 ST');
  });

  test('Leica GSI-8 in millimetres, and a code block before a point', () {
    final pts = _read('sample-8.gsi');
    _matches(pts, de: 436000, dn: 3487000, count: 6);
    expect(pts[2].code, 'RE1'); // from the code block
    expect(pts[1].code, 'RE1 ST');
  });

  test('Leica GSI measurements are worked out from the station', () {
    final r = readInstrument('sample-obs.gsi', File('test/fixtures/sample-obs.gsi').readAsStringSync())!;
    expect(r.notes, ['11 worked out from the measurements and the station']);
    final pts = readPoints(r.table, const ColumnMap()).points;
    _matches(pts, tol: 0.002, count: 11);
    expect(pts.first.code, 'RE1 ST');
  });

  test('measurements without a station are skipped and said so', () {
    final text = File('test/fixtures/sample-obs.gsi').readAsLinesSync().skip(1).join('\n');
    final r = readInstrument('x.gsi', text)!;
    expect(r.table.rows, isEmpty);
    expect(r.notes.single, contains('11 measurements skipped'));
  });

  test('a GSI file is known by its content too', () {
    final r = readInstrument('export.txt', File('test/fixtures/sample-16.gsi').readAsStringSync());
    expect(r?.format, 'Leica GSI-16');
  });

  test('Sokkia SDR33 and SDR2x coordinate records', () {
    final r = readInstrument('sample.sdr', File('test/fixtures/sample.sdr').readAsStringSync())!;
    expect(r.format, 'Sokkia SDR');
    expect(r.notes.last, contains('1 measurement record (09) not used'));
    final pts = readPoints(r.table, const ColumnMap()).points;
    _matches(pts, tol: 1e-4);
    expect(pts[1].code, 'RE1 ST');
    _matches(_read('sample-short.sdr'), de: 436000, dn: 3487000, count: 5);
  });

  test('Nikon RAW: the station point, then side shots from it', () {
    final r = readInstrument('sample.raw', File('test/fixtures/sample.raw').readAsStringSync())!;
    expect(r.format, 'Nikon RAW');
    expect(r.notes, ['1 point with coordinates', '11 side shots worked out from the station']);
    final pts = readPoints(r.table, const ColumnMap()).points;
    // angles to the whole second: within 5 mm at these distances
    _matches(pts, tol: 0.005);
    expect(pts[1].code, 'RE1 ST');
  });

  test('other files are not instrument files', () {
    expect(readInstrument('survey.csv', 'P,E,N,Z,Code\n1,2,3,4,TR\n'), isNull);
  });

  test('UTM ↔ latitude / longitude against a reference (pyproj)', () {
    // Lahore and Islamabad in zone 43, Karachi in 42
    var (e, n) = latLonToUtm(31.5204, 74.3587, 43);
    expect(e, closeTo(439112.0270, 0.001));
    expect(n, closeTo(3487455.8094, 0.001));
    (e, n) = latLonToUtm(33.6844, 73.0479, 43);
    expect(e, closeTo(319050.2697, 0.001));
    expect(n, closeTo(3728873.7980, 0.001));
    (e, n) = latLonToUtm(24.8607, 67.0011, 42);
    expect(e, closeTo(298038.0837, 0.001));
    expect(n, closeTo(2751004.9043, 0.001));
    final (lat, lon) = utmToLatLon(436200, 3487400, 43);
    expect(lat, closeTo(31.519739078, 1e-8));
    expect(lon, closeTo(74.328034558, 1e-8));
    // there and back
    final (la, lo) = utmToLatLon(581218.1955, 3973231.1410, 43);
    expect(la, closeTo(35.9, 1e-8));
    expect(lo, closeTo(75.9, 1e-8));
  });

  test('KML: lines, point features and all points, in latitude / longitude', () {
    final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
    final d = buildDrawing(readPoints(t, guessColumns(t)).points, CodeLibrary.defaults(), const DraftOptions());
    final kml = writeKml(d, zone: 43, title: 'Plot 42 & road');
    expect(kml, startsWith('<?xml'));
    expect(kml, contains('<name>Plot 42 &amp; road</name>'));
    expect(RegExp('<LineString>').allMatches(kml).length, 9);
    expect(kml, contains('<Folder><name>Road edge</name>'));
    expect(kml, contains('<Folder><name>Tree</name>'));
    expect(kml, contains('All survey points (67)'));
    // point 2 (436200, 3487400) as longitude,latitude
    expect(kml, contains('74.32803456,31.51973908,0'));
    // a closed building returns to its first corner
    final bld = RegExp(
      r'<name>BLD1</name>.*?<coordinates>(.*?)</coordinates>',
      dotAll: true,
    ).firstMatch(kml)!.group(1)!.split(' ');
    expect(bld.first, bld.last);
    expect(bld.length, 5);
  });
}
