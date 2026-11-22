import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'src/account/account.dart';
import 'src/account/api.dart';
import 'src/app.dart';
import 'src/state/app_state.dart';
import 'src/state/files.dart';
import 'src/state/store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(
    AutoDraftApp(
      state: AppState(store),
      files: DialogFileIo(),
      account: Account(Api(base: defaultApiBase(), client: http.Client()), store),
      checkForUpdates: true,
      dropFiles: true,
      signinCode: signinCodeFrom(args),
    ),
  );
}

/// The code after `--signin-code=`, when the Survey Toolkit opened it
String? signinCodeFrom(List<String> args) {
  for (final a in args) {
    if (a.startsWith('--signin-code=')) return a.substring('--signin-code='.length);
  }
  return null;
}
