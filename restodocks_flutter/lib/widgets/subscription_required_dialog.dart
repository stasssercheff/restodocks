import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

/// Сообщение о необходимости подписки (без названия конкретного тарифа — позже будут разные продукты).
Future<void> showSubscriptionRequiredDialog(BuildContext context) {
  final loc = context.read<LocalizationService>();
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.t('subscription_required_title')),
      content: Text(loc.t('subscription_required_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.push('/settings');
          },
          child: Text(loc.t('subscription_required_open_settings')),
        ),
      ],
    ),
  );
}
