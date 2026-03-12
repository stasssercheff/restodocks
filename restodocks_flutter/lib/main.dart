import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/url_strategy_stub.dart'
    if (dart.library.html) 'core/url_strategy_web.dart' as url_strategy;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/core.dart';
import 'utils/dev_log.dart';
import 'core/initial_location_stub.dart'
    if (dart.library.html) 'core/initial_location_web.dart' as initial_loc;
import 'core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'core/supabase_url_resolver_web.dart' as supabase_url;
import 'services/services.dart';
import 'services/translation_manager.dart';
import 'screens/screens.dart';

const String _supabaseUrlEnv = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://osglfptwbuqqmqunttha.supabase.co',
);
const String _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Критично: кэшировать путь+query до ВСЕГО остального — иначе теряются token_hash/type для auth/confirm-click
  if (kIsWeb) initial_loc.getInitialLocation();
  url_strategy.initUrlStrategy(); // после кэша — PathUrlStrategy не должен менять текущий URL
  FlutterError.onError = (details) {
    devLog('FlutterError: ${details.exception}');
    devLog('Stack: ${details.stack}');
  };

  final supabaseUrl = supabase_url.resolveSupabaseUrl(_supabaseUrlEnv);
  devLog('=== SUPABASE INIT: url=$supabaseUrl key=${_supabaseAnonKey.substring(0, 15)}... ===');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: _supabaseAnonKey,
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

  // Подключаем callback: при загрузке профиля сотрудника применяем его preferred_language.
  // Это обеспечивает сохранение языка между браузерами и режимом инкогнито (хранится в Supabase).
  AccountManagerSupabase().onPreferredLanguageLoaded = (langCode) {
    LocalizationService().setLocale(Locale(langCode));
  };

  await ThemeService().initialize();
  await HomeButtonConfigService().initialize();
  await OwnerViewPreferenceService().initialize();
  await TtkBranchFilterService().initialize();
  await ScreenLayoutPreferenceService().initialize();
  AppToastService.init(AppRouter.rootNavigatorKey);
  runApp(const RestodocksApp());
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
          return MaterialApp.router(
            title: localization.t('app_name'),
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            locale: localization.currentLocale,
            supportedLocales: LocalizationService.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: AppRouter.router,
            builder: (context, child) => WebLocationCorrection(child: child),
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
