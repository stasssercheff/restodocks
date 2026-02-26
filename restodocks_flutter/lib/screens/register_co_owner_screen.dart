import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Регистрация соучредителя после принятия приглашения (employees.id = auth.users.id)
class RegisterCoOwnerScreen extends StatefulWidget {
  const RegisterCoOwnerScreen({super.key, required this.token});

  final String token;

  @override
  State<RegisterCoOwnerScreen> createState() => _RegisterCoOwnerScreenState();
}

class _RegisterCoOwnerScreenState extends State<RegisterCoOwnerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _invitationData;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final invitation = await accountManager.supabase.client
          .from('co_owner_invitations')
          .select('*, establishments(*)')
          .eq('invitation_token', widget.token)
          .eq('status', 'accepted')
          .single();

      if (mounted) setState(() => _invitationData = invitation);
    } catch (e) {
      if (mounted) setState(() => _error = 'Приглашение не найдено');
    }
  }

  Future<void> _register() async {
    if (_invitationData == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final email = _invitationData!['invited_email'] as String;
      final password = _passwordController.text;
      final establishment = _invitationData!['establishments'] as Map<String, dynamic>;
      final establishmentId = establishment['id'] as String;
      final estab = Establishment(
        id: establishmentId,
        name: establishment['name'] as String,
        pinCode: establishment['pin_code'] as String? ?? '',
        ownerId: '',
        defaultCurrency: establishment['default_currency'] as String? ?? 'RUB',
        createdAt: DateTime.parse(establishment['created_at'] as String),
        updatedAt: DateTime.parse(establishment['updated_at'] as String),
      );

      final accSupabase = accountManager as AccountManagerSupabase;
      final signUpResult = await accSupabase.signUpWithEmailForOwner(email, password);
      final authUserId = signUpResult.userId;
      if (authUserId == null) throw Exception('Не удалось создать учётную запись');

      final employee = await accountManager.createEmployeeForCompany(
        company: estab,
        fullName: _nameController.text.trim(),
        surname: null,
        email: email,
        password: password,
        department: 'management',
        section: null,
        roles: ['owner'],
        authUserId: authUserId,
      );

      if (!mounted) return;
      if (signUpResult.hasSession) {
        await accountManager.login(employee, estab);
        context.go('/home');
      } else {
        context.go('/confirm-email?email=${Uri.encodeComponent(email)}');
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (_invitationData == null && _error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null && _invitationData == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.t('register') ?? 'Регистрация')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(loc.t('back_to_login') ?? 'Назад к входу'),
              ),
            ],
          ),
        ),
      );
    }

    final email = _invitationData!['invited_email'] as String;

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('register') ?? 'Регистрация')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Email: $email', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: loc.t('full_name') ?? 'ФИО',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Введите ФИО' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: loc.t('password') ?? 'Пароль',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v?.length ?? 0) < 6 ? 'Минимум 6 символов' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(loc.t('register') ?? 'Зарегистрироваться'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
