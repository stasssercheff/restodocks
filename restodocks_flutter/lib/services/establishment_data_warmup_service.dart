import '../models/models.dart';
import '../utils/dev_log.dart';
import 'localization_service.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';
import 'translation_service.dart';

/// Фоновая подгрузка данных заведения после входа: ТТК, номенклатура/продукты, оверлей переводов названий ТТК.
class EstablishmentDataWarmupService {
  EstablishmentDataWarmupService._();
  static final EstablishmentDataWarmupService instance =
      EstablishmentDataWarmupService._();

  String? _lastDataEstablishmentId;
  bool _running = false;

  /// Идёт без блокировки UI. Повтор для того же [dataEstablishmentId] в одной сессии пропускается.
  Future<void> runForEstablishment({
    required String dataEstablishmentId,
    required TechCardServiceSupabase techCards,
    required ProductStoreSupabase productStore,
    required TranslationService translationService,
    required LocalizationService localization,
  }) async {
    if (_running) return;
    if (_lastDataEstablishmentId == dataEstablishmentId) return;
    _running = true;
    try {
      final cards = await techCards.getTechCardsForEstablishment(
        dataEstablishmentId,
        includeIngredients: true,
      );
      final lang = localization.currentLanguageCode;
      final overlay = await translationService
          .fetchTechCardDishNameTranslationsForTargetLanguage(
        techCardIds: cards.map((e) => e.id).toList(),
        targetLanguage: lang,
      );
      TechCard.setTranslationOverlay(overlay);

      await productStore.loadProducts().catchError((_) {});
      await productStore.loadNomenclature(dataEstablishmentId).catchError((_) {});

      _lastDataEstablishmentId = dataEstablishmentId;
    } catch (e, st) {
      devLog('EstablishmentDataWarmupService: $e $st');
    } finally {
      _running = false;
    }
  }

  void resetSession() {
    _lastDataEstablishmentId = null;
    TechCard.clearTranslationOverlay();
  }
}
