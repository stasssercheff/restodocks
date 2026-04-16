import 'dart:async';
import 'dart:math' as math;

import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/mobile_browser_chrome_nudge_stub.dart'
    if (dart.library.html) '../core/mobile_browser_chrome_nudge_web.dart'
    as browser_chrome_doc;
import '../core/pwa_fullscreen_hint_gate_stub.dart'
    if (dart.library.html) '../core/pwa_fullscreen_hint_gate_web.dart'
    as pwa_hint_gate;
import '../core/subscription_entitlements.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/account_manager_supabase.dart';
import '../services/home_button_config_service.dart';
import '../services/shell_return_service.dart';
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
  bool _pwaHintQueued = false;
  Timer? _supportPollTimer;
  bool _supportAdminEntrySnackShown = false;

  bool _landscapeNarrowPhone(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.orientation == Orientation.landscape &&
        mq.size.shortestSide < 600;
  }

  double _effectiveNavBarHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final landscape = mq.orientation == Orientation.landscape;
    final factor = landscape ? 0.70 : 0.80;
    return AppTheme.navigationBarHeight * factor;
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
    _queuePwaHintIfNeeded();
    _ensureSupportPolling();
  }

  @override
  void dispose() {
    _supportPollTimer?.cancel();
    super.dispose();
  }

  void _ensureSupportPolling() {
    final account = context.read<AccountManagerSupabase>();
    final isOwner = account.currentEmployee?.hasRole('owner') ?? false;
    if (!isOwner) {
      _supportPollTimer?.cancel();
      _supportPollTimer = null;
      return;
    }
    _supportPollTimer ??=
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await account.refreshSupportSessionState();
    });
  }

  void _queuePwaHintIfNeeded() {
    if (_pwaHintQueued || !kIsWeb) return;
    final employee = context.read<AccountManagerSupabase>().currentEmployee;
    if (employee == null) return;
    if (!pwa_hint_gate.shouldShowPwaFullscreenHintAfterLogin()) return;
    _pwaHintQueued = true;
    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      _showPwaFullscreenHintDialog();
    });
  }

  Future<void> _showPwaFullscreenHintDialog() async {
    final loc = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pwa_fullscreen_hint_title')),
        content: Text(loc.t('pwa_fullscreen_hint_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('ok')),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    pwa_hint_gate.markPwaFullscreenHintDismissed();
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
    final ownerLite = SubscriptionEntitlements.from(accountManager.establishment)
            .isLiteTier &&
        (currentEmployee.hasRole('owner'));
    final kitchenOnlySchedule = SubscriptionEntitlements.from(
            accountManager.establishment)
        .kitchenOnlyDepartments;
    final middleAction = homeBtnConfig.effectiveAction(currentEmployee,
        hasProSubscription: accountManager.hasProSubscription,
        ownerLiteHome: ownerLite);
    final noDataAccess = !isOwner && !currentEmployee.effectiveDataAccess;
    final isKitchenNoData =
        noDataAccess && currentEmployee.department == 'kitchen';
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexForLocation(location, middleAction, noDataAccess,
        isKitchenNoData, currentEmployee, kitchenOnlySchedule);

    final isDataRequiredRoute =
        _kDataAccessRequiredPaths.any((p) => location.startsWith(p));
    final showAccessPendingStub = noDataAccess && isDataRequiredRoute;

    final tourController = context.watch<PageTourService>().homeTourController;
    final theme = Theme.of(context);
    final navBase = theme.navigationBarTheme.backgroundColor ??
        (theme.brightness == Brightness.dark
            ? AppTheme.navigationBarBackgroundDark
            : AppTheme.navigationBarBackgroundLight);
    final navBg = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.06),
      navBase,
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final navBarHeight = _effectiveNavBarHeight(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final navBottomInset = kIsWeb ? 0.0 : (isLandscape ? 0.0 : bottomInset);

    /// Единый кастомный футер на всех платформах:
    /// иконки строго по центру по вертикали, без лишней «полки» под ними.
    final Widget navBar = Material(
      color: navBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
          SizedBox(
            height: navBarHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _NativeNavIconSlot(
                  selected: selectedIndex == 0,
                  outlined: Icons.home_outlined,
                  filled: Icons.home,
                  onTap: () {
                    setState(() => _hideBottomBar = false);
                    _onTap(
                        context,
                        0,
                        middleAction,
                        noDataAccess,
                        isKitchenNoData,
                        currentEmployee,
                        selectedIndex,
                        kitchenOnlySchedule);
                  },
                ),
                _NativeNavIconSlot(
                  selected: selectedIndex == 1,
                  outlined: noDataAccess
                      ? Icons.calendar_month_outlined
                      : middleAction.iconOutlined,
                  filled:
                      noDataAccess ? Icons.calendar_month : middleAction.icon,
                  onTap: () {
                    setState(() => _hideBottomBar = false);
                    _onTap(
                        context,
                        1,
                        middleAction,
                        noDataAccess,
                        isKitchenNoData,
                        currentEmployee,
                        selectedIndex,
                        kitchenOnlySchedule);
                  },
                ),
                _NativeNavIconSlot(
                  selected: selectedIndex == 2,
                  outlined: Icons.person_outline,
                  filled: Icons.person,
                  onTap: () {
                    setState(() => _hideBottomBar = false);
                    _onTap(
                        context,
                        2,
                        middleAction,
                        noDataAccess,
                        isKitchenNoData,
                        currentEmployee,
                        selectedIndex,
                        kitchenOnlySchedule);
                  },
                ),
              ],
            ),
          ),
          if (navBottomInset > 0)
            ColoredBox(
              color: navBg,
              child: SizedBox(height: navBottomInset, width: double.infinity),
            ),
        ],
      ),
    );

    final bottomBar = tourController != null
        ? Stack(
            children: [
              navBar,
              Positioned.fill(
                child: IgnorePointer(
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
              ),
            ],
          )
        : navBar;

    final landscapeNarrow = _landscapeNarrowPhone(context);
    final landscapeWeb =
        kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideForKeyboard = landscapeNarrow &&
        (keyboardOpen ||
            FocusManager.instance.primaryFocus != null);
    // Веб на телефоне в альбоме: нижнюю панель не показываем — иначе остаётся полоска без футера.
    final hideNav = (kIsWeb && landscapeNarrow) ||
        (landscapeNarrow && (_hideBottomBar || hideForKeyboard));
    final bottomBarTotalHeight = navBarHeight + navBottomInset;

    final bodyChild = showAccessPendingStub
        ? _AccessPendingPlaceholder(loc: loc)
        : widget.child;
    final supportActive = accountManager.supportSessionActive;
    if (!supportActive) {
      _supportAdminEntrySnackShown = false;
    } else if (isOwner && supportActive && !_supportAdminEntrySnackShown) {
      _supportAdminEntrySnackShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!accountManager.supportSessionActive) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(loc.t('support_admin_session_snackbar')),
            duration: const Duration(seconds: 9),
          ),
        );
      });
    }
    final mq = MediaQuery.of(context);
    // Совпадает с main.dart: веб в альбоме — сброс боков; нативно — только без выреза
    // (иначе сохраняем горизонтальный safe area под камеру / Dynamic Island).
    final stripShellHorizontal = landscapeWeb || landscapeNarrow;
    final patchedMq = stripShellHorizontal
        ? mq.copyWith(
            padding: mq.padding.copyWith(left: 0, right: 0, bottom: 0),
            viewPadding: mq.viewPadding.copyWith(
              left: 0,
              right: 0,
              bottom: keyboardOpen ? mq.viewPadding.bottom : 0,
            ),
          )
        : mq;

    // Когда 71af6b31 скрывает bottomNavigationBar в веб+альбоме, пропадает Listener
    // с жестом «вверх» → mobileBrowserChromeScrollDocumentBy (1c342b89). Зона у нижнего
    // края (home indicator / узкая полоса) восстанавливает тот же жест без показа табов.
    final webLandscapeChromeDrag =
        kIsWeb && landscapeNarrow && hideNav;
    final webChromeStripHeight = webLandscapeChromeDrag
        ? math.max(36.0, mq.padding.bottom + 6.0)
        : 0.0;

    // When hidden, omit the slot entirely — a zero-height bar still reserves
    // theme/shadow and reads as a second strip under the real nav.
    return MediaQuery(
      data: patchedMq,
      child: Scaffold(
        // Reserve layout space for bottomNavigationBar to avoid overlapping
        // trailing controls/lists on desktop and web pages.
        extendBody: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: bodyChild,
            ),
            if (supportActive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: const Color(0xFF4A148C).withValues(alpha: 0.96),
                  elevation: 4,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.support_agent,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loc.t('support_admin_session_banner'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (webLandscapeChromeDrag)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: webChromeStripHeight,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerMove: (e) {
                    if (e.delta.dy >= -0.25) return;
                    browser_chrome_doc
                        .mobileBrowserChromeScrollDocumentBy(-e.delta.dy);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
        bottomNavigationBar: hideNav
            ? null
            : AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: bottomBarTotalHeight,
                color: navBg,
                child: landscapeNarrow && kIsWeb
                    ? Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerMove: (e) {
                          // Жест вверх по нижней панели — двигаем document (Safari/Chrome сворачивают UI).
                          if (e.delta.dy >= -0.25) return;
                          browser_chrome_doc
                              .mobileBrowserChromeScrollDocumentBy(-e.delta.dy);
                        },
                        child: bottomBar,
                      )
                    : bottomBar,
              ),
      ),
    );
  }

  int _indexForLocation(
    String location,
    HomeButtonAction action,
    bool noDataAccess, [
    bool isKitchenNoData = false,
    Employee? employee,
    bool kitchenOnlySchedule = false,
  ]) {
    if (location == '/home' || location == '/') return 0;
    if (location.startsWith('/personal-cabinet') ||
        location.startsWith('/profile') ||
        location.startsWith('/settings') ||
        location.startsWith('/establishments')) {
      return 2;
    }

    final middleRoute = noDataAccess
        ? '/schedule'
        : action.routeFor(employee,
            kitchenOnlySchedule: kitchenOnlySchedule);
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
    int currentIndex,
    bool kitchenOnlySchedule,
  ) {
    // Уже на домашнем экране: повторный тап «Дом» не должен вызывать go() — иначе
    // лишняя анимация (как «вперёд») поверх того же маршрута.
    if (index == 0) {
      final loc = GoRouterState.of(context).matchedLocation;
      final pathOnly = loc.split('?').first;
      if (pathOnly == '/home' || pathOnly == '/') {
        return;
      }
    }

    // Если переходим на вкладку с меньшим индексом — анимируем как «назад» (вправо)
    final isBackward = index < currentIndex;
    final extra = isBackward ? {'back': true} : null;

    String middleRoute = action.routeFor(employee,
        kitchenOnlySchedule: kitchenOnlySchedule);
    if (!noDataAccess &&
        action == HomeButtonAction.inbox &&
        (employee?.hasInboxDocuments ?? true) == false) {
      middleRoute = '/notifications?tab=messages';
    } else if (noDataAccess) {
      middleRoute = isKitchenNoData ? '/schedule' : '/schedule?personal=1';
    }

    final shellReturn = context.read<ShellReturnService>();
    switch (index) {
      case 0:
        shellReturn.onFooterWillNavigate(context,
            tabIndex: 0, middleRoute: middleRoute);
        context.go('/home', extra: extra);
        return;
      case 1:
        if (!noDataAccess) {
          final am = context.read<AccountManagerSupabase>();
          if (!am.hasProSubscription &&
              (action == HomeButtonAction.inventory ||
                  (action == HomeButtonAction.expenses && !kIsWeb))) {
            unawaited(showSubscriptionRequiredDialog(context));
            return;
          }
        }
        shellReturn.onFooterWillNavigate(context,
            tabIndex: 1, middleRoute: middleRoute);
        context.go(middleRoute, extra: extra);
        return;
      case 2:
        shellReturn.onFooterWillNavigate(context,
            tabIndex: 2, middleRoute: middleRoute);
        context.go('/personal-cabinet', extra: extra);
        return;
      default:
        shellReturn.onFooterWillNavigate(context,
            tabIndex: 0, middleRoute: middleRoute);
        context.go('/home', extra: extra);
        return;
    }
  }
}

/// Одна кнопка нижней навигации на iOS/Android: иконка строго по центру по вертикали в слоте.
class _NativeNavIconSlot extends StatelessWidget {
  const _NativeNavIconSlot({
    required this.selected,
    required this.outlined,
    required this.filled,
    required this.onTap,
  });

  final bool selected;
  final IconData outlined;
  final IconData filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.expand(
            child: Center(
              child: Icon(
                selected ? filled : outlined,
                size: 24,
                color: selected ? AppTheme.primaryColor : inactive,
              ),
            ),
          ),
        ),
      ),
    );
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
