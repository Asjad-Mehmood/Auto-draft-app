import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'src/account/account.dart';
import 'src/account/api.dart';
import 'src/app.dart';
import 'src/state/app_state.dart';
import 'src/state/files.dart';
import 'src/state/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(
    AutoDraftApp(
      state: AppState(store),
      files: DialogFileIo(),
      account: Account(Api(base: defaultApiBase(), client: http.Client()), store),
      checkForUpdates: true,
      dropFiles: true,
    ),
  );
}
