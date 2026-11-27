// The SurveyX Digital account in Auto Draft: sign in or create an account (with the 6-digit code the
// website emails), or sign in through the browser (Google and saved passwords work there). Once
// signed in, the account is remembered on this PC and the app opens at once, offline too.
// What is drawn stays on the PC: the website only learns that the app was used (and, when a drawing
// is saved, its name, size and point count, for Admin's activity).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/store.dart';
import 'api.dart';

class AccountUser {
  const AccountUser({required this.id, required this.email, required this.name});
  final String id;
  final String email;
  final String name;

  static AccountUser? from(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final id = j['id'], email = j['email'];
    if (id is! String || email is! String) return null;
    return AccountUser(id: id, email: email.toLowerCase(), name: (j['name'] as String?) ?? '');
  }

  Map<String, Object?> toJson() => {'id': id, 'email': email, 'name': name};
  String get display => name.isNotEmpty ? name : email;
}

/// The website wants the emailed code before the account can be used
class EmailCode {
  const EmailCode(this.challenge, this.sentTo);
  final String challenge;
  final String sentTo;
}

/// A browser sign-in in progress: the code to confirm at [url]
class BrowserSignIn {
  const BrowserSignIn({required this.code, required this.url, required this.poll});
  final String code;
  final String url;
  final String poll;
}

class Account extends ChangeNotifier {
  Account(this.api, this._store) {
    final j = _store.readJson(_key);
    api.token = j?['token'] as String?;
    _user = AccountUser.from(j?['user']);
    // a token but no account remembered: ask the website before showing the sign-in
    checking = _user == null && api.token != null;
  }

  final Api api;
  final Store _store;
  static const _key = 'account';

  /// Still asking the website whether the remembered sign-in is good
  bool checking = false;

  AccountUser? _user;
  AccountUser? get user => _user;
  bool get signedIn => _user != null;

  void _remember() =>
      _store.writeJson(_key, {if (api.token != null) 'token': api.token, if (_user != null) 'user': _user!.toJson()});

  void _signedIn(Map<String, Object?> j) {
    final user = AccountUser.from(j['user']);
    if (user == null) throw ApiError('The website answered without an account. Please try again.');
    if (j['token'] is String) api.token = j['token'] as String;
    _user = user;
    _remember();
    notifyListeners();
  }

  /// Opened some other way than from the Survey Toolkit (a shortcut, the Start menu): not signed
  /// in on this PC yet, it asks [ask] (the Toolkit on this PC) for a one-use code for the Toolkit's
  /// account and signs in with it, so the user signs in once, in the Toolkit. Signed in before,
  /// or no Toolkit to ask: as [restore].
  Future<void> signInWithToolkitOrRestore(Future<String?> Function() ask) async {
    if (_user != null || api.token != null) {
      return restore();
    }
    checking = true;
    notifyListeners();
    final code = await ask();
    if (code != null) return signInFromToolkit(code);
    checking = false;
    notifyListeners();
  }

