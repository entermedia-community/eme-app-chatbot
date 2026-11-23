import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter/material.dart' hide FormField;

/// Open (anonymous) chat: no login, just a header, the message list and a
/// composer with a menu button, input and send button.
///
/// Sending is not yet connected to a backend channel — messages the visitor
/// sends are shown in the list, but no reply is produced until the anonymous
/// chat endpoint is wired up.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _localUserId = 'anonymous';

  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(
        ChatMessage(
          messageId: DateTime.now().microsecondsSinceEpoch.toString(),
          channel: '',
          userId: _localUserId,
          message: text,
          createdAt: DateTime.now(),
        ),
      );
      _input.clear();
    });
    _inputFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newChat() => setState(_messages.clear);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _ChatHeader(),
            const Divider(height: 1),
            Expanded(
              child: _messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        return _MessageBubble(
                          message: m,
                          isMine: m.userId == _localUserId,
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _input,
              focusNode: _inputFocus,
              onSend: _send,
              onNewChat: _newChat,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

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
          Text(
            'EME Chat',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Ask anything to get started.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: SelectableText(
            message.message ?? '',
            style: TextStyle(
              color: isMine ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onNewChat,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Drop-up menu: the composer sits at the bottom of the screen, so
            // MenuAnchor flips the menu above the button.
            MenuAnchor(
              alignmentOffset: const Offset(0, 8),
              menuChildren: [
                Semantics(
                  identifier: 'chat_menu_new_chat',
                  child: MenuItemButton(
                    leadingIcon: const Icon(Icons.refresh),
                    onPressed: onNewChat,
                    child: const Text('New chat'),
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
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
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
    );
  }
}
