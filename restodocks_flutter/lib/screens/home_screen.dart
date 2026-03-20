import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/home_tour_config.dart';
import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import '../services/services.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/getting_started_document.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstEntry());
  }

  Future<void> _checkFirstEntry() async {
    if (_firstEntryCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    if (emp == null) return;
    _firstEntryCheckDone = true;
    // Показываем «Начало работы» только если не было ни одной сессии.
    if (emp.firstSessionAt == null) {
      try {
        await accountManager.supabase.client
            .from('employees')
            .update({'first_session_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', emp.id);
      } catch (_) {
        if (!mounted) return;
        _maybeShowHomeTour(emp.id);
        return;
      }
      if (!mounted) return;
      await GettingStartedReadService.setRead(emp.id);
      if (!mounted) return;
      await _showFirstEntryDialog(context, emp.id);
    }
    if (!mounted) return;
    _maybeShowHomeTour(emp.id);
  }

  Future<void> _maybeShowHomeTour(String employeeId) async {
    final tourService = context.read<PageTourService>();
    final forceReplay = tourService.consumeReplayRequest(PageTourKeys.home);
    if (!forceReplay && await tourService.isPageTourSeen(employeeId, PageTourKeys.home)) return;
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    final isOwnerView = emp != null && emp.hasRole('owner') &&
        (emp.positionRole == null || context.read<OwnerViewPreferenceService>().viewAsOwner);

    final List<SpotlightStep> steps;
    if (isOwnerView) {
      final ownerSteps = HomeTourConfig.ownerSteps(loc);
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
              skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
      barrierDismissible: false,
      builder: (ctx) => _FirstEntryDialog(
        employeeId: employeeId,
        loc: loc,
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
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
      return ManagementHomeContent(employee: employee);
    }
    return StaffHomeContent(employee: employee);
  }
}

/// Диалог первого входа: документ «Начало работы» с раскрытием разделов и галочка о прочтении.
class _FirstEntryDialog extends StatefulWidget {
  const _FirstEntryDialog({required this.employeeId, required this.loc});

  final String employeeId;
  final LocalizationService loc;

  @override
  State<_FirstEntryDialog> createState() => _FirstEntryDialogState();
}

class _FirstEntryDialogState extends State<_FirstEntryDialog> {
  bool _confirmed = false;
  String? _selectedLanguageCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final loc = context.watch<LocalizationService>();
    final selectedLang = _selectedLanguageCode ?? loc.currentLanguageCode;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: screenHeight * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                loc.t('getting_started') ?? 'Начало работы с Restodocks',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 400,
              child: GettingStartedDocument(showTitle: false, languageCodeOverride: selectedLang),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Выбор языка прямо в окне первого запуска.
                  Row(
                    children: [
                      Text(loc.t('language') ?? 'Язык', style: theme.textTheme.labelLarge),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedLang,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: LocalizationService.supportedLocales
                              .map((l) => DropdownMenuItem(
                                    value: l.languageCode,
                                    child: Text(loc.getLanguageName(l.languageCode)),
                                  ))
                              .toList(),
                          onChanged: (code) async {
                            if (code == null) return;
                            setState(() => _selectedLanguageCode = code);
                            await loc.setLocale(Locale(code));
                            if (context.mounted) {
                              await context.read<AccountManagerSupabase>().savePreferredLanguage(code);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    title: Text(
                      loc.t('getting_started_confirmed') ?? 'Я прочитал(а) инструкцию',
                      style: theme.textTheme.bodyMedium,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _confirmed
                        ? () async {
                            await GettingStartedReadService.setRead(widget.employeeId);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        : null,
                    child: Text(loc.t('start_work') ?? 'Начать работу'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
            skipLabel: PageTourService.getTourSkip(loc),
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
            skipLabel: PageTourService.getTourSkip(loc),
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
      appBar: AppBar(title: Text(loc.t('personal_cabinet'))),
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
