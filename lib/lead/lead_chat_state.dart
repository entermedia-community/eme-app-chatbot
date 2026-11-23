import 'package:eme_app_sdk/eme_app_sdk.dart';

/// Who wrote a line in the transcript.
enum EntryAuthor {
  /// The website visitor.
  visitor,

  /// Questionnaire prompts and the thank-you message.
  bot,

  /// A vendor admin replying on the lead's channel.
  agent,

  /// System notes, e.g. "We emailed you on 3 Dec about pricing".
  system,
}

/// One line of the locally stored transcript.
class TranscriptEntry {
  final String id;
  final EntryAuthor author;
  final String text;
  final DateTime createdAt;

  const TranscriptEntry({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) =>
      TranscriptEntry(
        id: json['id'].toString(),
        author: EntryAuthor.values.firstWhere(
          (a) => a.name == json['author'],
          orElse: () => EntryAuthor.bot,
        ),
        text: (json['text'] ?? '').toString(),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
}

enum LeadStep {
  /// Fetching the vendor.
  loading,

  /// Vendor could not be loaded; see [LeadChatState.error].
  loadFailed,

  /// Showing the vendor's menu (its chosen automation scenarios).
  menu,
  askName,
  askEmail,

  /// Asking `questionnaire.questions[questionIndex]`.
  question,
  consent,

  /// Questionnaire finished; free conversation with the vendor's admins.
  chat,
}

class LeadChatState {
  final LeadStep step;
  final VendorModel? vendor;

  /// Menu item the visitor last picked.
  final String? selectedMenuId;
  final LeadQuestionnaire? questionnaire;
  final int questionIndex;
  final String? name;
  final String? email;
  final LeadSession? session;
  final List<TranscriptEntry> entries;

  /// A request is in flight.
  final bool busy;

  /// Last request failure, shown with a Retry button.
  final String? error;

  const LeadChatState({
    this.step = LeadStep.loading,
    this.vendor,
    this.selectedMenuId,
    this.questionnaire,
    this.questionIndex = 0,
    this.name,
    this.email,
    this.session,
    this.entries = const [],
    this.busy = false,
    this.error,
  });

  LeadQuestion? get currentQuestion {
    final q = questionnaire;
    if (step != LeadStep.question || q == null) return null;
    if (questionIndex < 0 || questionIndex >= q.questions.length) return null;
    return q.questions[questionIndex];
  }

  /// Whether the text input accepts a typed answer right now.
  bool get acceptsText {
    if (busy) return false;
    switch (step) {
      case LeadStep.askName:
      case LeadStep.askEmail:
      case LeadStep.chat:
        return true;
      case LeadStep.question:
        final t = currentQuestion?.type;
        return t == FormFieldType.text || t == FormFieldType.number;
      default:
        return false;
    }
  }

  LeadChatState copyWith({
    LeadStep? step,
    VendorModel? vendor,
    String? selectedMenuId,
    LeadQuestionnaire? questionnaire,
    int? questionIndex,
    String? name,
    String? email,
    LeadSession? session,
    List<TranscriptEntry>? entries,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => LeadChatState(
    step: step ?? this.step,
    vendor: vendor ?? this.vendor,
    selectedMenuId: selectedMenuId ?? this.selectedMenuId,
    questionnaire: questionnaire ?? this.questionnaire,
    questionIndex: questionIndex ?? this.questionIndex,
    name: name ?? this.name,
    email: email ?? this.email,
    session: session ?? this.session,
    entries: entries ?? this.entries,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );

  /// What survives a reload. Transient flags ([busy], [error]) are dropped.
  Map<String, dynamic> toJson() => {
    'step': step.name,
    if (vendor != null) 'vendor': vendor!.toJson(),
    if (selectedMenuId != null) 'selectedMenuId': selectedMenuId,
    if (questionnaire != null) 'questionnaire': questionnaire!.toJson(),
    'questionIndex': questionIndex,
    if (name != null) 'name': name,
    if (email != null) 'email': email,
    if (session != null) 'session': session!.toJson(),
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory LeadChatState.fromJson(Map<String, dynamic> json) {
    final rawVendor = json['vendor'];
    final rawQ = json['questionnaire'];
    final rawSession = json['session'];
    final rawEntries = json['entries'];
    return LeadChatState(
      step: LeadStep.values.firstWhere(
        (s) => s.name == json['step'],
        orElse: () => LeadStep.loading,
      ),
      vendor: rawVendor is Map
          ? VendorModel.fromJson(Map<String, dynamic>.from(rawVendor))
          : null,
      selectedMenuId: json['selectedMenuId']?.toString(),
      questionnaire: rawQ is Map
          ? LeadQuestionnaire.fromJson(Map<String, dynamic>.from(rawQ))
          : null,
      questionIndex: (json['questionIndex'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      session: rawSession is Map
          ? LeadSession.fromJson(Map<String, dynamic>.from(rawSession))
          : null,
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(
                  (e) => TranscriptEntry.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
    );
  }
}
