// Pictures of Auto Draft's screens with its real fonts, for the docs and to see them without
// Windows. Only when SHOTS_DIR is set:  SHOTS_DIR=/tmp/shots flutter test test/shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:auto_draft/src/ui/drawing_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final _dir = Platform.environment['SHOTS_DIR'];

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    await _font('Inter', [
      for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold'])
        'assets/fonts/Inter_$w.ttf',
    ]);
    await _font('JetBrainsMono', [
      'assets/fonts/JetBrainsMono_500Medium.ttf',
      'assets/fonts/JetBrainsMono_700Bold.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
    await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  testWidgets('screens', (t) async {
    if (_dir == null) return;
    debugDisableShadows = false;
    const size = Size(1360, 860);
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final h = Harness();
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: h.app));
    await t.pumpAndSettle();

    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    // the images inside the app need a real frame to decode
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await shot('1-start');

    await t.tap(find.text('Try the sample survey'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await shot('2-columns');

    await t.tap(find.text('Draw it'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await shot('3-drawing');

    // zoom in on the plot: the + button twice, then move the drawing a little
    for (var i = 0; i < 2; i++) {
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
    }
    await t.drag(find.byType(DrawingView), const Offset(240, 180));
    await shot('4-zoomed');

    await t.tap(find.text('Codes'));
    await shot('5-codes');

    await t.tap(find.text('1:500'));
    await shot('6-settings');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    // a survey with mistakes: the problem list, one picked
    h.files.queue('job-42.csv', surveyWithMistakes);
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Problems'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Code XX').first);
    await shot('7-problems');

    // phase 2: add the unknown code from its problem
    await t.tap(find.text('Add XX to the code list'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('code-name')), 'Boundary pillar');
    await t.pumpAndSettle();
    await shot('8-code-editor');
    await t.tap(find.text('Add code'));
    await t.pumpAndSettle();

    // a point clicked on the drawing: its card
    h.state.showPoint(h.state.points[7]);
    await t.pumpAndSettle();
    h.state.pick(7);
    await shot('9-picked-point');

    // the More menu
    h.state.setCode(6, 'TR NEEM');
    await t.pumpAndSettle();
    t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).hideCurrentSnackBar();
    await t.tap(find.byTooltip('More'));
    await shot('10-more-menu');
    await t.tapAt(const Offset(5, 400));
    await t.pumpAndSettle();

    // phase 3: the sample on its sheet, with the title block filled in
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Close this survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Don\'t save'));
    await t.pumpAndSettle();
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Sheet and title block: paper, firm, title, date'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('sheet-firm')), 'Al-Noor Surveys');
    await t.enterText(find.byKey(const ValueKey('sheet-title')), 'Topographic survey of plot 42, Model Town');
    await t.enterText(find.byKey(const ValueKey('sheet-surveyedBy')), 'M. Asif');
    await t.enterText(find.byKey(const ValueKey('sheet-drawingNo')), 'AD-042');
    await t.pumpAndSettle();
    await shot('11-sheet-dialog');
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    await shot('12-sheet');

    // phase 4: a Leica GSI file, measured from a station
    h.files.toOpen.add(('job.gsi', File('test/fixtures/sample-obs.gsi').readAsBytesSync()));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await shot('13-gsi');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save KML (Google Earth)'));
    await shot('14-kml');
    debugDisableShadows = true; // as the test framework expects it back
  });
}
