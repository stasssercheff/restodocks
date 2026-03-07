import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Поле выбора времени: на мобильном — Cupertino scroll picker (прокрутка как на iOS),
/// на веб/ПК — простой ввод цифр HH:mm.
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

    // Мобильный (узкий экран) — Cupertino scroll picker, как на iOS
    final isMobile = MediaQuery.of(context).size.shortestSide < 600;

    if (!isMobile) {
      // Веб, ПК — простой ввод цифр
      final result = await _showSimpleTimeInputDialog(initialHour, initialMin);
      if (result != null) {
        widget.onChanged('${_fmt(result.$1)}:${_fmt(result.$2)}');
      }
      return;
    }

    // Мобильный — Cupertino scroll picker
    var duration = Duration(hours: initialHour, minutes: initialMin);
    final result = await showModalBottomSheet<Duration>(
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
                      onPressed: () => Navigator.of(ctx).pop(duration),
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

  /// Диалог с простым вводом времени цифрами (час и минуты).
  Future<(int, int)?> _showSimpleTimeInputDialog(int initialHour, int initialMin) async {
    final hourController = TextEditingController(text: _fmt(initialHour));
    final minController = TextEditingController(text: _fmt(initialMin));

    return showDialog<(int, int)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.label),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              child: TextField(
                controller: hourController,
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _TimeInputFormatter(0, 23),
                ],
                decoration: const InputDecoration(
                  labelText: 'ЧЧ',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: Theme.of(ctx).textTheme.headlineSmall),
            ),
            SizedBox(
              width: 56,
              child: TextField(
                controller: minController,
                keyboardType: TextInputType.number,
                maxLength: 2,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _TimeInputFormatter(0, 59),
                ],
                decoration: const InputDecoration(
                  labelText: 'ММ',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () {
              final h = _parseHour(hourController.text);
              final m = _parseMin(minController.text);
              Navigator.of(ctx).pop((h, m));
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
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

/// Ограничивает ввод числом в диапазоне [minVal, maxVal].
class _TimeInputFormatter extends TextInputFormatter {
  final int minVal;
  final int maxVal;

  _TimeInputFormatter(this.minVal, this.maxVal);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final n = int.tryParse(newValue.text);
    if (n == null) return oldValue;
    if (n < minVal) return TextEditingValue(text: minVal.toString(), selection: TextSelection.collapsed(offset: minVal.toString().length));
    if (n > maxVal) return TextEditingValue(text: maxVal.toString(), selection: TextSelection.collapsed(offset: maxVal.toString().length));
    return newValue;
  }
}
