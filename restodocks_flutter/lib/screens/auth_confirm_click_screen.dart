import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/redirect_to_url_stub.dart'
    if (dart.library.html) '../core/redirect_to_url_web.dart' as redirect_impl;
import '../services/services.dart';

/// Ссылка в письме ведёт сюда. Сразу вызываем verifyOTP (одноразовый токен), при успехе — /home.
class AuthConfirmClickScreen extends StatefulWidget {
  const AuthConfirmClickScreen({
    super.key,
    required this.redirectParam,
    this.tokenHash = '',
    this.otpType = '',
    this.languageCode = '',
  });

  /// Legacy: Base64url-encoded Supabase verify URL (query param r)
  final String redirectParam;
  /// token_hash + type → verifyOtp (предпочтительный способ)
  final String tokenHash;
  final String otpType;
  final String languageCode;

  @override
  State<AuthConfirmClickScreen> createState() => _AuthConfirmClickScreenState();
}

class _AuthConfirmClickScreenState extends State<AuthConfirmClickScreen> {
  String? _error;

  bool get _hasTokenHash => widget.tokenHash.isNotEmpty && widget.otpType.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final lang = widget.languageCode.trim().toLowerCase();
    if (lang.isNotEmpty && LocalizationService.isSupportedLanguageCode(lang)) {
      await LocalizationService().setLocale(Locale(lang));
    }
    if (!mounted) return;
    if (_hasTokenHash) {
      _performVerify();
    } else if (widget.redirectParam.isNotEmpty) {
      _handleLegacyRedirect();
    } else {
      _error = 'Неверная ссылка. Войдите по паролю.';
    }
  }

  Future<void> _performVerify() async {
    if (!_hasTokenHash) return;
    final account = context.read<AccountManagerSupabase>();
    final router = GoRouter.of(context);
    try {
      final otpType = widget.otpType == 'signup' ? OtpType.signup : OtpType.magiclink;
      final res = await Supabase.instance.client.auth.verifyOTP(
        tokenHash: widget.tokenHash,
        type: otpType,
      );
      if (res.session != null) {
        // Retry до 4 раз: complete_pending_owner и загрузка employee могут занять время
        for (var i = 0; i < 4; i++) {
          if (!mounted) return;
          await account.initialize(forceRetryFromAuth: true);
          if (!mounted) return;
          if (account.isLoggedInSync) {
            final lang = widget.languageCode.trim().toLowerCase();
            if (lang.isNotEmpty && LocalizationService.isSupportedLanguageCode(lang)) {
              await account.savePreferredLanguage(lang);
              await LocalizationService().setLocale(Locale(lang));
            }
            if (!mounted) return;
            router.go('/home');
            return;
          }
          if (i < 3) {
            await Future.delayed(Duration(milliseconds: 400 * (i + 2))); // 800, 1200, 1600 ms
          }
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ссылка истекла или уже использована. Войдите по паролю.';
      });
      return;
    }
    router.go('/login');
  }

  void _handleLegacyRedirect() {
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
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text('Вход...', style: Theme.of(context).textTheme.bodyLarge),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
