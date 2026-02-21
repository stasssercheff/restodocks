import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';
import '../core/config/roles_config.dart';

/// Регистрация владельца после создания компании. PIN подставлен с предыдущего шага.
class OwnerRegistrationScreen extends StatefulWidget {
  const OwnerRegistrationScreen({super.key, required this.establishment});

  final Establishment establishment;

  @override
  State<OwnerRegistrationScreen> createState() => _OwnerRegistrationScreenState();
}

class _OwnerRegistrationScreenState extends State<OwnerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _selectedRole;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _roleKey(String code) => 'role_$code';

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
      final password = _passwordController.text;
<<<<<<< HEAD

      print('DEBUG: Raw email from controller: "${_emailController.text}"');
      print('DEBUG: Trimmed email: "$email"');
      print('DEBUG: Email is empty: ${email.isEmpty}');
      print('Owner registration: Checking email globally: $email');

      // ПРОВЕРКА НА ДУБЛИРОВАНИЕ EMAIL (глобально, так как establishment только что создан)
      final taken = await accountManager.isEmailTakenGlobally(email);
      print('Owner registration: Email taken result: $taken');
      print('DEBUG: taken is bool: ${taken is bool}, value: $taken');
      if (taken && mounted) {
        print('DEBUG: Email is taken, showing error message');
        final loc = context.read<LocalizationService>();
        setState(() => _errorMessage = loc.t('email_already_registered') ?? 'Этот email уже зарегистрирован в системе');
        setState(() => _isLoading = false);
        return;
      }

      print('DEBUG: Email check passed, proceeding with registration');
=======
>>>>>>> cf105ca (Добавлена отладка для поиска ошибки при регистрации)
      print('Owner registration: Creating employee for company...');
      final employee = await accountManager.createEmployeeForCompany(
        company: estab,
        fullName: _nameController.text.trim(),
        email: email,
        password: password,
        department: 'management',
        section: null,
        roles: roles,
      );

<<<<<<< HEAD
      print('DEBUG: Employee created successfully: ${employee?.fullName}, ${employee?.email}');
      await accountManager.login(employee, estab);
=======
      print('Owner registration: Employee created successfully: ${employee.fullName}, ID: ${employee.id}');
>>>>>>> cf105ca (Добавлена отладка для поиска ошибки при регистрации)

      // ВХОД В СИСТЕМУ
      print('Owner registration: Logging in...');
      await accountManager.login(employee, estab);
      print('Owner registration: Login successful, current employee: ${accountManager.currentEmployee?.fullName}');

      // Отправка письма владельцу
      context.read<EmailService>().sendRegistrationEmail(
        isOwner: true,
        to: email,
        companyName: estab.name,
        email: email,
        password: password,
        pinCode: estab.pinCode,
      );

      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      print('DEBUG: Owner registration error: $e');
      print('DEBUG: Owner registration error type: ${e.runtimeType}');
      print('DEBUG: Owner registration error stack trace: ${StackTrace.current}');
      final loc = context.read<LocalizationService>();
      final eStr = e.toString().toLowerCase();
      print('DEBUG: Owner registration error string: $eStr');
      if (eStr.contains('email_already_exists') ||
          eStr.contains('email already exists') ||
          eStr.contains('23505') ||
          eStr.contains('duplicate') ||
          eStr.contains('employees_email_key')) {
        print('DEBUG: Setting email already registered message');
        setState(() => _errorMessage = loc.t('email_already_registered') ?? 'Этот email уже зарегистрирован в системе');
      } else {
        print('DEBUG: Setting generic register error message');
        setState(() => _errorMessage = loc.t('register_error', args: {'error': e.toString()}));
      }
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

                Text(loc.t('role_optional'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: loc.t('role'),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(loc.t('role_optional'))),
                    ...RolesConfig.allRoles().map((role) =>
                      DropdownMenuItem(
                        value: role.roleCode,
                        child: Text(loc.t(_roleKey(role.roleCode))),
                      ),
                    ),
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
