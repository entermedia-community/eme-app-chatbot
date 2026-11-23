import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/lead/lead_chat_controller.dart';
import 'package:eme_chatbot/lead/lead_store.dart';
import 'package:eme_chatbot/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lead_chat_controller_test.dart' show FakeLeadService, FakeLiveChannel;

void main() {
  late FakeLeadService service;
  late LeadChatController controller;

  Future<void> pumpChat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    service = FakeLeadService();
    controller = LeadChatController(
      vendorUrlName: 'VendorOne',
      service: service,
      live: FakeLiveChannel(),
      store: LeadStore(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leadChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.runAsync(controller.init);
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
    // The pick shows as the visitor's message; the menu stays available.
    expect(find.text('Book a demo'), findsNWidgets(2));
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
