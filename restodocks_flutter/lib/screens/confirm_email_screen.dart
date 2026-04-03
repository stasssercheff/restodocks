import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Промежуточный экран после регистрации: «Подтвердите учётную запись».
/// Письмо с данными заведения и письмо со ссылкой (Auth Hook) уходят после регистрации;
/// при необходимости можно запросить ссылку повторно (Edge + запас auth.resend).
class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({
    super.key,
    required this.email,
    this.resendFailed = false,
  });

  final String email;
  /// Раньше: автодубль через Resend не ушёл. Сейчас дубля из приложения нет — флаг для текста-подсказки.
  final bool resendFailed;

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  bool _isSendingLink = false;

  Future<void> _resendConfirmationLink() async {
    if (widget.email.trim().isEmpty) return;
    setState(() => _isSendingLink = true);
    try {
      final loc = context.read<LocalizationService>();
      final result = await EmailService().sendConfirmationLinkRequest(
        widget.email.trim(),
        languageCode: loc.currentLanguageCode,
      );
      if (!mounted) return;
      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('confirmation_link_sent'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('confirmation_link_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingLink = false);
    }
  }

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
                loc.t('confirm_email_hint').replaceAll('{email}', widget.email),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (widget.resendFailed) ...[
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
                loc.t('confirm_email_check_spam'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: _isSendingLink ? null : _resendConfirmationLink,
                child: _isSendingLink
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(loc.t('send_confirmation_link')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
