import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Поле выбора времени: на мобильном — Cupertino scroll picker, на ПК — ввод цифр без диалога.
class TimePickerField extends StatefulWidget {
  const TimePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  /// Текущее значение в формате HH:mm (например "09:30")
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<TimePickerField> {
  late TextEditingController _hourController;
  late TextEditingController _minController;
  late FocusNode _hourFocus;
  late FocusNode _minFocus;

  static int _parseHour(String s) => (int.tryParse(s) ?? 0).clamp(0, 23);
  static int _parseMin(String s) => (int.tryParse(s) ?? 0).clamp(0, 59);
  static String _fmt(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    final parts = widget.value.trim().split(RegExp(r'[:\s.,-]'));
    final h = parts.isNotEmpty ? _parseHour(parts[0]) : 0;
    final m = parts.length > 1 ? _parseMin(parts[1]) : 0;
    _hourController = TextEditingController(text: _fmt(h));
    _minController = TextEditingController(text: _fmt(m));
    _hourFocus = FocusNode();
    _minFocus = FocusNode();
  }

  @override
  void didUpdateWidget(TimePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final parts = widget.value.trim().split(RegExp(r'[:\s.,-]'));
      final h = parts.isNotEmpty ? _parseHour(parts[0]) : 0;
      final m = parts.length > 1 ? _parseMin(parts[1]) : 0;
      _hourController.text = _fmt(h);
      _minController.text = _fmt(m);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minController.dispose();
    _hourFocus.dispose();
    _minFocus.dispose();
    super.dispose();
  }

  void _emitFromControllers() {
    final h = _parseHour(_hourController.text);
    final m = _parseMin(_minController.text);
    _hourController.text = _fmt(h);
    _minController.text = _fmt(m);
    widget.onChanged('${_fmt(h)}:${_fmt(m)}');
  }

  Future<void> _openMobilePicker() async {
    final parts = widget.value.trim().split(RegExp(r'[:\s.,-]'));
    var duration = Duration(
      hours: parts.isNotEmpty ? _parseHour(parts[0]) : 0,
      minutes: parts.length > 1 ? _parseMin(parts[1]) : 0,
    );
    Duration? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 220,
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  initialTimerDuration: duration,
                  onTimerDurationChanged: (d) => duration = d,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        result = duration;
                        Navigator.of(ctx).pop();
                      },
                      child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      final h = result!.inHours % 24;
      final m = result!.inMinutes % 60;
      widget.onChanged('${_fmt(h)}:${_fmt(m)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return InkWell(
        onTap: widget.enabled ? _openMobilePicker : null,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.schedule, size: 20),
          ),
          child: Text(widget.value.isEmpty ? 'HH:mm' : widget.value),
        ),
      );
    }

    // Desktop: inline HH and MM fields
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: TextField(
            controller: _hourController,
            focusNode: _hourFocus,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            decoration: InputDecoration(
              labelText: widget.label,
              counterText: '',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitFromControllers(),
            onEditingComplete: () {
              _hourFocus.unfocus();
              _minFocus.requestFocus();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, left: 4, right: 4),
          child: Text(':', style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          width: 60,
          child: TextField(
            controller: _minController,
            focusNode: _minFocus,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _emitFromControllers(),
          ),
        ),
      ],
    );
  }
}
