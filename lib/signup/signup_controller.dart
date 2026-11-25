import 'dart:async';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SignupStatus {
  /// Looking for a saved session on this device.
  checking,
  signedOut,
  signedIn,
}

class SignupState {
  final SignupStatus status;
  final EmUser? user;

  const SignupState({this.status = SignupStatus.checking, this.user});

  bool get isSignedIn => status == SignupStatus.signedIn;
}

enum CodeOutcome { sent, needsRegistration, failed }

class CodeResult {
  final CodeOutcome outcome;
  final String? error;
  const CodeResult(this.outcome, [this.error]);
}

final signupControllerProvider =
    StateNotifierProvider<SignupController, SignupState>((ref) {
      final controller = SignupController(ref.watch(authServiceProvider));
      unawaited(controller.init());
      return controller;
    });

/// Signs the visitor in with an emailed one-time code (`sendusercode.json`,
/// then `token.json` `grant_type=otp`), like the backoffice app: email first;
/// an unknown email is asked for a name to register, and the server creates
/// the user when the code is redeemed.
///
/// Uses [IAuthService] directly rather than the SDK's `AuthNotifier`, which
/// also signs in to Firebase for push notifications, which the chatbot does
/// not set up.
class SignupController extends StateNotifier<SignupState> {
  SignupController(this._auth) : super(const SignupState());

  final IAuthService _auth;

  Future<void> init() async {
    EmUser? user;
    try {
      user = await _auth.checkAuthSession();
    } catch (_) {
      user = null;
    }
    if (!mounted) return;
    state = user != null
        ? SignupState(status: SignupStatus.signedIn, user: user)
        : const SignupState(status: SignupStatus.signedOut);
  }

  /// Asks the server to email a code. Without names it is a sign-in: an
  /// unknown email answers [CodeOutcome.needsRegistration] when the server
  /// allows new accounts, [CodeOutcome.registrationClosed] when it doesn't.
  /// With names it registers the visitor; the account is created when the
  /// code is redeemed.
  Future<CodeResult> sendCode({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    final result = await _auth.sendUserCode(
      email: email,
      firstName: firstName,
      lastName: lastName,
    );
    if (result.isSuccess) return const CodeResult(CodeOutcome.sent);
    if (result.isNoUser) {
      final registering = (firstName ?? '').trim().isNotEmpty;
      if (!registering && result.allowGuestRegistration) {
        return const CodeResult(CodeOutcome.needsRegistration);
      }
      return CodeResult(
        CodeOutcome.failed,
        registering
            ? "We couldn't create your account. Please try again."
            : 'No account found for this email, and new sign-ups are not '
                  'available.',
      );
    }
    final message = result.errorMessage;
    return CodeResult(
      CodeOutcome.failed,
      message != null && message.isNotEmpty
          ? message
          : "We couldn't send the code. Check your connection and try again.",
    );
  }

  /// Redeems the emailed code. Returns an error message, or null when the
  /// visitor is now signed in.
  Future<String?> verifyCode({
    required String email,
    required String code,
  }) async {
    final result = await _auth.loginWithCode(email: email, code: code);
    if (!result.isSuccess || result.user == null) {
      return result.errorMessage ?? 'Invalid or expired code.';
    }
    if (mounted) {
      state = SignupState(status: SignupStatus.signedIn, user: result.user);
    }
    return null;
  }
}
