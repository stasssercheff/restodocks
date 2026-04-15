import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

String _stripTierPrice(String title) {
  return title.replaceFirst(
    RegExp(r'\s*[-–—]\s*\d+(?:[.,]\d+)?\s*\$.*$'),
    '',
  ).trimRight();
}

/// Полное описание тарифов Lite / Pro / Ultra и расширений (из локализации).
Future<void> showSubscriptionPlansDialog(BuildContext context) async {
  final loc = context.read<LocalizationService>();
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.t('subscription_plans_dialog_title')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _stripTierPrice(loc.t('subscription_tier_lite_title')),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('subscription_tier_lite_features'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.38),
            ),
            const SizedBox(height: 16),
            Text(
              _stripTierPrice(loc.t('subscription_tier_pro_title')),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('subscription_tier_pro_features'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.38),
            ),
            const SizedBox(height: 16),
            Text(
              _stripTierPrice(loc.t('subscription_tier_ultra_title')),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('subscription_tier_ultra_features'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.38),
            ),
            const SizedBox(height: 16),
            Text(
              loc.t('subscription_tier_addons_title'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('subscription_tier_addons_features'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.38),
            ),
            const SizedBox(height: 16),
            Text(
              loc.t('subscription_plans_employee_cap_note'),
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.38,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.t('subscription_plans_trial_72h_note'),
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.38,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(loc.t('close')),
        ),
      ],
    ),
  );
}
