import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../services/services.dart';
import '../../services/ai_service_supabase.dart';

/// Настройка всех провайдеров приложения
class AppProviders {
  static List<SingleChildWidget> get providers => [
        // Сервисы
        ChangeNotifierProvider<LocalizationService>(
          create: (_) => LocalizationService(),
        ),
        ChangeNotifierProvider<ThemeService>(
          create: (_) => ThemeService(),
        ),
        // Используем Supabase версии сервисов
        Provider<AccountManagerSupabase>(
          create: (_) => AccountManagerSupabase(),
        ),
        Provider<ProductStoreSupabase>(
          create: (_) => ProductStoreSupabase(),
        ),
        Provider<ImageService>(
          create: (_) => ImageService(),
        ),
        Provider<TechCardServiceSupabase>(
          create: (_) => TechCardServiceSupabase(),
        ),
        Provider<ChecklistServiceSupabase>(
          create: (_) => ChecklistServiceSupabase(),
        ),
        Provider<AiServiceSupabase>(
          create: (_) => AiServiceSupabase(),
        ),
        Provider<NutritionApiService>(
          create: (_) => NutritionApiService(),
        ),

        // Инициализация сервисов при запуске + загрузка продуктов после входа
        FutureProvider<void>(
          create: (context) async {
            final accountManager = context.read<AccountManagerSupabase>();
            await accountManager.initialize();
            if (accountManager.isLoggedInSync) {
              await context.read<ProductStoreSupabase>().loadProducts();
            }
          },
          initialData: null,
        ),
      ];
}