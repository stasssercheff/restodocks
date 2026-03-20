import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Домашняя страница владельца: график, кухня, бар, зал, менеджмент, уведомления, расходы.
/// Визуал как у менеджмента/сотрудника — Card + ListTile, без цветных плиток.
class OwnerHomeContent extends StatefulWidget {
  const OwnerHomeContent({super.key, this.tourController});

  final SpotlightController? tourController;

  @override
  State<OwnerHomeContent> createState() => _OwnerHomeContentState();
}

class _OwnerHomeContentState extends State<OwnerHomeContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.tourController?.addListener(_onTourStepChanged);
  }

  @override
  void didUpdateWidget(OwnerHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tourController != widget.tourController) {
      oldWidget.tourController?.removeListener(_onTourStepChanged);
      widget.tourController?.addListener(_onTourStepChanged);
    }
  }

  @override
  void dispose() {
    widget.tourController?.removeListener(_onTourStepChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTourStepChanged() {
    final ctrl = widget.tourController;
    if (ctrl == null || !ctrl.isTourActive) return;
    final key = ctrl.getKeyForCurrentStep();
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentCtx = key.currentContext;
        if (currentCtx != null) {
          Scrollable.ensureVisible(
            currentCtx,
            alignment: 0.3,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Widget _wrap(Widget child, String id) {
    if (widget.tourController == null) return child;
    return SpotlightTarget(
      id: id,
      controller: widget.tourController!,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final screenPref = context.watch<ScreenLayoutPreferenceService>();

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: loc.t('management')),
        _wrap(_Tile(icon: Icons.description_outlined, title: loc.t('documentation') ?? 'Документация', onTap: () => context.go('/documentation')), 'home-doc'),
        _wrap(_Tile(icon: Icons.assignment, title: loc.t('haccp_journals') ?? 'Журналы и ХАССП', onTap: () => context.go('/haccp-journals')), 'home-haccp'),
        _wrap(_Tile(icon: Icons.chat_bubble_outline, title: loc.t('inbox_tab_messages') ?? 'Сообщения', onTap: () => context.go('/notifications?tab=messages')), 'home-messages'),
        _wrap(_Tile(icon: Icons.inbox, title: loc.t('inbox'), onTap: () => context.go('/inbox')), 'home-inbox'),
        _wrap(_Tile(icon: Icons.people, title: loc.t('employees'), onTap: () => context.go('/employees')), 'home-employees'),
        _wrap(_Tile(icon: Icons.calendar_month, title: loc.t('schedule'), onTap: () => context.go('/schedule/all')), 'home-schedule-mgmt'),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('kitchen')),
        _wrap(_Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/kitchen')), 'home-schedule-kitchen'),
        _wrap(_Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/kitchen')), 'home-menu-kitchen'),
        _wrap(_Tile(icon: Icons.description, title: loc.t('ttk_kitchen'), onTap: () => context.go('/tech-cards/kitchen')), 'home-ttk-kitchen'),
        _wrap(_Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature/kitchen')), 'home-nomenclature-kitchen'),
        _wrap(_Tile(icon: Icons.add_business, title: loc.t('suppliers') ?? loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.push('/suppliers/kitchen')), 'home-suppliers-kitchen'),
        _wrap(_Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=kitchen')), 'home-order-kitchen'),
        _wrap(_Tile(icon: Icons.remove_circle_outline, title: loc.t('writeoffs') ?? 'Списания', onTap: () => context.push('/writeoffs')), 'home-writeoffs-kitchen'),
        _wrap(_Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=kitchen')), 'home-checklists-kitchen'),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('bar')),
        _wrap(_Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/bar')), 'home-schedule-bar'),
        _wrap(_Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/bar')), 'home-menu-bar'),
        _wrap(_Tile(icon: Icons.description, title: loc.t('ttk_bar') ?? 'ТТК бара', onTap: () => context.go('/tech-cards/bar')), 'home-ttk-bar'),
        _wrap(_Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature/bar')), 'home-nomenclature-bar'),
        _wrap(_Tile(icon: Icons.add_business, title: loc.t('suppliers') ?? loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.push('/suppliers/bar')), 'home-suppliers-bar'),
        _wrap(_Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=bar')), 'home-order-bar'),
        _wrap(_Tile(icon: Icons.remove_circle_outline, title: loc.t('writeoffs') ?? 'Списания', onTap: () => context.push('/writeoffs')), 'home-writeoffs-bar'),
        _wrap(_Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=bar')), 'home-checklists-bar'),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('dining_room')),
        _wrap(_Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/hall')), 'home-schedule-hall'),
        _wrap(_Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/hall')), 'home-menu-hall'),
        _wrap(_Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=hall')), 'home-checklists-hall'),
        _wrap(_Tile(icon: Icons.add_business, title: loc.t('suppliers') ?? loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.push('/suppliers/hall')), 'home-suppliers-hall'),
        _wrap(_Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=hall')), 'home-order-hall'),
        _wrap(_Tile(icon: Icons.remove_circle_outline, title: loc.t('writeoffs') ?? 'Списания', onTap: () => context.push('/writeoffs')), 'home-writeoffs-hall'),

        if (screenPref.showBanquetCatering) ...[
          const SizedBox(height: 16),
          _ExpandableBanquetSection(loc: loc),
        ],
        const SizedBox(height: 16),
        _SectionTitle(title: '${loc.t('expenses')} (${loc.t('pro')})'),
        _wrap(_Tile(icon: Icons.payments, title: loc.t('expenses'), onTap: () => context.go('/expenses')), 'home-expenses'),
      ],
    );
  }
}

/// Выдвижная секция «Банкет / Кейтринг» — кнопка в стиле остальных, внутри Меню и ТТК.
class _ExpandableBanquetSection extends StatelessWidget {
  const _ExpandableBanquetSection({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.celebration),
        title: Text(loc.t('banquet_catering') ?? 'Банкет / Кейтринг'),
        trailing: const Icon(Icons.chevron_right),
        children: [
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: Text(loc.t('menu')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go('/menu/banquet-catering'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(loc.t('ttk_kitchen')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go('/tech-cards/banquet-catering'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// Такой же вид, как в ManagementHomeContent / StaffHomeContent (вход в учётную запись).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
