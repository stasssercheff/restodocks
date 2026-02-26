import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран принятия приглашения соучредителем
class AcceptCoOwnerInvitationScreen extends StatefulWidget {
  const AcceptCoOwnerInvitationScreen({super.key, required this.token});

  final String token;

  @override
  State<AcceptCoOwnerInvitationScreen> createState() => _AcceptCoOwnerInvitationScreenState();
}

class _AcceptCoOwnerInvitationScreenState extends State<AcceptCoOwnerInvitationScreen> {
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
      final invitation = await accountManager.supabase.client
          .from('co_owner_invitations')
          .select('*, establishments(name)')
          .eq('invitation_token', widget.token)
          .eq('status', 'pending')
          .gt('expires_at', DateTime.now().toIso8601String())
          .single();

      if (invitation == null) {
        setState(() {
          _error = 'Приглашение не найдено или истекло';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _invitationData = invitation;
        _isLoading = false;
      });
    } catch (e) {
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

      // Обновляем статус приглашения (сотрудник создаётся на экране регистрации с id = auth.uid())
      await accountManager.supabase.client
          .from('co_owner_invitations')
          .update({'status': 'accepted', 'updated_at': DateTime.now().toIso8601String()})
          .eq('invitation_token', widget.token);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Приглашение принято! Теперь зарегистрируйтесь.')),
        );
        context.go('/register-co-owner?token=${widget.token}');
      }
    } catch (e) {
      setState(() {
        _error = 'Ошибка принятия приглашения: $e';
        _isLoading = false;
      });
    }
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
        ),
      );
    }

    final establishmentName = _invitationData!['establishments']['name'];

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('invitation'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              loc.t('co_owner_invitation_title') ?? 'Приглашение стать соучредителем',
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