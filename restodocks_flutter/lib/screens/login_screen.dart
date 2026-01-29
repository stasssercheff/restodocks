import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// Экран входа в систему
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyPinController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _companyPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : null,
        title: Text(localization.t('login')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => _showLanguagePicker(context, localization),
            tooltip: localization.t('language'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: localization.t('home'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Заголовок
                Text(
                  localization.t('welcome'),
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  localization.t('enter_credentials'),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Поле PIN компании
                TextFormField(
                  controller: _companyPinController,
                  decoration: InputDecoration(
                    labelText: localization.t('company_pin'),
                    hintText: localization.t('enter_company_pin'),
                    prefixIcon: const Icon(Icons.business),
                  ),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localization.t('company_pin_required');
                    }
                    if (value.length != 8) {
                      return localization.t('pin_must_be_8_chars');
                    }
                    return null;
                  },
                  onChanged: (value) {
                    _companyPinController.text = value.toUpperCase();
                    _companyPinController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _companyPinController.text.length),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Поле email
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: localization.t('email'),
                    hintText: localization.t('enter_email'),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localization.t('email_required');
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                      return localization.t('invalid_email');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Поле пароля
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: localization.t('password'),
                    hintText: localization.t('enter_password'),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localization.t('password_required');
                    }
                    if (value.length < 6) {
                      return localization.t('password_too_short');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Сообщение об ошибке
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),

                const SizedBox(height: 24),

                // Кнопка входа
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(localization.t('login')),
                ),

                const SizedBox(height: 16),

                OutlinedButton(
                  onPressed: () => context.push('/register-company'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(localization.t('register_company')),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/register'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(localization.t('register_employee')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final loc = context.read<LocalizationService>();

      // Находим компанию по PIN
      final establishment = await accountManager.findEstablishmentByPinCode(
        _companyPinController.text.trim(),
      );

      if (establishment == null) {
        if (mounted) setState(() => _errorMessage = loc.t('company_not_found'));
        return;
      }

      final employee = await accountManager.findEmployeeByEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        company: establishment,
      );

      if (employee == null) {
        if (mounted) setState(() => _errorMessage = loc.t('invalid_email_or_password'));
        return;
      }

      await accountManager.login(employee, establishment);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      setState(() {
        _errorMessage = loc.t('login_error', args: {'error': e.toString()});
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLanguagePicker(BuildContext context, LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 400),
              decoration: BoxDecoration(
                color: Theme.of(ctx).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      loc.t('language'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: LocalizationService.supportedLocales.map((locale) {
                        final selected = loc.currentLocale.languageCode == locale.languageCode;
                        return ListTile(
                          leading: Text(
                            _flag(locale.languageCode),
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(loc.getLanguageName(locale.languageCode)),
                          selected: selected,
                          onTap: () async {
                            await loc.setLocale(locale);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _flag(String code) {
    switch (code) {
      case 'ru': return '🇷🇺';
      case 'en': return '🇺🇸';
      case 'es': return '🇪🇸';
      case 'de': return '🇩🇪';
      case 'fr': return '🇫🇷';
      default: return '🏳️';
    }
  }
}