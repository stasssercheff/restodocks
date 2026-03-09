import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/redirect_to_url_stub.dart'
    if (dart.library.html) '../core/redirect_to_url_web.dart' as redirect_impl;

/// Страница-прокладка: ссылка в письме ведёт сюда, чтобы prefetch почтового клиента
/// не исчерпывал одноразовый токен Supabase. Пользователь нажимает кнопку — только
/// тогда происходит редирект на Supabase verify.
class AuthConfirmClickScreen extends StatefulWidget {
  const AuthConfirmClickScreen({super.key, required this.redirectParam});

  /// Base64url-encoded Supabase verify URL (query param r)
  final String redirectParam;

  @override
  State<AuthConfirmClickScreen> createState() => _AuthConfirmClickScreenState();
}

class _AuthConfirmClickScreenState extends State<AuthConfirmClickScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.redirectParam.isEmpty) {
      _error = 'Неверная ссылка. Войдите по паролю.';
    }
  }

  void _onContinue() {
    if (widget.redirectParam.isEmpty) {
      context.go('/login');
      return;
    }
    try {
      String encoded = widget.redirectParam
          .replaceAll('-', '+')
          .replaceAll('_', '/');
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
                    onPressed: _onContinue,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Завершить регистрацию'),
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
