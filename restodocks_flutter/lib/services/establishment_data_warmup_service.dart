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
  String? _lastWarmupLang;
  Future<void> _chain = Future<void>.value();

  /// Сброс кэша «последний прогретый язык» — следующий [runForEstablishment] не пропустится по языку.
  void markTranslationsStale() {
    _lastWarmupLang = null;
  }

  /// Идёт без блокировки UI. Запросы выстраиваются в очередь; повтор для того же заведения и того же языка пропускается.
  Future<void> runForEstablishment({
    required String dataEstablishmentId,
    required TechCardServiceSupabase techCards,
    required ProductStoreSupabase productStore,
    required TranslationService translationService,
    required LocalizationService localization,
  }) {
    _chain = _chain.then((_) => _runForEstablishmentBody(
          dataEstablishmentId: dataEstablishmentId,
          techCards: techCards,
          productStore: productStore,
          translationService: translationService,
          localization: localization,
        ));
    return _chain;
  }

  Future<void> _runForEstablishmentBody({
    required String dataEstablishmentId,
    required TechCardServiceSupabase techCards,
    required ProductStoreSupabase productStore,
    required TranslationService translationService,
    required LocalizationService localization,
  }) async {
    try {
      final lang = localization.currentLanguageCode;
      if (_lastDataEstablishmentId == dataEstablishmentId &&
          _lastWarmupLang == lang) {
        return;
      }
      final cards = await techCards.getTechCardsForEstablishment(
        dataEstablishmentId,
        includeIngredients: true,
      );
      final ids = <String>{};
      for (final tc in cards) {
        ids.add(tc.id);
        for (final ing in tc.ingredients) {
          final sid = ing.sourceTechCardId?.trim();
          if (sid != null && sid.isNotEmpty) ids.add(sid);
        }
      }
      final overlay = await translationService
          .fetchTechCardDishNameTranslationsForTargetLanguage(
        techCardIds: ids.toList(),
        targetLanguage: lang,
      );
      TechCard.setTranslationOverlay(overlay, merge: true);

      await productStore.loadProducts().catchError((_) {});
      await productStore.loadNomenclature(dataEstablishmentId).catchError((_) {});

      _lastDataEstablishmentId = dataEstablishmentId;
      _lastWarmupLang = localization.currentLanguageCode;
    } catch (e, st) {
      devLog('EstablishmentDataWarmupService: $e $st');
    }
  }

  void resetSession() {
    _lastDataEstablishmentId = null;
    _lastWarmupLang = null;
    _chain = Future<void>.value();
    TechCard.clearTranslationOverlay();
  }
}
