import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_draft/src/account/account.dart';
import 'package:auto_draft/src/account/api.dart';
import 'package:auto_draft/src/app.dart';
import 'package:auto_draft/src/state/app_state.dart';
import 'package:auto_draft/src/state/files.dart';
import 'package:auto_draft/src/state/store.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Files to "open" are queued; "saved" files are kept
class FakeFiles implements FileIo {
  final toOpen = <(String, Uint8List)>[];
  final saved = <String, List<int>>{};

  void queue(String name, String text) => toOpen.add((name, Uint8List.fromList(utf8.encode(text))));

  @override
  Future<(String, Uint8List)?> open({required String label, required List<String> extensions}) async =>
      toOpen.isEmpty ? null : toOpen.removeAt(0);

  @override
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
    required List<int> bytes,
  }) async {
    saved[suggestedName] = bytes;
    return 'C:\\Users\\surveyor\\Documents\\$suggestedName';
  }
}

/// The website, as the app sees it: a signed-in account; every request kept to look at
class FakeSite {
  final requests = <http.Request>[];

  /// What /api/auth/login answers (null: the email still needs its code)
  bool loginOk = true;

  static const user = {'id': 'u1', 'email': 'asif@example.com', 'name': 'M. Asif'};

  late final client = MockClient((req) async {
    requests.add(req);
    String json(Object o) => jsonEncode(o);
    return switch (req.url.path) {
      '/api/auth/me' => http.Response(json({'user': user}), 200),
      '/api/auth/login' =>
        loginOk
            ? http.Response(json({'user': user, 'token': 't1'}), 200)
            : http.Response(
                json({
                  'error': 'Confirm your email',
                  'verifyRequired': true,
                  'challenge': 'c1',
                  'sentTo': 'a***@example.com',
                }),
                403,
              ),
      '/api/auth/verify-email' => http.Response(json({'user': user, 'token': 't2'}), 200),
      '/api/auth/logout' => http.Response('{}', 200),
      '/api/user/activity' => http.Response('{}', 201),
      _ => http.Response(json({'error': 'Not found'}), 404),
    };
  });

  /// The activity reports sent, as JSON
  List<Map<String, Object?>> get reports => [
    for (final r in requests)
      if (r.url.path == '/api/user/activity') jsonDecode(r.body) as Map<String, Object?>,
  ];
}

class Harness {
  /// [signedIn]: the account is remembered on this PC (the app opens straight away)
  Harness({Store? store, bool signedIn = true}) : this._(store ?? Store.memory(), signedIn);

  Harness._(this.store, bool signedIn) : state = AppState(store) {
    if (signedIn && store.readJson('account') == null) {
      store.writeJson('account', {'token': 't0', 'user': FakeSite.user});
    }
    account = Account(Api(base: 'https://www.exceltokml.com', client: site.client), store);
  }

  final Store store;
  final AppState state;
  final files = FakeFiles();
  final site = FakeSite();
  late final Account account;
  // a PDF drawing is drafted directly, not in the background (tests run on fake time)
  Widget get app => AutoDraftApp(state: state, files: files, account: account, pdfRunner: (work) async => work());
}

/// A survey with mistakes in it, for the problem list
const surveyWithMistakes = '''Point,Easting,Northing,Level,Code
1,436200,3487400,214.60,RE1
2,436220,3487400,214.56,RE1
3,436240,3487400,214.52,RE1
4,436400,3487400,214.40,RE1
5,436260,3487392.7,214.30,RE2
6,436280,3487392.7,214.26,RE2
7,436210,3487410,214.10,TR
8,436230,3487412,214.15,XX
9,436250,3487415,214.12,FN1
10,436222,3487405,0,SP
''';
