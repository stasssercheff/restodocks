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
  print('DEBUG: main() started');

  // DEBUG: Показываем временный экран загрузки
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Container(
          color: Colors.yellow.withOpacity(0.3),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('DEBUG: Loading app...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text('Check Safari console for debug logs', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String supabaseUrl = '';
  String supabaseAnonKey = '';

  // 1. Пробуем config.json (Vercel подставляет при сборке)
  try {
    print('DEBUG: Loading config.json');
    final json = await rootBundle.loadString('assets/config.json');
    final map = jsonDecode(json) as Map<String, dynamic>;
    supabaseUrl = (map['SUPABASE_URL'] as String?) ?? '';
    supabaseAnonKey = (map['SUPABASE_ANON_KEY'] as String?) ?? '';
    print('DEBUG: config.json loaded - URL: ${supabaseUrl.isNotEmpty}, Key: ${supabaseAnonKey.isNotEmpty}');
  } catch (e) {
    print('DEBUG: config.json error: $e');
  }

  // 2. Локальная разработка: .env
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    try {
      print('DEBUG: Loading .env');
      await dotenv.load(fileName: ".env");
      supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      print('DEBUG: .env loaded - URL: ${supabaseUrl.isNotEmpty}, Key: ${supabaseAnonKey.isNotEmpty}');
    } catch (e) {
      print('DEBUG: .env error: $e');
    }
  }

  // Обработка ошибок инициализации
  print('DEBUG: Final config - URL: ${supabaseUrl.isNotEmpty}, Key: ${supabaseAnonKey.isNotEmpty}');
  try {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      print('DEBUG: Config missing, showing error screen');
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

    print('DEBUG: Initializing Supabase...');
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    print('DEBUG: Supabase initialized');

    print('DEBUG: Initializing LocalizationService...');
    await LocalizationService.initialize();
    print('DEBUG: LocalizationService initialized');

    print('DEBUG: Initializing ThemeService...');
    await ThemeService().initialize();
    print('DEBUG: ThemeService initialized');

    print('DEBUG: Starting RestodocksApp...');
    runApp(const RestodocksApp());
  } catch (e, stackTrace) {
    print('DEBUG: Initialization error: $e');
    print('DEBUG: Stack trace: $stackTrace');
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
    print('DEBUG: RestodocksApp.build() called');
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
