// Auto Drafting inside another Flutter program: the Survey Toolkit shows it as one of its pages.
// The same screens, drawings and settings as the program itself, signed in to the same account
// as the Toolkit (with the one-use code the Toolkit asks the website for). There is no "Look
// for an update": the Toolkit brings new versions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'account/account.dart';
import 'account/api.dart';
import 'assets.dart';
import 'screens/home_screen.dart';
import 'screens/pdf_draft_screen.dart';
import 'screens/sign_in_screen.dart';
import 'state/app_state.dart';
import 'state/files.dart';
import 'state/store.dart';
import 'ui/theme.dart';

class AutoDraftView extends StatefulWidget {
  const AutoDraftView({super.key, this.signinCode, this.store, this.files, this.client, this.dropFiles = true});

  /// Asks the host for a one-use sign-in code for this account (null: none, the sign-in shows)
  final Future<String?> Function()? signinCode;

  /// For tests: a store, files and a website of their own
  final Store? store;
  final FileIo? files;
  final http.Client? client;

  /// Files dropped on the page open in it (tests have no drop support)
  final bool dropFiles;

  @override
  State<AutoDraftView> createState() => _AutoDraftViewState();
}

class _AutoDraftViewState extends State<AutoDraftView> {
  ({AppState state, Account account})? _ready;

  @override
  void initState() {
    super.initState();
    assetPackage = 'auto_draft';
    _start();
  }

  Future<void> _start() async {
    final store = widget.store ?? await Store.open();
    final account = Account(Api(base: defaultApiBase(), client: widget.client ?? http.Client()), store);
    // not signed in on this PC: the Toolkit's account, asked for before the page shows so the
    // sign-in doesn't flash up first
    final code = account.signedIn ? null : await widget.signinCode?.call();
    if (!mounted) return;
    unawaited(code == null ? account.restore() : account.signInFromToolkit(code));
    setState(() => _ready = (state: AppState(store), account: account));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready == null) return const Center(child: CircularProgressIndicator());
    // its own colours, and its own pages (a PDF drawing opens over it, not over the whole window)
    return Theme(
      data: appTheme(),
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => ListenableBuilder(
            listenable: ready.account,
            builder: (context, _) => ready.account.signedIn
                ? HomeScreen(
                    state: ready.state,
                    files: widget.files ?? DialogFileIo(),
                    account: ready.account,
                    dropFiles: widget.dropFiles,
                    pdfRunner: backgroundDraft,
                  )
                : SignInScreen(account: ready.account),
          ),
        ),
      ),
    );
  }
}
