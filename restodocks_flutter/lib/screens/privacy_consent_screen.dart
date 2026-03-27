import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, this.nextPath});

  final String? nextPath;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _accept() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loc = context.read<LocalizationService>();
      await context.read<PrivacyPolicyConsentService>().acceptCurrentVersion(
            locale: loc.currentLanguageCode,
          );
      if (!mounted) return;
      final target = (widget.nextPath != null && widget.nextPath!.isNotEmpty)
          ? widget.nextPath!
          : '/home';
      context.go(target.startsWith('/') ? target : '/$target');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AccountManagerSupabase>().logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Privacy Policy'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Перед началом работы нужно принять Политику конфиденциальности.',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SingleChildScrollView(
                    child: SelectableText(_privacyPolicyTextRu),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _accept,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Принять и продолжить'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _loading ? null : _logout,
                child: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const String _privacyPolicyTextRu = '''
PRIVACY POLICY (Политика конфиденциальности)
Версия 1.0

Оператор: Ребриков Станислав Александрович.
Контакт по вопросам данных: info@restodocks.com.

Мы обрабатываем данные, которые вы предоставляете при регистрации и работе в сервисе:
- данные аккаунта (email, имя, роль, идентификатор пользователя);
- данные заведения и рабочие данные (номенклатура, ТТК, инвентаризация, заказы, документы);
- служебные технические данные (логи, ошибки, кэш, черновики).

Цели обработки:
- предоставление доступа к функционалу сервиса;
- хранение и синхронизация рабочих данных заведения;
- обеспечение безопасности и предотвращение злоупотреблений;
- улучшение качества и стабильности сервиса.

Данные могут обрабатываться инфраструктурными провайдерами, необходимыми для работы сервиса
(база данных, хостинг, хранилище файлов, email и AI-сервисы по запросу пользователя).

Мы не продаем персональные данные третьим лицам.

Пользователь вправе запросить доступ, исправление или удаление данных в пределах применимого законодательства.

Нажимая «Принять и продолжить», вы подтверждаете согласие с Политикой конфиденциальности.
''';
