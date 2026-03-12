import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../services/services.dart';
import '../../services/ai_service.dart';
import '../../services/ai_service_supabase.dart';
import '../../services/order_history_service.dart';
import '../../services/inventory_history_service.dart';
import '../../services/translation_service.dart';
import '../../services/translation_manager.dart';
import '../../services/iiko_product_store.dart';

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
        ChangeNotifierProvider<HomeButtonConfigService>(
          create: (_) => HomeButtonConfigService(),
        ),
        ChangeNotifierProvider<HomeLayoutConfigService>(
          create: (_) => HomeLayoutConfigService(),
        ),
        ChangeNotifierProvider<OwnerViewPreferenceService>(
          create: (_) => OwnerViewPreferenceService(),
        ),
        ChangeNotifierProvider<TtkBranchFilterService>(
          create: (_) => TtkBranchFilterService(),
        ),
        ChangeNotifierProvider<ScreenLayoutPreferenceService>(
          create: (_) => ScreenLayoutPreferenceService(),
        ),
        ChangeNotifierProvider<NotificationPreferencesService>(
          create: (_) => NotificationPreferencesService(),
        ),
        ChangeNotifierProvider<InboxViewedService>(
          create: (_) => InboxViewedService(),
        ),
        // Используем Supabase версии сервисов
        ChangeNotifierProvider<AccountManagerSupabase>(
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
        Provider<ChecklistSubmissionService>(
          create: (_) => ChecklistSubmissionService(),
        ),
        Provider<AiServiceSupabase>(
          create: (_) => AiServiceSupabase(),
        ),
        Provider<AiService>(
          create: (context) => context.read<AiServiceSupabase>(),
        ),
        Provider<TranslationService>(
          create: (context) => TranslationService(
            aiService: context.read<AiServiceSupabase>(),
            supabase: SupabaseService(),
          ),
        ),
        Provider<TranslationManager>(
          create: (context) => TranslationManager(
            aiService: context.read<AiServiceSupabase>(),
            translationService: context.read<TranslationService>(),
            getSupportedLanguages: () => LocalizationService.productLanguageCodes,
          ),
        ),
        Provider<OrderHistoryService>(
          create: (_) => OrderHistoryService(),
        ),
        Provider<InventoryHistoryService>(
          create: (_) => InventoryHistoryService(),
        ),
        Provider<TechCardHistoryService>(
          create: (_) => TechCardHistoryService(),
        ),
        Provider<NutritionApiService>(
          create: (_) => NutritionApiService(),
        ),
        Provider<EmailService>(
          create: (_) => EmailService(),
        ),
        Provider<EmployeeMessageService>(
          create: (_) => EmployeeMessageService(),
        ),
        Provider<MenuStopGoService>(
          create: (_) => MenuStopGoService(),
        ),
        ChangeNotifierProvider<IikoProductStore>(
          create: (_) => IikoProductStore(),
        ),

        // Инициализация сервисов при запуске + загрузка продуктов после входа
        FutureProvider<void>(
          create: (context) async {
            final accountManager = context.read<AccountManagerSupabase>();
            await accountManager.initialize();
            if (accountManager.isLoggedInSync) {
              await context.read<ProductStoreSupabase>().loadProducts();
              await context.read<HomeLayoutConfigService>().loadForEmployee(accountManager.currentEmployee?.id);
              await context.read<NotificationPreferencesService>().load(accountManager.currentEmployee?.id);
            }
          },
          initialData: null,
        ),
      ];
}