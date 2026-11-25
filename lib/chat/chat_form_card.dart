import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter/material.dart' hide FormField;

/// Max length of a multi-line answer; the server keeps the same.
const formTextareaMaxLength = 1000;

/// The visitor's UTC offset, e.g. `UTC+06:00`, sent with a date and time so
/// the vendor knows which time zone it is in.
String utcOffsetLabel(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'UTC$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
String formatFormDate(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';
String formatFormTime(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// e.g. "Wed 3 Dec 2026".
String displayFormDate(DateTime d) =>
    '${_dayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// The "label: value" lines of a submitted form, as the server kept them in
/// the fields' `value`. Hidden and empty fields are left out.
String submittedFormText(ChatMessage message) {
  final lines = <String>[];
  for (final f in message.formFields) {
    if (f.type == FormFieldType.hidden) continue;
    final raw = f.value?.toString().trim() ?? '';
    if (raw.isEmpty) continue;
    lines.add('${f.label}: ${_submittedValue(f, raw)}');
  }
  return lines.join('\n');
}

String _submittedValue(FormField f, String raw) {
  switch (f.type) {
    case FormFieldType.datetime:
      final parsed = DateTime.tryParse(raw);
      return parsed == null
          ? raw
          : '${displayFormDate(parsed)}, ${formatFormTime(TimeOfDay.fromDateTime(parsed))}';
    case FormFieldType.date:
      final parsed = DateTime.tryParse(raw);
      return parsed == null ? raw : displayFormDate(parsed);
    case FormFieldType.select:
    case FormFieldType.radio:
      for (final o in f.options) {
        if (o.value.toString() == raw) return o.label;
      }
      return raw;
    default:
      return raw;
  }
}

/// A form the server sent in the chat (e.g. Request a Meeting). Hidden
/// fields are sent as they came. Locks once [enabled] turns false.
class ChatFormCard extends StatefulWidget {
  const ChatFormCard({
    super.key,
    required this.message,
    required this.enabled,
    required this.onSubmit,
  });

  final ChatMessage message;

  /// False once submitted, or after a newer server message replaced it.
  final bool enabled;

  /// [values] are field name → value. Once the server has them it sends the
  /// form back as submitted, shown as text ([submittedFormText]).
  final void Function(Map<String, dynamic> values) onSubmit;

  @override
  State<ChatFormCard> createState() => _ChatFormCardState();
}

class _ChatFormCardState extends State<ChatFormCard> {
  final _text = <String, TextEditingController>{};
  final _dates = <String, DateTime>{};
  final _times = <String, TimeOfDay>{};
  final _selects = <String, dynamic>{};
  String? _error;

  List<FormField> get _fields => widget.message.formFields;
  String get _id => widget.message.messageId;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      switch (f.type) {
        case FormFieldType.hidden:
        case FormFieldType.date:
        case FormFieldType.time:
        case FormFieldType.datetime:
          break;
        case FormFieldType.select:
        case FormFieldType.radio:
          if (f.value != null) _selects[f.name] = f.value;
        default:
          // Text-like fields (text, number, textarea, and types this card
          // has no special input for) are typed.
          _text[f.name] = TextEditingController(
            text: f.value?.toString() ?? '',
          );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(FormField f, {required bool withTime}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _dates[f.name];
    final date = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(today)
          ? current
          : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (date == null || !mounted) return;
    if (!withTime) {
      setState(() => _dates[f.name] = date);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: _times[f.name] ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _dates[f.name] = date;
      _times[f.name] = time;
      _error = null;
    });
  }

  Future<void> _pickTime(FormField f) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _times[f.name] ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _times[f.name] = time;
      _error = null;
    });
  }

  /// The field's value to send, or null when it is empty.
  dynamic _valueOf(FormField f) {
    switch (f.type) {
      case FormFieldType.hidden:
        // The server leaves a `...timezone` field empty for the visitor's
        // UTC offset, so it knows which time zone a picked time is in.
        final empty = f.value == null || f.value.toString().isEmpty;
        if (empty && f.name.toLowerCase().endsWith('timezone')) {
          return utcOffsetLabel(DateTime.now().timeZoneOffset);
        }
        return f.value;
      case FormFieldType.datetime:
        final d = _dates[f.name];
        final t = _times[f.name];
        if (d == null || t == null) return null;
        return '${formatFormDate(d)}T${formatFormTime(t)}';
      case FormFieldType.date:
        final d = _dates[f.name];
        return d == null ? null : formatFormDate(d);
      case FormFieldType.time:
        final t = _times[f.name];
        return t == null ? null : formatFormTime(t);
      case FormFieldType.select:
      case FormFieldType.radio:
        return _selects[f.name];
      default:
        final t = _text[f.name]?.text.trim() ?? '';
        return t.isEmpty ? null : t;
    }
  }

  /// What the visitor sees for the field in their echo line.
  String? _displayOf(FormField f) {
    switch (f.type) {
      case FormFieldType.hidden:
        return null;
      case FormFieldType.datetime:
        final d = _dates[f.name];
        final t = _times[f.name];
        if (d == null || t == null) return null;
        return '${displayFormDate(d)}, ${formatFormTime(t)}';
      case FormFieldType.date:
        final d = _dates[f.name];
        return d == null ? null : displayFormDate(d);
      case FormFieldType.select:
      case FormFieldType.radio:
        final v = _selects[f.name];
        if (v == null) return null;
        return f.options
            .firstWhere(
              (o) => o.value == v,
              orElse: () => FormFieldOption(value: v, label: v.toString()),
            )
            .label;
      default:
        return _valueOf(f)?.toString();
    }
  }

  void _submit() {
    final values = <String, dynamic>{};
    for (final f in _fields) {
      final v = _valueOf(f);
      if (v == null) {
        if (f.required) {
          setState(() => _error = 'Please fill in ${f.label}.');
          return;
        }
        continue;
      }
      values[f.name] = v;
    }
    setState(() => _error = null);
    widget.onSubmit(values);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final intro = widget.message.text.trim();
    final enabled = widget.enabled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (intro.isNotEmpty) ...[
                Text(intro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              for (final f in _fields)
                if (f.type != FormFieldType.hidden)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _field(f, enabled),
                  ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  identifier: 'chat_form_submit_$_id',
                  child: FilledButton(
                    onPressed: enabled ? _submit : null,
                    child: Text(
                      enabled
                          ? (widget.message.formSubmitLabel ?? 'Submit')
                          : 'Sent',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(FormField f, bool enabled) {
    final label = f.required ? '${f.label} *' : f.label;
    final id = 'chat_form_${_id}_${f.name}';
    switch (f.type) {
      case FormFieldType.datetime:
      case FormFieldType.date:
      case FormFieldType.time:
        final shown = f.type == FormFieldType.time
            ? (_times[f.name] == null ? null : formatFormTime(_times[f.name]!))
            : _displayOf(f);
        return Semantics(
          identifier: id,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: !enabled
                ? null
                : () => f.type == FormFieldType.time
                      ? _pickTime(f)
                      : _pickDate(
                          f,
                          withTime: f.type == FormFieldType.datetime,
                        ),
            child: InputDecorator(
              isEmpty: shown == null,
              decoration: InputDecoration(
                labelText: label,
                enabled: enabled,
                border: const OutlineInputBorder(),
                suffixIcon: Icon(
                  f.type == FormFieldType.time
                      ? Icons.schedule
                      : Icons.event_outlined,
                ),
              ),
              child: Text(shown ?? ''),
            ),
          ),
        );
      case FormFieldType.select:
      case FormFieldType.radio:
        return Semantics(
          identifier: id,
          child: DropdownButtonFormField<dynamic>(
            initialValue: _selects[f.name],
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final o in f.options)
                DropdownMenuItem(value: o.value, child: Text(o.label)),
            ],
            onChanged: enabled
                ? (v) => setState(() => _selects[f.name] = v)
                : null,
          ),
        );
      default:
        final multiline = f.type == FormFieldType.textarea;
        return Semantics(
          identifier: id,
          child: TextField(
            controller: _text[f.name],
            enabled: enabled,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 6 : 1,
            maxLength: multiline ? formTextareaMaxLength : null,
            keyboardType: f.type == FormFieldType.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : (multiline ? TextInputType.multiline : TextInputType.text),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        );
    }
  }
}
