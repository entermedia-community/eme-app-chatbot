import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live connection to the visitor's vendor chat channel. An interface so the
/// controller can be tested without a socket.
abstract class ChannelSocket {
  Future<void> connect({required String channel, required String userId});
  bool get isConnected;
  Stream<ChatMessage> get messages;
  void disconnect();
}

class SdkChannelSocket implements ChannelSocket {
  SdkChannelSocket([ChatSocketService? socket])
    : _socket = socket ?? ChatSocketService();

  final ChatSocketService _socket;

  @override
  Future<void> connect({required String channel, required String userId}) =>
      _socket.connect(
        channel: channel,
        channelType: vendorChatChannelType,
        userId: userId,
      );

  @override
  bool get isConnected => _socket.isConnected;

  @override
  Stream<ChatMessage> get messages => _socket.messageStream;

  @override
  void disconnect() => _socket.disconnect();
}

final channelSocketProvider = Provider<ChannelSocket>(
  (ref) => SdkChannelSocket(),
);
