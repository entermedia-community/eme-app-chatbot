import 'dart:async';
import 'dart:convert';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:eme_chatbot/chat/channel_socket.dart';

/// The vendor chat calls of [IApiService]; anything else is unexpected.
class FakeVendorChatApi implements IApiService {
  Object? connectError;
  Object? submitError;
  final connected = <String>[];
  final scenarios = <Map<String, String>>[];
  final submitted = <Map<String, dynamic>>[];
  List<ChatMessage> history = const [];

  @override
  Future<String> connectVendorChat(String vendorId) async {
    connected.add(vendorId);
    if (connectError != null) throw connectError!;
    return 'ch_$vendorId';
  }

  @override
  Future<List<ChatMessage>> fetchServerChatMessages(
    String channelId, {
    String? serverId,
    String? baseUrl,
  }) async => history;

  @override
  Future<void> changeChatScenario(
    String channel, {
    required String scenarioId,
    required String functionName,
  }) async {
    scenarios.add({
      'channel': channel,
      'scenario': scenarioId,
      'function': functionName,
    });
  }

  @override
  Future<void> submitChatForm(
    String channel,
    Map<String, dynamic> values,
  ) async {
    if (submitError != null) throw submitError!;
    submitted.add({'channel': channel, ...values});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeChannelSocket implements ChannelSocket {
  final _controller = StreamController<ChatMessage>.broadcast();
  final connects = <String>[];
  bool connected = false;

  void push(ChatMessage m) => _controller.add(m);

  @override
  Future<void> connect({
    required String channel,
    required String userId,
  }) async {
    connects.add('$channel/$userId');
    connected = true;
  }

  @override
  bool get isConnected => connected;

  @override
  Stream<ChatMessage> get messages => _controller.stream;

  @override
  void disconnect() => connected = false;
}

/// The form EmeChatbotRequestMeetingSkill sends, as it arrives on the socket.
///
/// With [submitted] set it is the form as the server sends it back after a
/// submit: each field's `value` filled in and `"submitted": true`.
ChatMessage meetingForm({
  String id = 'form1',
  String channel = 'ch_V1',
  Map<String, String>? submitted,
}) => ChatMessage.fromJson({
  'messageid': id,
  'channel': channel,
  'user': 'agent',
  'message': jsonEncode({
    'messageplain': 'Request a Meeting',
    'ops': [
      {'insert': 'Request a Meeting\n'},
    ],
    'form': [
      {'type': 'hidden', 'name': 'channel', 'value': channel},
      {
        'type': 'hidden',
        'name': 'functionname',
        'value': 'eme_chatbot_request_meeting_submit',
      },
      {
        'type': 'hidden',
        'name': 'context_meetingtimezone',
        'value': submitted?['context_meetingtimezone'] ?? '',
      },
      {
        'type': 'datetime-local',
        'name': 'context_meetingtime',
        'label': 'Date and time',
        'required': true,
        if (submitted != null) 'value': submitted['context_meetingtime'],
      },
      {
        'type': 'textarea',
        'name': 'context_meetingmessage',
        'label': 'Message (optional)',
        if (submitted != null) 'value': submitted['context_meetingmessage'],
      },
    ],
    'submitLabel': 'Request meeting',
    if (submitted != null) 'submitted': true,
  }),
});

ChatMessage agentText(String id, String text, {String channel = 'ch_V1'}) =>
    ChatMessage.fromJson({
      'messageid': id,
      'channel': channel,
      'user': 'agent',
      'message': text,
    });
