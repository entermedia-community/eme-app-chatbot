import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/chat/vendor_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_vendor_chat.dart';

void main() {
  late FakeVendorChatApi api;
  late FakeChannelSocket socket;
  late VendorChatController c;

  const meeting = VendorMenuItem(
    id: 'eme_chatbot_request_meeting',
    name: 'Request a Meeting',
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    api = FakeVendorChatApi();
    socket = FakeChannelSocket();
    c = VendorChatController(api: api, socket: socket);
  });

  test('opens the vendor channel and loads its history once', () async {
    api.history = [agentText('h1', 'Earlier reply')];
    await c.open(vendorId: 'V1', userId: 'u1');
    await c.open(vendorId: 'V1', userId: 'u1');

    expect(api.connected, ['V1']);
    expect(socket.connects, ['ch_V1/u1']);
    expect(c.state.channel, 'ch_V1');
    expect(c.state.messages.single.message.text, 'Earlier reply');
    expect(c.state.connecting, isFalse);
  });

  test('history listed newest first is shown oldest first', () async {
    ChatMessage at(String id, String text, int minute) => ChatMessage.fromJson({
      'messageid': id,
      'channel': 'ch_V1',
      'user': 'agent',
      'message': text,
      'date': '2026-01-01T10:0$minute:00Z',
    });
    api.history = [
      at('h3', 'third', 3),
      at('h2', 'second', 2),
      at('h1', 'first', 1),
    ];
    await c.open(vendorId: 'V1', userId: 'u1');

    expect(c.state.messages.map((e) => e.message.text), [
      'first',
      'second',
      'third',
    ]);
    // Placed by load time, in order, not by the server's (2026) dates.
    final times = c.state.messages.map((e) => e.at).toList();
    expect(times[0].isBefore(times[1]), isTrue);
    expect(times[1].isBefore(times[2]), isTrue);
    expect(times[0].year, DateTime.now().year);
  });

  test('a connect failure is shown and can be retried', () async {
    api.connectError = Exception('offline');
    await c.open(vendorId: 'V1', userId: 'u1');
    expect(c.state.channel, isNull);
    expect(c.state.error, contains("couldn't reach the server"));

    api.connectError = null;
    await c.retry();
    expect(c.state.channel, 'ch_V1');
    expect(c.state.error, isNull);
  });

  test('a menu pick runs the scenario confirm step', () async {
    await c.open(vendorId: 'V1', userId: 'u1');
    await c.startScenario(meeting);

    expect(api.scenarios.single, {
      'channel': 'ch_V1',
      'scenario': 'eme_chatbot_request_meeting',
      'function': 'eme_chatbot_request_meeting_confirm',
    });
    expect(c.state.awaitingReply, isTrue);

    socket.push(meetingForm());
    await flush();
    expect(c.state.awaitingReply, isFalse);
    final form = c.state.messages.single.message;
    expect(form.messageRenderType, MessageRenderType.form);
    expect(c.state.isFormOpen(form), isTrue);
  });

  test(
    'ignores other channels, keepalives and the visitor\'s own rows',
    () async {
      await c.open(vendorId: 'V1', userId: 'u1');
      socket.push(agentText('x', 'Elsewhere', channel: 'other'));
      socket.push(
        ChatMessage.fromJson({
          'messageid': 's1',
          'channel': 'ch_V1',
          'user': 'u1',
          'message': 'picked',
          'messagetype': 'system',
        }),
      );
      socket.push(
        ChatMessage.fromJson({'channel': 'ch_V1', 'command': 'keepalive'}),
      );
      await flush();
      expect(c.state.messages, isEmpty);
    },
  );

  test('submitting a form sends its values and locks it', () async {
    await c.open(vendorId: 'V1', userId: 'u1');
    socket.push(meetingForm());
    await flush();
    final form = c.state.messages.single.message;

    await c.submitForm(form, {
      'functionname': 'eme_chatbot_request_meeting_submit',
      'context_meetingtime': '2026-12-03T14:00',
    });

    // The form's message id goes along so the server can keep the values on it.
    expect(api.submitted.single, {
      'channel': 'ch_V1',
      'functionname': 'eme_chatbot_request_meeting_submit',
      'context_meetingtime': '2026-12-03T14:00',
      'formmessageid': form.messageId,
    });
    expect(c.state.isFormOpen(form), isFalse);
    expect(c.state.awaitingReply, isTrue);

    socket.push(agentText('r1', 'Thanks! Your meeting request has been sent.'));
    await flush();
    expect(c.state.awaitingReply, isFalse);
    expect(c.state.messages.last.message.text, contains('sent'));
  });

  test('a failed submit keeps the form open and shows the error', () async {
    await c.open(vendorId: 'V1', userId: 'u1');
    socket.push(meetingForm());
    await flush();
    final form = c.state.messages.single.message;

    api.submitError = Exception('500');
    await c.submitForm(form, {'a': 'b'});
    expect(c.state.isFormOpen(form), isTrue);
    expect(c.state.error, isNotNull);
  });

  test('no reply in time is reported', () async {
    c = VendorChatController(
      api: api,
      socket: socket,
      replyTimeout: const Duration(milliseconds: 10),
    );
    await c.open(vendorId: 'V1', userId: 'u1');
    await c.startScenario(meeting);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.state.awaitingReply, isFalse);
    expect(c.state.error, contains("haven't heard back"));
  });
}
