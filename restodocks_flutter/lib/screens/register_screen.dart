import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/config/roles_config.dart';
import '../services/services.dart';

/// Регистрация сотрудника: имя, фамилия (pro), почта, пароль, PIN, подразделение → цех → должность.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _pinController = TextEditingController();

  String _department = 'kitchen';
  String _section = 'control';
  String _role = 'sous_chef';

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _updateRoleFromSection();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _updateRoleFromSection() {
    if (_department == 'kitchen') {
      final roles = RolesConfig.kitchenRolesForSection(_section);
      if (roles.isNotEmpty && !roles.any((r) => r.roleCode == _role)) {
        _role = roles.first.roleCode;
      } else if (roles.isEmpty) {
        _role = 'cook'; // fallback role
      }
    } else if (_department == 'bar') {
      final roles = RolesConfig.barRoles();
      if (roles.isNotEmpty) {
        _role = roles.first.roleCode;
      } else {
        _role = 'bartender'; // fallback role
      }
    } else if (_department == 'dining_room') {
      final roles = RolesConfig.hallRoles();
      if (roles.isNotEmpty) {
        _role = roles.first.roleCode;
      } else {
        _role = 'waiter'; // fallback role
      }
    } else if (_department == 'management') {
      final roles = RolesConfig.managementRoles();
      if (roles.isNotEmpty) {
        _role = roles.first.roleCode;
      } else {
        _role = 'manager'; // fallback role
      }
    }
  }

  String _roleKey(String code) => 'role_$code';
  String _sectionKey(String code) => 'section_$code';

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final pin = _pinController.text.trim().toUpperCase();
      final establishment = await accountManager.findEstablishmentByPinCode(pin);

      if (establishment == null) {
        if (!mounted) return;
        final loc = context.read<LocalizationService>();
        setState(() => _errorMessage = loc.t('company_not_found'));
        return;
      }

      final email = _emailController.text.trim();

      // Проверяем, занят ли email глобально (email должен быть уникальным во всех заведениях)
      final emailTakenGlobally = await accountManager.isEmailTakenGlobally(email);
      if (emailTakenGlobally) {
        if (!mounted) return;
        final loc = context.read<LocalizationService>();
        setState(() => _errorMessage = loc.t('email_already_registered_globally'));
        return;
      }

      // Также проверяем в рамках заведения (на всякий случай)
      final emailTakenInEstablishment = await accountManager.isEmailTakenInEstablishment(email, establishment.id);
      if (emailTakenInEstablishment) {
        if (!mounted) return;
        final loc = context.read<LocalizationService>();
        setState(() => _errorMessage = loc.t('email_already_registered'));
        return;
      }

      final name = _nameController.text.trim();
      final surname = _surnameController.text.trim();
      final fullName = surname.isEmpty ? name : '$name $surname';

      final section = _department == 'kitchen' ? _section : null;

      final password = _passwordController.text;
      final employee = await accountManager.createEmployeeForCompany(
        company: establishment,
        fullName: fullName,
        email: email,
        password: password,
        department: _department,
        section: section,
        roles: [_role],
      );

      await accountManager.login(employee, establishment);

      // Отправка письма сотруднику
      final emailService = EmailService();
      emailService.sendRegistrationEmail(
        isOwner: false,
        to: email,
        companyName: establishment.name,
        email: email,
        password: password,
      );

      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      setState(() => _errorMessage = loc.t('register_error', args: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('register_employee')),
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
                  controller: _surnameController,
                  decoration: InputDecoration(
                    labelText: '${loc.t('surname')} (Pro)',
                    hintText: loc.t('enter_surname'),
                    prefixIcon: const Icon(Icons.badge),
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

                TextFormField(
                  controller: _pinController,
                  decoration: InputDecoration(
                    labelText: loc.t('company_pin'),
                    hintText: loc.t('enter_company_pin'),
                    prefixIcon: const Icon(Icons.pin),
                  ),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return loc.t('company_pin_required');
                    if (v.trim().length != 8) return loc.t('pin_must_be_8_chars');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _department,
                  decoration: InputDecoration(
                    labelText: loc.t('department'),
                    prefixIcon: const Icon(Icons.work),
                  ),
                  items: [
                    _deptItem(loc, 'kitchen', loc.t('kitchen')),
                    _deptItem(loc, 'bar', loc.t('bar')),
                    _deptItem(loc, 'dining_room', loc.t('dining_room')),
                    _deptItem(loc, 'management', loc.t('management')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _department = v;
                      if (v == 'kitchen') {
                        _section = RolesConfig.kitchenSections().first;
                      }
                      _updateRoleFromSection();
                    });
                  },
                  validator: (v) => v == null || v.isEmpty ? loc.t('department_required') : null,
                ),

                if (_department == 'kitchen') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _section,
                    decoration: InputDecoration(
                      labelText: loc.t('kitchen_section'),
                      prefixIcon: const Icon(Icons.restaurant),
                    ),
                    items: RolesConfig.kitchenSections().map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(loc.t(_sectionKey(s))),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _section = v;
                        _updateRoleFromSection();
                      });
                    },
                  ),
                ],

                const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                  decoration: InputDecoration(
                    labelText: loc.t('role'),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                  items: _roleItems(loc),
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                  validator: (v) => v == null || v.isEmpty ? loc.t('role_required') : null,
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

  DropdownMenuItem<String> _deptItem(LocalizationService loc, String value, String label) {
    return DropdownMenuItem(value: value, child: Text(label));
  }

  List<DropdownMenuItem<String>> _roleItems(LocalizationService loc) {
    List<SectionRole> roles;
    switch (_department) {
      case 'kitchen':
        roles = RolesConfig.kitchenRolesForSection(_section);
        break;
      case 'bar':
        roles = RolesConfig.barRoles();
        break;
      case 'dining_room':
        roles = RolesConfig.hallRoles();
        break;
      case 'management':
        roles = RolesConfig.managementRoles();
        break;
      default:
        roles = [];
    }
    return roles
        .map((r) => DropdownMenuItem(
              value: r.roleCode,
              child: Text(loc.t(_roleKey(r.roleCode))),
            ))
        .toList();
  }
}
