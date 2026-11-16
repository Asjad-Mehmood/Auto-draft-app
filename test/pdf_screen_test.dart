// PDF to drawing in the app: open a PDF printed from CAD, see it redrawn, save the DXF.
// With SHOTS_DIR set, also a picture of the screen for the docs.
import 'dart:io';
import 'dart:ui' as ui;

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
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
    await _font('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  testWidgets('a PDF drawing: redrawn with its scale, layers and dimensions, saved as a DXF', (t) async {
    const size = Size(1360, 860);
    t.view.physicalSize = size * (_dir == null ? 1 : 2);
    t.view.devicePixelRatio = _dir == null ? 1 : 2;
    addTearDown(t.view.reset);
    final h = Harness();
    h.files.toOpen.add(('site-plan.pdf', File('test/fixtures/pdf/cad-plot.pdf').readAsBytesSync()));
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: h.app));
    await t.pumpAndSettle();

    await t.tap(find.text('Draft a PDF drawing'));
    await t.pumpAndSettle();
    expect(find.text('PDF drawing · site-plan.pdf'), findsOneWidget);
    expect(find.text('Drawn in metres at 1:200'), findsOneWidget);
    expect(find.text('From its dimensions (1:200)'), findsOneWidget);
    expect(find.text('1 dimension'), findsOneWidget);
    expect(find.text('2 hatches'), findsOneWidget);
    expect(find.text('3 circles'), findsOneWidget);
    expect(find.text('LINES-MAGENTA-DASHED'), findsOneWidget);
    expect(find.text('DIMENSIONS'), findsOneWidget);

    if (_dir != null) {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/17-pdf-drawing.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    // a layer can be hidden in the preview
    await t.tap(find.text('TEXT'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // as printed: millimetres
    await t.tap(find.text('From its dimensions (1:200)'));
    await t.pumpAndSettle();
    await t.tap(find.text('As printed (millimetres)').last);
    await t.pumpAndSettle();
    expect(find.text('Drawn in millimetres, as printed'), findsOneWidget);

    await t.tap(find.text('Save DXF'));
    await t.pumpAndSettle();
    final dxf = String.fromCharCodes(h.files.saved['site-plan.dxf']!);
    expect(dxf, contains('AC1015'));
    expect(dxf, contains('DIMENSION'));
    expect(find.textContaining('Saved C:'), findsOneWidget);
    await t.pumpAndSettle();
    expect(h.site.reports.single['title'], 'Saved DXF from a PDF drawing');
  });

  testWidgets('a file that is not a PDF says why', (t) async {
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final h = Harness();
    h.files.queue('notes.pdf', 'just some text');
    await t.pumpWidget(h.app);
    await t.pumpAndSettle();
    await t.tap(find.text('Draft a PDF drawing'));
    await t.pumpAndSettle();
    expect(find.text("This isn't a PDF file."), findsOneWidget);
  });
}
