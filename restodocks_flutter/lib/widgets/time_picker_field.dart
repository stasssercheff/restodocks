import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

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
  static int _parseHour(String s) => (int.tryParse(s) ?? 0).clamp(0, 23);
  static int _parseMin(String s) => (int.tryParse(s) ?? 0).clamp(0, 59);
  static String _fmt(int n) => n.toString().padLeft(2, '0');

  Future<void> _openPicker() async {
    final parts = widget.value.trim().split(RegExp(r'[:\s.,-]'));
    final initialHour = parts.isNotEmpty ? _parseHour(parts[0]) : 0;
    final initialMin = parts.length > 1 ? _parseMin(parts[1]) : 0;

    // Android, desktop, web — Material showTimePicker (цифры + циферблат)
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: initialHour, minute: initialMin),
      );
      if (picked != null) {
        widget.onChanged('${_fmt(picked.hour)}:${_fmt(picked.minute)}');
      }
      return;
    }

    // iOS — Cupertino scroll picker
    var duration = Duration(hours: initialHour, minutes: initialMin);
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
    return InkWell(
      onTap: widget.enabled ? _openPicker : null,
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
}
