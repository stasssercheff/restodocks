import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/clear_hash_stub.dart'
    if (dart.library.html) '../core/clear_hash_web.dart' as clear_hash;
import '../services/services.dart';

/// Экран обработки перехода по ссылке подтверждения email.
/// Supabase редиректит сюда с #access_token=... — восстанавливаем сессию и ведём в приложение.
class AuthConfirmScreen extends StatefulWidget {
  const AuthConfirmScreen({super.key});

  @override
  State<AuthConfirmScreen> createState() => _AuthConfirmScreenState();
}

class _AuthConfirmScreenState extends State<AuthConfirmScreen> {
  String _status = '';
  bool _showLoginButton = false;

  @override
  void initState() {
    super.initState();
    _processCallback();
  }

  Future<void> _processCallback() async {
    if (!mounted) return;

    // Supabase при ошибке редиректит с #error=access_denied&error_code=otp_expired
    final fragment = Uri.base.fragment;
    if (fragment.contains('error=') &&
        (fragment.contains('otp_expired') || fragment.contains('access_denied'))) {
      setState(() {
        _status = 'Ссылка истекла или уже использована. Войдите, используя email и пароль.';
        _showLoginButton = true;
      });
      clear_hash.clearHashFromUrl();
      return;
    }

    setState(() => _status = 'Вход в аккаунт...');

    final account = context.read<AccountManagerSupabase>();

    // Даём Supabase время обработать hash (#access_token=...) при detectSessionInUri
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await account.initialize();
    if (!mounted) return;

    if (account.isLoggedInSync) {
      clear_hash.clearHashFromUrl();
      if (!mounted) return;
      context.go('/home');
      return;
    }

    // Повторная попытка — иногда сессия восстанавливается с задержкой
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await account.initialize();

    if (!mounted) return;
    if (account.isLoggedInSync) {
      clear_hash.clearHashFromUrl();
      if (!mounted) return;
      context.go('/home');
      return;
    }

    setState(() {
      _status = 'Сессия не восстановлена.';
      _showLoginButton = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_showLoginButton) const CircularProgressIndicator(),
              if (_showLoginButton)
                Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(_status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              if (_showLoginButton) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Войти'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
