import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/foundation.dart';

import 'localization_service.dart';
import 'supabase_service.dart';

/// Ключи страниц для туров. Каждая страница при первом посещении показывает свой тур.
abstract final class PageTourKeys {
  static const home = 'home';
  static const personalCabinet = 'personal_cabinet';
  static const techCards = 'tech_cards';
  static const writeoffs = 'writeoffs';
  static const inventory = 'inventory';
}

/// Сервис для хранения и проверки «тур страницы показан» в Supabase.
/// Для сотрудников с закрытым доступом тур показывается после первого посещения страницы
/// (когда доступ уже открыт — иначе виден placeholder).
class PageTourService extends ChangeNotifier {
  PageTourService({SupabaseService? supabase})
      : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  final Set<String> _seenInMemory = {};

  /// Контроллер тура домашнего экрана (общий для HomeScreen и AppShell).
  SpotlightController? homeTourController;

  /// Запрос повтора тура (из настроек). Потребляется при открытии экрана.
  String? _replayRequested;

  void requestTourReplay(String pageKey) {
    _replayRequested = pageKey;
    notifyListeners();
  }

  bool consumeReplayRequest(String pageKey) {
    if (_replayRequested == pageKey) {
      _replayRequested = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  void setHomeTourController(SpotlightController? c) {
    if (homeTourController == c) return;
    homeTourController = c;
    notifyListeners();
  }

  void clearHomeTourController() {
    setHomeTourController(null);
  }

  /// Проверяет, видел ли сотрудник тур этой страницы.
  Future<bool> isPageTourSeen(String employeeId, String pageKey) async {
    if (employeeId.isEmpty || pageKey.isEmpty) return true;
    if (_seenInMemory.contains('${employeeId}_$pageKey')) return true;
    try {
      final res = await _supabase.client
          .from('employee_page_tour_seen')
          .select('id')
          .eq('employee_id', employeeId)
          .eq('page_key', pageKey)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Отмечает тур страницы как показанный.
  Future<void> markPageTourSeen(String employeeId, String pageKey) async {
    if (employeeId.isEmpty || pageKey.isEmpty) return;
    _seenInMemory.add('${employeeId}_$pageKey');
    try {
      await _supabase.client.from('employee_page_tour_seen').upsert(
            {
              'employee_id': employeeId,
              'page_key': pageKey,
              'seen_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'employee_id,page_key',
          );
    } catch (_) {
      // Не блокируем UX при ошибке сети
    }
    notifyListeners();
  }

  /// Строки тура для страницы (локализованные).
  static String getHomeTourTitle(LocalizationService loc) =>
      loc.t('tour_home_title') ?? 'Рабочий стол';
  static String getHomeTourBody(LocalizationService loc) =>
      loc.t('tour_home_body') ?? 'Здесь быстрый доступ ко всем разделам: меню, ТТК, чеклисты, заказы и др.';
  static String getHomeTourNav(LocalizationService loc) =>
      loc.t('tour_home_nav') ?? 'Нижняя панель — рабочий стол, средняя кнопка и личный кабинет. В личном кабинете находятся настройки приложения.';
  static String getTourNavHome(LocalizationService loc) =>
      loc.t('tour_nav_home') ?? 'Кнопка возврата на домашний экран.';
  static String getTourNavMiddle(LocalizationService loc) =>
      loc.t('tour_nav_middle') ?? 'Настраиваемая кнопка. Выбор осуществляется в настройках.';
  static String getTourNavCabinet(LocalizationService loc) =>
      loc.t('tour_nav_cabinet') ?? 'Личный кабинет и настройки.';
  static String getPersonalCabinetTourTitle(LocalizationService loc) =>
      loc.t('tour_cabinet_title') ?? 'Личный кабинет';
  static String getPersonalCabinetTourProfile(LocalizationService loc) =>
      loc.t('tour_cabinet_profile') ?? 'Профиль — данные и настройки аккаунта.';
  static String getPersonalCabinetTourSettings(LocalizationService loc) =>
      loc.t('tour_cabinet_settings') ?? 'Настройки приложения.';
  static String getTourNext(LocalizationService loc) => loc.t('tour_next') ?? 'Далее';
  static String getTourSkip(LocalizationService loc) => loc.t('tour_skip') ?? 'Пропустить';
  static String getTourFinish(LocalizationService loc) => loc.t('tour_finish') ?? 'Закончить тур';
  static String getTourDone(LocalizationService loc) => loc.t('tour_done') ?? 'Понятно';
  static String getTourTechCards(LocalizationService loc) =>
      loc.t('tour_tech_cards') ?? 'ТТК: создание из номенклатуры, цех, категория, тип (ПФ/блюдо). Поиск и фильтры.';
  static String getTourWriteoffs(LocalizationService loc) =>
      loc.t('tour_writeoffs') ?? 'Списания: персонал, порча, бракераж, проработка, отказ гостя. Отправка во Входящие.';
  static String getTourInventory(LocalizationService loc) =>
      loc.t('tour_inventory') ?? 'Бланк инвентаризации: продукты и полуфабрикаты. Завершение отправляет во Входящие.';

  /// Тексты тура ТТК (многошаговый).
  static String getTourTtkActions(LocalizationService loc) =>
      loc.t('tour_ttk_actions') ?? 'Счётчик карточек, создание, импорт из Excel, экспорт, обновление списка.';
  static String getTourTtkTabPf(LocalizationService loc) =>
      loc.t('tour_ttk_tab_pf') ?? 'Полуфабрикаты — заготовки и основы. Стоимость за кг.';
  static String getTourTtkTabDishes(LocalizationService loc) =>
      loc.t('tour_ttk_tab_dishes') ?? 'Блюда — готовые позиции меню. Себестоимость за порцию.';
  static String getTourTtkTabReview(LocalizationService loc) =>
      loc.t('tour_ttk_tab_review') ?? 'На проверку: ТТК с проблемами (нет цен у ингредиентов, неоднозначные ПФ). Удобно для доработки себестоимости.';
}
