import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/account_manager_supabase.dart';
import 'subscription_required_dialog.dart';

/// Прямой заход по URL без подписки и после триала: диалог и выход (на домашний или назад).
/// С главного экрана пользователь видит блеклые плитки ([HomeFeatureTile]), сюда обычно не попадает.
class SubscriptionOrTrialGate extends StatefulWidget {
  const SubscriptionOrTrialGate({super.key, required this.child});

  final Widget child;

  @override
  State<SubscriptionOrTrialGate> createState() => _SubscriptionOrTrialGateState();
}

class _SubscriptionOrTrialGateState extends State<SubscriptionOrTrialGate> {
  bool _dialogScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.read<AccountManagerSupabase>();
    if (account.establishment == null) return;
    if (account.hasProSubscription) return;
    if (_dialogScheduled) return;
    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showSubscriptionRequiredDialog(context);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountManagerSupabase>();
    if (account.establishment == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!account.hasProSubscription) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
