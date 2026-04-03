import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Промежуточный экран после регистрации: «Подтвердите учётную запись».
/// Письмо с PIN и письмо со ссылкой отправляются автоматически после регистрации (без кнопок повторной отправки).
class ConfirmEmailScreen extends StatelessWidget {
  const ConfirmEmailScreen({
    super.key,
    required this.email,
    this.resendFailed = false,
  });

  final String email;
  /// Дублирующее письмо через Resend не ушло (сеть / Edge / API).
  final bool resendFailed;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('confirm_email_title')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.mark_email_read_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                loc.t('confirm_email_title'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                loc.t('confirm_email_hint').replaceAll('{email}', email),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (resendFailed) ...[
                const SizedBox(height: 16),
                Material(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      loc.t('confirm_email_resend_failed'),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.t('confirm_email_steps'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('1. ${loc.t('confirm_email_step1')}', style: Theme.of(context).textTheme.bodyMedium),
                    Text('2. ${loc.t('confirm_email_step2')}', style: Theme.of(context).textTheme.bodyMedium),
                    Text('3. ${loc.t('confirm_email_step3')}', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                loc.t('confirm_email_check_spam') ?? 'Если письмо со ссылкой не пришло — проверьте папку «Спам».',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
