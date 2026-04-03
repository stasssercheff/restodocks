import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/pending_owner_role.dart';
import '../services/services.dart';
import '../utils/person_name_format.dart';
import '../models/models.dart';

/// Регистрация владельца после создания компании. PIN подставлен с предыдущего шага.
class OwnerRegistrationScreen extends StatefulWidget {
  const OwnerRegistrationScreen({super.key, required this.establishment});

  final Establishment establishment;

  @override
  State<OwnerRegistrationScreen> createState() => _OwnerRegistrationScreenState();
}

String _ownerRegisterErrorMessage(Object e, LocalizationService loc) {
  final s = e.toString().toLowerCase();
  if (s.contains('over_email_send_rate_limit') ||
      s.contains('email rate limit exceeded') ||
      s.contains('over_request_rate_limit') ||
      s.contains('too many requests') ||
      s.contains('429') ||
      s.contains('rate limit')) {
    return loc.t('auth_email_rate_limit');
  }
  return loc.t('register_error', args: {'error': e.toString()});
}

class _OwnerRegistrationScreenState extends State<OwnerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _selectedRole;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final estab = widget.establishment;
      final roles = _selectedRole != null && _selectedRole!.isNotEmpty
          ? ['owner', _selectedRole!]
          : ['owner'];

      final email = _emailController.text.trim();
      await PendingOwnerRole.saveForOwner(
        email: email,
        establishmentId: estab.id,
        role: _selectedRole,
      );
      final nameStr = formatPersonNameField(_nameController.text);
      final surnameStr = formatPersonNameField(_surnameController.text);
      final fullName =
          surnameStr.isEmpty ? nameStr : '$nameStr $surnameStr';
      final registeredAtLocal = DateTime.now().toLocal().toString();

      // Проверяем, занят ли email глобально (email должен быть уникальным во всех заведениях)
      final emailTakenGlobally = await accountManager.isEmailTakenGlobally(email);
      if (emailTakenGlobally) {
        if (!mounted) return;
        final loc = context.read<LocalizationService>();
        setState(() => _errorMessage = loc.t('email_already_registered_globally'));
        return;
      }

      final password = _passwordController.text;
      // 1. Supabase Auth
      final accSupabase = accountManager as AccountManagerSupabase;
      final signUpResult = await accSupabase.signUpWithEmailForOwner(
        email,
        password,
        interfaceLanguageCode: context.read<LocalizationService>().currentLanguageCode,
        positionRole: _selectedRole,
      );
      final authUserId = signUpResult.userId;
      if (authUserId == null) throw Exception('Не удалось создать учётную запись');

      // 2. Сохраняем pending — employee создадим после confirm (когда user в auth.users)
      final loc = context.read<LocalizationService>();
      // После signUp иногда auth.users ещё не “виден” в БД сразу (race),
      // поэтому делаем небольшой ретрай по P0001.
      final preferredLanguage = loc.currentLanguageCode;
      for (var attempt = 1; attempt <= 5; attempt++) {
        try {
          await accSupabase.savePendingOwnerRegistration(
            authUserId: authUserId,
            establishment: estab,
            fullName: nameStr,
            surname: surnameStr.isEmpty ? null : surnameStr,
            email: email,
            roles: roles,
            preferredLanguage: preferredLanguage,
          );
          break;
        } on PostgrestException catch (e) {
          final isAuthMismatch = e.code == 'P0001' ||
              e.message.toLowerCase().contains('auth user mismatch');
          if (!isAuthMismatch || attempt >= 5) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }

      // Инфо-письмо отправляем через Resend (best-effort, не блокирует регистрацию).
      unawaited(
        EmailService().sendRegistrationEmail(
          isOwner: true,
          to: email,
          companyName: estab.name,
          email: email,
          fullName: fullName,
          registeredAtLocal: registeredAtLocal,
          pinCode: estab.pinCode,
          languageCode: loc.currentLanguageCode,
        ),
      );
      var resendFailed = false;
      if (!signUpResult.hasSession) {
        // Нельзя unawaited: на web переход на /confirm-email рвёт запрос к Edge до отправки письма.
        final dup = await EmailService().sendConfirmationLinkRequest(
          email,
          languageCode: loc.currentLanguageCode,
          password: password,
        );
        resendFailed = !dup.ok;
      }

      if (!mounted) return;
      if (signUpResult.hasSession) {
        final result = await accSupabase.completePendingOwnerRegistration();
        if (result != null) {
          await accountManager.login(
            result.employee,
            result.establishment,
            interfaceLanguageCode: loc.currentLanguageCode,
          );
          context.go('/home');
        } else {
          // Без сессии после signUp письмо уже запросили выше; здесь — сессия есть, но pending
          // не завершился: на экран подтверждения всё равно нужна ссылка из письма.
          final dup = await EmailService().sendConfirmationLinkRequest(
            email,
            languageCode: loc.currentLanguageCode,
            password: password,
          );
          resendFailed = !dup.ok;
          final confirmQ =
              'email=${Uri.encodeComponent(email)}&resendFailed=${resendFailed ? '1' : '0'}';
          context.go('/confirm-email?$confirmQ');
        }
      } else {
        final confirmQ =
            'email=${Uri.encodeComponent(email)}&resendFailed=${resendFailed ? '1' : '0'}';
        context.go('/confirm-email?$confirmQ');
      }
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      setState(() => _errorMessage = _ownerRegisterErrorMessage(e, loc));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final pin = widget.establishment.pinCode;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('register_owner')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: loc.t('language'),
            onPressed: () => loc.showLocalePickerDialog(context),
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
                Text(
                  loc.t('employee_info'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: loc.t('name'),
                    hintText: loc.t('enter_name'),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return loc.t('name_required');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _surnameController,
                  decoration: InputDecoration(
                    labelText: loc.t('surname'),
                    hintText: loc.t('enter_surname'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: loc.t('email'),
                    hintText: loc.t('enter_email'),
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return loc.t('email_required');
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                      return loc.t('invalid_email');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: loc.t('password'),
                    hintText: loc.t('enter_password'),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return loc.t('password_required');
                    if (v.length < 6) return loc.t('password_too_short');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: loc.t('confirm_password'),
                    hintText: loc.t('confirm_password_hint'),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return loc.t('confirm_password_required');
                    if (v != _passwordController.text) return loc.t('passwords_not_match');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                Text(loc.t('company_pin'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    pin,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 20),

                Text(loc.t('position_optional'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: loc.t('position'),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(loc.t('owner_only'))),
                    DropdownMenuItem(value: 'executive_chef', child: Text(loc.t('role_executive_chef'))),
                    DropdownMenuItem(value: 'bar_manager', child: Text(loc.t('role_bar_manager'))),
                    DropdownMenuItem(value: 'floor_manager', child: Text(loc.t('role_floor_manager'))),
                    DropdownMenuItem(value: 'general_manager', child: Text(loc.t('role_general_manager'))),
                  ],
                  onChanged: (v) => setState(() => _selectedRole = v),
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                  const SizedBox(height: 16),
                ],

                FilledButton(
                  onPressed: _isLoading ? null : _register,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.t('register')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
