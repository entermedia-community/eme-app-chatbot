import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/lead/lead_chat_controller.dart';
import 'package:eme_chatbot/lead/lead_store.dart';
import 'package:eme_chatbot/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lead_chat_controller_test.dart' show FakeLeadService, FakeLiveChannel;

void main() {
  testWidgets('renders the questionnaire and answers by tapping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeLeadService();
    final controller = LeadChatController(
      vendorId: 'acme',
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
    await tester.pump();

    expect(find.text('Acme'), findsOneWidget);
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
