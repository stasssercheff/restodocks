import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/localization_service.dart';

/// Почта поддержки (дублирует текст в локализации).
const kRestodocksSupportEmail = 'info@restodocks.com';

/// После успешной регистрации: условия бесплатного периода 72 ч и Pro, оплата, поддержка.
Future<void> showPostRegistrationTrialDialog(BuildContext context) async {
  final loc = context.read<LocalizationService>();
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(loc.t('post_registration_trial_title')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.t('post_registration_trial_intro'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              loc.t('post_registration_trial_free_heading'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('post_registration_trial_free_list'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 16),
            Text(
              loc.t('post_registration_trial_paid_heading'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('post_registration_trial_paid_list'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 16),
            Text(
              loc.t('post_registration_trial_footer'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final uri = Uri.parse('mailto:$kRestodocksSupportEmail');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                kRestodocksSupportEmail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
}
