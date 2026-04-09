import 'dart:async';

import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/account_manager_supabase.dart';
import '../services/home_button_config_service.dart';
import '../services/page_tour_service.dart';
import 'subscription_required_dialog.dart';

const _kDataAccessRequiredPaths = [
  '/tech-cards',
  '/nomenclature',
  '/inventory',
  '/checklists',
  '/product-order',
  '/menu',
  '/suppliers',
  '/order-lists',
  '/expenses',
  '/haccp-journals',
  '/inbox',
];

/// Оболочка с нижней навигацией для всех рабочих экранов (кроме инвентаризации).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// В альбоме на телефоне скрываем нижнюю панель при прокрутке вниз (больше места под контент).
  bool _hideBottomBar = false;
  double _lastScrollPixels = 0;
  String? _lastPath;

  static const _navBarHeight = 62.0;

  bool _landscapeNarrowPhone(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.orientation == Orientation.landscape &&
        mq.size.shortestSide < 600;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = GoRouterState.of(context).matchedLocation;
    if (_lastPath != path) {
      _lastPath = path;
      _lastScrollPixels = 0;
      if (_hideBottomBar) {
        setState(() => _hideBottomBar = false);
      }
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (!_landscapeNarrowPhone(context)) {
      if (_hideBottomBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hideBottomBar = false);
        });
      }
      return false;
    }
    if (n is! ScrollUpdateNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;

    final p = n.metrics.pixels;
    final delta = p - _lastScrollPixels;
    _lastScrollPixels = p;

    if (p <= 12) {
      if (_hideBottomBar) setState(() => _hideBottomBar = false);
      return false;
    }

    if (delta > 10 && p > 48) {
      if (!_hideBottomBar) setState(() => _hideBottomBar = true);
    } else if (delta < -10) {
      if (_hideBottomBar) setState(() => _hideBottomBar = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;

    if (currentEmployee == null) return widget.child;

    final isOwner = currentEmployee.hasRole('owner');
    final homeBtnConfig = context.watch<HomeButtonConfigService>();
    final middleAction = homeBtnConfig.effectiveAction(currentEmployee,
        hasProSubscription: accountManager.hasProSubscription);
    final noDataAccess = !isOwner && !currentEmployee.effectiveDataAccess;
    final isKitchenNoData =
        noDataAccess && currentEmployee.department == 'kitchen';
    final middleLabel = noDataAccess
        ? (isKitchenNoData ? loc.t('schedule') : loc.t('personal_schedule'))
        : _labelForAction(loc, middleAction, currentEmployee);

    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexForLocation(
        location, middleAction, noDataAccess, isKitchenNoData, currentEmployee);

    final isDataRequiredRoute =
        _kDataAccessRequiredPaths.any((p) => location.startsWith(p));
    final showAccessPendingStub = noDataAccess && isDataRequiredRoute;

    final tourController = context.watch<PageTourService>().homeTourController;
    final navBar = NavigationBarTheme(
      data: const NavigationBarThemeData(
        height: _navBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _hideBottomBar = false);
          _onTap(context, i, middleAction, noDataAccess, isKitchenNoData,
              currentEmployee, selectedIndex);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: loc.t('home'),
          ),
          NavigationDestination(
            icon: Icon(noDataAccess
                ? Icons.calendar_month_outlined
                : middleAction.iconOutlined),
            selectedIcon:
                Icon(noDataAccess ? Icons.calendar_month : middleAction.icon),
            label: middleLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: loc.t('personal_cabinet'),
          ),
        ],
      ),
    );

    final bottomBar = tourController != null
        ? Stack(
            children: [
              navBar,
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: SpotlightTarget(
                        id: 'home-nav-home',
                        controller: tourController,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: SpotlightTarget(
                        id: 'home-nav-middle',
                        controller: tourController,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: SpotlightTarget(
                        id: 'home-nav-cabinet',
                        controller: tourController,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : navBar;

    final landscapeNarrow = _landscapeNarrowPhone(context);
    final landscapeWeb =
        kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    final hideNav = landscapeNarrow && _hideBottomBar;

    final bodyChild = showAccessPendingStub
        ? _AccessPendingPlaceholder(loc: loc)
        : widget.child;
    final mq = MediaQuery.of(context);
    // Низ и бока: web в альбоме или узкий телефон в альбоме (совпадает с main.dart).
    final patchedMq = (landscapeNarrow || landscapeWeb)
        ? mq.copyWith(
            padding: mq.padding.copyWith(left: 0, right: 0, bottom: 0),
            viewPadding:
                mq.viewPadding.copyWith(left: 0, right: 0, bottom: 0),
          )
        : mq;

    // When hidden, omit the slot entirely — a zero-height bar still reserves
    // theme/shadow and reads as a second strip under the real nav.
    return MediaQuery(
      data: patchedMq,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: bodyChild,
          ),
        ),
        bottomNavigationBar: hideNav
            ? null
            : AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: _navBarHeight,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: bottomBar,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _labelForAction(
      LocalizationService loc, HomeButtonAction action, Employee? employee) {
    switch (action) {
      case HomeButtonAction.inbox:
        return loc.t('inbox');
      case HomeButtonAction.messages:
        return loc.t('inbox_tab_messages');
      case HomeButtonAction.schedule:
        return loc.t('schedule');
      case HomeButtonAction.productOrder:
        return loc.t('product_order');
      case HomeButtonAction.menu:
        return loc.t('menu');
      case HomeButtonAction.ttk:
        return loc.t('tech_cards');
      case HomeButtonAction.checklists:
        return loc.t('checklists');
      case HomeButtonAction.nomenclature:
        return loc.t('nomenclature');
      case HomeButtonAction.inventory:
        return loc.t('inventory_blank');
      case HomeButtonAction.expenses:
        return loc.t('expenses');
    }
  }

  int _indexForLocation(
      String location, HomeButtonAction action, bool noDataAccess,
      [bool isKitchenNoData = false, Employee? employee]) {
    if (location == '/home' || location == '/') return 0;
    if (location.startsWith('/personal-cabinet') ||
        location.startsWith('/profile') ||
        location.startsWith('/settings') ||
        location.startsWith('/establishments')) return 2;

    final middleRoute = noDataAccess ? '/schedule' : action.routeFor(employee);
    if (location.startsWith(middleRoute)) return 1;

    // Дополнительные маршруты для средней вкладки
    if (location.startsWith('/schedule') ||
        location.startsWith('/inbox') ||
        location.startsWith('/notifications') ||
        location.startsWith('/checklists') ||
        location.startsWith('/tech-cards') ||
        location.startsWith('/product-order') ||
        location.startsWith('/inventory') ||
        location.startsWith('/writeoffs') ||
        location.startsWith('/menu') ||
        location.startsWith('/nomenclature') ||
        location.startsWith('/expenses')) {
      return 1;
    }
    return 0;
  }

  void _onTap(
      BuildContext context,
      int index,
      HomeButtonAction action,
      bool noDataAccess,
      bool isKitchenNoData,
      Employee? employee,
      int currentIndex) {
    // Если переходим на вкладку с меньшим индексом — анимируем как «назад» (вправо)
    final isBackward = index < currentIndex;
    final extra = isBackward ? {'back': true} : null;

    String middleRoute = action.routeFor(employee);
    if (!noDataAccess &&
        action == HomeButtonAction.inbox &&
        (employee?.hasInboxDocuments ?? true) == false) {
      middleRoute = '/notifications?tab=messages';
    } else if (noDataAccess) {
      middleRoute = isKitchenNoData ? '/schedule' : '/schedule?personal=1';
    }

    switch (index) {
      case 0:
        context.go('/home', extra: extra);
      case 1:
        if (!noDataAccess) {
          final am = context.read<AccountManagerSupabase>();
          if (!am.hasProSubscription &&
              (action == HomeButtonAction.inventory ||
                  action == HomeButtonAction.expenses)) {
            unawaited(showSubscriptionRequiredDialog(context));
            return;
          }
        }
        context.go(middleRoute, extra: extra);
      case 2:
        context.go('/personal-cabinet', extra: extra);
      default:
        context.go('/home', extra: extra);
    }
  }
}

class _AccessPendingPlaceholder extends StatelessWidget {
  const _AccessPendingPlaceholder({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 72,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 24),
            Text(
              loc.t('account_awaiting_confirmation'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.t('account_awaiting_confirmation_subtitle'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
