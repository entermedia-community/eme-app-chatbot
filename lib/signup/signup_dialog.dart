import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'signup_controller.dart';

/// Shows the sign-up popup. Completes with true once the visitor is signed in.
Future<bool> showSignupDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const SignupDialog(),
  );
  return ok ?? false;
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
const _codeLength = 6;
const _resendSeconds = 60;

/// Two steps: name + email, then the code emailed to that address.
class SignupDialog extends ConsumerStatefulWidget {
  const SignupDialog({super.key});

  @override
  ConsumerState<SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends ConsumerState<SignupDialog> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  SignupController get _controller =>
      ref.read(signupControllerProvider.notifier);

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final email = _email.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'Please enter your first and last name.');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await _controller.sendCode(
      firstName: first,
      lastName: last,
      email: email,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _codeSent = true;
        _code.clear();
      }
    });
    if (error == null) _startResendTimer();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < _codeLength) {
      setState(() => _error = 'Please enter the $_codeLength-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await _controller.verifyCode(
      email: _email.text.trim(),
      code: code,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
      _code.clear();
    });
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _codeSent = false;
      _error = null;
      _resendIn = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_codeSent ? 'Check your email' : 'Sign up to chat'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_codeSent) ..._codeStep(theme) else ..._detailsStep(theme),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Semantics(
          identifier: 'signup_cancel_button',
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ),
        Semantics(
          identifier: _codeSent ? 'signup_verify_button' : 'signup_send_button',
          child: FilledButton(
            onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_codeSent ? 'Verify' : 'Send code'),
          ),
        ),
      ],
    );
  }

  List<Widget> _detailsStep(ThemeData theme) => [
    Text(
      "Tell us who you are and we'll email you a code to get started.",
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: Semantics(
            identifier: 'signup_first_name_input',
            child: TextField(
              controller: _firstName,
              autofocus: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              decoration: const InputDecoration(
                labelText: 'First name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            identifier: 'signup_last_name_input',
            child: TextField(
              controller: _lastName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.familyName],
              decoration: const InputDecoration(
                labelText: 'Last name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Semantics(
      identifier: 'signup_email_input',
      child: TextField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.send,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _sendCode(),
        decoration: const InputDecoration(
          labelText: 'Email',
          hintText: 'you@example.com',
          border: OutlineInputBorder(),
        ),
      ),
    ),
  ];

  List<Widget> _codeStep(ThemeData theme) => [
    Text(
      'We sent a $_codeLength-digit code to ${_email.text.trim()}.',
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: 16),
    Semantics(
      identifier: 'signup_code_input',
      child: TextField(
        controller: _code,
        autofocus: true,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: _codeLength,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
        onChanged: (v) {
          if (_error != null) setState(() => _error = null);
          if (v.length == _codeLength) _verify();
        },
        onSubmitted: (_) => _verify(),
        decoration: const InputDecoration(
          hintText: '000000',
          counterText: '',
          border: OutlineInputBorder(),
        ),
      ),
    ),
    const SizedBox(height: 8),
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          identifier: 'signup_change_email_button',
          child: TextButton(
            onPressed: _busy ? null : _changeEmail,
            child: const Text('Change email'),
          ),
        ),
        Semantics(
          identifier: 'signup_resend_button',
          child: TextButton(
            onPressed: _busy || _resendIn > 0 ? null : _sendCode,
            child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend'),
          ),
        ),
      ],
    ),
  ];
}
