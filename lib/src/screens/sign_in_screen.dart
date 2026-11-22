// The first screen: Auto Draft is used with a free Excel to KML account, the same as the website,
// Excel to KML, Traverse & Level and Slope Calculator. Once signed in, the account is remembered
// on this PC and the app opens at once, offline too.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account.dart';
import '../account/api.dart';
import '../assets.dart';
import '../brand.dart';
import '../ui/theme.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.navy, BrandColors.navyLight],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      asset('assets/brand/icon-512.png'),
                      width: 80,
                      height: 80,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  appTagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFC9D5EA), fontSize: 15),
                ),
                const SizedBox(height: 22),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: account.checking
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 14),
                                Text('Checking your sign-in…', style: TextStyle(color: Tone.muted)),
                              ],
                            ),
                          )
                        : SignInCard(account: account),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Version $appVersion · $appPublisher',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA9B8D3), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

enum _Step { signIn, register, code, browser }

class SignInCard extends StatefulWidget {
  const SignInCard({super.key, required this.account});
  final Account account;

  @override
  State<SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends State<SignInCard> {
  _Step _step = _Step.signIn;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _company = TextEditingController();
  final _code = TextEditingController();
  EmailCode? _challenge;
  BrowserSignIn? _browser;
  Timer? _poll;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_name, _email, _password, _company, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await work();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _needCode(EmailCode? c) {
    if (c == null) return;
    _challenge = c;
    _code.clear();
    setState(() => _step = _Step.code);
  }

  Future<void> _startBrowser() => _run(() async {
    final s = await widget.account.startBrowserSignIn();
    setState(() {
      _browser = s;
      _step = _Step.browser;
    });
    await launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        if (await widget.account.checkBrowserSignIn(s)) _poll?.cancel();
      } on ApiError catch (e) {
        _poll?.cancel();
        if (mounted) setState(() => _error = e.message);
      }
    });
  });

  Widget _field(TextEditingController c, String label, {bool secret = false, String? hint, Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key,
      controller: c,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onSubmitted: (_) => _submit(),
    ),
  );

  void _submit() {
    if (_busy) return;
    final a = widget.account;
    switch (_step) {
      case _Step.signIn || _Step.register:
        _run(() async {
          final code = _step == _Step.signIn
              ? await a.signIn(_email.text, _password.text)
              : await a.register(
                  name: _name.text,
                  email: _email.text,
                  password: _password.text,
                  company: _company.text,
                );
          _needCode(code);
        });
      case _Step.code:
        _run(() => a.confirmEmail(_challenge!, _code.text));
      case _Step.browser:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final body = switch (_step) {
      _Step.signIn || _Step.register => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_Step>(
            segments: const [
              ButtonSegment(value: _Step.signIn, label: Text('Sign in')),
              ButtonSegment(value: _Step.register, label: Text('Create an account')),
            ],
            selected: {_step},
            onSelectionChanged: (v) => setState(() {
              _step = v.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_step == _Step.register) _field(_name, 'Your name', key: const ValueKey('signin-name')),
          _field(_email, 'Email', hint: 'name@company.com', key: const ValueKey('signin-email')),
          _field(
            _password,
            'Password',
            secret: true,
            hint: _step == _Step.register ? 'At least 8 characters' : null,
            key: const ValueKey('signin-password'),
          ),
          if (_step == _Step.register) _field(_company, 'Company (optional)'),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_step == _Step.signIn ? 'Sign in' : 'Create the account'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _startBrowser,
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('Sign in with the browser (Google)'),
          ),
          if (_step == _Step.signIn)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        if (_email.text.trim().isEmpty) throw ApiError('Type your email first.');
                        await a.forgotPassword(_email.text);
                        setState(
                          () => _info = 'If that email has an account, a link to set a new password is on its way.',
                        );
                      }),
                child: const Text('Forgot the password?'),
              ),
            ),
        ],
      ),
      _Step.code => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'We sent a 6-digit code to ${_challenge?.sentTo}. Type it here to confirm your email. Not there? Look in Spam.',
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 14),
          _field(_code, 'Code', hint: '123456', key: const ValueKey('signin-code')),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Confirm')),
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        _challenge = await a.resendCode(_challenge!);
                        setState(() => _info = 'A new code is on its way to ${_challenge!.sentTo}.');
                      }),
                child: const Text('Send a new code'),
              ),
              TextButton(onPressed: () => setState(() => _step = _Step.signIn), child: const Text('Back')),
            ],
          ),
        ],
      ),
      _Step.browser => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your browser is open at exceltokml.com. Sign in there (Google works), then confirm this code:',
            style: TextStyle(height: 1.45),
          ),
          const SizedBox(height: 14),
          Center(
            child: SelectableText(
              _browser?.code ?? '',
              style: mono.copyWith(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
          const SizedBox(height: 8),
          const Center(
            child: Text('Waiting for the browser…', style: TextStyle(color: Tone.muted)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _browser == null
                    ? null
                    : () => launchUrl(Uri.parse(_browser!.url), mode: LaunchMode.externalApplication),
                child: const Text('Open the browser again'),
              ),
              TextButton(
                onPressed: () {
                  _poll?.cancel();
                  setState(() => _step = _Step.signIn);
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    };

    Widget notice(String text, Color color, IconData icon) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Your Excel to KML account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Sign in with your Excel to KML account, or create one for free. One account works on exceltokml.com '
          'and in all our programs. Opened from the Survey Toolkit, you\'re signed in already.',
          style: TextStyle(color: Tone.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        body,
        if (_error != null) notice(_error!, Tone.error, Icons.error_outline),
        if (_info != null) notice(_info!, Tone.ok, Icons.check_circle_outline),
      ],
    );
  }
}
