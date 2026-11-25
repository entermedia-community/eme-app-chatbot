import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter/material.dart' hide FormField;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_form_card.dart';
import '../chat/vendor_chat_controller.dart';
import '../lead/lead_chat_controller.dart';
import '../lead/lead_chat_state.dart';
import '../signup/signup_controller.dart';
import '../signup/signup_dialog.dart';

/// Open (anonymous) lead-capture chat: header, transcript, quick replies for
/// the current question, and a composer with a drop-up menu.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  String? _inputError;
  bool _signupOpen = false;

  /// Any tap on the chat while signed out lands here.
  Future<void> _promptSignup() async {
    if (_signupOpen) return;
    _signupOpen = true;
    final signedIn = await showSignupDialog(context);
    _signupOpen = false;
    if (signedIn && mounted) _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final controller = ref.read(leadChatControllerProvider.notifier);
    final error = controller.submitText(_input.text);
    setState(() => _inputError = error);
    if (error == null) _input.clear();
    _inputFocus.requestFocus();
  }

  /// A menu pick shows in the transcript and starts the item's scenario on
  /// the vendor's server chat.
  void _pickMenuItem(VendorMenuItem item) {
    final picked = ref
        .read(leadChatControllerProvider.notifier)
        .selectMenuItem(item);
    if (picked) {
      ref.read(vendorChatControllerProvider.notifier).startScenario(item);
    }
  }

  Future<void> _confirmStartOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text(
          'This clears the conversation saved on this device.',
        ),
        actions: [
          Semantics(
            identifier: 'start_over_cancel_button',
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
          Semantics(
            identifier: 'start_over_confirm_button',
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start over'),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      _input.clear();
      setState(() => _inputError = null);
      await ref.read(leadChatControllerProvider.notifier).startOver();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      leadChatControllerProvider.select((s) => (s.entries.length, s.busy)),
      (_, _) => _scrollToEnd(),
    );
    ref.listen(
      vendorChatControllerProvider.select(
        (s) => (s.messages.length, s.awaitingReply),
      ),
      (_, _) => _scrollToEnd(),
    );
    final state = ref.watch(leadChatControllerProvider);
    final chat = ref.watch(vendorChatControllerProvider);
    final chatController = ref.read(vendorChatControllerProvider.notifier);
    final controller = ref.read(leadChatControllerProvider.notifier);
    final vendorName = state.vendor?.name ?? '';
    final title = vendorName.isNotEmpty ? vendorName : 'Chat';
    final canPickMenu = state.step == LeadStep.menu && !state.busy;

    final signup = ref.watch(signupControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: _SignupGate(
          // Until the visitor has signed up, every tap opens the sign-up
          // popup instead of reaching the chat. While the saved session is
          // still being checked, taps are held back without a popup.
          locked: !signup.isSignedIn,
          onTap: signup.status == SignupStatus.signedOut ? _promptSignup : null,
          child: Column(
            children: [
              _ChatHeader(title: title),
              const Divider(height: 1),
              Expanded(child: _body(state, controller, chat, chatController)),
              if (state.error != null && state.step != LeadStep.loadFailed)
                _ErrorBanner(message: state.error!, onRetry: controller.retry),
              if (chat.error != null && state.step != LeadStep.loadFailed)
                _ErrorBanner(
                  message: chat.error!,
                  onRetry: chatController.retry,
                ),
              if (!state.busy)
                _QuickReplies(state: state, controller: controller),
              _Composer(
                controller: _input,
                focusNode: _inputFocus,
                enabled: state.acceptsText,
                hintText: _hintFor(state),
                errorText: _inputError,
                keyboardType: _keyboardFor(state),
                onSend: _send,
                onChanged: () {
                  if (_inputError != null) setState(() => _inputError = null);
                },
                menuItems: state.vendor?.menu ?? const [],
                onMenuItem: canPickMenu ? _pickMenuItem : null,
                onStartOver: _confirmStartOver,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    LeadChatState state,
    LeadChatController controller,
    VendorChatState chat,
    VendorChatController chatController,
  ) {
    if (state.step == LeadStep.loading && state.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.step == LeadStep.loadFailed) {
      return _LoadFailed(
        message: state.error ?? 'Could not load this chat.',
        onRetry: controller.retry,
      );
    }
    final vendorName = state.vendor?.name ?? '';
    final agentName = vendorName.isNotEmpty ? vendorName : null;
    final menu = state.vendor?.menu ?? const <VendorMenuItem>[];
    // Once the chat has started (an item was picked, or the server has
    // replied) the items live in the + menu only.
    final chatStarted =
        state.selectedMenuId != null ||
        chat.messages.isNotEmpty ||
        chat.awaitingReply;
    final showMenu =
        state.step == LeadStep.menu && menu.isNotEmpty && !chatStarted;

    // The chatbot's own lines and the server's messages, in the order they
    // showed up.
    final items = <(DateTime, Widget)>[
      for (final e in state.entries)
        (
          e.createdAt,
          e.author == EntryAuthor.system
              ? _SystemNote(entry: e)
              : _MessageBubble(entry: e, agentName: agentName),
        ),
      for (final s in chat.messages)
        (s.at, _serverMessage(s.message, chat, chatController, agentName)),
    ];
    // List.sort isn't stable; keep same-time lines in their list order.
    final ordered = [for (var i = 0; i < items.length; i++) (i, items[i])]
      ..sort((a, b) {
        final byTime = a.$2.$1.compareTo(b.$2.$1);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

    final rows = <Widget>[
      for (final o in ordered) o.$2.$2,
      if (showMenu)
        _VendorMenu(
          items: menu,
          selectedId: state.selectedMenuId,
          onSelect: state.busy ? null : _pickMenuItem,
        ),
      if (state.busy || chat.connecting || chat.awaitingReply)
        const _TypingIndicator(),
    ];
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }

  Widget _serverMessage(
    ChatMessage m,
    VendorChatState chat,
    VendorChatController chatController,
    String? agentName,
  ) {
    if (m.messageRenderType == MessageRenderType.form &&
        m.formFields.isNotEmpty) {
      // A submitted form is shown as the visitor's "label: value" lines.
      if (m.formSubmitted) {
        return _MessageBubble(
          entry: TranscriptEntry(
            id: 'form_${m.messageId}',
            author: EntryAuthor.visitor,
            text: submittedFormText(m),
            createdAt: m.createdAt,
          ),
          agentName: agentName,
        );
      }
      // Sent, waiting for the server to send it back as submitted.
      if (chat.submittedFormIds.contains(m.messageId)) {
        return const SizedBox.shrink();
      }
      return ChatFormCard(
        key: ValueKey('chat_form_${m.messageId}'),
        message: m,
        enabled: chat.isFormOpen(m),
        onSubmit: (values) => chatController.submitForm(m, values),
      );
    }
    final text = m.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return _MessageBubble(
      entry: TranscriptEntry(
        id: 'srv_${m.messageId}',
        author: EntryAuthor.agent,
        text: text,
        createdAt: m.createdAt,
      ),
      agentName: agentName,
    );
  }

  static String _hintFor(LeadChatState s) {
    if (s.busy) return 'One moment…';
    switch (s.step) {
      case LeadStep.menu:
        return 'Choose an option from the menu';
      case LeadStep.askName:
        return 'Your name';
      case LeadStep.askEmail:
        return 'you@example.com';
      case LeadStep.question:
        return s.acceptsText
            ? (s.currentQuestion?.placeholder ?? 'Type your answer')
            : 'Choose an answer above';
      case LeadStep.consent:
        return 'Tap "I agree" to continue';
      case LeadStep.chat:
        return 'Message';
      default:
        return '';
    }
  }

  static TextInputType _keyboardFor(LeadChatState s) {
    if (s.step == LeadStep.askEmail) return TextInputType.emailAddress;
    if (s.currentQuestion?.type == FormFieldType.number) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.multiline;
  }
}

/// Covers [child] with a transparent layer that swallows pointer input and
/// calls [onTap] while [locked].
class _SignupGate extends StatelessWidget {
  const _SignupGate({
    required this.locked,
    required this.onTap,
    required this.child,
  });

  final bool locked;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Keep the chat out of focus traversal while it can't be used.
        ExcludeFocus(excluding: locked, child: child),
        if (locked)
          Positioned.fill(
            child: Semantics(
              identifier: 'signup_gate',
              button: true,
              label: 'Sign up to chat',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            child: Icon(
              Icons.chat_bubble_outline,
              size: 14,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'load_retry_button',
              child: FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.entry, this.agentName});

  final TranscriptEntry entry;
  final String? agentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMine = entry.author == EntryAuthor.visitor;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (entry.author == EntryAuthor.agent)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text(
                  agentName ?? 'Team',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine
                    ? scheme.primary
                    : entry.author == EntryAuthor.agent
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
              ),
              child: SelectableText(
                entry.text,
                style: TextStyle(
                  color: isMine
                      ? scheme.onPrimary
                      : entry.author == EntryAuthor.agent
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// e.g. "We emailed you on 3 Dec about pricing".
class _SystemNote extends StatelessWidget {
  const _SystemNote({required this.entry});

  final TranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          Semantics(
            identifier: 'error_retry_button',
            child: TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-answer options for the current step.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.state, required this.controller});

  final LeadChatState state;
  final LeadChatController controller;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (state.step == LeadStep.consent) {
      children.add(
        Semantics(
          identifier: 'consent_agree_button',
          child: FilledButton(
            onPressed: controller.agree,
            child: const Text(LeadCopy.agree),
          ),
        ),
      );
    }

    final q = state.currentQuestion;
    if (q != null) {
      switch (q.type) {
        case FormFieldType.select:
        case FormFieldType.radio:
          for (var i = 0; i < q.options.length; i++) {
            final o = q.options[i];
            children.add(
              Semantics(
                identifier: 'answer_option_${q.id}_$i',
                child: ActionChip(
                  label: Text(o.label),
                  onPressed: () => controller.choose(o.value, o.label),
                ),
              ),
            );
          }
        case FormFieldType.boolean:
          children.addAll([
            Semantics(
              identifier: 'answer_yes_${q.id}',
              child: ActionChip(
                label: const Text('Yes'),
                onPressed: () => controller.choose(true, 'Yes'),
              ),
            ),
            Semantics(
              identifier: 'answer_no_${q.id}',
              child: ActionChip(
                label: const Text('No'),
                onPressed: () => controller.choose(false, 'No'),
              ),
            ),
          ]);
        case FormFieldType.checkbox:
          children.add(
            _MultiChoice(
              key: ValueKey('multi_${q.id}'),
              question: q,
              onDone: controller.chooseMany,
            ),
          );
        default:
          break;
      }
      if (!q.required) {
        children.add(
          Semantics(
            identifier: 'skip_question_button',
            child: TextButton(
              onPressed: controller.skip,
              child: const Text('Skip'),
            ),
          ),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: children,
        ),
      ),
    );
  }
}

class _MultiChoice extends StatefulWidget {
  const _MultiChoice({super.key, required this.question, required this.onDone});

  final LeadQuestion question;
  final void Function(List<FormFieldOption>) onDone;

  @override
  State<_MultiChoice> createState() => _MultiChoiceState();
}

class _MultiChoiceState extends State<_MultiChoice> {
  final _picked = <int>{};

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < q.options.length; i++)
          Semantics(
            identifier: 'answer_option_${q.id}_$i',
            child: FilterChip(
              label: Text(q.options[i].label),
              selected: _picked.contains(i),
              onSelected: (on) => setState(() {
                on ? _picked.add(i) : _picked.remove(i);
              }),
            ),
          ),
        Semantics(
          identifier: 'answer_done_${q.id}',
          child: FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => widget.onDone([
                    for (final i in _picked.toList()..sort()) q.options[i],
                  ]),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.keyboardType,
    required this.onSend,
    required this.onChanged,
    required this.onStartOver,
    this.menuItems = const [],
    this.onMenuItem,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hintText;
  final String? errorText;
  final TextInputType keyboardType;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  final VoidCallback onStartOver;
  final List<VendorMenuItem> menuItems;

  /// Null while menu items can't be picked (they show disabled).
  final ValueChanged<VendorMenuItem>? onMenuItem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: errorText != null
                  ? Border.all(color: scheme.error)
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Drop-up menu: the composer sits at the bottom of the screen,
                // so MenuAnchor flips the menu above the button.
                MenuAnchor(
                  alignmentOffset: const Offset(0, 8),
                  menuChildren: [
                    for (final item in menuItems)
                      Semantics(
                        identifier: 'chat_menu_item_${item.id}',
                        child: MenuItemButton(
                          leadingIcon: Icon(menuIconFor(item.icon)),
                          onPressed: onMenuItem == null
                              ? null
                              : () => onMenuItem!(item),
                          child: Text(item.name),
                        ),
                      ),
                    if (menuItems.isNotEmpty) const Divider(height: 1),
                    Semantics(
                      identifier: 'chat_menu_start_over',
                      child: MenuItemButton(
                        leadingIcon: const Icon(Icons.restart_alt),
                        onPressed: onStartOver,
                        child: const Text('Start over'),
                      ),
                    ),
                  ],
                  builder: (context, menu, _) => Semantics(
                    identifier: 'chat_menu_button',
                    child: IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.add),
                      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    identifier: 'chat_input',
                    child: CallbackShortcuts(
                      // Enter sends, Shift+Enter adds a new line.
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): onSend,
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: keyboardType,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        onChanged: (_) => onChanged(),
                        decoration: InputDecoration(
                          hintText: hintText,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final canSend = enabled && value.text.trim().isNotEmpty;
                    return Semantics(
                      identifier: 'chat_send_button',
                      child: IconButton.filled(
                        tooltip: 'Send',
                        onPressed: canSend ? onSend : null,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(
                errorText!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Material icon for an `automationscenario.scenarioicon` name (these are
/// Bootstrap icon names on the server).
IconData menuIconFor(String? name) {
  final key = (name ?? '').toLowerCase();
  const icons = <String, IconData>{
    'robot': Icons.smart_toy_outlined,
    'broadcast': Icons.campaign_outlined,
    'list': Icons.list_alt,
    'checklist': Icons.checklist,
    'fill': Icons.edit_note,
    'card': Icons.credit_card,
    'cash': Icons.payments_outlined,
    'coin': Icons.monetization_on_outlined,
    'earmark': Icons.description_outlined,
    'file': Icons.description_outlined,
    'richtext': Icons.article_outlined,
    'search': Icons.search,
    'calendar': Icons.calendar_today_outlined,
    'event': Icons.event_outlined,
    'chat': Icons.chat_bubble_outline,
    'envelope': Icons.mail_outline,
    'folder': Icons.folder_outlined,
    'image': Icons.image_outlined,
    'upload': Icons.upload_outlined,
  };
  for (final entry in icons.entries) {
    if (key.contains(entry.key)) return entry.value;
  }
  return Icons.auto_awesome_outlined;
}

/// The vendor's menu, shown in the conversation under the greeting.
class _VendorMenu extends StatelessWidget {
  const _VendorMenu({
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final List<VendorMenuItem> items;
  final String? selectedId;
  final ValueChanged<VendorMenuItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Semantics(
                identifier: 'vendor_menu_item_${item.id}',
                child: Material(
                  color: item.id == selectedId
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    enabled: onSelect != null,
                    leading: Icon(
                      menuIconFor(item.icon),
                      color: scheme.primary,
                    ),
                    title: Text(item.name, style: theme.textTheme.titleSmall),
                    subtitle: item.description == null
                        ? null
                        : Text(
                            item.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onSelect == null ? null : () => onSelect!(item),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
