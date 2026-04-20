import 'dart:async';

import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/home_tour_config.dart';
import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import '../services/fcm_push_service.dart';
import '../services/services.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/branded_auth_loading.dart';
import '../widgets/tour_tooltip.dart';

/// Главный экран — контент домашней вкладки по роли.
/// Нижняя навигация управляется AppShell (ShellRoute).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _firstEntryCheckDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstEntry();
      _warmupEstablishmentDataIfNeeded();
      unawaited(PushNotificationService.requestPermissionOnceAfterLogin());
      unawaited(FcmPushService.syncRegistrationAfterLogin());
    });
  }

  /// Web: синх после входа. Натив: полное зеркало стартует из [main] / login — без дубля здесь.
  void _warmupEstablishmentDataIfNeeded() {
    if (!mounted) return;
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    EstablishmentLocalHydrationService.instance.ensurePeriodicSyncStarted();
    unawaited(EstablishmentDataWarmupService.instance.runForEstablishment(
      dataEstablishmentId: est.dataEstablishmentId,
      techCards: context.read<TechCardServiceSupabase>(),
      productStore: context.read<ProductStoreSupabase>(),
      translationService: context.read<TranslationService>(),
      localization: context.read<LocalizationService>(),
      establishment: est,
    ));
  }

  Future<void> _checkFirstEntry() async {
    if (_firstEntryCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    if (emp == null) return;
    _firstEntryCheckDone = true;
    // Первый заход: фиксируем first_session_at в БД и сразу в памяти — иначе при каждом
    // новом билде HomeScreen поле в Employee остаётся null и модалка показывается снова.
    if (emp.firstSessionAt == null) {
      final nowUtc = DateTime.now().toUtc();
      try {
        await accountManager.supabase.client.from('employees').update(
            {'first_session_at': nowUtc.toIso8601String()}).eq('id', emp.id);
      } catch (_) {
        if (!mounted) return;
        _maybeShowHomeTour(emp.id);
        return;
      }
      if (!mounted) return;
      accountManager.mergeCurrentEmployeeInMemory(
        emp.copyWith(firstSessionAt: nowUtc),
      );
      if (!mounted) return;
      await GettingStartedReadService.setRead(emp.id);
      if (emp.hasRole('owner')) {
        await _maybeShowOwnerTrialWelcomeDialog(context, accountManager);
      } else {
        if (!mounted) return;
        await _showFirstEntryDialog(context, emp.id);
      }
    }
    if (!mounted) return;
    _maybeShowHomeTour(emp.id);
  }

  /// Регистрация без промокода: 72 ч пробного доступа с лимитами — один раз пояснить условия.
  Future<void> _maybeShowOwnerTrialWelcomeDialog(
    BuildContext context,
    AccountManagerSupabase accountManager,
  ) async {
    if (!context.mounted) return;
    final emp = accountManager.currentEmployee;
    final est = accountManager.establishment;
    if (emp == null || est == null || !emp.hasRole('owner')) return;
    if (await GettingStartedReadService.isOwnerTrialWelcomeSeen(emp.id)) return;
    if (!context.mounted) return;

    final st = est.subscriptionType?.toLowerCase().trim();
    if (st != null && Establishment.kPaidSubscriptionTiers.contains(st)) return;
    final trialEnd = est.proTrialEndsAt ?? DateTime.now().add(const Duration(hours: 72));
    if (!DateTime.now().isBefore(trialEnd)) return;

    final loc = context.read<LocalizationService>();
    final localeTag = loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    final formattedEnd =
        DateFormat.yMMMd(localeTag).format(trialEnd.toLocal());
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('owner_trial_welcome_title')),
        content: SingleChildScrollView(
          child: Text(
            loc.t('owner_trial_welcome_body').replaceFirst('%s', formattedEnd),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('start_work')),
          ),
        ],
      ),
    );
    await GettingStartedReadService.setOwnerTrialWelcomeSeen(emp.id);
  }

  Future<void> _maybeShowHomeTour(String employeeId) async {
    final tourService = context.read<PageTourService>();
    final forceReplay = tourService.consumeReplayRequest(PageTourKeys.home);
    if (!forceReplay && await tourService.isPageTourSeen(employeeId, PageTourKeys.home)) return;
    if (!mounted) return;

    // Локаль уже согласована в bootstrap (prefs + профиль); тур использует текущий [LocalizationService].
    final accountManager = context.read<AccountManagerSupabase>();
    if (!mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final loc = context.read<LocalizationService>();
    final screenPref = context.read<ScreenLayoutPreferenceService>();
    final emp = accountManager.currentEmployee;
    final isOwnerView = emp != null && emp.hasRole('owner') &&
        (emp.positionRole == null || context.read<OwnerViewPreferenceService>().viewAsOwner);

    final List<SpotlightStep> steps;
    if (isOwnerView) {
      final ownerSteps = HomeTourConfig.ownerStepsForLayout(
        showBarSection: screenPref.showBarSection,
        showHallSection: screenPref.showHallSection,
      );
      steps = [
        for (var i = 0; i < ownerSteps.length; i++)
          SpotlightStep(
            id: ownerSteps[i].id,
            text: ownerSteps[i].text(loc),
            shape: SpotlightShape.rectangle,
            padding: const EdgeInsets.all(4),
            fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
              text: ownerSteps[i].text(loc),
              onNext: onNext,
              onPrevious: onPrev,
              onSkip: onSkip,
              isFirstStep: i == 0,
              isLastStep: false,
              nextLabel: PageTourService.getTourNext(loc),
              skipLabel: PageTourService.getTourFinish(loc),
            ),
          ),
        SpotlightStep(
          id: 'home-nav-home',
          text: PageTourService.getTourNavHome(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavHome(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'home-nav-middle',
          text: PageTourService.getTourNavMiddle(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavMiddle(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'home-nav-cabinet',
          text: PageTourService.getTourNavCabinet(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavCabinet(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: true,
            nextLabel: PageTourService.getTourDone(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
      ];
    } else {
      steps = [
        SpotlightStep(
          id: 'home-content',
          text: PageTourService.getHomeTourBody(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getHomeTourBody(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: true,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'home-nav-home',
          text: PageTourService.getTourNavHome(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavHome(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'home-nav-middle',
          text: PageTourService.getTourNavMiddle(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavMiddle(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'home-nav-cabinet',
          text: PageTourService.getTourNavCabinet(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourNavCabinet(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: true,
            nextLabel: PageTourService.getTourDone(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
      ];
    }

    final controller = SpotlightController(
      steps: steps,
      onTourCompleted: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employeeId, PageTourKeys.home);
        tourService.clearHomeTourController();
      },
      onTourSkipped: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employeeId, PageTourKeys.home);
        tourService.clearHomeTourController();
      },
    );
    tourService.setHomeTourController(controller);
    // Даём время на пересборку SpotlightTarget и layout перед запуском
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      try {
        FeatureSpotlight.of(context).startTour(controller);
      } catch (e) {
        debugPrint('[Tour] startTour error: $e');
        tourService.clearHomeTourController();
      }
    });
  }

  static Future<void> _showFirstEntryDialog(BuildContext context, String employeeId) async {
    final loc = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('training')),
        content: Text(loc.t('first_entry_training_hint')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('start_work')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/login');
      });
      return const Scaffold(body: BrandedAuthLoading(fullscreenLogo: true));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: GoRouter.of(context).canPop() ? appBarBackButton(context) : null,
        title: Text(loc.t('app_name')),
      ),
      body: _buildContent(context, currentEmployee),
    );
  }

  Widget _buildContent(BuildContext context, Employee employee) {
    final tourCtrl = context.watch<PageTourService>().homeTourController;
    if (employee.hasRole('owner')) {
      final pref = context.read<OwnerViewPreferenceService>();
      if (employee.positionRole != null && !pref.viewAsOwner) {
        if (employee.canViewDepartment('management')) {
          return ManagementHomeContent(employee: employee, tourController: tourCtrl);
        }
        return StaffHomeContent(employee: employee, tourController: tourCtrl);
      }
      return OwnerHomeContent(tourController: tourCtrl);
    }
    if (employee.canViewDepartment('management')) {
      return ManagementHomeContent(employee: employee, tourController: tourCtrl);
    }
    return StaffHomeContent(employee: employee, tourController: tourCtrl);
  }
}

/// Экран личного кабинета — меню: Профиль, Настройки, Выход.
class PersonalCabinetScreen extends StatefulWidget {
  const PersonalCabinetScreen({super.key});

  @override
  State<PersonalCabinetScreen> createState() => _PersonalCabinetScreenState();
}

class _PersonalCabinetScreenState extends State<PersonalCabinetScreen> {
  bool _tourCheckDone = false;
  SpotlightController? _tourController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  Future<void> _maybeShowTour() async {
    if (_tourCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    if (employee == null) return;
    _tourCheckDone = true;
    final tourService = context.read<PageTourService>();
    final forceReplay = tourService.consumeReplayRequest(PageTourKeys.personalCabinet);
    if (!forceReplay && await tourService.isPageTourSeen(employee.id, PageTourKeys.personalCabinet)) return;
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final controller = SpotlightController(
      steps: [
        SpotlightStep(
          id: 'cabinet-profile',
          text: PageTourService.getPersonalCabinetTourProfile(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getPersonalCabinetTourProfile(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: true,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'cabinet-settings',
          text: PageTourService.getPersonalCabinetTourSettings(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
            skipButtonOnTooltip: true,
            useGlowOnly: true,
            tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getPersonalCabinetTourSettings(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: true,
            nextLabel: PageTourService.getTourDone(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
      ],
      onTourCompleted: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employee.id, PageTourKeys.personalCabinet);
        if (mounted) setState(() => _tourController = null);
      },
      onTourSkipped: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employee.id, PageTourKeys.personalCabinet);
        if (mounted) setState(() => _tourController = null);
      },
    );
    if (!mounted) return;
    setState(() => _tourController = controller);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      try {
        FeatureSpotlight.of(context).startTour(controller);
      } catch (e) {
        debugPrint('[Tour] cabinet startTour error: $e');
        if (mounted) setState(() => _tourController = null);
      }
    });
  }

  Widget _wrapIfTour(Widget child, String id) {
    final ctrl = _tourController;
    if (ctrl == null) return child;
    return SpotlightTarget(id: id, controller: ctrl, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (employee == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ??
            (GoRouter.of(context).canPop() ? appBarBackButton(context) : null),
        title: Text(loc.t('personal_cabinet')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _wrapIfTour(
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(loc.t('profile')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile'),
              ),
              'cabinet-profile',
            ),
            _wrapIfTour(
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(loc.t('settings')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings'),
              ),
              'cabinet-settings',
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(loc.t('logout'), style: const TextStyle(color: Colors.red)),
              onTap: () async {
                await accountManager.logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
