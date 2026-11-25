import 'dart:async';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lead/lead_chat_controller.dart';
import '../signup/signup_controller.dart';
import 'channel_socket.dart';

/// A server message, with when it showed up in this chat (used to order it
/// among the chatbot's own lines).
class ServerEntry {
  final ChatMessage message;
  final DateTime at;

  const ServerEntry(this.message, this.at);
}

class VendorChatState {
  /// The visitor's channel with the vendor, once open.
  final String? channel;

  /// Server messages, oldest first, one per message id.
  final List<ServerEntry> messages;

  /// Forms the visitor submitted in this session.
  final Set<String> submittedFormIds;

  /// Opening the channel.
  final bool connecting;

  /// A request went out and the server's reply hasn't arrived yet.
  final bool awaitingReply;

  /// Last failure, shown with a Retry button.
  final String? error;

  const VendorChatState({
    this.channel,
    this.messages = const [],
    this.submittedFormIds = const {},
    this.connecting = false,
    this.awaitingReply = false,
    this.error,
  });

  /// Whether [form] can still be filled in: not submitted, and nothing came
  /// from the server after it (a newer step replaced it).
  bool isFormOpen(ChatMessage form) {
    if (submittedFormIds.contains(form.messageId)) return false;
    final i = messages.indexWhere((e) => e.message.messageId == form.messageId);
    return i == messages.length - 1;
  }

  VendorChatState copyWith({
    String? channel,
    List<ServerEntry>? messages,
    Set<String>? submittedFormIds,
    bool? connecting,
    bool? awaitingReply,
    String? error,
    bool clearError = false,
  }) => VendorChatState(
    channel: channel ?? this.channel,
    messages: messages ?? this.messages,
    submittedFormIds: submittedFormIds ?? this.submittedFormIds,
    connecting: connecting ?? this.connecting,
    awaitingReply: awaitingReply ?? this.awaitingReply,
    error: clearError ? null : (error ?? this.error),
  );
}

final vendorChatControllerProvider =
    StateNotifierProvider<VendorChatController, VendorChatState>((ref) {
      final controller = VendorChatController(
        api: ref.watch(apiServiceProvider),
        socket: ref.watch(channelSocketProvider),
      );
      // The channel opens once the visitor has signed up and the vendor is
      // known, whichever comes last.
      void maybeOpen() {
        final signup = ref.read(signupControllerProvider);
        final vendor = ref.read(leadChatControllerProvider).vendor;
        final user = signup.user;
        if (signup.isSignedIn && user != null && vendor != null) {
          unawaited(
            controller.open(vendorId: vendor.id, userId: user.username),
          );
        }
      }

      ref.listen(signupControllerProvider, (_, _) => maybeOpen());
      ref.listen(
        leadChatControllerProvider.select((s) => s.vendor?.id),
        (_, _) => maybeOpen(),
      );
      maybeOpen();
      return controller;
    });

/// The visitor's server chat with the vendor (`connectvendorchat.json`):
/// menu picks start the item's scenario, and server-sent forms are submitted
/// back on the same channel.
class VendorChatController extends StateNotifier<VendorChatState> {
  VendorChatController({
    required this.api,
    required this.socket,
    this.replyTimeout = const Duration(seconds: 60),
  }) : super(const VendorChatState());

  final IApiService api;
  final ChannelSocket socket;
  final Duration replyTimeout;

  String? _vendorId;
  String? _userId;
  StreamSubscription<ChatMessage>? _sub;
  Future<void> Function()? _retry;
  Timer? _replyTimer;

  /// Opens the channel for [vendorId] once; later calls do nothing.
  Future<void> open({required String vendorId, required String userId}) async {
    if (_vendorId == vendorId && _userId == userId) return;
    _vendorId = vendorId;
    _userId = userId;
    await _run(_connect);
  }

