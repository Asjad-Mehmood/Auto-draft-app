// The app: theme, the window, and the update check on Windows.
import 'package:flutter/material.dart';

import 'brand.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'state/files.dart';
import 'ui/theme.dart';
import 'update/updater_io.dart';

class AutoDraftApp extends StatefulWidget {
  const AutoDraftApp({super.key, required this.state, required this.files, this.checkForUpdates = false});
  final AppState state;
  final FileIo files;
  final bool checkForUpdates;

  @override
  State<AutoDraftApp> createState() => _AutoDraftAppState();
}

class _AutoDraftAppState extends State<AutoDraftApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (widget.checkForUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _navigator.currentContext;
        if (c != null) checkForUpdate(c);
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: HomeScreen(state: widget.state, files: widget.files),
  );
}