  /// Opened from the Survey Toolkit: signs in to the Toolkit's account with the one-use code it was
  /// started with. When the code can't be used (too old, offline), it carries on as [restore].
  Future<void> signInFromToolkit(String code) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) return restore();
    checking = true;
    notifyListeners();
    try {
      _signedIn(await api.call('POST', '/api/toolkit/app-code/redeem', {'code': code, 'app': 'auto-draft'}));
      checking = false;
      notifyListeners();
    } on ApiError {
      // as at start: ask about the remembered sign-in, or show the sign-in
      checking = _user == null && api.token != null;
      notifyListeners();
      await restore();
    }
  }

  /// On start: is the remembered sign-in still good? Offline, the remembered account is kept.
  /// The call also tells the website the app was opened (Admin counts its use).
  Future<void> restore() async {
    if (!checking && _user == null) return;
    try {
      final j = await api.call('GET', '/api/auth/me');
      final user = AccountUser.from(j['user']);
      if (user == null) {
        if (_user != null) _forget();
        return;
      }
      _user = user;
      _remember();
      notifyListeners();
    } on ApiError catch (e) {
      if (e.status == 401) _forget();
    } finally {
      if (checking) {
        checking = false;
        notifyListeners();
      }
    }
  }

  /// Signs in; returns the code challenge when the email still has to be confirmed
  Future<EmailCode?> signIn(String email, String password) async {
    try {
      _signedIn(await api.call('POST', '/api/auth/login', {'email': email.trim().toLowerCase(), 'password': password}));
      return null;
    } on ApiError catch (e) {
      if (!e.needsEmailCode) rethrow;
      return EmailCode(e.data['challenge']! as String, (e.data['sentTo'] as String?) ?? 'your email');
    }
  }

  /// Creates the account; the website then emails a code (returned) to confirm it
  Future<EmailCode?> register({
    required String name,
    required String email,
    required String password,
    String? company,
  }) async {
    try {
      _signedIn(
        await api.call('POST', '/api/auth/register', {
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          if (company != null && company.trim().isNotEmpty) 'organization': company.trim(),
        }),
      );
      return null;
    } on ApiError catch (e) {
      if (!e.needsEmailCode) rethrow;
      return EmailCode(e.data['challenge']! as String, (e.data['sentTo'] as String?) ?? 'your email');
    }
  }

  Future<void> confirmEmail(EmailCode c, String code) async =>
      _signedIn(await api.call('POST', '/api/auth/verify-email', {'challenge': c.challenge, 'code': code.trim()}));

  Future<EmailCode> resendCode(EmailCode c) async {
    final j = await api.call('POST', '/api/auth/resend-verify', {'challenge': c.challenge});
    return EmailCode((j['challenge'] as String?) ?? c.challenge, (j['sentTo'] as String?) ?? c.sentTo);
  }

  Future<void> forgotPassword(String email) =>
      api.call('POST', '/api/auth/forgot-password', {'email': email.trim().toLowerCase()});

  /// Starts a sign-in to confirm in the browser (where Google sign-in works)
  Future<BrowserSignIn> startBrowserSignIn() async {
    final j = await api.call('POST', '/api/auth/device/start', {'app': 'Auto Draft'});
    final code = j['code'], poll = j['poll'];
    if (code is! String || poll is! String) throw ApiError('The website could not start a sign-in. Please try again.');
    final url = (j['url'] as String?) ?? '/link';
    return BrowserSignIn(code: code, poll: poll, url: url.startsWith('http') ? url : '${api.base}$url?code=$code');
  }

  /// Asks once whether the browser sign-in was confirmed: true when signed in, false to ask again,
  /// an [ApiError] when the code expired
  Future<bool> checkBrowserSignIn(BrowserSignIn s) async {
    final j = await api.call('POST', '/api/auth/device/poll', {'poll': s.poll});
    if (j['user'] != null) {
      _signedIn(j);
      return true;
    }
    if (j['state'] == 'expired' || j['state'] == 'denied') {
      throw ApiError('The sign-in code ran out. Start again.');
    }
    return false;
  }

  Future<void> signOut() async {
    try {
      await api.call('POST', '/api/auth/logout');
    } on ApiError {
      // signed out on this PC anyway
    }
    _forget();
  }

  /// Tells the website a drawing was saved (Admin → activity). Never stops the save: offline or
  /// refused, it is simply not counted.
  Future<void> report({
    required String title,
    required String format,
    required String fileName,
    required int fileSize,
    required int points,
    required int lines,
  }) async {
    if (!signedIn) return;
    try {
      await api.call('POST', '/api/user/activity', {
        'action': 'export',
        'title': title,
        'fileName': fileName,
        'fileSize': fileSize,
        'pointsCount': points,
        'linesCount': lines,
        'exportFormat': format,
        'status': 'success',
      });
    } on ApiError {
      // not counted
    }
  }

  void _forget() {
    api.token = null;
    _user = null;
    _store.remove(_key);
    notifyListeners();
  }
}
