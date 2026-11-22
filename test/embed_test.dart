// Auto Drafting inside the Survey Toolkit: the whole program as a widget, signed in with the
// Toolkit's one-use code.
import 'package:auto_draft/auto_draft.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> _desktop(WidgetTester t) async {
  t.view.physicalSize = const Size(1360, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(Widget view) => MaterialApp(home: Scaffold(body: view));

void main() {
  testWidgets('signed in with the Toolkit\'s code: the program, no sign-in screen', (t) async {
    await _desktop(t);
    final site = FakeSite();
    await t.pumpWidget(
      _host(
        AutoDraftView(
          store: Store.memory(),
          client: site.client,
          files: FakeFiles(),
          dropFiles: false,
          signinCode: () async => 'a' * 64,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsNothing);
    expect(find.text('Try the sample survey'), findsOneWidget);
    expect(site.requests.any((r) => r.url.path == '/api/toolkit/app-code/redeem'), isTrue);
  });

  testWidgets('no code from the Toolkit: the sign-in, inside the page', (t) async {
    await _desktop(t);
    await t.pumpWidget(
      _host(AutoDraftView(store: Store.memory(), client: FakeSite().client, files: FakeFiles(), dropFiles: false)),
    );
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsOneWidget);
  });

  testWidgets('the sample survey opens from inside the Toolkit too (its file is under packages/)', (t) async {
    await _desktop(t);
    await t.pumpWidget(
      _host(
        AutoDraftView(
          store: Store.memory(),
          client: FakeSite().client,
          files: FakeFiles(),
          dropFiles: false,
          signinCode: () async => 'a' * 64,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    expect(find.textContaining('sample-survey'), findsWidgets);
  });
}
