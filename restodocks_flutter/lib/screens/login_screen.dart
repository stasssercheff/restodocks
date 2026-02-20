import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';

/// Экран входа в систему
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.returnTo});

  /// Путь для перехода после успешного входа (сохранение места при F5)
  final String? returnTo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _rememberCredentials = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadRememberedCredentials();
      });
    });
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : null,
        title: Text(loc.t('login')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => _showLanguagePicker(context, loc),
            tooltip: loc.t('language'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
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
        autocorrect: false,
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
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: loc.t('password'),
          hintText: loc.t('enter_password'),
          prefixIcon: const Icon(Icons.lock),
        ),
        obscureText: true,
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
      const SizedBox(height: 8),
      CheckboxListTile(
        value: _rememberCredentials,
        onChanged: (v) => setState(() => _rememberCredentials = v ?? true),
        title: Text(loc.t('remember_credentials'), style: Theme.of(context).textTheme.bodyMedium),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
      TextButton.icon(
        onPressed: _loadRememberedCredentials,
        icon: const Icon(Icons.restore, size: 18),
        label: Text(loc.t('fill_saved_credentials')),
      ),
      const SizedBox(height: 16),
      if (_errorMessage != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
        ),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: _isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(loc.t('login')),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => context.push('/register-company'),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(loc.t('register_company')),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => context.push('/register'),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(loc.t('register_employee')),
      ),
    ];
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

      final result = await accountManager.findEmployeeByEmailAndPasswordGlobal(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result == null) {
        if (mounted) setState(() => _errorMessage = loc.t('invalid_email_or_password'));
        return;
      }

      await accountManager.login(
        result.employee,
        result.establishment,
        rememberCredentials: _rememberCredentials,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        final target = widget.returnTo;
        if (target != null && target.startsWith('/') && !target.startsWith('/login')) {
          context.go(target);
        } else {
          context.go('/home');
        }
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