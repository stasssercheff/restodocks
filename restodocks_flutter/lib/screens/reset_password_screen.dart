import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран смены пароля по токену из письма
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  String get _token => widget.token ?? '';

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_token.isEmpty) {
      setState(() => _errorMessage = 'Токен не найден');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final loc = context.read<LocalizationService>();
    final result = await context.read<EmailService>().resetPasswordWithToken(
      _token,
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _success = result.ok;
      _errorMessage = result.error;
    });

    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('password_changed') ?? 'Пароль успешно изменён')),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (_token.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.t('reset_password') ?? 'Смена пароля')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  loc.t('invalid_reset_link') ?? 'Ссылка недействительна или устарела. Запросите новую.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: Text(loc.t('forgot_password') ?? 'Восстановление доступа'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('reset_password') ?? 'Смена пароля'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  loc.t('enter_new_password') ?? 'Введите новый пароль',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage == 'invalid_or_expired_token'
                        ? (loc.t('invalid_reset_link') ?? 'Ссылка недействительна или устарела')
                        : _errorMessage == 'password_min_6_chars'
                            ? (loc.t('password_min_6') ?? 'Пароль должен быть не менее 6 символов')
                            : _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc.t('new_password') ?? 'Новый пароль',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) return loc.t('password_min_6') ?? 'Минимум 6 символов';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc.t('confirm_password') ?? 'Подтвердите пароль',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v != _passwordController.text) return loc.t('passwords_mismatch') ?? 'Пароли не совпадают';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(loc.t('save') ?? 'Сохранить'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text(loc.t('back_to_login') ?? 'Вернуться к входу'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
