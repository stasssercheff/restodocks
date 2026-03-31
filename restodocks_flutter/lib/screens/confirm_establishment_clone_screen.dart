import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/localization_service.dart';

/// Публичная страница подтверждения копирования данных по ссылке из письма.
class ConfirmEstablishmentCloneScreen extends StatefulWidget {
  const ConfirmEstablishmentCloneScreen({super.key, this.token});

  final String? token;

  @override
  State<ConfirmEstablishmentCloneScreen> createState() =>
      _ConfirmEstablishmentCloneScreenState();
}

class _ConfirmEstablishmentCloneScreenState
    extends State<ConfirmEstablishmentCloneScreen> {
  bool _loading = true;
  String? _error;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final loc = context.read<LocalizationService>();
    final t = widget.token?.trim();
    if (t == null || t.isEmpty) {
      setState(() {
        _loading = false;
        _error = loc.t('clone_confirm_error');
      });
      return;
    }
    try {
      // RPC работает с anon — отдельная сессия не обязательна
      await Supabase.instance.client.rpc(
        'confirm_establishment_data_clone',
        params: {'p_token': t},
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _ok = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = loc.t('clone_confirm_error');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('clone_confirm_title') ?? 'Копирование данных'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _loading
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _ok ? Icons.check_circle : Icons.error_outline,
                          size: 56,
                          color: _ok
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _ok
                              ? (loc.t('clone_confirm_success') ?? '')
                              : (_error ?? loc.t('clone_confirm_error') ?? ''),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (_ok) ...[
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => context.go('/login'),
                            child: Text(loc.t('login') ?? 'Войти'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
