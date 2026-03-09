import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/redirect_to_url_stub.dart'
    if (dart.library.html) '../core/redirect_to_url_web.dart' as redirect_impl;
import '../services/services.dart';

/// Страница-прокладка: ссылка в письме ведёт сюда (prefetch не тратит токен).
/// Пользователь нажимает кнопку — вызываем verifyOtp или редирект на Supabase.
class AuthConfirmClickScreen extends StatefulWidget {
  const AuthConfirmClickScreen({
    super.key,
    required this.redirectParam,
    this.tokenHash = '',
    this.otpType = '',
  });

  /// Legacy: Base64url-encoded Supabase verify URL (query param r)
  final String redirectParam;
  /// token_hash + type → verifyOtp (предпочтительный способ)
  final String tokenHash;
  final String otpType;

  @override
  State<AuthConfirmClickScreen> createState() => _AuthConfirmClickScreenState();
}

class _AuthConfirmClickScreenState extends State<AuthConfirmClickScreen> {
  String? _error;
  bool _loading = false;

  bool get _hasTokenHash => widget.tokenHash.isNotEmpty && widget.otpType.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!_hasTokenHash && widget.redirectParam.isEmpty) {
      _error = 'Неверная ссылка. Войдите по паролю.';
    }
  }

  Future<void> _onContinue() async {
    if (_loading) return;
    if (_hasTokenHash) {
      setState(() => _loading = true);
      try {
        final otpType = widget.otpType == 'signup' ? OtpType.signup : OtpType.magiclink;
        final res = await Supabase.instance.client.auth.verifyOtp(
          tokenHash: widget.tokenHash,
          type: otpType,
        );
        if (res.session != null) {
          await context.read<AccountManagerSupabase>().initialize(forceRetryFromAuth: true);
          if (!mounted) return;
          if (context.read<AccountManagerSupabase>().isLoggedInSync) {
            context.go('/home');
            return;
          }
        }
      } catch (e) {
        setState(() {
          _error = 'Ссылка истекла или уже использована. Войдите по паролю.';
          _loading = false;
        });
        return;
      }
      setState(() => _loading = false);
      if (!mounted) return;
      context.go('/login');
      return;
    }
    if (widget.redirectParam.isEmpty) {
      context.go('/login');
      return;
    }
    try {
      String encoded = widget.redirectParam.replaceAll('-', '+').replaceAll('_', '/');
      switch (encoded.length % 4) {
        case 2:
          encoded += '==';
          break;
        case 3:
          encoded += '=';
          break;
      }
      final bytes = base64Url.decode(encoded);
      final url = utf8.decode(bytes);
      if (url.startsWith('http://') || url.startsWith('https://')) {
        redirect_impl.redirectToUrl(url);
      } else {
        setState(() => _error = 'Неверная ссылка');
      }
    } catch (e) {
      setState(() => _error = 'Ссылка повреждена. Войдите по паролю.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_error != null) ...[
                  Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Войти'),
                  ),
                ] else ...[
                  Text(
                    'Для завершения регистрации нажмите кнопку:',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : () => _onContinue(),
                    icon: _loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_loading ? 'Вход...' : 'Завершить регистрацию'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ссылка одноразовая. Если письмо открывали ранее — войдите по паролю.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
