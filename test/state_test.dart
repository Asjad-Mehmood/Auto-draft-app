import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/import.dart';
import 'package:auto_draft/src/state/app_state.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

AppState _opened([Store? store]) {
  final s = AppState(store ?? Store.memory());
  final t = readText(surveyWithMistakes);
  s.open(OpenedFile('job.csv', t, guessColumns(t)), guessColumns(t));
  return s;
}

void main() {
  test('a code change is undone and redone', () {
    final s = _opened();
    expect(s.canUndo, isFalse);
    s.setCode(7, 'TR');
    expect(s.points[7].code, 'TR');
    expect(s.changedCodes, 1);
    expect(s.fileCodeOf(7), 'XX');
    expect(s.undoLabel, 'code of point 8');
    s.undo();
    expect(s.points[7].code, 'XX');
    expect(s.changedCodes, 0);
    expect(s.canRedo, isTrue);
    s.redo();
    expect(s.points[7].code, 'TR');
    expect(s.drawing!.problems.any((p) => p.title.contains('XX')), isFalse);
  });

  test('the same code again is not a step', () {
    final s = _opened();
    s.setCode(0, 'RE1');
    expect(s.canUndo, isFalse);
  });

  test('a new change clears redo', () {
    final s = _opened()
      ..setCode(0, 'KB1')
      ..undo();
    expect(s.canRedo, isTrue);
    s.setCode(1, 'KB1');
    expect(s.canRedo, isFalse);
  });

  test('replace a code on every point keeps the words after it', () {
    final s = _opened();
    s.setCode(8, 'XX ST');
    final n = s.replaceCode('xx', 'TR');
    expect(n, 2);
    expect(s.points[7].code, 'TR');
    expect(s.points[8].code, 'TR ST');
    expect(s.undoLabel, 'xx → TR on 2 points');
    s.undo();
    expect(s.points[7].code, 'XX');
    expect(s.replaceCode('NOPE', 'TR'), 0);
  });

  test('adding, changing and removing codes; the list is remembered and undone', () {
    final store = Store.memory();
    final s = _opened(store);
    s.saveCode(
      const FeatureCode(code: 'XX', name: 'Boundary pillar', kind: CodeKind.point, layer: 'PILLAR', symbol: 'AD_SPOT'),
    );
    expect(s.library['XX']!.name, 'Boundary pillar');
    expect(s.drawing!.problems.any((p) => p.title.contains('XX')), isFalse);
    expect(AppState(store).library['XX'], isNotNull);

    // renaming XX to PIL replaces it
    s.saveCode(
      const FeatureCode(code: 'PIL', name: 'Boundary pillar', kind: CodeKind.point, layer: 'PILLAR', symbol: 'AD_SPOT'),
      replacing: 'XX',
    );
    expect(s.library['XX'], isNull);
    expect(s.library['PIL'], isNotNull);

    s.deleteCode('TR');
    expect(s.library['TR'], isNull);
    s.undo();
    expect(s.library['TR'], isNotNull);
    s.undo();
    s.undo();
    expect(s.library['XX'], isNull);
    expect(AppState(store).library['XX'], isNull); // the undone list is what is remembered
  });

  test('back to the file\'s codes', () {
    final s = _opened()
      ..setCode(0, 'KB1')
      ..setCode(1, 'KB1');
    expect(s.changedCodes, 2);
    s.revertCodes();
    expect(s.changedCodes, 0);
    s.undo();
    expect(s.changedCodes, 2);
  });

  test('opening a file clears the history', () {
    final s = _opened()..setCode(0, 'KB1');
    final t = readText(surveyWithMistakes);
    s.open(OpenedFile('b.csv', t, guessColumns(t)), guessColumns(t));
    expect(s.canUndo, isFalse);
    expect(s.changedCodes, 0);
  });

  test('the history keeps the last 100 steps', () {
    final s = _opened();
    for (var i = 0; i < 130; i++) {
      s.setCode(0, 'RE${i + 2}');
    }
    var n = 0;
    while (s.canUndo) {
      s.undo();
      n++;
    }
    expect(n, 100);
  });

  test('points as CSV, with corrected codes and quoting', () {
    final s = _opened()..setCode(7, 'TR, NEEM');
    final csv = s.pointsCsv();
    final lines = csv.split('\r\n');
    expect(lines.first, 'Point,Easting,Northing,Level,Code');
    expect(lines[1], '1,436200.0000,3487400.0000,214.6000,RE1');
    expect(lines[8], '8,436230.0000,3487412.0000,214.1500,"TR, NEEM"');
    expect(s.csvName, 'job-corrected.csv');
    // and it reads back the same
    final back = readPoints(readText(csv), guessColumns(readText(csv))).points;
    expect(back.map((p) => p.code), s.points.map((p) => p.code));
  });
}
