import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

/// Экран-заглушка: раздел доступен только с подпиской Pro.
class ProRequiredScreen extends StatelessWidget {
  const ProRequiredScreen({
    super.key,
    this.appBarTitleKey = 'expenses',
  });

  /// Ключ локализации заголовка раздела ([LocalizationService.t]).
  final String appBarTitleKey;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final sectionTitle = loc.t(appBarTitleKey);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home', extra: {'back': true});
            }
          },
        ),
        title: Text('$sectionTitle (${loc.t('pro')})'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                loc.t('pro_required_expenses'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