  Future<void> _connect() async {
    state = state.copyWith(connecting: true);
    try {
      final channel = await api.connectVendorChat(_vendorId!);
      if (!mounted) return;
      state = state.copyWith(channel: channel);
      _sub ??= socket.messages.listen(_onMessage);
      await socket.connect(channel: channel, userId: _userId!);
      final history = await api.fetchServerChatMessages(channel);
      // The server may list newest first; show oldest first.
      final ordered = [...history]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      // Place history by when it loaded, not by the server's own dates: they
      // can sit hours off this device's clock and would land above the
      // chatbot's greeting. The order among them is kept.
      final loadedAt = DateTime.now();
      for (var i = 0; i < ordered.length; i++) {
        _add(ordered[i], at: loadedAt.add(Duration(microseconds: i)));
      }
    } finally {
      if (mounted) state = state.copyWith(connecting: false);
    }
  }

  /// Runs [item]'s scenario on the server (`<scenario>_confirm`). Its reply
  /// arrives on the socket.
  Future<void> startScenario(VendorMenuItem item) => _run(() async {
    final channel = await _requireChannel();
    await api.changeChatScenario(
      channel,
      scenarioId: item.id,
      functionName: '${item.id}_confirm',
    );
    _awaitReply();
  });

  /// Submits [form] with [values] (its field names, hidden ones included),
  /// along with the form's message id (`formmessageid`) so the server keeps
  /// the values on that message and marks it submitted. It sends the message
  /// back, and the chat then shows what was submitted as text.
  Future<void> submitForm(ChatMessage form, Map<String, dynamic> values) =>
      _run(() async {
        final channel = await _requireChannel();
        await api.submitChatForm(channel, {
          ...values,
          'formmessageid': form.messageId,
        });
        if (!mounted) return;
        state = state.copyWith(
          submittedFormIds: {...state.submittedFormIds, form.messageId},
        );
        _awaitReply();
      });

  Future<void> retry() async {
    final action = _retry;
    if (action == null) return;
    await _run(action);
  }

  Future<String> _requireChannel() async {
    if (state.channel == null) {
      if (_vendorId == null) {
        throw const _ChatNotReady('This chat is not connected yet.');
      }
      await _connect();
    }
    return state.channel!;
  }

  void _awaitReply() {
    if (!mounted) return;
    _replyTimer?.cancel();
    state = state.copyWith(awaitingReply: true);
    _replyTimer = Timer(replyTimeout, () {
      if (!mounted || !state.awaitingReply) return;
      state = state.copyWith(
        awaitingReply: false,
        error: "We haven't heard back yet. Please try again.",
      );
    });
  }

  void _onMessage(ChatMessage m) {
    if (!mounted) return;
    final channel = state.channel;
    if (channel == null) return;
    if (m.channel.isNotEmpty && m.channel != channel) return;
    if (m.isKeepAlive) return;
    _add(m, at: DateTime.now());
  }

  void _add(ChatMessage m, {required DateTime at}) {
    if (!mounted) return;
    // The visitor's own rows (menu picks, form submissions) are shown by the
    // chatbot already.
    if (m.userId == _userId || m.messageType == 'system') return;
    final list = [...state.messages];
    final i = list.indexWhere((e) => e.message.messageId == m.messageId);
    if (m.isMessageRemoved) {
      if (i >= 0) list.removeAt(i);
      state = state.copyWith(messages: list);
      return;
    }
    if (m.isPatch) {
      if (i < 0) return; // A patch for a message we never saw.
      list[i] = ServerEntry(list[i].message.applyPatch(m), list[i].at);
    } else if (i >= 0) {
      list[i] = ServerEntry(m, list[i].at);
    } else {
      list.add(ServerEntry(m, at));
    }
    _replyTimer?.cancel();
    state = state.copyWith(messages: list, awaitingReply: false);
  }

  Future<void> _run(Future<void> Function() action) async {
    _retry = null;
    state = state.copyWith(clearError: true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      _retry = action;
      state = state.copyWith(awaitingReply: false, error: _describe(e));
    }
  }

  static String _describe(Object e) {
    if (e is _ChatNotReady) return e.message;
    return "We couldn't reach the server. Check your connection.";
  }

  @override
  void dispose() {
    _replyTimer?.cancel();
    _sub?.cancel();
    socket.disconnect();
    super.dispose();
  }
}

class _ChatNotReady implements Exception {
  const _ChatNotReady(this.message);
  final String message;
}
