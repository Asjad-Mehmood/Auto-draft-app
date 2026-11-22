import 'package:auto_draft/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> _desktop(WidgetTester t) async {
  t.view.physicalSize = const Size(1360, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('opened from the Survey Toolkit: signed in with its code, no sign-in screen', (t) async {
    await _desktop(t);
    final h = Harness(signedIn: false);
    await t.pumpWidget(h.appWith(signinCode: 'a' * 64));
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsNothing);
    expect(h.account.signedIn, isTrue);
    expect(h.account.api.token, 't3');
    expect(signinCodeFrom(['--signin-code=${'a' * 64}']), 'a' * 64);
    expect(signinCodeFrom(const []), isNull);
  });

  testWidgets('a Toolkit code that has run out: the sign-in shows as before', (t) async {
    await _desktop(t);
    final h = Harness(signedIn: false);
    await t.pumpWidget(h.appWith(signinCode: 'b' * 64));
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsOneWidget);
    expect(h.account.checking, isFalse);
  });

  testWidgets('not signed in: the sign-in comes first, then the app', (t) async {
    await _desktop(t);
    final h = Harness(signedIn: false);
    await t.pumpWidget(h.app);
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsOneWidget);
    expect(find.text('Try the sample survey'), findsNothing);

    await t.enterText(find.byKey(const ValueKey('signin-email')), 'Asif@Example.com');
    await t.enterText(find.byKey(const ValueKey('signin-password')), 'secret-123');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await t.pumpAndSettle();
    expect(find.text('Try the sample survey'), findsOneWidget);
    expect(h.account.user!.name, 'M. Asif');
    // remembered on this PC
    expect(h.store.readJson('account')?['token'], 't1');
    // the email was sent in lower case, and every call names the app
    final login = h.site.requests.firstWhere((r) => r.url.path == '/api/auth/login');
    expect(login.body, contains('"asif@example.com"'));
    expect(login.headers['X-App-Name'], 'auto-draft');
    expect(login.headers['X-App-Platform'], 'windows');
  });

  testWidgets('an email to confirm: the code, then the app', (t) async {
    await _desktop(t);
    final h = Harness(signedIn: false);
    h.site.loginOk = false;
    await t.pumpWidget(h.app);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('signin-email')), 'asif@example.com');
    await t.enterText(find.byKey(const ValueKey('signin-password')), 'secret-123');
    await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await t.pumpAndSettle();
    expect(find.textContaining('We sent a 6-digit code to a***@example.com'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('signin-code')), '123456');
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(h.account.signedIn, isTrue);
    expect(find.text('Try the sample survey'), findsOneWidget);
  });

  testWidgets('remembered: opens at once, the website is asked, and sign out goes back', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    await t.pumpAndSettle();
    expect(find.text('Try the sample survey'), findsOneWidget);
    expect(
      h.site.requests.any((r) => r.url.path == '/api/auth/me' && r.headers['Authorization'] == 'Bearer t0'),
      isTrue,
    );

    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('asif@example.com'), findsNothing); // the name is shown
    expect(find.text('M. Asif'), findsOneWidget);
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(find.text('Your Excel to KML account'), findsOneWidget);
    expect(h.store.readJson('account'), isNull);
  });

  testWidgets('a saved DXF is reported: name, size and counts only', (t) async {
    await _desktop(t);
    final h = Harness();
    await t.pumpWidget(h.app);
    await t.pumpAndSettle();
    await t.tap(find.text('Try the sample survey'));
    await t.pumpAndSettle();
    await t.tap(find.text('Draw it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save DXF'));
    await t.pumpAndSettle();
    final r = h.site.reports.single;
    expect(r['action'], 'export');
    expect(r['title'], 'Saved DXF');
    expect(r['exportFormat'], 'DXF');
    expect(r['fileName'], 'sample-survey.dxf');
    expect(r['pointsCount'], 67);
    expect(r['linesCount'], 9);
    expect(r['fileSize'], h.files.saved['sample-survey.dxf']!.length);
    // nothing of the survey itself
    expect(r.keys.toSet(), {
      'action',
      'title',
      'fileName',
      'fileSize',
      'pointsCount',
      'linesCount',
      'exportFormat',
      'status',
    });
  });

  testWidgets('a token remembered without its account: the website is asked, then the app opens', (t) async {
    await _desktop(t);
    final h = Harness(signedIn: false);
    h.store.writeJson('account', {'token': 'kept'});
    final fresh = Harness(store: h.store, signedIn: false);
    expect(fresh.account.checking, isTrue);
    await t.pumpWidget(fresh.app);
    await t.pumpAndSettle();
    expect(fresh.account.signedIn, isTrue);
    expect(find.text('Try the sample survey'), findsOneWidget);
  });
}
