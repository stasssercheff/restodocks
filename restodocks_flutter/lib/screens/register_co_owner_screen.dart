import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/pending_co_owner_registration.dart';
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
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _passwordController = TextEditingController();
  DateTime? _birthday;
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
    _firstNameController.dispose();
    _surnameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final raw = await accountManager.supabase.client.rpc(
        'get_co_owner_invitation_by_token',
        params: {'p_token': widget.token},
      );
      if (raw != null && mounted) {
        setState(() => _invitationData = Map<String, dynamic>.from(raw as Map));
      } else if (mounted) {
        setState(() => _error = 'Приглашение не найдено или истекло');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Приглашение не найдено');
    }
  }

  Map<String, dynamic> _rpcParams(String token) {
    final params = <String, dynamic>{
      'p_invitation_token': token,
      'p_full_name': _firstNameController.text.trim(),
      'p_surname': _surnameController.text.trim().isEmpty
          ? null
          : _surnameController.text.trim(),
    };
    if (_birthday != null) {
      final d = _birthday!;
      params['p_birthday'] =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return params;
  }

  Future<void> _register() async {
    if (_invitationData == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final interfaceLang = context.read<LocalizationService>().currentLanguageCode;
      final email = _invitationData!['invited_email'] as String;
      final password = _passwordController.text;
      final token = widget.token;
      final establishment = Map<String, dynamic>.from(
        _invitationData!['establishments'] as Map<dynamic, dynamic>,
      );

      final accSupabase = accountManager;
      final signUpResult = await accSupabase.signUpWithEmailForOwner(
        email,
        password,
        interfaceLanguageCode: interfaceLang,
      );
      if (signUpResult.userId == null) throw Exception('Не удалось создать учётную запись');

      if (!signUpResult.hasSession) {
        await PendingCoOwnerRegistration.save(
          email: email,
          token: token,
          firstName: _firstNameController.text.trim(),
          surname: _surnameController.text.trim(),
          birthday: _birthday,
        );
        final dup = await EmailService().sendConfirmationLinkRequest(
          email,
          languageCode: interfaceLang,
          password: password,
        );
        if (!mounted) {
          return;
        }
        setState(() => _isLoading = false);
        final q =
            'email=${Uri.encodeComponent(email)}&resendFailed=${dup.ok ? '0' : '1'}';
        context.go('/confirm-email?$q');
        if (!dup.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dup.error ??
                    'Не удалось отправить дублирующее письмо. Проверьте настройки почты.',
              ),
            ),
          );
        }
        return;
      }

      await PendingCoOwnerRegistration.clear();

      final empRaw = await accSupabase.supabase.client.rpc(
        'create_co_owner_from_invitation',
        params: _rpcParams(token),
      );
      final empMap = Map<String, dynamic>.from(empRaw as Map<dynamic, dynamic>);
      empMap['password'] = '';
      final employee = Employee.fromJson(empMap);
      final estab = Establishment(
        id: establishment['id'] as String,
        name: establishment['name'] as String,
        pinCode: establishment['pin_code'] as String? ?? '',
        ownerId: establishment['owner_id']?.toString() ?? '',
        address: establishment['address']?.toString(),
        innBin: establishment['inn_bin']?.toString(),
        defaultCurrency: establishment['default_currency'] as String? ?? 'RUB',
        createdAt: DateTime.parse(establishment['created_at'] as String),
        updatedAt: DateTime.parse(establishment['updated_at'] as String),
      );

      if (!mounted) {
        return;
      }
      await accountManager.login(
        employee,
        estab,
        interfaceLanguageCode: interfaceLang,
      );
      if (!mounted) {
        return;
      }
      context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Widget _scrollableCenteredBody(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight -
                    MediaQuery.of(context).padding.vertical -
                    48,
                maxWidth: 440,
              ),
              child: Center(
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (_invitationData == null && _error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null && _invitationData == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(loc.t('register')),
          actions: [
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: loc.t('language'),
              onPressed: () => loc.showLocalePickerDialog(context),
            ),
          ],
        ),
        body: _scrollableCenteredBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(loc.t('back_to_login')),
              ),
            ],
          ),
        ),
      );
    }

    final email = _invitationData!['invited_email'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('register')),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: loc.t('language'),
            onPressed: () => loc.showLocalePickerDialog(context),
          ),
        ],
      ),
      body: _scrollableCenteredBody(
        Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Email: $email',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: loc.t('name'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? loc.t('enter_name') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _surnameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: loc.t('surname'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? loc.t('enter_surname') : null,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cake_outlined, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  _birthday == null
                      ? '${loc.t('birthday')} — ${loc.t('not_specified')}'
                      : '${loc.t('birthday')}: ${_birthday!.day.toString().padLeft(2, '0')}.${_birthday!.month.toString().padLeft(2, '0')}.${_birthday!.year}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_birthday != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _birthday = null),
                        tooltip: loc.t('clear'),
                      ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _birthday ??
                              DateTime.now().subtract(const Duration(days: 365 * 25)),
                          firstDate: DateTime(1920),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null && mounted) setState(() => _birthday = picked);
                      },
                      child: Text(_birthday == null ? loc.t('set') : loc.t('change')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: loc.t('password'),
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
                    : Text(loc.t('register')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
