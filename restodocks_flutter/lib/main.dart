import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'core/url_strategy_stub.dart'
    if (dart.library.html) 'core/url_strategy_web.dart' as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_session_lifecycle.dart';
import 'core/core.dart';
import 'core/deep_link_bootstrap.dart';
import 'core/mobile_deep_link_listener.dart';
import 'core/supabase_env.dart';
import 'core/public_app_origin.dart';
import 'core/supabase_retry_http_client.dart';
import 'utils/dev_log.dart';
import 'core/initial_location_stub.dart'
    if (dart.library.html) 'core/initial_location_web.dart' as initial_loc;
import 'core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'core/supabase_url_resolver_web.dart' as supabase_url;
import 'core/mobile_browser_chrome_nudge_stub.dart'
    if (dart.library.html) 'core/mobile_browser_chrome_nudge_web.dart'
        as mobile_chrome;
import 'services/fcm_push_service.dart';
import 'services/services.dart';
import 'services/translation_manager.dart';
import 'widgets/widgets.dart';

/// Язык интерфейса из профиля сотрудника: хранится в учётной записи и совпадает на всех устройствах.
Future<void> _applyLocaleFromEmployeeProfile(String profileLang) async {
  final loc = LocalizationService();
  final p = profileLang.trim().toLowerCase();
  if (!LocalizationService.supportedLocales.any((l) => l.languageCode == p)) {
    return;
  }
  if (loc.currentLanguageCode != p) {
    await loc.setLocale(Locale(p));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Критично: кэшировать путь+query до ВСЕГО остального — иначе теряются token_hash/type для auth/confirm-click
  if (kIsWeb) initial_loc.getInitialLocation();
  url_strategy.initUrlStrategy(); // после кэша — PathUrlStrategy не должен менять текущий URL
  FlutterError.onError = (details) {
    devLog('FlutterError: ${details.exception}');
    devLog('Stack: ${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    devLog('Uncaught async: $error');
    devLog('Stack: $stack');
    return true;
  };

  // Сначала рисуем лёгкий экран загрузки — иначе на web долгий «белый экран»
  // пока Supabase, переводы и сервисы инициализируются в _bootstrapApp().
  runApp(const _StartupGate());
}

Future<void> _bootstrapApp() async {
  // iOS / Android / macOS: config до DeepLink — иначе ссылки с зеркала (PUBLIC_APP_ORIGIN) не примутся.
  var urlIn = kSupabaseUrlFromEnvironment;
  var keyIn = kSupabaseAnonKeyFromEnvironment;
  if (!kIsWeb) {
    try {
      final raw = await rootBundle.loadString('assets/config.json');
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) {
        final u = j['SUPABASE_URL']?.toString().trim();
        final k = j['SUPABASE_ANON_KEY']?.toString().trim();
        if (u != null && u.isNotEmpty) urlIn = u;
        if (k != null && k.isNotEmpty) keyIn = k;
        final po = j['PUBLIC_APP_ORIGIN']?.toString().trim();
        if (po != null && po.isNotEmpty) {
          setNativePublicAppOriginFromConfig(po);
        }
      }
    } catch (e) {
      devLog('assets/config.json (native): $e');
    }
    await DeepLinkBootstrap.captureInitial();
  }

  final supabaseUrl = supabase_url.resolveSupabaseUrl(urlIn);
  final keyPreview = keyIn.length > 15 ? '${keyIn.substring(0, 15)}...' : keyIn;
  devLog('=== SUPABASE INIT: url=$supabaseUrl key=$keyPreview ===');

  if (!kIsWeb) {
    supabase_url.setNativeSupabaseRuntimeConfig(
      url: supabaseUrl,
      anonKey: keyIn,
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: keyIn,
    httpClient: createSupabaseRetryHttpClient(),
    authOptions: const FlutterAuthClientOptions(
      detectSessionInUri: true,
      authFlowType: AuthFlowType.implicit, // сессия из hash при переходе по ссылке подтверждения
    ),
  );
  await FcmPushService.setup();
  // Сразу обрабатываем токены из URL (Supabase redirect после confirm) — до роутера и AccountManager
  if (kIsWeb) {
    final uri = Uri.base;
    final hasTokens = uri.fragment.contains('access_token') || uri.query.contains('access_token');
    if (hasTokens) {
      try {
        devLog('[Auth] getSessionFromUrl path=${uri.path} hasFragment=${uri.fragment.isNotEmpty}');
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        devLog('[Auth] getSessionFromUrl error: $e');
      }
    }
  } else {
    final u = DeepLinkBootstrap.initialUri;
    if (u != null) {
      final hasTokens =
          u.fragment.contains('access_token') || u.query.contains('access_token');
      if (hasTokens) {
        try {
          devLog(
              '[Auth] getSessionFromUrl mobile path=${u.path} frag=${u.fragment.isNotEmpty}');
          await Supabase.instance.client.auth.getSessionFromUrl(u);
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          devLog('[Auth] getSessionFromUrl (mobile) error: $e');
        }
      }
    }
  }
  // Сначала переводы + сохранённая локаль (SharedPreferences), затем аккаунт.
  // Иначе загрузка профиля вызывает onPreferredLanguageLoaded и затирает язык из prefs.
  await LocalizationService.initialize();
  await AccountManagerSupabase().initialize();

  // Оверлей переводов ТТК не сбрасываем при смене языка — слои по языкам копятся локально; догрузка — в onAfterLocaleChanged.
  LocalizationService.onAfterLocaleChanged = () async {
    final acc = AccountManagerSupabase();
    final est = acc.establishment;
    if (est == null) return;
    final dataId = est.dataEstablishmentId.trim();
    if (dataId.isEmpty) return;
    final loc = LocalizationService();
    await EstablishmentDataWarmupService.instance.runForEstablishment(
      dataEstablishmentId: dataId,
      techCards: TechCardServiceSupabase(),
      productStore: ProductStoreSupabase(),
      translationService: TranslationService(
        aiService: AiServiceSupabase(),
        supabase: SupabaseService(),
      ),
      localization: loc,
      establishment: acc.establishment,
    );
  };

  // При загрузке профиля: язык из БД + локальный выбор (prefs не затираем языком из БД).
  AccountManagerSupabase().onPreferredLanguageLoaded = (langCode) {
    unawaited(_applyLocaleFromEmployeeProfile(langCode));
  };

  // Только SharedPreferences / локальные prefs — безопасно грузить параллельно.
  await Future.wait([
    ThemeService().initialize(),
    HomeButtonConfigService().initialize(),
    OwnerViewPreferenceService().initialize(),
    TtkBranchFilterService().initialize(),
    ScreenLayoutPreferenceService().initialize(),
    MobileUiScaleService().initialize(),
    PosOrdersDisplaySettingsService().initialize(),
  ]);

  ThemeService.accountPersistHook = (mode) async {
    await AccountUiSyncService.instance.persistThemeFromUser(mode);
  };
  OwnerViewPreferenceService.accountPersistHook = (value) async {
    await AccountUiSyncService.instance.persistViewAsOwnerFromUser(value);
  };
  AccountUiSyncService.instance.onEmployeeMerged = (e) {
    AccountManagerSupabase().mergeCurrentEmployeeInMemory(e);
  };
  final syncedEmployee = AccountManagerSupabase().currentEmployee;
  if (syncedEmployee != null) {
    unawaited(AccountUiSyncService.instance.applyAfterLogin(syncedEmployee));
  }

  // Натив: сразу полное локальное зеркало заведения (офлайн + быстрый UI). Web — см. [HomeScreen].
  if (!kIsWeb) {
    final accWarm = AccountManagerSupabase();
    if (accWarm.isLoggedInSync && accWarm.establishment != null) {
      final est = accWarm.establishment!;
      final dataId = est.dataEstablishmentId.trim();
      if (dataId.isNotEmpty) {
        EstablishmentLocalHydrationService.instance.ensurePeriodicSyncStarted();
        unawaited(
          EstablishmentDataWarmupService.instance.runForEstablishment(
            dataEstablishmentId: dataId,
            techCards: TechCardServiceSupabase(),
            productStore: ProductStoreSupabase(),
            translationService: TranslationService(
              aiService: AiServiceSupabase(),
              supabase: SupabaseService(),
            ),
            localization: LocalizationService(),
            establishment: est,
          ),
        );
      }
    }
  }

  AppToastService.init(AppRouter.rootNavigatorKey);
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await _bootstrapApp();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      devLog('Startup failed: $e');
      devLog('Stack: $st');
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _BootstrapFailureApp(message: _error!);
    }
    if (!_ready) {
      // Web: тот же логотип уже на #loading-screen в index.html до первого кадра Flutter —
      // не дублируем welcome_logo.png (иначе визуальное «двойное маркето»).
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFAD292C)),
          useMaterial3: true,
        ),
        home: kIsWeb
            ? const Scaffold(
                backgroundColor: AppTheme.primaryColor,
                body: SizedBox.expand(),
              )
            : const Scaffold(
                backgroundColor: AppTheme.primaryColor,
                body: BrandedAuthLoading(fullscreenLogo: true),
              ),
      );
    }
    return const RestodocksApp();
  }
}

