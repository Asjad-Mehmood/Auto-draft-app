// The app: theme, the sign-in (an SurveyX Digital account), the window, and the update check.
import 'package:flutter/material.dart';

import 'account/account.dart';
import 'account/toolkit_code.dart';
import 'brand.dart';
import 'screens/home_screen.dart';
import 'screens/pdf_draft_screen.dart';
import 'screens/sign_in_screen.dart';
import 'state/app_state.dart';
import 'state/files.dart';
import 'support/app_info.dart';
import 'support/crash_log.dart';
import 'ui/theme.dart';
import 'update/updater_io.dart';

class AutoDraftApp extends StatefulWidget {
  const AutoDraftApp({
    super.key,
    required this.state,
    required this.files,
    required this.account,
    this.checkForUpdates = false,
    this.dropFiles = false,
    this.pdfRunner = backgroundDraft,
    this.signinCode,
  });

  /// The one-use sign-in code the Survey Toolkit started it with (`--signin-code=`)
  final String? signinCode;
  final AppState state;
  final FileIo files;
  final Account account;
  final bool checkForUpdates;

  /// Drag-and-drop of files onto the window (the real program; tests have no drop support)
  final bool dropFiles;

  /// How a PDF drawing is drafted: in the background in the program, directly in the tests
  final DraftRunner pdfRunner;

  @override
  State<AutoDraftApp> createState() => _AutoDraftAppState();
}

class _AutoDraftAppState extends State<AutoDraftApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    final code = widget.signinCode;
    code == null
        ? widget.account.signInWithToolkitOrRestore(() => askToolkitForCode('auto-draft'))
        : widget.account.signInFromToolkit(code);
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
    builder: (context, child) => CrashNotice(onReport: appInfo.report, child: child!),
    home: ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) => widget.account.signedIn
          ? HomeScreen(
              state: widget.state,
              files: widget.files,
              account: widget.account,
              dropFiles: widget.dropFiles,
              pdfRunner: widget.pdfRunner,
            )
          : SignInScreen(account: widget.account),
    ),
  );
}
