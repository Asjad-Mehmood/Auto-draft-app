import 'dart:io';

import 'package:auto_draft/src/engine/codes.dart';
import 'package:auto_draft/src/engine/sheet.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:auto_draft/src/ui/drawing_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> _desktop(WidgetTester t) async {
  t.view.physicalSize = const Size(1360, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  phase2();
  phase3();
  phase4();
  phase5();
  testWidgets('the sample survey: open, check the columns, draw, save the DXF', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    expect(find.text('From field points to a finished drawing'), findsOneWidget);

    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    expect(find.text('Columns in sample-survey.csv'), findsOneWidget);
    expect(find.text('67 points read.'), findsOneWidget);

    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    expect(find.text('67 points'), findsOneWidget);
    expect(find.text('9 lines'), findsOneWidget);
    expect(find.text('23 symbols'), findsOneWidget);
    expect(find.text('Ready to save'), findsOneWidget);
    expect(find.text('No problems found'), findsOneWidget);

    await t.tap(find.text('Save DXF'));
    await t.pumpAndSettle();
    final dxf = String.fromCharCodes(h.files.saved['sample-survey.dxf']!);
    expect(dxf, startsWith('  0\r\nSECTION'));
    expect(dxf, contains('AC1009'));
    expect(dxf.trimRight(), endsWith('EOF'));
    expect(find.textContaining('Saved C:'), findsOneWidget);
  });

  testWidgets('mistakes are listed; fixing a code redraws', (t) async {
    await _desktop(t);
    final h = Harness();
    h.files.queue('job-42.csv', surveyWithMistakes);
    await t.pumpWidget(h.app);
    await t.tap(find.text('Open a survey file'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();

    expect(find.textContaining('Code XX isn\'t in the code list'), findsOneWidget);
    expect(find.textContaining('Fence FN1 has only one point'), findsOneWidget);
    expect(find.textContaining('jumps 160.0 m'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('at level 0.000'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('at level 0.000'), findsOneWidget);
    expect(find.textContaining('things to check'), findsOneWidget);

    // a problem shows its place on the drawing
    await t.scrollUntilVisible(find.textContaining('Code XX'), -200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.textContaining('Code XX').first);
    await t.pumpAndSettle();
    expect(h.state.focus.value!.pointIds, ['8']);

    // correct point 8's code from the points list
    await t.tap(find.text('Points'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '8');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Change the code of point 8'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'TR');
    await t.tap(find.text('Redraw'));
    await t.pumpAndSettle();
    expect(h.state.drawing!.problems.any((p) => p.title.contains('XX')), isFalse);
    expect(h.state.drawing!.symbols.where((s) => s.symbol == 'AD_TREE').length, 2);
  });

  testWidgets('a file that isn\'t a survey says why', (t) async {
    await _desktop(t);
    final h = Harness();
    h.files.queue('old.xls', 'x');
    await t.pumpWidget(h.app);
    await t.tap(find.text('Open a survey file'));
    await t.pumpAndSettle();
    expect(find.textContaining('Old Excel files (.xls) can\'t be read'), findsOneWidget);
    expect(h.state.drawing, isNull);
  });

  testWidgets('settings change the drawing and are remembered', (t) async {
    await _desktop(t);
    final store = Store.memory();
    final h = Harness(store: store);
    h.files.queue('a.csv', surveyWithMistakes);
    await t.pumpWidget(h.app);
    await t.tap(find.text('Open a survey file'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();

    await t.tap(find.text('1:500'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('opt-scale')));
    await t.pumpAndSettle();
    await t.tap(find.text('1:1000').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Write point numbers'));
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(find.text('1:1000'), findsOneWidget);
    expect(h.state.drawing!.options.pointNumbers, isTrue);
    expect(Harness(store: store).state.options.scale, 1000);
  });

  testWidgets('layers can be hidden in the preview', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Layers'));
    await t.pumpAndSettle();
    await t.tap(find.text('ROAD_EDGE'));
    await t.pumpAndSettle();
    expect(h.state.hiddenLayers, {'ROAD_EDGE'});
    await t.tap(find.text('ROAD_EDGE'));
    await t.pumpAndSettle();
    expect(h.state.hiddenLayers, isEmpty);
  });

  testWidgets('a code list can be saved and loaded', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Codes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Codes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save this list'));
    await t.pumpAndSettle();
    final saved = String.fromCharCodes(h.files.saved['auto-draft-codes.json']!);
    expect(saved, contains('"format": "auto-draft-codes"'));

    h.files.queue('team.json', saved.replaceFirst('"name": "Tree"', '"name": "Darakht"'));
    await t.tap(find.text('Load a code list'));
    await t.pumpAndSettle();
    expect(h.state.library['TR']!.name, 'Darakht');
    expect(find.textContaining('codes loaded from team.json'), findsOneWidget);
  });
}

Future<Harness> _withMistakes(WidgetTester t) async {
  await _desktop(t);
  final h = Harness();
  h.files.queue('job-42.csv', surveyWithMistakes);
  await t.pumpWidget(h.app);
  await t.tap(find.text('Open a survey file'));
  await t.pumpAndSettle();
  await t.tap(find.text('Draw it'));
  await t.pumpAndSettle();
  return h;
}

void phase2() {
  testWidgets('an unknown code is added to the list from its problem, and undone', (t) async {
    final h = await _withMistakes(t);
    await t.tap(find.text('Add XX to the code list'));
    await t.pumpAndSettle();
    expect(find.text('A new code'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'XX'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('code-name')), 'Boundary pillar');
    await t.pumpAndSettle();
    expect(find.text('layer BOUNDARY_PILLAR', findRichText: true), findsNothing); // shown in the preview line
    await t.tap(find.text('Add code'));
    await t.pumpAndSettle();
    expect(h.state.library['XX']!.layer, 'BOUNDARY_PILLAR');
    expect(find.textContaining('Code XX isn\'t in the code list'), findsNothing);

    await t.tap(find.byTooltip('Undo: add code XX (Ctrl+Z)'));
    await t.pumpAndSettle();
    expect(h.state.library['XX'], isNull);
    await t.tap(find.byTooltip('Redo: add code XX (Ctrl+Y)'));
    await t.pumpAndSettle();
    expect(h.state.library['XX'], isNotNull);
  });

  testWidgets('a code is changed on every point from its problem; Ctrl+Z undoes it', (t) async {
    final h = await _withMistakes(t);
    await t.tap(find.text('Change it on every point'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('replace-to')), 'tr');
    await t.pumpAndSettle();
    expect(find.text('✓ in the code list'), findsOneWidget);
    await t.tap(find.text('Change all'));
    await t.pumpAndSettle();
    expect(h.state.points[7].code, 'TR');
    expect(find.textContaining('XX changed to TR on 1 point'), findsOneWidget);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(h.state.points[7].code, 'XX');
  });

  testWidgets('the code editor refuses a code in use or a control word', (t) async {
    final h = await _withMistakes(t);
    await t.ensureVisible(find.text('Codes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Codes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add a code'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('code-code')), 'tr');
    await t.enterText(find.byKey(const ValueKey('code-name')), 'Another tree');
    await t.pumpAndSettle();
    expect(find.text('TR is already Tree'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('code-code')), 'cls');
    await t.pumpAndSettle();
    expect(find.textContaining('CLS is a control word'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('code-code')), 'PIL');
    await t.pumpAndSettle();
    await t.tap(find.text('Line: joins its points'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add code'));
    await t.pumpAndSettle();
    expect(h.state.library['PIL']!.kind, CodeKind.line);
    expect(h.state.library['PIL']!.layer, 'ANOTHER_TREE');

    // change an existing one, then remove it (the "added" message out of the way first)
    t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).hideCurrentSnackBar();
    await t.pumpAndSettle();
    final codesList = find.ancestor(of: find.text('Load a code list'), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.text('Another tree'), 300, scrollable: codesList);
    await t.ensureVisible(find.text('Another tree'));
    await t.pumpAndSettle();
    await t.tap(find.text('Another tree'));
    await t.pumpAndSettle();
    expect(find.text('Code PIL'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(h.state.library['PIL'], isNull);
  });

  testWidgets('a point clicked on the drawing shows its card; its code is changed there', (t) async {
    final h = await _withMistakes(t);
    // ask the drawing to show point 7 (the tree), then click on it
    h.state.showPoint(h.state.points[6]);
    await t.pumpAndSettle();
    h.state.pick(null);
    await t.pumpAndSettle();
    final view = t.getRect(find.byType(DrawingView));
    await t.tapAt(view.center);
    await t.pump(const Duration(milliseconds: 400)); // past the double-click wait
    await t.pumpAndSettle();
    expect(h.state.picked, 6);
    expect(find.text('Point 7'), findsOneWidget);
    await t.tap(find.text('Change code'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('point-code')), 'TR NEEM');
    await t.tap(find.text('Redraw'));
    await t.pumpAndSettle();
    expect(h.state.points[6].code, 'TR NEEM');
    expect(find.textContaining('was TR'), findsOneWidget);

    // clicking empty space clears the pick
    await t.tapAt(view.topLeft + const Offset(30, 30));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(h.state.picked, isNull);
  });

  testWidgets('closing with corrected codes offers to save the points', (t) async {
    final h = await _withMistakes(t);
    h.state.setCode(7, 'TR');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('With 1 corrected code'), findsOneWidget);
    await t.tap(find.text('Close this survey'));
    await t.pumpAndSettle();
    expect(find.text('1 corrected code not saved'), findsOneWidget);
    await t.tap(find.text('Save points…'));
    await t.pumpAndSettle();
    final csv = String.fromCharCodes(h.files.saved['job-42-corrected.csv']!);
    expect(csv, contains('8,436230.0000,3487412.0000,214.1500,TR'));
    expect(h.state.drawing, isNull);
  });

  testWidgets('closing without changes asks nothing', (t) async {
    final h = await _withMistakes(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Close this survey'));
    await t.pumpAndSettle();
    expect(h.state.drawing, isNull);
    expect(find.text('From field points to a finished drawing'), findsOneWidget);
  });
}

void phase3() {
  testWidgets('the sheet: title block filled in, a paper too small, fixed in one click, PDF saved', (t) async {
    final h = await _withMistakes(t);
    // the smallest paper that fits, on the bar: a 200 m survey at 1:500 needs A2
    final paper = h.state.sheet!.paper;
    expect(paper, Paper.a2);
    expect(find.text('A2'), findsOneWidget);
    await t.tap(find.text('A2'));
    await t.pumpAndSettle();
    expect(find.text('Sheet and title block'), findsOneWidget);
    expect(find.textContaining('Fits on A2'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('sheet-firm')), 'Al-Noor Surveys');
    await t.enterText(find.byKey(const ValueKey('sheet-title')), 'Job 42');
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(h.state.sheetInfo.firm, 'Al-Noor Surveys');
    expect(h.state.sheet!.items.whereType<SheetText>().map((x) => x.text), contains('Al-Noor Surveys'));
    expect(h.state.dxf(), contains('SHEET_FRAME'));

    // A4 chosen: it doesn't fit
    h.state.setSheetInfo(h.state.sheetInfo.copyWith(paper: () => Paper.a4));
    await t.pumpAndSettle();
    expect(find.textContaining('doesn\'t fit on A4'), findsOneWidget);
    expect(find.textContaining('Doesn\'t fit A4'), findsOneWidget); // status bar
    await t.tap(find.text('Smallest paper that fits'));
    await t.pumpAndSettle();
    expect(h.state.sheet!.fits, isTrue);
    expect(h.state.sheet!.paper.index, greaterThan(Paper.a4.index));

    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save PDF'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    final pdf = h.files.saved['job-42.pdf']!;
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(find.textContaining('Print it at 100 %'), findsOneWidget);
  });

  testWidgets('the sheet can be left out of the DXF', (t) async {
    final h = await _withMistakes(t);
    await t.tap(find.byTooltip('Sheet and title block: paper, firm, title, date'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Show the sheet on screen and in the DXF'));
    await t.pumpAndSettle();
    await t.tap(find.text('Show the sheet on screen and in the DXF'));
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(h.state.showSheet, isFalse);
    expect(h.state.dxf(), isNot(contains('SHEET_FRAME')));
  });
}

void phase4() {
  testWidgets('a Leica GSI file opens with what was read, and draws', (t) async {
    await _desktop(t);
    final h = Harness();
    h.files.toOpen.add(('job.gsi', File('test/fixtures/sample-obs.gsi').readAsBytesSync()));
    await t.pumpWidget(h.app);
    await t.tap(find.text('Open a survey file'));
    await t.pumpAndSettle();
    expect(find.text('Leica GSI-16 file: 11 worked out from the measurements and the station.'), findsOneWidget);
    expect(find.text('11 points read.'), findsOneWidget);
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    expect(h.state.points.length, 11);
    expect(h.state.drawing!.lines.where((l) => l.feature.code == 'RE').length, 2); // RE1 and RE2
  });

  testWidgets('saved for Google Earth in the zone chosen, which is remembered', (t) async {
    final store = Store.memory();
    await _desktop(t);
    final h = Harness(store: store);
    await t.pumpWidget(h.app);
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save KML (Google Earth)'));
    await t.pumpAndSettle();
    expect(find.text('Save for Google Earth'), findsOneWidget);
    await t.tap(find.text('Save KML'));
    await t.pumpAndSettle();
    final kml = String.fromCharCodes(h.files.saved['sample-survey.kml']!);
    expect(kml, contains('74.32803456,31.51973908,0'));
    expect(find.textContaining('Open it in Google Earth'), findsOneWidget);

    h.state.kml(zone: 42, north: true);
    expect(Harness(store: store).state.kmlZone, 42);
  });

  testWidgets('an instrument file with nothing usable says why', (t) async {
    await _desktop(t);
    final h = Harness();
    final lines = File('test/fixtures/sample-obs.gsi').readAsLinesSync().skip(1).join('\n');
    h.files.queue('nostation.gsi', lines);
    await t.pumpWidget(h.app);
    await t.tap(find.text('Open a survey file'));
    await t.pumpAndSettle();
    expect(find.textContaining('No points could be read from this Leica GSI-16 file'), findsOneWidget);
  });
}

void phase5() {
  testWidgets('contours switched on in the settings, then the triangles', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.text('1:500'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('opt-contours')));
    await t.tap(find.byKey(const ValueKey('opt-contours')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Show the triangles (TIN)'));
    await t.tap(find.text('Show the triangles (TIN)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    final d = h.state.drawing!;
    expect(d.contours, isNotEmpty);
    expect(d.options.showTin, isTrue);
    expect(h.state.dxf(), contains('CONTOUR_MINOR'));
    // the legend has them
    expect(h.state.sheet!.items.whereType<SheetText>().map((x) => x.text), contains('Contour, every 0.1 m'));
  });
}
