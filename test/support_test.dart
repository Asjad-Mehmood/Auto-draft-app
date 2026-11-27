import 'package:auto_draft/src/brand.dart';
import 'package:auto_draft/src/support/app_info.dart';
import 'package:auto_draft/src/support/crash_log.dart';
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
  tearDown(() => CrashLog.last.value = null);

  testWidgets('Help on the bar: what is new, the guide, shortcuts, report a problem, licences', (t) async {
    await _desktop(t);
    await t.pumpWidget(Harness().app);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('help')));
    await t.pumpAndSettle();
    expect(find.text('Version $appVersion · exceltokml.com'), findsOneWidget);
    for (final s in ["What's new", 'User guide', 'Keyboard shortcuts', 'Report a problem', 'Open-source licences']) {
      expect(find.text(s), findsOneWidget);
    }
    await t.tap(find.text('Keyboard shortcuts'));
    await t.pumpAndSettle();
    expect(find.text('Ctrl+O'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    await t.pumpAndSettle();
    await t.tap(find.text('Open-source licences'));
    await t.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('Report a problem: the contact form with the program and version', () {
    final u = Uri.parse(appInfo.reportUrl);
    expect(u.path, '/contact');
    expect(u.queryParameters, containsPair('program', 'auto-draft'));
    expect(u.queryParameters, containsPair('version', appVersion));
  });

  testWidgets('an error shows a notice with Report a problem', (t) async {
    await _desktop(t);
    await t.pumpWidget(Harness().app);
    await t.pumpAndSettle();
    CrashLog.record(const FormatException('bad GSI line'), StackTrace.current);
    await t.pump();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('crash notice')), findsOneWidget);
    expect(find.textContaining('bad GSI line'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('crash notice')), findsNothing);
  });
}
