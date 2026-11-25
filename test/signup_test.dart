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

  Future<void> fillDetails(WidgetTester tester) async {
    await tester.enterText(input('signup_first_name_input'), 'Ada');
    await tester.enterText(input('signup_last_name_input'), 'Lovelace');
    await tester.enterText(input('signup_email_input'), 'ada@example.com');
    await tester.tap(byId('signup_send_button'));
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

    await tester.tap(byId('signup_cancel_button'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupDialog), findsNothing);

    // Still gated: the composer opens it again.
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SignupDialog), findsOneWidget);
  });

  testWidgets('name + email, then the code, signs the visitor up', (
    tester,
  ) async {
    await pumpChat(tester);
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await fillDetails(tester);
    expect(auth.sent.single, {
      'email': 'ada@example.com',
      'firstName': 'Ada',
      'lastName': 'Lovelace',
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
    // The vendor chat opens right after sign-up.
    expect(chatApi.connected, ['V1']);

    // The chat now takes taps.
    await tester.tap(find.text('Book a demo'));
    await settle(tester);
    expect(find.byType(SignupDialog), findsNothing);
    expect(lead.state.selectedMenuId, 'book_demo');
  });

  testWidgets('a failed send stays on the details step with an error', (
    tester,
  ) async {
    await pumpChat(tester);
    auth.sendResult = const SendUserCodeResult(
      status: SendUserCodeStatus.nouser,
    );
    await tester.tap(find.text('Book a demo'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await fillDetails(tester);
    expect(find.text('Sign up to chat'), findsOneWidget);
    expect(find.textContaining("couldn't send the code"), findsOneWidget);
  });

  testWidgets('a saved session skips the popup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuthService(signedInUser: EmUser.fromJson({'id': 'u1'}));
    signup = SignupController(auth);
    await signup.init();
    expect(signup.state.isSignedIn, isTrue);
  });
}
