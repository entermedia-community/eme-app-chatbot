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

final signupControllerProvider =
    StateNotifierProvider<SignupController, SignupState>((ref) {
      final controller = SignupController(ref.watch(authServiceProvider));
      unawaited(controller.init());
      return controller;
    });

/// Signs the visitor up (or in, if the email already has an account) with an
/// emailed one-time code: `sendusercode.json` with first/last name, then
/// `token.json` `grant_type=otp`. The server creates the user when the code
/// is redeemed.
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

  /// Emails a sign-up code. Returns an error message, or null when sent.
  Future<String?> sendCode({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final result = await _auth.sendUserCode(
      email: email,
      firstName: firstName,
      lastName: lastName,
    );
    if (result.isSuccess) return null;
    // With a name given the server never answers "nouser"; the SDK reports a
    // failed request that way, so treat anything but ok as not sent.
    final message = result.errorMessage;
    return message != null && message.isNotEmpty
        ? message
        : "We couldn't send the code. Check your connection and try again.";
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
