import 'dart:io';

import 'package:auto_draft/src/engine/import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV with a header', () {
    final t = readText(
      'Point,Easting,Northing,Level,Code\n1,436200.0,3487400.0,214.6,RE1 ST\n2,436220,3487400,214.56,RE1\n',
    );
    expect(t.delimiter, ',');
    final m = guessColumns(t);
    expect(m, const ColumnMap(headerRows: 1));
    final r = readPoints(t, m);
    expect(r.points.length, 2);
    expect(r.points.first.code, 'RE1 ST');
    expect(r.points.first.row, 2);
    expect(r.points[1].z, 214.56);
  });

  test('header names in another order (N, E, RL, Description)', () {
    final t = readText('Stn;Northing;Easting;RL;Description\nA;3487400;436200;214.6;TR\n');
    expect(t.delimiter, ';');
    final m = guessColumns(t);
    expect((m.id, m.n, m.e, m.z, m.code), (0, 1, 2, 3, 4));
    expect(readPoints(t, m).points.single.e, 436200);
  });

  test('no header, tab separated, P E N Z D', () {
    final t = readText('1\t436200\t3487400\t214.6\tRE1\n2\t436220\t3487400\t214.5\tRE1\n');
    expect(t.delimiter, '\t');
    expect(guessColumns(t), const ColumnMap());
  });

  test('no header, P N E Z D: the northing is found by its size', () {
    final t = readText('1,3487400.1,436200.2,214.6,TR\n2,3487410.1,436210.2,214.5,TR\n');
    final m = guessColumns(t);
    expect((m.e, m.n), (2, 1));
    expect(readPoints(t, m).points.first.e, 436200.2);
  });

  test('space separated with a text point name and no level', () {
    final t = readText('STN1   436200.0  3487400.0  TBM\nSTN2   436210.0  3487400.0  TR\n');
    expect(t.delimiter, ' ');
    final m = guessColumns(t);
    expect((m.id, m.e, m.n, m.z, m.code), (0, 1, 2, -1, 3));
    final r = readPoints(t, m);
    expect(r.points.first.id, 'STN1');
    expect(r.points.first.z, isNull);
  });

  test('quoted cells may hold the delimiter', () {
    final t = readText('1,10,20,5,"RE1, ST"\n2,11,20,5,"RE1"\n3,12,20,5,RE1\n');
    expect(t.rows.first, ['1', '10', '20', '5', 'RE1, ST']);
  });

  test('a byte order mark, blank lines and a title line', () {
    final t = readText('﻿Job 42 Lahore\n\nP,E,N,Z,Code\n1,10,20,5,TR\n');
    final m = guessColumns(t);
    expect(m.headerRows, 2);
    expect(readPoints(t, m).points.single.id, '1');
  });

  test('bad lines are skipped and named', () {
    final t = readText('P,E,N,Z,Code\n1,10,20,5,TR\n2,x,20,5,TR\n3,10,20,abc,TR\n');
    final r = readPoints(t, guessColumns(t));
    expect(r.points.length, 1);
    expect(r.skipped.map((s) => s.$1), [3, 4]);
    expect(r.skipped.last.$2, contains('abc'));
  });

  test('a point with no number is numbered by its place', () {
    final t = readText('E,N,Z\n10,20,5\n11,20,5\n');
    final m = guessColumns(t);
    expect(m.id, -1);
    expect(readPoints(t, m).points.map((p) => p.id), ['1', '2']);
  });

  test('Excel: the first sheet with data', () {
    final book = Excel.createExcel();
    final s = book['Sheet1'];
    s.appendRow([
      TextCellValue('Point'),
      TextCellValue('Easting'),
      TextCellValue('Northing'),
      TextCellValue('Level'),
      TextCellValue('Code'),
    ]);
    s.appendRow([
      const IntCellValue(1),
      const DoubleCellValue(436200.125),
      const DoubleCellValue(3487400.5),
      const DoubleCellValue(214.6),
      TextCellValue('TR'),
    ]);
    s.appendRow([
      const IntCellValue(2),
      const IntCellValue(436210),
      const IntCellValue(3487400),
      const DoubleCellValue(214.55),
      TextCellValue('MH'),
    ]);
    final t = readExcel(book.encode()!);
    final r = readPoints(t, guessColumns(t));
    expect(r.points.length, 2);
    expect(r.points.first.e, 436200.125);
    expect(r.points.last.code, 'MH');
  });

  test('the sample survey reads completely', () {
    final t = readText(File('assets/samples/sample-survey.csv').readAsStringSync());
    final r = readPoints(t, guessColumns(t));
    expect(r.skipped, isEmpty);
    expect(r.points.length, 67);
  });
}
