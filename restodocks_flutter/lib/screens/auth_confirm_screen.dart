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

  @override
  void initState() {
    super.initState();
    _processCallback();
  }

  Future<void> _processCallback() async {
    if (!mounted) return;
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

    setState(() => _status = 'Сессия не восстановлена. Переход на вход...');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
