import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/account_manager_supabase.dart';
import '../services/localization_service.dart';

String _locOr(
  LocalizationService loc,
  String key,
  String fallbackRu,
  String fallbackEn,
) {
  final s = loc.t(key);
  if (s != key) return s;
  return loc.currentLanguageCode == 'ru' ? fallbackRu : fallbackEn;
}

/// Краткое уведомление (кнопки выгрузки, отправки и т.п.): Lite — отдельный текст.
void showSubscriptionRequiredSnackBar(BuildContext context) {
  final loc = context.read<LocalizationService>();
  final isLite = context.read<AccountManagerSupabase>().isLiteTier;
  final msg = isLite
      ? _locOr(
          loc,
          'subscription_required_lite_body',
          'В тарифе Lite эта функция недоступна. Оформите подписку Pro или Ultra в настройках.',
          'This isn’t available on the Lite plan. Subscribe to Pro or Ultra in Settings.',
        )
      : _locOr(
          loc,
          'subscription_required_body',
          'Этот раздел доступен после оформления подписки. Подключить её можно в настройках.',
          'This section is available after you subscribe. You can enable it in Settings.',
        );
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Сообщение о необходимости подписки; на Lite — явно про тариф и апгрейд.
Future<void> showSubscriptionRequiredDialog(BuildContext context) {
  final loc = context.read<LocalizationService>();
  final isLite = context.read<AccountManagerSupabase>().isLiteTier;
  final title = isLite
      ? _locOr(
          loc,
          'subscription_required_lite_title',
          'Недоступно в Lite',
          'Not available on Lite',
        )
      : loc.t('subscription_required_title');
  final body = isLite
      ? _locOr(
          loc,
          'subscription_required_lite_body',
          'В бесплатном тарифе Lite этой функции нет. Оформите подписку Pro или Ultra — раздел «Подписка» в настройках.',
          'This feature isn’t included in the free Lite plan. Subscribe to Pro or Ultra in Settings.',
        )
      : loc.t('subscription_required_body');
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
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
