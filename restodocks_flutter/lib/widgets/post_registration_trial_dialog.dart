import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/account_manager_supabase.dart';
import '../services/localization_service.dart';

/// После входа по ссылке из письма: один раз на аккаунт, только для роли owner (не сотрудникам).
Future<void> maybeShowPostRegistrationTrialDialogAfterEmailLink(
  BuildContext context,
  AccountManagerSupabase account,
) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;
  final emp = account.currentEmployee;
  if (emp == null || !emp.hasRole('owner')) return;
  final prefs = await SharedPreferences.getInstance();
  final key = 'post_registration_trial_email_link_shown_$userId';
  if (prefs.getBool(key) == true) return;
  if (!context.mounted) return;
  await showPostRegistrationTrialDialog(context);
  if (!context.mounted) return;
  await prefs.setBool(key, true);
}

/// Условия бесплатного периода 72 ч и Pro, оплата, поддержка.
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
