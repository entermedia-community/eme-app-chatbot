import 'dart:async';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'lead_chat_state.dart';
import 'lead_store.dart';
import 'live_channel.dart';

/// UI copy the app owns (vendor-specific text comes from the questionnaire).
class LeadCopy {
  static const askName = "Before we start, what's your name?";
  static String askEmail(String firstName) =>
      'Nice to meet you, $firstName! What email can we reach you at?';
  static const agree = 'I agree';
  static const skipped = 'Skipped';
  static String thankYou(String firstName) =>
      "Thank you, $firstName! We'll be in touch soon. "
      'Feel free to keep chatting here.';
}

final liveChannelProvider = Provider<LiveChannel>((ref) => SocketLiveChannel());
final leadStoreProvider = Provider<LeadStore>((ref) => LeadStore());

final leadChatControllerProvider =
    StateNotifierProvider<LeadChatController, LeadChatState>((ref) {
      final controller = LeadChatController(
        vendorId: ChatbotConfig.vendorId,
        service: ref.watch(leadServiceProvider),
        live: ref.watch(liveChannelProvider),
        store: ref.watch(leadStoreProvider),
      );
      unawaited(controller.init());
      return controller;
    });

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Drives the lead questionnaire: name → email → vendor questions (one at a
/// time) → consent → thank-you, then an open conversation on the lead's
/// channel. Every change is saved to the visitor's device.
class LeadChatController extends StateNotifier<LeadChatState> {
  LeadChatController({
    required this.vendorId,
    required this.service,
    required this.live,
    required this.store,
  }) : super(const LeadChatState());

  final String vendorId;
  final ILeadService service;
  final LiveChannel live;
  final LeadStore store;

  Future<void> Function()? _retry;
  StreamSubscription<ChatMessage>? _liveSub;
  int _idCounter = 0;

  Future<void> init() async {
    if (vendorId.isEmpty) {
      _set(
        state.copyWith(
          step: LeadStep.loadFailed,
          error: 'This chat is not configured (missing VENDOR_ID).',
        ),
        persist: false,
      );
      return;
    }
    final saved = await store.load(vendorId);
    if (!mounted) return;
    if (saved != null &&
        saved.questionnaire != null &&
        saved.step != LeadStep.loading &&
        saved.step != LeadStep.loadFailed) {
      _set(saved, persist: false);
      if (saved.step == LeadStep.chat) await _openLiveChat();
      return;
    }
    await _run(_loadQuestionnaire);
  }

  Future<void> _loadQuestionnaire() async {
    final q = await service.fetchQuestionnaire(vendorId);
    final entries = [
      if (q.greeting != null) _entry(EntryAuthor.bot, q.greeting!),
      _entry(EntryAuthor.bot, LeadCopy.askName),
    ];
    _set(
      LeadChatState(step: LeadStep.askName, questionnaire: q, entries: entries),
    );
  }

  /// Handles typed input for the current step. Returns a validation message
  /// to show under the input, or null when the text was accepted.
  String? submitText(String raw) {
    final text = raw.trim();
    if (text.isEmpty || !state.acceptsText) return null;

    switch (state.step) {
      case LeadStep.askName:
        _addEntry(EntryAuthor.visitor, text);
        _set(
          state.copyWith(
            name: text,
            step: LeadStep.askEmail,
            entries: [
              ...state.entries,
              _entry(EntryAuthor.bot, LeadCopy.askEmail(_firstName(text))),
            ],
          ),
        );
        return null;

      case LeadStep.askEmail:
        if (!_emailPattern.hasMatch(text)) {
          return 'Please enter a valid email address.';
        }
        _addEntry(EntryAuthor.visitor, text);
        _set(state.copyWith(email: text));
        unawaited(_run(_startLead));
        return null;

      case LeadStep.question:
        final q = state.currentQuestion!;
        dynamic value = text;
        if (q.type == FormFieldType.number) {
          value = num.tryParse(text.replaceAll(',', ''));
          if (value == null) return 'Please enter a number.';
        }
        _answer(q, value, text);
        return null;

      case LeadStep.chat:
        final session = state.session!;
        if (!live.isConnected) {
          _set(
            state.copyWith(
              error: "You're offline, so your message wasn't sent.",
            ),
            persist: false,
          );
          _retry = () async {
            await live.connect(session);
            if (!live.isConnected) {
              throw const LeadServiceException('Still offline');
            }
          };
          return 'Not sent. Reconnect and try again.';
        }
        live.send(session, text);
        _addEntry(EntryAuthor.visitor, text);
        return null;

      default:
        return null;
    }
  }

  /// Answer a select / radio / boolean question by tapping an option.
  void choose(dynamic value, String label) {
    final q = state.currentQuestion;
    if (q == null || state.busy) return;
    _answer(q, value, label);
  }

  /// Answer a checkbox (multi-select) question.
  void chooseMany(List<FormFieldOption> picked) {
    final q = state.currentQuestion;
    if (q == null || state.busy || picked.isEmpty) return;
    _answer(
      q,
      picked.map((o) => o.value).toList(),
      picked.map((o) => o.label).join(', '),
    );
  }

  void skip() {
    final q = state.currentQuestion;
    if (q == null || q.required || state.busy) return;
    _addEntry(EntryAuthor.visitor, LeadCopy.skipped);
    unawaited(_run(() => _askFrom(state.questionIndex + 1)));
  }

  void agree() {
    if (state.step != LeadStep.consent || state.busy) return;
    _addEntry(EntryAuthor.visitor, LeadCopy.agree);
    unawaited(_run(_complete));
  }

  Future<void> retry() async {
    final action = _retry;
    if (action == null) return;
    await _run(action);
  }

  /// Forget this device's chat and start the questionnaire again.
  Future<void> startOver() async {
    await _liveSub?.cancel();
    _liveSub = null;
    live.disconnect();
    await store.clear(vendorId);
    _retry = null;
    _set(const LeadChatState(), persist: false);
    await init();
  }

  // ── Steps ──────────────────────────────────────────────────────────────

  Future<void> _startLead() async {
    final q = state.questionnaire!;
    final session = await service.startLead(
      vendorId: vendorId,
      questionnaireId: q.id,
      name: state.name!,
      email: state.email!,
    );
    _set(state.copyWith(session: session));
    await _askFrom(0);
  }

  void _answer(LeadQuestion q, dynamic value, String display) {
    _addEntry(EntryAuthor.visitor, display);
    final index = state.questionIndex;
    unawaited(
      _run(() async {
        await service.saveAnswer(
          state.session!,
          questionId: q.id,
          value: value,
        );
        await _askFrom(index + 1);
      }),
    );
  }

  /// Asks the next visible question at or after [index], sending preset
  /// hidden answers along the way; moves to consent after the last one.
  Future<void> _askFrom(int index) async {
    final questions = state.questionnaire!.questions;
    var i = index;
    while (i < questions.length && questions[i].type == FormFieldType.hidden) {
      final q = questions[i];
      if (q.value != null) {
        await service.saveAnswer(
          state.session!,
          questionId: q.id,
          value: q.value,
        );
      }
      i++;
      _set(state.copyWith(questionIndex: i));
    }
    if (i < questions.length) {
      _set(
        state.copyWith(
          step: LeadStep.question,
          questionIndex: i,
          entries: [
            ...state.entries,
            _entry(EntryAuthor.bot, questions[i].prompt),
          ],
        ),
      );
      return;
    }
    _set(
      state.copyWith(
        step: LeadStep.consent,
        questionIndex: questions.length,
        entries: [
          ...state.entries,
          _entry(EntryAuthor.bot, state.questionnaire!.consentText),
        ],
      ),
    );
  }

  Future<void> _complete() async {
    final serverThanks = await service.completeLead(
      state.session!,
      consent: true,
    );
    final thanks =
        serverThanks ??
        state.questionnaire!.thankYouMessage ??
        LeadCopy.thankYou(_firstName(state.name ?? ''));
    _set(
      state.copyWith(
        step: LeadStep.chat,
        entries: [...state.entries, _entry(EntryAuthor.bot, thanks)],
      ),
    );
    await _openLiveChat();
  }

  /// Connects to the lead's channel and pulls messages sent while the
  /// visitor was away. A history failure is shown but doesn't block chat.
  Future<void> _openLiveChat() async {
    final session = state.session;
    if (session == null) return;
    _liveSub ??= live.messages.listen(_onLiveMessage);
    await live.connect(session);
    await _run(() async {
      final history = await service.fetchMessages(session);
      history.forEach(_onLiveMessage);
    });
  }

  void _onLiveMessage(ChatMessage m) {
    final session = state.session;
    if (!mounted || session == null) return;
    if (m.channel.isNotEmpty && m.channel != session.channel) return;
    // The visitor's own messages are already in the local transcript.
    if (m.userId == session.userId) return;
    final text = m.text.trim();
    if (text.isEmpty) return;
    final id = 'srv_${m.messageId}';
    if (state.entries.any((e) => e.id == id)) return;
    final entry = TranscriptEntry(
      id: id,
      author: m.messageType == 'emaillog'
          ? EntryAuthor.system
          : EntryAuthor.agent,
      text: text,
      createdAt: m.createdAt,
    );
    _set(state.copyWith(entries: [...state.entries, entry]));
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action) async {
    _retry = null;
    _set(state.copyWith(busy: true, clearError: true), persist: false);
    try {
      await action();
      if (!mounted) return;
      _set(state.copyWith(busy: false));
    } catch (e) {
      if (!mounted) return;
      _retry = action;
      final failedLoad = state.questionnaire == null;
      _set(
        state.copyWith(
          busy: false,
          step: failedLoad ? LeadStep.loadFailed : null,
          error: _describe(e),
        ),
        persist: !failedLoad,
      );
    }
  }

  String _describe(Object e) {
    if (e is LeadServiceException) {
      return 'Something went wrong (${e.message}).';
    }
    // Anything else is a transport failure (DNS, offline, timeout, CORS).
    return "We couldn't reach the server. Check your connection.";
  }

  void _addEntry(EntryAuthor author, String text) =>
      _set(state.copyWith(entries: [...state.entries, _entry(author, text)]));

  TranscriptEntry _entry(EntryAuthor author, String text) => TranscriptEntry(
    id: 'local_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
    author: author,
    text: text,
    createdAt: DateTime.now(),
  );

  void _set(LeadChatState next, {bool persist = true}) {
    if (!mounted) return;
    state = next;
    if (persist && next.questionnaire != null) {
      unawaited(store.save(vendorId, next));
    }
  }

  static String _firstName(String name) =>
      name.trim().split(RegExp(r'\s+')).first;

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }
}
