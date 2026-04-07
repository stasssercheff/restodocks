import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

/// На телефонах — колесо как в iOS; на ПК и в веб — ввод времени без «диска».
Future<TimeOfDay?> showAdaptiveTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) async {
  final mat = MaterialLocalizations.of(context);
  final useWheel = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  if (!useWheel) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }

  var selected = DateTime(2020, 1, 1, initialTime.hour, initialTime.minute);
  final picked = await showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (ctx) {
      return Container(
        height: 280,
        padding: const EdgeInsets.only(top: 4),
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(mat.cancelButtonLabel),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: Text(mat.okButtonLabel),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: selected,
                onDateTimeChanged: (v) => selected = v,
              ),
            ),
          ],
        ),
      );
    },
  );
  if (picked == null) return null;
  return TimeOfDay(hour: picked.hour, minute: picked.minute);
}
