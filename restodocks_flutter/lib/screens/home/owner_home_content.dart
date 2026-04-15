import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/feature_flags.dart';
import '../../core/subscription_entitlements.dart';
import '../../services/services.dart';
import '../../widgets/home_feature_tile.dart';

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
  int _lastScrolledStepIndex = -1;

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
    if (ctrl == null) return;
    if (!ctrl.isTourActive) {
      _lastScrolledStepIndex = -1;
      return;
    }
    final idx = ctrl.currentIndex;
    if (idx == _lastScrolledStepIndex) return;
    _lastScrolledStepIndex = idx;
    final key = ctrl.getKeyForCurrentStep();
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentCtx = key.currentContext;
        if (currentCtx != null && mounted) {
          Scrollable.ensureVisible(
            currentCtx,
            alignment: 0.3,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          Future.delayed(const Duration(milliseconds: 220), () {
            if (mounted) {
              ctrl.notifyListeners();
            }
          });
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
    final account = context.watch<AccountManagerSupabase>();
    final subOk = account.hasProSubscription;
    final hiddenKeys = context
        .watch<HomeLayoutConfigService>()
        .getHiddenKeys(account.currentEmployee?.id);
    final screenPref = context.watch<ScreenLayoutPreferenceService>();
    bool visible(String key) => !hiddenKeys.contains(key);
    Widget ownerTile(String key, Widget child) =>
        visible(key) ? child : const SizedBox.shrink();

    final ent = SubscriptionEntitlements.from(account.establishment);
    final posOn = FeatureFlags.posEnabledForSubscription(ent);
    final showBarBlock = screenPref.showBarSection && ent.hasUltraLevelFeatures;
    if (ent.isLiteTier) {
      final layoutSvc = context.watch<HomeLayoutConfigService>();
      const liteKeys = <String>[
        'owner_schedule_all',
        'owner_menu_kitchen',
        'owner_ttk_kitchen',
        'owner_nomenclature_kitchen',
        'owner_messages',
        'owner_employees',
        'owner_expenses_lite',
      ];
      final liteOrder = layoutSvc.getOwnerLiteOrder(
        account.currentEmployee?.id,
        liteKeys,
      );
      final liteTiles = <String, Widget>{
        'owner_schedule_all': _wrap(
          HomeFeatureTile(
            icon: Icons.calendar_month,
            title: loc.t('schedule'),
            onTap: () => context.go('/schedule/kitchen'),
          ),
          'home-schedule-mgmt',
        ),
        'owner_menu_kitchen': _wrap(
          HomeFeatureTile(
            icon: Icons.restaurant_menu,
            title: loc.t('menu'),
            onTap: () => context.go('/menu/kitchen'),
          ),
          'home-menu-kitchen',
        ),
        'owner_ttk_kitchen': _wrap(
          HomeFeatureTile(
            icon: Icons.description,
            title: loc.t('ttk_kitchen'),
            onTap: () => context.go('/tech-cards/kitchen'),
          ),
          'home-ttk-kitchen',
        ),
        'owner_nomenclature_kitchen': _wrap(
          HomeFeatureTile(
            icon: Icons.assignment,
            title: loc.t('nomenclature'),
            onTap: () => context.go('/nomenclature/kitchen'),
          ),
          'home-nomenclature-kitchen',
        ),
        'owner_messages': _wrap(
          HomeFeatureTile(
            icon: Icons.chat_bubble_outline,
            title: loc.t('inbox_tab_messages') ?? 'Сообщения',
            onTap: () => context.go('/notifications?tab=messages'),
          ),
          'home-messages',
        ),
        'owner_employees': _wrap(
          HomeFeatureTile(
            icon: Icons.people,
            title: loc.t('employees'),
            onTap: () => context.go('/employees'),
          ),
          'home-employees',
        ),
        'owner_expenses_lite': _wrap(
          HomeFeatureTile(
            icon: Icons.payments,
            title: loc.t('expenses') ?? 'Расходы',
            onTap: () => context.go('/expenses'),
          ),
          'home-expenses-lite',
        ),
      };
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(title: loc.t('kitchen')),
          ...liteOrder.map((key) => ownerTile(
                key,
                liteTiles[key] ?? const SizedBox.shrink(),
              )),
        ],
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: loc.t('management')),
        ownerTile(
            'owner_doc',
            _wrap(
            HomeFeatureTile(
                icon: Icons.description_outlined,
                title: loc.t('documentation') ?? 'Документация',
                onTap: () => context.go('/documentation')),
            'home-doc')),
        ownerTile(
            'owner_haccp',
            _wrap(
            HomeFeatureTile(
                icon: Icons.assignment,
                title: loc.t('haccp_journals') ?? 'Журналы и ХАССП',
                subscriptionLocked: !subOk,
                onTap: () => context.go('/haccp-journals')),
            'home-haccp')),
        ownerTile(
            'owner_messages',
            _wrap(
            HomeFeatureTile(
                icon: Icons.chat_bubble_outline,
                title: loc.t('inbox_tab_messages') ?? 'Сообщения',
                onTap: () => context.go('/notifications?tab=messages')),
            'home-messages')),
        ownerTile(
            'owner_inbox',
            _wrap(
            HomeFeatureTile(
                icon: Icons.inbox,
                title: loc.t('inbox'),
                onTap: () => context.go('/inbox')),
            'home-inbox')),
        ownerTile(
            'owner_employees',
            _wrap(
            HomeFeatureTile(
                icon: Icons.people,
                title: loc.t('employees'),
                onTap: () => context.go('/employees')),
            'home-employees')),
        ownerTile(
            'owner_schedule_all',
            _wrap(
            HomeFeatureTile(
                icon: Icons.calendar_month,
                title: loc.t('schedule'),
                onTap: () => context.go('/schedule/all')),
            'home-schedule-mgmt')),
        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('kitchen')),
        ownerTile(
            'owner_schedule_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.schedule,
                title: loc.t('schedule'),
                onTap: () => context.go('/schedule/kitchen')),
            'home-schedule-kitchen')),
        ownerTile(
            'owner_menu_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.restaurant_menu,
                title: loc.t('menu'),
                onTap: () => context.go('/menu/kitchen')),
            'home-menu-kitchen')),
        ownerTile(
            'owner_ttk_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.description,
                title: loc.t('ttk_kitchen'),
                onTap: () => context.go('/tech-cards/kitchen')),
            'home-ttk-kitchen')),
        ownerTile(
            'owner_nomenclature_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.assignment,
                title: loc.t('nomenclature'),
                onTap: () => context.go('/nomenclature/kitchen')),
            'home-nomenclature-kitchen')),
        if (!posOn) ...[
          ownerTile(
              'owner_procurement_kitchen',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.local_shipping,
                  title: loc.t('pos_nav_procurement') ?? 'Закупка',
                  onTap: () => context.push('/procurement/kitchen')),
              'home-procurement-kitchen')),
        ],
        if (posOn) ...[
          ownerTile(
              'owner_pos_orders_kitchen',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.receipt_long,
                  title: loc.t('order_tab_orders') ?? 'Заказы',
                  onTap: () => context.push('/pos/orders/kitchen')),
              'home-pos-orders-kitchen')),
          ownerTile(
              'owner_pos_sales_kitchen',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.point_of_sale_outlined,
                  title: loc.t('sales_title') ?? 'Продажи',
                  onTap: () => context.push('/sales/kitchen')),
              'home-pos-sales-kitchen')),
          ownerTile(
              'owner_pos_warehouse_kitchen',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.warehouse,
                  title: loc.t('pos_nav_warehouse') ?? 'Склад',
                  onTap: () => context.push('/pos/warehouse/kitchen')),
              'home-pos-wh-kitchen')),
          ownerTile(
              'owner_pos_procurement_kitchen',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.local_shipping,
                  title: loc.t('pos_nav_procurement') ?? 'Закупка',
                  onTap: () => context.push('/pos/procurement/kitchen')),
              'home-pos-pr-kitchen')),
        ],
        ownerTile(
            'owner_writeoffs_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.remove_circle_outline,
                title: loc.t('writeoffs') ?? 'Списания',
                subscriptionLocked: !subOk,
                onTap: () => context.push('/writeoffs')),
            'home-writeoffs-kitchen')),
        ownerTile(
            'owner_checklists_kitchen',
            _wrap(
            HomeFeatureTile(
                icon: Icons.checklist,
                title: loc.t('checklists'),
                onTap: () => context.go('/checklists?department=kitchen')),
            'home-checklists-kitchen')),
        if (showBarBlock) ...[
          const SizedBox(height: 16),
          _SectionTitle(title: loc.t('bar')),
          ownerTile(
              'owner_schedule_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.schedule,
                  title: loc.t('schedule'),
                  onTap: () => context.go('/schedule/bar')),
              'home-schedule-bar')),
          ownerTile(
              'owner_menu_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.restaurant_menu,
                  title: loc.t('menu'),
                  onTap: () => context.go('/menu/bar')),
              'home-menu-bar')),
          ownerTile(
              'owner_ttk_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.description,
                  title: loc.t('ttk_bar') ?? 'ТТК бара',
                  onTap: () => context.go('/tech-cards/bar')),
              'home-ttk-bar')),
          ownerTile(
              'owner_nomenclature_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.assignment,
                  title: loc.t('nomenclature'),
                  onTap: () => context.go('/nomenclature/bar')),
              'home-nomenclature-bar')),
          if (!posOn) ...[
            ownerTile(
                'owner_procurement_bar',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.local_shipping,
                    title: loc.t('pos_nav_procurement') ?? 'Закупка',
                    onTap: () => context.push('/procurement/bar')),
                'home-procurement-bar')),
          ],
          if (posOn) ...[
            ownerTile(
                'owner_pos_orders_bar',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.receipt_long,
                    title: loc.t('order_tab_orders') ?? 'Заказы',
                    onTap: () => context.push('/pos/orders/bar')),
                'home-pos-orders-bar')),
            ownerTile(
                'owner_pos_sales_bar',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.point_of_sale_outlined,
                    title: loc.t('sales_title') ?? 'Продажи',
                    onTap: () => context.push('/sales/bar')),
                'home-pos-sales-bar')),
            ownerTile(
                'owner_pos_warehouse_bar',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.warehouse,
                    title: loc.t('pos_nav_warehouse') ?? 'Склад',
                    onTap: () => context.push('/pos/warehouse/bar')),
                'home-pos-wh-bar')),
            ownerTile(
                'owner_pos_procurement_bar',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.local_shipping,
                    title: loc.t('pos_nav_procurement') ?? 'Закупка',
                    onTap: () => context.push('/pos/procurement/bar')),
                'home-pos-pr-bar')),
          ],
          ownerTile(
              'owner_writeoffs_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.remove_circle_outline,
                  title: loc.t('writeoffs') ?? 'Списания',
                  subscriptionLocked: !subOk,
                  onTap: () => context.push('/writeoffs')),
              'home-writeoffs-bar')),
          ownerTile(
              'owner_checklists_bar',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.checklist,
                  title: loc.t('checklists'),
                  onTap: () => context.go('/checklists?department=bar')),
              'home-checklists-bar')),
        ],
        if (screenPref.showHallSection) ...[
          const SizedBox(height: 16),
          _SectionTitle(title: loc.t('dining_room')),
          ownerTile(
              'owner_schedule_hall',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.schedule,
                  title: loc.t('schedule'),
                  onTap: () => context.go('/schedule/hall')),
              'home-schedule-hall')),
          ownerTile(
              'owner_menu_hall',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.restaurant_menu,
                  title: loc.t('menu'),
                  onTap: () => context.go('/menu/hall')),
              'home-menu-hall')),
          ownerTile(
              'owner_checklists_hall',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.checklist,
                  title: loc.t('checklists'),
                  onTap: () => context.go('/checklists?department=hall')),
              'home-checklists-hall')),
          if (!posOn) ...[
            ownerTile(
                'owner_procurement_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.local_shipping,
                    title: loc.t('pos_nav_procurement') ?? 'Закупка',
                    onTap: () => context.push('/procurement/hall')),
                'home-procurement-hall')),
          ],
          if (posOn) ...[
            ownerTile(
                'owner_pos_orders_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.receipt_long,
                    title: loc.t('order_tab_orders') ?? 'Заказы',
                    onTap: () => context.push('/pos/hall/orders')),
                'home-pos-orders-hall')),
            ownerTile(
                'owner_pos_cash_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.point_of_sale,
                    title: loc.t('pos_nav_cash_register') ?? 'Касса',
                    onTap: () => context.push('/pos/hall/cash-register')),
                'home-pos-cash-hall')),
            ownerTile(
                'owner_pos_tables_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.table_restaurant,
                    title: loc.t('pos_nav_tables') ?? 'Столы',
                    onTap: () => context.push('/pos/hall/tables')),
                'home-pos-tables-hall')),
            ownerTile(
                'owner_pos_warehouse_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.warehouse,
                    title: loc.t('pos_nav_warehouse') ?? 'Склад',
                    onTap: () => context.push('/pos/warehouse/hall')),
                'home-pos-wh-hall')),
            ownerTile(
                'owner_pos_procurement_hall',
                _wrap(
                HomeFeatureTile(
                    icon: Icons.local_shipping,
                    title: loc.t('pos_nav_procurement') ?? 'Закупка',
                    onTap: () => context.push('/pos/procurement/hall')),
                'home-pos-pr-hall')),
          ],
          ownerTile(
              'owner_writeoffs_hall',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.remove_circle_outline,
                  title: loc.t('writeoffs') ?? 'Списания',
                  subscriptionLocked: !subOk,
                  onTap: () => context.push('/writeoffs')),
              'home-writeoffs-hall')),
        ],
        if (screenPref.showBanquetCatering && ent.canAccessBanquetCatering) ...[
          const SizedBox(height: 16),
          if (visible('owner_banquet')) _ExpandableBanquetSection(loc: loc),
        ],
        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('expenses')),
        if (posOn) ...[
          ownerTile(
              'owner_pos_warehouse_est',
              _wrap(
              HomeFeatureTile(
                  icon: Icons.warehouse,
                  title: loc.t('pos_warehouse_establishment_title') ??
                      'Сводная по заведению',
                  onTap: () => context.push('/pos/warehouse/establishment')),
              'home-pos-wh-est')),
        ],
        ownerTile(
            'owner_expenses',
            _wrap(
            HomeFeatureTile(
                icon: Icons.payments,
                title: loc.t('expenses'),
                subscriptionLocked: !subOk && !kIsWeb,
                onTap: () => context.go('/expenses')),
            'home-expenses')),
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

