import 'dart:async';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/lead/lead_chat_controller.dart';
import 'package:eme_chatbot/lead/lead_chat_state.dart';
import 'package:eme_chatbot/lead/lead_store.dart';
import 'package:eme_chatbot/lead/live_channel.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = LeadSession(
  leadId: 'L1',
  userId: 'visitor-1',
  token: 'tok',
  channel: 'ch1',
);

LeadQuestionnaire _questionnaire() => LeadQuestionnaire.fromJson({
  'id': 'Q1',
  'vendorid': 'acme',
  'vendorname': 'Acme',
  'greeting': 'Hi! Welcome to Acme.',
  'consenttext': 'Can we contact you about this?',
  'questions': [
    {'id': 'job', 'prompt': 'What is your job title?', 'required': true},
    {'id': 'source', 'type': 'hidden', 'value': 'website'},
    {
      'id': 'budget',
      'prompt': 'What is your budget?',
      'type': 'radio',
      'required': true,
      'options': [
        {'value': 'lt10', 'label': '< 10k'},
        {'value': 'gt10', 'label': '10k+'},
      ],
    },
    {
      'id': 'features',
      'prompt': 'Which features interest you?',
      'type': 'checkbox',
      'options': [
        {'value': 'a', 'label': 'A'},
        {'value': 'b', 'label': 'B'},
      ],
    },
  ],
});

class FakeLeadService implements ILeadService {
  final answers = <String, dynamic>{};
  Object? fetchError;
  Object? answerError;
  bool? consent;
  String? startedName;
  String? startedEmail;
  List<ChatMessage> history = [];

  @override
  Future<LeadQuestionnaire> fetchQuestionnaire(String vendorId) async {
    if (fetchError != null) throw fetchError!;
    return _questionnaire();
  }

  @override
  Future<LeadSession> startLead({
    required String vendorId,
    required String questionnaireId,
    required String name,
    required String email,
  }) async {
    startedName = name;
    startedEmail = email;
    return _session;
  }

  @override
  Future<void> saveAnswer(
    LeadSession session, {
    required String questionId,
    required dynamic value,
  }) async {
    if (answerError != null) throw answerError!;
    answers[questionId] = value;
  }

  @override
  Future<String?> completeLead(
    LeadSession session, {
    required bool consent,
  }) async {
    this.consent = consent;
    return 'Thanks from Acme!';
  }

  @override
  Future<List<ChatMessage>> fetchMessages(LeadSession session) async => history;
}

class FakeLiveChannel implements LiveChannel {
  final controller = StreamController<ChatMessage>.broadcast();
  final sent = <String>[];
  bool connected = false;
  bool online = true;

  @override
  Future<void> connect(LeadSession session) async => connected = online;
  @override
  bool get isConnected => connected;
  @override
  Stream<ChatMessage> get messages => controller.stream;
  @override
  void send(LeadSession session, String text) => sent.add(text);
  @override
  void disconnect() => connected = false;
}

