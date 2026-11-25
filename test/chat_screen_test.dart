import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/chat/channel_socket.dart';
import 'package:eme_chatbot/lead/lead_chat_controller.dart';
import 'package:eme_chatbot/lead/lead_store.dart';
import 'package:eme_chatbot/chat/chat_form_card.dart';
import 'package:eme_chatbot/screens/chat_screen.dart';
import 'package:eme_chatbot/signup/signup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_service.dart';
import 'fake_vendor_chat.dart';
import 'lead_chat_controller_test.dart' show FakeLeadService, FakeLiveChannel;

void main() {
  late FakeLeadService service;
  late LeadChatController controller;
  late FakeVendorChatApi chatApi;
  late FakeChannelSocket socket;

  Future<void> pumpChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    chatApi = FakeVendorChatApi();
    socket = FakeChannelSocket();
    service = FakeLeadService();
    controller = LeadChatController(
      vendorUrlName: 'VendorOne',
      service: service,
      live: FakeLiveChannel(),
      store: LeadStore(),
    );
    // These tests cover the chat itself, so the visitor is signed up.
    final signup = SignupController(
      FakeAuthService(signedInUser: EmUser.fromJson({'id': 'u1'})),
    );
    await signup.init();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leadChatControllerProvider.overrideWith((ref) => controller),
          signupControllerProvider.overrideWith((ref) => signup),
          apiServiceProvider.overrideWithValue(chatApi),
          channelSocketProvider.overrideWithValue(socket),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.runAsync(controller.init);
    // The vendor chat opens once the vendor has loaded; let it finish.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the vendor name and menu in the chat', (tester) async {
    await pumpChat(tester);

    expect(find.text('Acme'), findsOneWidget);
    expect(find.text(LeadCopy.menuGreeting('Acme')), findsOneWidget);
    expect(find.text('Answer Questions'), findsOneWidget);
    expect(find.text('Quick answers.'), findsOneWidget);
    expect(find.text('Book a demo'), findsOneWidget);

    await tester.tap(find.text('Book a demo'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(controller.state.selectedMenuId, 'book_demo');
    // The pick shows as the visitor's message and the in-chat menu goes away
    // (the items stay in the + menu).
    expect(find.text('Book a demo'), findsOneWidget);
    expect(find.text('Answer Questions'), findsNothing);
  });

  testWidgets('signing in opens the vendor chat; a pick runs its scenario', (
    tester,
  ) async {
    await pumpChat(tester);
    expect(chatApi.connected, ['V1']);
    expect(socket.connects, ['ch_V1/u1']);

    await tester.tap(find.text('Book a demo'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(chatApi.scenarios.single['function'], 'book_demo_confirm');
    // Waiting for the server's reply.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    socket.push(agentText('r1', 'Book a demo is not implemented yet.'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Book a demo is not implemented yet.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('request a meeting: pick a date and time, add a message', (
    tester,
  ) async {
    await pumpChat(tester);
    socket.push(meetingForm());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Request meeting');
    expect(submit, findsOneWidget);

    // The date and time are required.
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Please fill in Date and time.'), findsOneWidget);
    expect(chatApi.submitted, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'chat_form_form1_context_meetingtime',
        ),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // date picker, today
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // time picker, 10:00
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Message (optional)'),
      'About pricing',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final sent = chatApi.submitted.single;
    expect(sent['channel'], 'ch_V1');
    expect(sent['functionname'], 'eme_chatbot_request_meeting_submit');
    expect(
      sent['context_meetingtime'],
      '${now.year}-${two(now.month)}-${two(now.day)}T10:00',
    );
    expect(sent['context_meetingtimezone'], startsWith('UTC'));
    expect(sent['context_meetingmessage'], 'About pricing');

    // The form id goes along so the server can keep the values on it.
    expect(sent['formmessageid'], 'form1');

    // The server sends the form back submitted: it is replaced by the
    // visitor's "label: value" lines.
    socket.push(
      meetingForm(
        submitted: {
          'context_meetingtimezone': sent['context_meetingtimezone'] as String,
          'context_meetingtime': sent['context_meetingtime'] as String,
          'context_meetingmessage': 'About pricing',
        },
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(ChatFormCard), findsNothing);
    expect(
      find.textContaining('10:00\nMessage (optional): About pricing'),
      findsOneWidget,
    );
    expect(find.textContaining('Date and time: '), findsOneWidget);
  });

  testWidgets('drop-up menu lists the vendor items', (tester) async {
    await pumpChat(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    expect(find.text('Start over'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('Answer Questions'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(controller.state.selectedMenuId, 'entity_chat_questions');
  });

  testWidgets('questionnaire renders and answers by tapping', (tester) async {
    await pumpChat(tester);
    await tester.runAsync(controller.startQuestionnaire);
    await tester.pumpAndSettle();
    expect(find.text(LeadCopy.askName), findsOneWidget);

    Future<void> type(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    await type('Ada');
    await type('ada@example.com');
    await type('CTO');
    await tester.pumpAndSettle();

    expect(find.text('What is your budget?'), findsOneWidget);
    await tester.tap(find.text('10k+'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(service.answers['budget'], 'gt10');
    expect(find.text('Skip'), findsOneWidget);
  });
}
