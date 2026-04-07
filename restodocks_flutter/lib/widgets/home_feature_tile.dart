import 'package:flutter/material.dart';

import 'subscription_required_dialog.dart';

/// Плитка главного экрана: при [subscriptionLocked] визуально блеклая, по нажатию — диалог вместо перехода.
class HomeFeatureTile extends StatelessWidget {
  const HomeFeatureTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.subscriptionLocked = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool subscriptionLocked;

  @override
  Widget build(BuildContext context) {
    void handleTap() {
      if (subscriptionLocked) {
        showSubscriptionRequiredDialog(context);
        return;
      }
      onTap();
    }

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: handleTap,
      ),
    );

    if (!subscriptionLocked) return card;

    return Opacity(
      opacity: 0.48,
      child: card,
    );
  }
}
