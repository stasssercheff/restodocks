import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Заглушка расходов (Pro).
class ExpensesPlaceholderScreen extends StatelessWidget {
  const ExpensesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text('${loc.t('expenses')} (${loc.t('pro')})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.savings, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              loc.t('expenses'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'ФЗП план, аренда, коммунальные, закупки, доп. расходы',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
