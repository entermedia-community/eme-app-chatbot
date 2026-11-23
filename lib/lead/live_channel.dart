import 'package:eme_app_sdk/eme_app_sdk.dart';

/// Live connection to the lead's chat channel (admin replies, email logs).
/// An interface so the controller can be tested without a socket.
abstract class LiveChannel {
  Future<void> connect(LeadSession session);
  bool get isConnected;
  Stream<ChatMessage> get messages;
  void send(LeadSession session, String text);
  void disconnect();
}

class SocketLiveChannel implements LiveChannel {
  SocketLiveChannel([ChatSocketService? socket])
    : _socket = socket ?? ChatSocketService();

  final ChatSocketService _socket;

  @override
  Future<void> connect(LeadSession session) => _socket.connect(
    channel: session.channel,
    userId: session.userId,
    token: session.token,
  );

  @override
  bool get isConnected => _socket.isConnected;

  @override
  Stream<ChatMessage> get messages => _socket.messageStream;

  @override
  void send(LeadSession session, String text) => _socket.sendMessage(
    message: text,
    user: session.userId,
    channel: session.channel,
  );

  @override
  void disconnect() => _socket.disconnect();
}
