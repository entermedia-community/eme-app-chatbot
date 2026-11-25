import 'package:eme_app_sdk/eme_app_sdk.dart';

/// Records sign-up calls; [sendResult] / [validCode] decide the outcome.
class FakeAuthService implements IAuthService {
  FakeAuthService({this.signedInUser});

  EmUser? signedInUser;
  SendUserCodeResult sendResult = const SendUserCodeResult(
    status: SendUserCodeStatus.ok,
  );

  /// False: an email sent without a name answers "nouser".
  bool existingUser = true;
  bool allowRegistration = true;
  String validCode = '123456';
  final sent = <Map<String, String?>>[];

  @override
  Future<EmUser?> checkAuthSession() async => signedInUser;

  @override
  Future<SendUserCodeResult> sendUserCode({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    sent.add({'email': email, 'firstName': firstName, 'lastName': lastName});
    if (!existingUser && firstName == null) {
      return SendUserCodeResult(
        status: SendUserCodeStatus.nouser,
        allowGuestRegistration: allowRegistration,
      );
    }
    return sendResult;
  }

  @override
  Future<LoginResult> loginWithCode({
    required String email,
    required String code,
  }) async {
    if (code != validCode) {
      return const LoginResult(
        isSuccess: false,
        errorMessage: 'Invalid or expired verification code',
      );
    }
    final last = sent.last;
    signedInUser = EmUser.fromJson({
      'id': 'u1',
      'email': email,
      'firstname': last['firstName'],
      'lastname': last['lastName'],
    });
    return LoginResult(isSuccess: true, user: signedInUser, token: 't');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
