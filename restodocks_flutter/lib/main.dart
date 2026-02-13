import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/core.dart';
import 'services/services.dart';
import 'screens/screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App started

  // Temporary loading screen
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );

  String supabaseUrl = '';
  String supabaseAnonKey = '';

  // 1. Пробуем config.json (Vercel подставляет при сборке)
  try {
    // Loading config.json
    final json = await rootBundle.loadString('assets/config.json');
    final map = jsonDecode(json) as Map<String, dynamic>;
    supabaseUrl = (map['SUPABASE_URL'] as String?) ?? '';
    supabaseAnonKey = (map['SUPABASE_ANON_KEY'] as String?) ?? '';
    // config.json loaded
  } catch (e) {
    // config.json error
  }

  // 2. Локальная разработка: .env
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    try {
      // Loading .env
      await dotenv.load(fileName: ".env");
      supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      // .env loaded
    } catch (e) {
      print('DEBUG: .env error: $e');
    }
  }

  // Обработка ошибок инициализации
  // Final config loaded
  try {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      // Config missing, showing error screen
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 20),
                    const Text(
                      'Ошибка конфигурации',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'SUPABASE_URL и SUPABASE_ANON_KEY должны быть заданы.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'URL: ${supabaseUrl.isEmpty ? "не задан" : "задан"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      'Key: ${supabaseAnonKey.isEmpty ? "не задан" : "задан"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    // Initializing Supabase...
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    // Supabase initialized

    // Initializing LocalizationService...
    await LocalizationService.initialize();
    // LocalizationService initialized

    // Initializing ThemeService...
    await ThemeService().initialize();
    // ThemeService initialized

    // Starting RestodocksApp...
    runApp(const RestodocksApp());
  } catch (e, stackTrace) {
    // Initialization error
    // Показываем ошибку пользователю вместо белого экрана
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 20),
                  const Text(
                    'Ошибка инициализации',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Проверьте консоль браузера (F12) для подробностей',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Выводим в консоль для отладки
    print('Error: $e');
    print('Stack: $stackTrace');
  }
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
