import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Хаб кухни: три вкладки — Заказ продуктов, Инвентаризация, Чеклисты.
/// Каждая вкладка ведёт на соответствующий раздел.
class KitchenHubScreen extends StatefulWidget {
  const KitchenHubScreen({super.key, this.initialTab = 2});

  /// 0 = product order, 1 = inventory, 2 = checklists
  final int initialTab;

  @override
  State<KitchenHubScreen> createState() => _KitchenHubScreenState();
}

class _KitchenHubScreenState extends State<KitchenHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('kitchen_hub')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.shopping_cart_outlined),
              text: loc.t('product_order'),
            ),
            Tab(
              icon: const Icon(Icons.inventory_2_outlined),
              text: loc.t('inventory'),
            ),
            Tab(
              icon: const Icon(Icons.checklist_outlined),
              text: loc.t('checklists'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _HubTabContent(
            icon: Icons.shopping_cart_outlined,
            title: loc.t('product_order'),
            description: loc.t('product_order_desc') ?? 'Управление заказами продуктов и поставщиками',
            primaryAction: loc.t('open') ?? 'Открыть',
            onPrimaryAction: () => context.push('/product-order'),
          ),
          _HubTabContent(
            icon: Icons.inventory_2_outlined,
            title: loc.t('inventory'),
            description: loc.t('inventory_desc') ?? 'Проведение инвентаризации продуктов и полуфабрикатов',
            primaryAction: loc.t('inventory_new'),
            onPrimaryAction: () => context.push('/inventory'),
            secondaryAction: loc.t('inventory_pf') ?? 'Инвентаризация ПФ',
            onSecondaryAction: () => context.push('/inventory-pf'),
          ),
          _HubTabContent(
            icon: Icons.checklist_outlined,
            title: loc.t('checklists'),
            description: loc.t('checklists_desc') ?? 'Ежедневные чеклисты для кухни',
            primaryAction: loc.t('open') ?? 'Открыть',
            onPrimaryAction: () => context.push('/checklists-list'),
          ),
        ],
      ),
    );
  }
}

class _HubTabContent extends StatelessWidget {
  const _HubTabContent({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryAction,
    required this.onPrimaryAction,
    this.secondaryAction,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryAction;
  final VoidCallback onPrimaryAction;
  final String? secondaryAction;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPrimaryAction,
                icon: const Icon(Icons.arrow_forward),
                label: Text(primaryAction),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            if (secondaryAction != null && onSecondaryAction != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSecondaryAction,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(secondaryAction!),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
