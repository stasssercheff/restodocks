import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Промежуточный экран после регистрации: «Подтвердите учётную запись».
/// После перехода по ссылке из письма Supabase вернёт пользователя в приложение с сессией.
class ConfirmEmailScreen extends StatelessWidget {
  const ConfirmEmailScreen({super.key, required this.email});

  final String email;

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
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
              const Spacer(),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(loc.t('go_to_login')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
