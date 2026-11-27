// Opened from a shortcut (not from the Survey Toolkit) and not signed in: the Toolkit on this PC
// gives a one-use code for its account.
import 'package:auto_draft/src/account/account.dart';
import 'package:auto_draft/src/account/api.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  Account account(FakeSite site, Store store) =>
      Account(Api(base: 'https://www.surveyxdigital.com', client: site.client), store);

  test('not signed in: the Toolkit gives a code and it signs in', () async {
    final a = account(FakeSite(), Store.memory());
    final asked = <bool>[];
    await a.signInWithToolkitOrRestore(() async {
      asked.add(true);
      return 'a' * 64;
    });
    expect(asked, hasLength(1));
    expect(a.signedIn, isTrue);
    expect(a.checking, isFalse);
  });

  test('no Toolkit to ask (or it is signed out): the sign-in shows, nothing waits', () async {
    final a = account(FakeSite(), Store.memory());
    await a.signInWithToolkitOrRestore(() async => null);
    expect(a.signedIn, isFalse);
    expect(a.checking, isFalse);
  });

  test('signed in on this PC before: the Toolkit isn\'t asked', () async {
    final store = Store.memory()..writeJson('account', {'token': 't0', 'user': FakeSite.user});
    var asked = false;
    final a = account(FakeSite(), store);
    await a.signInWithToolkitOrRestore(() async {
      asked = true;
      return 'a' * 64;
    });
    expect(asked, isFalse);
    expect(a.signedIn, isTrue);
  });
}
