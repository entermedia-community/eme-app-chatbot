import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/chat/channel_socket.dart';
import 'package:eme_chatbot/lead/lead_chat_controller.dart';
import 'package:eme_chatbot/lead/lead_store.dart';
import 'package:eme_chatbot/screens/chat_screen.dart';
import 'package:eme_chatbot/signup/signup_controller.dart';
import 'package:eme_chatbot/signup/signup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_service.dart';
import 'fake_vendor_chat.dart';
import 'lead_chat_controller_test.dart' show FakeLeadService, FakeLiveChannel;

void main() {
  late FakeAuthService auth;
  late LeadChatController lead;
  late SignupController signup;
  late FakeVendorChatApi chatApi;

  Finder byId(String id) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.identifier == id,
  );
  Finder input(String id) =>
      find.descendant(of: byId(id), matching: find.byType(TextField));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> pumpChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuthService();
    lead = LeadChatController(
      vendorUrlName: 'VendorOne',
      service: FakeLeadService(),
      live: FakeLiveChannel(),
      store: LeadStore(),
    );
    signup = SignupController(auth);
    chatApi = FakeVendorChatApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leadChatControllerProvider.overrideWith((ref) => lead),
          signupControllerProvider.overrideWith((ref) => signup),
          apiServiceProvider.overrideWithValue(chatApi),
          channelSocketProvider.overrideWithValue(FakeChannelSocket()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.runAsync(lead.init);
    await tester.runAsync(signup.init);
    await tester.pumpAndSettle();
  }

  Future<void> submitEmail(WidgetTester tester) async {
    await tester.enterText(input('signup_email_input'), 'ada@example.com');
    await tester.tap(byId('signup_send_button'));
    await settle(tester);
  }

  Future<void> submitName(WidgetTester tester) async {
    await tester.enterText(input('signup_first_name_input'), 'Ada');
    await tester.enterText(input('signup_last_name_input'), 'Lovelace');
    await tester.tap(byId('signup_register_button'));
    await settle(tester);
  }

  testWidgets('tapping the chat while signed out opens the popup', (
    tester,
  ) async {
    await pumpChat(tester);
    expect(find.byType(SignupDialog), findsNothing);
    // No chat channel before sign-up.
    expect(chatApi.connected, isEmpty);

    // A menu item would normally select; the gate takes the tap instead.
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SignupDialog), findsOneWidget);
    expect(lead.state.selectedMenuId, isNull);

    // No cancel button: tapping outside the dialog dismisses it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SignupDialog), findsNothing);

    // Still gated: the composer opens it again.
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SignupDialog), findsOneWidget);
  });

  testWidgets('an existing account signs in with just email + code', (
    tester,
  ) async {
    await pumpChat(tester);
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to chat'), findsOneWidget);
    expect(input('signup_first_name_input'), findsNothing);
    await submitEmail(tester);
    expect(auth.sent.single, {
      'email': 'ada@example.com',
      'firstName': null,
      'lastName': null,
    });
    expect(find.text('Check your email'), findsOneWidget);

    await tester.enterText(input('signup_code_input'), '999999');
    await settle(tester);
    expect(find.text('Invalid or expired verification code'), findsOneWidget);
    expect(signup.state.isSignedIn, isFalse);

    await tester.enterText(input('signup_code_input'), '123456');
    await settle(tester);
    expect(find.byType(SignupDialog), findsNothing);
    expect(signup.state.isSignedIn, isTrue);
    // The vendor chat opens right after sign-in.
    expect(chatApi.connected, ['V1']);

    // The chat now takes taps.
    await tester.tap(find.text('Book a demo'));
    await settle(tester);
    expect(find.byType(SignupDialog), findsNothing);
    expect(lead.state.selectedMenuId, 'book_demo');
  });

  testWidgets('a new email asks for a name when sign-ups are open', (
    tester,
  ) async {
    await pumpChat(tester);
    auth.existingUser = false;
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await submitEmail(tester);
    expect(find.text('Create your profile'), findsOneWidget);
    // The email is kept, read only.
    expect(
      tester.widget<TextField>(input('signup_email_input')).enabled,
      isFalse,
    );
    expect(find.text('ada@example.com'), findsOneWidget);

    await submitName(tester);
    expect(auth.sent.last, {
      'email': 'ada@example.com',
      'firstName': 'Ada',
      'lastName': 'Lovelace',
    });
    expect(find.text('Check your email'), findsOneWidget);

    await tester.enterText(input('signup_code_input'), '123456');
    await settle(tester);
    expect(find.byType(SignupDialog), findsNothing);
    expect(signup.state.isSignedIn, isTrue);
    expect(signup.state.user?.email, 'ada@example.com');
  });

  testWidgets('a new email is refused when sign-ups are closed', (
    tester,
  ) async {
    await pumpChat(tester);
    auth
      ..existingUser = false
      ..allowRegistration = false;
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await submitEmail(tester);
    expect(find.text('Sign in to chat'), findsOneWidget);
    expect(find.textContaining('No account found'), findsOneWidget);
    expect(input('signup_first_name_input'), findsNothing);
  });

  testWidgets('a failed send stays on the email step with an error', (
    tester,
  ) async {
    await pumpChat(tester);
    auth.sendResult = const SendUserCodeResult(
      status: SendUserCodeStatus.error,
      errorMessage: 'Server unavailable',
    );
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await submitEmail(tester);
    expect(find.text('Sign in to chat'), findsOneWidget);
    expect(find.text('Server unavailable'), findsOneWidget);
  });

  testWidgets('a saved session skips the popup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuthService(signedInUser: EmUser.fromJson({'id': 'u1'}));
    signup = SignupController(auth);
    await signup.init();
    expect(signup.state.isSignedIn, isTrue);
  });
}
