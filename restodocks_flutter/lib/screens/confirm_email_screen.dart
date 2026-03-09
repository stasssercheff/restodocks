import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Промежуточный экран после регистрации: «Подтвердите учётную запись».
/// Письмо с PIN приходит без ссылки (чтобы не падало в спам). Ссылку можно запросить кнопкой.
class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  bool _sending = false;

  Future<void> _sendLink() async {
    if (_sending) return;
    setState(() => _sending = true);
    final result = await EmailService().sendConfirmationLinkRequest(widget.email);
    if (!mounted) return;
    setState(() => _sending = false);
    final loc = context.read<LocalizationService>();
    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('confirm_link_sent') ?? 'Ссылка отправлена. Проверьте почту.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Ошибка отправки'), backgroundColor: Colors.red),
      );
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _sending ? null : _sendLink,
                icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: Text(_sending ? (loc.t('sending') ?? 'Отправка...') : (loc.t('send_confirm_link') ?? 'Отправить ссылку подтверждения')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const SizedBox(height: 16),
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
