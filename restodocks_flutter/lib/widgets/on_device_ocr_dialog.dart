import 'package:flutter/material.dart';

import '../services/localization_service.dart';

enum OnDeviceOcrHintKind { ttk, receipt }

Future<bool> showOnDeviceOcrEducationDialog(
  BuildContext context,
  LocalizationService loc, {
  required OnDeviceOcrHintKind kind,
}) async {
  final bodyKey = kind == OnDeviceOcrHintKind.ttk
      ? 'on_device_ocr_edu_ttk_body'
      : 'on_device_ocr_edu_receipt_body';
  final body = loc.t(bodyKey);
  final title = loc.t('on_device_ocr_edu_title');
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text(
          body,
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(loc.t('on_device_ocr_continue')),
        ),
      ],
    ),
  );
  return result == true;
}
