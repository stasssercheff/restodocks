import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран принятия приглашения соучредителем
class AcceptCoOwnerInvitationScreen extends StatefulWidget {
  const AcceptCoOwnerInvitationScreen({super.key, required this.token});

  final String token;

  @override
  State<AcceptCoOwnerInvitationScreen> createState() =>
      _AcceptCoOwnerInvitationScreenState();
}

class _AcceptCoOwnerInvitationScreenState
    extends State<AcceptCoOwnerInvitationScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _invitationData;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  Future<void> _loadInvitation() async {
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final invitation = await accountManager.supabase.client.rpc(
        'get_co_owner_invitation_by_token',
        params: {'p_token': widget.token},
      );

      if (!mounted) return;
      if (invitation == null) {
        final loc = context.read<LocalizationService>();
        setState(() {
          _error = loc.t('invitation_not_found_or_expired');
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _invitationData = invitation;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки приглашения: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation() async {
    if (_invitationData == null) return;

    setState(() => _isLoading = true);

    try {
      final accountManager = context.read<AccountManagerSupabase>();

      // Принимаем приглашение через защищенный RPC (без прямого UPDATE таблицы).
      await accountManager.supabase.client.rpc(
        'accept_co_owner_invitation',
        params: {'p_token': widget.token},
      );

      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('invitation_accepted'))),
        );
        context.go('/register-co-owner?token=${widget.token}');
      }
    } catch (e) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      setState(() {
        _error = '${loc.t('error')}: $e';
        _isLoading = false;
      });
    }
  }

  Widget _bodyWithScroll(Widget child) {
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
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(loc.t('invitation')),
        ),
        body: _bodyWithScroll(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                child: Text(loc.t('back_to_login')),
              ),
            ],
          ),
        ),
      );
    }

    final establishmentName = _invitationData!['establishments']['name'];

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('invitation'))),
      body: _bodyWithScroll(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.person_add, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              loc.t('co_owner_invitation_title') ??
                  'Приглашение стать соучредителем',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '${loc.t('establishment')}: $establishmentName',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('co_owner_invitation_description') ??
                  'Вы были приглашены стать соучредителем этого заведения. Примите приглашение, чтобы продолжить регистрацию.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _acceptInvitation,
              child: Text(loc.t('accept_invitation') ?? 'Принять приглашение'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/login'),
              child: Text(loc.t('decline')),
            ),
          ],
        ),
      ),
    );
  }
}