/// Минимальный экран, если до runApp(RestodocksApp) не дошли (иначе на устройстве — вечный белый кадр).
class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    // До LocalizationService.initialize() нет бандла переводов — нейтральный английский.
                    'Unable to start the app. Check your network and try again.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RestodocksApp extends StatelessWidget {
  const RestodocksApp({super.key});

  @override
  Widget build(BuildContext context) {
    // RestodocksApp.build() called
    return AuthSessionLifecycle(
      child: MultiProvider(
      providers: AppProviders.providers,
      child: _TranslationManagerConnector(
        child: Consumer2<LocalizationService, ThemeService>(
        builder: (context, localization, themeService, child) {
          final uiScale = context.watch<MobileUiScaleService>();
          // iOS + macOS: одна «стеклянная» тема; web/Android/desktop (кроме macOS) — classic.
          final useIosGlassTheme = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS);
          return MaterialApp.router(
            title: localization.t('app_name'),
            theme: useIosGlassTheme
                ? AppTheme.lightTheme
                : AppTheme.classicLightTheme,
            darkTheme: useIosGlassTheme
                ? AppTheme.darkTheme
                : AppTheme.classicDarkTheme,
            themeMode: themeService.themeMode,
            locale: localization.currentLocale,
            supportedLocales: LocalizationService.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            routerConfig: AppRouter.router,
            builder: (context, child) {
              final raw = child ?? const SizedBox.shrink();
              final c = kIsWeb ? raw : MobileDeepLinkListener(child: raw);
              final media = MediaQuery.of(context);
              // Телефонный масштаб: нативный iOS/Android и веб при узком экране (Safari и т.д.).
              // Раньше веб не трогали — из‑за этого шрифты/плитки казались «раздутыми» относительно
              // нативного приложения с тем же пресетом (0.9).
              final narrowPhone = media.size.shortestSide < 600;
              final applyMobileUiScale = narrowPhone &&
                  (kIsWeb ||
                      defaultTargetPlatform == TargetPlatform.iOS ||
                      defaultTargetPlatform == TargetPlatform.android);
              // Альбом: Safari даёт большие боковые inset'ы; контент оказывается в «окошке», по бокам
              // полосы цвета браузера/primary. Убираем горизонтальные padding/viewPadding везде
              // на вебе в альбоме и на телефоне в альбоме (iPad в портрете не трогаем).
              final landscape = media.orientation == Orientation.landscape;
              final stripLandscapeSideInsets =
                  landscape && (kIsWeb || narrowPhone);
              var m = media;
              if (applyMobileUiScale) {
                m = m.copyWith(
                  textScaler: TextScaler.linear(
                      media.textScaleFactor * uiScale.scaleFactor),
                );
              }
              if (stripLandscapeSideInsets) {
                m = m.copyWith(
                  padding: m.padding.copyWith(left: 0, right: 0),
                  viewPadding: m.viewPadding.copyWith(left: 0, right: 0),
                );
              }
              final needsMediaWrap =
                  applyMobileUiScale || stripLandscapeSideInsets;
              var content =
                  needsMediaWrap ? MediaQuery(data: m, child: c) : c;
              // Мобильный Chrome/Safari: сворачивание адресной строки привязано к scroll документа,
              // а не к внутренним ListView канваса — слегка двигаем window при вертикальном скролле.
              if (kIsWeb) {
                content = NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification n) {
                    if (n is! ScrollUpdateNotification) return false;
                    if (n.metrics.axis != Axis.vertical) return false;
                    final d = n.scrollDelta;
                    if (d == null || d.abs() < 0.5) return false;
                    mobile_chrome.mobileBrowserChromeNudgeFromFlutterScroll();
                    return false;
                  },
                  child: content,
                );
              }
              return WebLocationCorrection(
                child: AppPrimaryScrollController(child: content),
              );
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
      ),
      ),
    );
  }
}

/// Подключает TranslationManager к LocalizationService после старта провайдеров
class _TranslationManagerConnector extends StatefulWidget {
  final Widget child;
  const _TranslationManagerConnector({required this.child});

  @override
  State<_TranslationManagerConnector> createState() => _TranslationManagerConnectorState();
}

class _TranslationManagerConnectorState extends State<_TranslationManagerConnector> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = context.read<TranslationManager>();
    LocalizationService().setTranslationManager(manager);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// Force rebuild trigger
// Test deploy Wed Feb 18 21:21:55 +07 2026
