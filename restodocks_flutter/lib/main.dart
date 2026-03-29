import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'core/url_strategy_stub.dart'
    if (dart.library.html) 'core/url_strategy_web.dart' as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/core.dart';
import 'core/supabase_env.dart';
import 'utils/dev_log.dart';
import 'core/initial_location_stub.dart'
    if (dart.library.html) 'core/initial_location_web.dart' as initial_loc;
import 'core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'core/supabase_url_resolver_web.dart' as supabase_url;
import 'models/models.dart';
import 'services/services.dart';
import 'services/translation_manager.dart';
import 'widgets/widgets.dart';

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

  try {
    await _bootstrapApp();
    runApp(const RestodocksApp());
  } catch (e, st) {
    devLog('Startup failed: $e');
    devLog('Stack: $st');
    runApp(_BootstrapFailureApp(message: '$e'));
  }
}

Future<void> _bootstrapApp() async {
  final supabaseUrl = supabase_url.resolveSupabaseUrl(kSupabaseUrlFromEnvironment);
  devLog('=== SUPABASE INIT: url=$supabaseUrl key=${kSupabaseAnonKeyFromEnvironment.substring(0, 15)}... ===');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: kSupabaseAnonKeyFromEnvironment,
    authOptions: const FlutterAuthClientOptions(
      detectSessionInUri: true,
      authFlowType: AuthFlowType.implicit, // сессия из hash при переходе по ссылке подтверждения
    ),
  );
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
  }
  await AccountManagerSupabase().initialize();
  await LocalizationService.initialize();

  LocalizationService.onBeforeLocaleChanged = () {
    TechCard.clearTranslationOverlay();
    EstablishmentDataWarmupService.instance.markTranslationsStale();
  };
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
    );
  };

  // Подключаем callback: при загрузке профиля сотрудника применяем его preferred_language.
  // Это обеспечивает сохранение языка между браузерами и режимом инкогнито (хранится в Supabase).
  AccountManagerSupabase().onPreferredLanguageLoaded = (langCode) {
    unawaited(LocalizationService().setLocale(Locale(langCode)));
  };

  await ThemeService().initialize();
  await HomeButtonConfigService().initialize();
  await OwnerViewPreferenceService().initialize();
  await TtkBranchFilterService().initialize();
  await ScreenLayoutPreferenceService().initialize();
  await MobileUiScaleService().initialize();
  await PosOrdersDisplaySettingsService().initialize();
  AppToastService.init(AppRouter.rootNavigatorKey);
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
                    'Не удалось запустить приложение. Проверьте сеть и откройте снова.',
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
    return MultiProvider(
      providers: AppProviders.providers,
      child: _TranslationManagerConnector(
        child: Consumer2<LocalizationService, ThemeService>(
        builder: (context, localization, themeService, child) {
          final uiScale = context.watch<MobileUiScaleService>();
          final useIosGlassTheme =
              !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
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
              final c = child ?? const SizedBox.shrink();
              final media = MediaQuery.of(context);
              final isPhone = media.size.shortestSide < 600;
              Widget content = c;
              if (isPhone) {
                final factor = uiScale.scaleFactor;
                content = MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(media.textScaleFactor * factor),
                  ),
                  child: c,
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