ChatMessage _msg(String id, String user, String text, {String? type}) =>
    ChatMessage(
      messageId: id,
      channel: 'ch1',
      userId: user,
      message: text,
      messageType: type ?? 'message',
      createdAt: DateTime(2026, 11, 24),
    );

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeLeadService service;
  late FakeLiveChannel live;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = FakeLeadService();
    live = FakeLiveChannel();
  });

  LeadChatController make({String vendorId = 'acme'}) => LeadChatController(
    vendorId: vendorId,
    service: service,
    live: live,
    store: LeadStore(),
  );

  List<String> texts(LeadChatController c) =>
      c.state.entries.map((e) => e.text).toList();

  test('walks name → email → questions → consent → chat', () async {
    final c = make();
    await c.init();
    expect(c.state.step, LeadStep.askName);
    expect(texts(c), ['Hi! Welcome to Acme.', LeadCopy.askName]);

    c.submitText('Ada Lovelace');
    expect(c.state.step, LeadStep.askEmail);
    expect(texts(c).last, LeadCopy.askEmail('Ada'));

    expect(c.submitText('not-an-email'), isNotNull);
    expect(c.state.step, LeadStep.askEmail);

    expect(c.submitText('ada@example.com'), isNull);
    await settle();
    expect(service.startedName, 'Ada Lovelace');
    expect(service.startedEmail, 'ada@example.com');
    expect(c.state.step, LeadStep.question);
    expect(c.state.currentQuestion!.id, 'job');

    c.submitText('CTO');
    await settle();
    // Hidden question is sent silently, then the radio is asked.
    expect(service.answers, {'job': 'CTO', 'source': 'website'});
    expect(c.state.currentQuestion!.id, 'budget');
    expect(c.state.acceptsText, isFalse);

    c.choose('gt10', '10k+');
    await settle();
    expect(service.answers['budget'], 'gt10');
    expect(c.state.currentQuestion!.id, 'features');

    c.skip();
    await settle();
    expect(service.answers.containsKey('features'), isFalse);
    expect(c.state.step, LeadStep.consent);
    expect(texts(c).last, 'Can we contact you about this?');

    c.agree();
    await settle();
    expect(service.consent, isTrue);
    expect(c.state.step, LeadStep.chat);
    expect(texts(c).last, 'Thanks from Acme!');
    expect(live.connected, isTrue);

    c.submitText('When can we talk?');
    expect(live.sent, ['When can we talk?']);
    expect(texts(c).last, 'When can we talk?');
  });

  test('restores progress from local storage', () async {
    final first = make();
    await first.init();
    first.submitText('Ada');
    first.dispose();

    final second = make();
    await second.init();
    expect(second.state.step, LeadStep.askEmail);
    expect(second.state.name, 'Ada');
    expect(second.state.entries.length, 4);
  });

  test('a failed answer shows an error and retry continues', () async {
    final c = make();
    await c.init();
    c.submitText('Ada');
    c.submitText('ada@example.com');
    await settle();

    service.answerError = const LeadServiceException('answer failed');
    c.submitText('CTO');
    await settle();
    expect(c.state.error, contains('answer failed'));
    expect(c.state.currentQuestion!.id, 'job');

    service.answerError = null;
    await c.retry();
    await settle();
    expect(c.state.error, isNull);
    expect(service.answers['job'], 'CTO');
    expect(c.state.currentQuestion!.id, 'budget');
  });

  test('questionnaire load failure can be retried', () async {
    service.fetchError = const LeadServiceException('HTTP 503');
    final c = make();
    await c.init();
    expect(c.state.step, LeadStep.loadFailed);
    expect(c.state.error, contains('HTTP 503'));

    service.fetchError = null;
    await c.retry();
    expect(c.state.step, LeadStep.askName);
  });

  test('missing vendor id fails without calling the server', () async {
    final c = make(vendorId: '');
    await c.init();
    expect(c.state.step, LeadStep.loadFailed);
    expect(c.state.error, contains('VENDOR_ID'));
  });

  Future<LeadChatController> inChat() async {
    final c = make();
    await c.init();
    c.submitText('Ada');
    c.submitText('ada@example.com');
    await settle();
    c.submitText('CTO');
    await settle();
    c.choose('lt10', '< 10k');
    await settle();
    c.skip();
    await settle();
    c.agree();
    await settle();
    expect(c.state.step, LeadStep.chat);
    return c;
  }

  test('shows admin replies and email logs, ignores own echoes', () async {
    service.history = [_msg('h1', 'admin', 'Hi Ada, thanks for reaching out')];
    final c = await inChat();
    expect(c.state.entries.last.author, EntryAuthor.agent);

    live.controller.add(_msg('m1', 'visitor-1', 'my own echo'));
    live.controller.add(
      _msg(
        'm2',
        'system',
        'We emailed you on 24 Nov about pricing',
        type: 'emaillog',
      ),
    );
    live.controller.add(_msg('h1', 'admin', 'Hi Ada, thanks for reaching out'));
    await settle();

    final last = c.state.entries.last;
    expect(last.author, EntryAuthor.system);
    expect(last.text, 'We emailed you on 24 Nov about pricing');
    expect(texts(c).where((t) => t == 'my own echo'), isEmpty);
    expect(
      texts(c).where((t) => t == 'Hi Ada, thanks for reaching out'),
      hasLength(1),
    );
  });

  test('offline send is refused, not silently dropped', () async {
    live.online = false;
    final c = await inChat();
    final before = c.state.entries.length;
    expect(c.submitText('hello?'), isNotNull);
    expect(live.sent, isEmpty);
    expect(c.state.entries.length, before);
    expect(c.state.error, isNotNull);
  });
}
