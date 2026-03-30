import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'legal_document_screen.dart';
import '../widgets/app_bar_home_button.dart';
import '../services/services.dart';

/// Экран входа в систему
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.redirectAfterLogin});

  /// URL для перехода после успешного входа (при обновлении страницы)
  final String? redirectAfterLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  bool _isUnconfirmedEmail = false;
  bool _isSendingLink = false;
  DateTime? _passwordFieldFocusedAt;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(_onPasswordFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadRememberedCredentials();
      });
    });
  }

  void _onPasswordFocusChange() {
    if (_passwordFocusNode.hasFocus) {
      _passwordFieldFocusedAt = DateTime.now();
    }
  }

  Future<void> _loadRememberedCredentials() async {
    final account = context.read<AccountManagerSupabase>();
    final saved = await account.loadRememberedCredentials();
    if (!mounted) return;
    if (saved.email != null && saved.email!.isNotEmpty) {
      _emailController.text = saved.email!;
    }
    if (saved.password != null && saved.password!.isNotEmpty) {
      _passwordController.text = saved.password!;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _passwordFocusNode.removeListener(_onPasswordFocusChange);
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading:
            GoRouter.of(context).canPop() ? appBarBackButton(context) : null,
        title: Text(loc.t('login')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => loc.showLocalePickerDialog(context),
            tooltip: loc.t('language'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildFormChildren(loc),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFormChildren(LocalizationService loc) {
    return [
      Text(
        loc.t('welcome'),
        style: Theme.of(context).textTheme.headlineMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        loc.t('enter_credentials'),
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 32),
      TextFormField(
        controller: _emailController,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: loc.t('email'),
          hintText: loc.t('enter_email'),
          prefixIcon: const Icon(Icons.email),
        ),
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
        validator: (value) {
          if (value == null || value.isEmpty) return loc.t('email_required');
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return loc.t('invalid_email');
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: loc.t('password'),
          hintText: loc.t('enter_password'),
          prefixIcon: const Icon(Icons.lock),
        ),
        obscureText: true,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) {
          if (_isLoading) return;
          // Вход только если пользователь сам нажал Enter: не сразу после фокуса (автозаполнение браузера вызывает submit без Enter).
          final focusedAt = _passwordFieldFocusedAt;
          if (focusedAt == null)
            return; // поле не получало фокус — скорее всего submit от автозаполнения
          if (DateTime.now().difference(focusedAt).inMilliseconds < 500) return;
          _login();
        },
        validator: (value) {
          if (value == null || value.isEmpty) return loc.t('password_required');
          if (value.length < 6) return loc.t('password_too_short');
          return null;
        },
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => context.push('/forgot-password'),
          child: Text(loc.t('forgot_password') ?? 'Забыли пароль?'),
        ),
      ),
      const SizedBox(height: 16),
      if (_errorMessage != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isUnconfirmedEmail
                ? Colors.orange.shade50
                : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _isUnconfirmedEmail
                    ? Colors.orange.shade200
                    : Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                _errorMessage!,
                style: TextStyle(
                  color: _isUnconfirmedEmail
                      ? Colors.orange.shade900
                      : Colors.red.shade700,
                  fontSize: 13,
                ),
                maxLines: 8,
              ),
              if (_isUnconfirmedEmail) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _isSendingLink ? null : _resendConfirmationLink,
                  icon: _isSendingLink
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.email_outlined, size: 18),
                  label: Text(loc.t('send_confirmation_link')),
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16)),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(loc.t('login')),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => _showRegistrationLegalDialog(
          onContinue: () => context.push('/register-company'),
        ),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(loc.t('register_company')),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => _showRegistrationLegalDialog(
          onContinue: () => context.push('/register'),
        ),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(loc.t('register_employee')),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _showPublicLegalLinksDialog,
        icon: const Icon(Icons.gavel_outlined),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        label: Text(loc.t('legal_offer_and_privacy_button')),
      ),
    ];
  }

  Future<void> _showPublicLegalLinksDialog() async {
    final loc = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('legal_documents')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/legal/offer');
                },
                child: Text(loc.t('public_offer')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/legal/privacy');
                },
                child: Text(loc.t('privacy_policy')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRegistrationLegalDialog({
    required VoidCallback onContinue,
  }) async {
    final loc = context.read<LocalizationService>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('before_registration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.t('registration_accepts_prefix'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _openLegalFromRegistrationDialog(
                  ctx,
                  LegalDocumentType.publicOffer,
                ),
                child: Text(
                  loc.t('offer_read'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                loc.t('and_short'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => _openLegalFromRegistrationDialog(
                  ctx,
                  LegalDocumentType.privacyPolicy,
                ),
                child: Text(
                  loc.t('privacy_policy_read'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(loc.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(loc.t('continue_action')),
            ),
          ],
        );
      },
    );
    if (accepted == true && mounted) onContinue();
  }

  Future<void> _openLegalFromRegistrationDialog(
    BuildContext dialogContext,
    LegalDocumentType type,
  ) async {
    await Navigator.of(dialogContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LegalDocumentScreen(type: type),
      ),
    );
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isUnconfirmedEmail = false;
    });

    try {
      // На web: дать браузеру время дописать автозаполнение в поля.
      // Иначе первый запрос может уйти с пустым/устаревшим паролем → 401.
      if (kIsWeb) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
      }

      final accountManager = context.read<AccountManagerSupabase>();
      final loc = context.read<LocalizationService>();
      final uiLang = loc.currentLanguageCode;

      final result = await accountManager
          .findEmployeeByEmailAndPasswordGlobal(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('login'),
      );

      if (result == null) {
        if (mounted) {
          final am = context.read<AccountManagerSupabase>();
          final detail = am.lastLoginError ?? '';
          final unconfirmed = _isUnconfirmedError(detail);
          final serviceDown = _isServiceUnavailableError(detail);
          // Не показывать технические детали для неверного пароля — только понятное сообщение
          final isInvalidCredentials = _isInvalidCredentialsError(detail);
          setState(() {
            _isUnconfirmedEmail = unconfirmed;
            if (serviceDown) {
              _errorMessage = _loginServiceUnavailableMessage(loc);
            } else {
              _errorMessage = unconfirmed
                  ? loc.t('email_not_confirmed_resend_prompt')
                  : (detail.isNotEmpty && !isInvalidCredentials
                      ? '${loc.t('invalid_email_or_password')}\n\n$detail'
                      : loc.t('invalid_email_or_password'));
            }
          });
        }
        return;
      }

      await accountManager.login(
        result.employee,
        result.establishment,
        rememberCredentials: false,
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        interfaceLanguageCode: uiLang,
      );

      if (mounted) {
        // Возврат на страницу, где был пользователь до выхода (после F5)
        final redirect = widget.redirectAfterLogin;
        final target = (redirect != null && redirect.isNotEmpty)
            ? Uri.decodeComponent(redirect)
            : '/home';
        context.go(target.startsWith('/') ? target : '/$target');
      }
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      if (e is TimeoutException) {
        final hint = loc.currentLanguageCode == 'ru'
            ? 'Сервер не ответил вовремя. Проверьте интернет, VPN или блокировки.'
            : 'Server did not respond in time. Check network, VPN, or firewall.';
        setState(() {
          _isUnconfirmedEmail = false;
          _errorMessage = loc.t('login_error', args: {'error': hint});
        });
        return;
      }
      final errStr = e.toString();
      if (errStr.contains('employee_not_found')) {
        setState(() {
          _errorMessage = loc.t('employee_not_found_use_fix_script');
          _isUnconfirmedEmail = false;
        });
        return;
      }
      final unconfirmed = _isUnconfirmedError(errStr);
      if (unconfirmed) {
        setState(() {
          _isUnconfirmedEmail = true;
          _errorMessage = loc.t('email_not_confirmed_resend_prompt');
        });
        return;
      }
      final fallback = loc.t('invalid_email_or_password');
      final msg = _safeErrorString(
        e,
        fallback,
        confirmEmailMsg: loc.t('confirm_email_then_login'),
      );
      setState(() {
        _isUnconfirmedEmail = false;
        _errorMessage = (msg == fallback)
            ? msg
            : loc.t('login_error', args: {'error': msg});
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isUnconfirmedError(String text) {
    final s = text.toLowerCase();
    return s.contains('not confirmed') || s.contains('email_not_confirmed');
  }

  /// Проверяет, является ли ошибка типичной "неверный пароль" — технические детали пользователю не показываем.
  bool _isInvalidCredentialsError(String text) {
    final s = text.toLowerCase();
    return s.contains('invalid_credentials') ||
        s.contains('invalid login credentials') ||
        s.contains('legacy: 401 invalid credentials') ||
        s.contains('authapiexception');
  }

  /// 521/503/прокси — не путать с неверным паролем.
  bool _isServiceUnavailableError(String text) {
    final s = text.toLowerCase();
    return text == 'login_service_unavailable' ||
        s.contains('521') ||
        s.contains('522') ||
        s.contains('upstream_unavailable') ||
        s.contains('authretryablefetchexception') ||
        s.contains('load failed') && s.contains('auth/v1/token') ||
        s.contains('база данных временно недоступна') ||
        s.contains('database is temporarily unavailable');
  }

  String _loginServiceUnavailableMessage(LocalizationService loc) {
    return loc.currentLanguageCode == 'ru'
        ? 'Сервис входа временно недоступен (сеть или хостинг Supabase). '
            'Подождите несколько минут или попробуйте другую сеть. '
            'Коды 521/503 в консоли — это сбой до сервера, а не неверный пароль.'
        : 'Sign-in is temporarily unavailable (network or Supabase hosting). '
            'Wait a few minutes or try another connection. '
            'Errors 521/503 mean the server could not be reached — not a wrong password.';
  }

  Future<void> _resendConfirmationLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isSendingLink = true);
    try {
      final result = await EmailService().sendConfirmationLinkRequest(email);
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
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

  /// Безопасное преобразование ошибки в строку (избегаем JSNull на Web)
  /// Для ошибок Auth (400, invalid_grant) — [authErrorFallback]
  /// Для "Email not confirmed" — [confirmEmailMsg]
  String _safeErrorString(Object? e, String authErrorFallback,
      {String? confirmEmailMsg}) {
    if (e == null) return authErrorFallback;
    try {
      final s = e.toString().toLowerCase();
      if (s.isEmpty) return authErrorFallback;
      // Email не подтверждён — подсказка перейти по ссылке
      if ((s.contains('not confirmed') || s.contains('email_not_confirmed')) &&
          confirmEmailMsg != null) {
        return confirmEmailMsg;
      }
      // Неверный пароль / учётные данные (Auth, Edge Function 401)
      if (s.contains('invalid_credentials') ||
          s.contains('invalid login credentials') ||
          s.contains('invalid_grant') ||
          (s.contains('401') && s.contains('error'))) {
        return authErrorFallback;
      }
      // Ошибки Auth при 400/token
      if (s.contains('jsnull') || (s.contains('400') && s.contains('token'))) {
        return authErrorFallback;
      }
      return e.toString();
    } catch (_) {
      return authErrorFallback;
    }
  }

}
