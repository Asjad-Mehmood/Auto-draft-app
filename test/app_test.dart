import 'package:auto_draft/src/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> _desktop(WidgetTester t) async {
  t.view.physicalSize = const Size(1360, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
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
    expect(find.textContaining('at level 0.000'), findsOneWidget);
    expect(find.textContaining('things to check'), findsOneWidget);

    // a problem shows its place on the drawing
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
