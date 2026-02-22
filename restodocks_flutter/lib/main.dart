import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/core.dart';
import 'services/services.dart';
import 'screens/screens.dart';

const String _supabaseUrl = 'https://osglfptwbuqqmqunttha.supabase.co';
const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  print('=== SUPABASE INIT: url=${_supabaseUrl.substring(0, 20)}... key=${_supabaseAnonKey.substring(0, 15)}... ===');

  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  await AccountManagerSupabase().initialize();
  await LocalizationService.initialize();
  await ThemeService().initialize();
  await HomeButtonConfigService().initialize();
  runApp(const RestodocksApp());
}

class RestodocksApp extends StatelessWidget {
  const RestodocksApp({super.key});

  @override
  Widget build(BuildContext context) {
    // RestodocksApp.build() called
    return MultiProvider(
      providers: AppProviders.providers,
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
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}// Force rebuild trigger
// Test deploy Wed Feb 18 21:21:55 +07 2026
