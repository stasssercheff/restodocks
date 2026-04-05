import 'dart:async' show unawaited;

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'establishment_local_hydration_service.dart';
import 'localization_service.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';
import 'tech_card_translation_cache.dart';
import 'translation_service.dart';

/// Фоновая подгрузка данных заведения после входа: ТТК, номенклатура/продукты, оверлей переводов,
/// на мобильных — ещё документация, график, список сотрудников (кэш), филиальная номенклатура.
class EstablishmentDataWarmupService {
  EstablishmentDataWarmupService._();
  static final EstablishmentDataWarmupService instance =
      EstablishmentDataWarmupService._();

  Future<void> _chain = Future<void>.value();

  /// Запросы выстраиваются в очередь. Переводы для пары заведение+язык пропускаются, если уже в памяти/на диске.
  Future<void> runForEstablishment({
    required String dataEstablishmentId,
    required TechCardServiceSupabase techCards,
    required ProductStoreSupabase productStore,
    required TranslationService translationService,
    required LocalizationService localization,
    Establishment? establishment,
  }) {
    _chain = _chain.then((_) => _runForEstablishmentBody(
          dataEstablishmentId: dataEstablishmentId,
          techCards: techCards,
          productStore: productStore,
          translationService: translationService,
          localization: localization,
          establishment: establishment,
        ));
    return _chain;
  }

  Future<void> _runForEstablishmentBody({
    required String dataEstablishmentId,
    required TechCardServiceSupabase techCards,
    required ProductStoreSupabase productStore,
    required TranslationService translationService,
    required LocalizationService localization,
    Establishment? establishment,
  }) async {
    try {
      // Сначала каталог и номенклатура — экраны инвентаризации/остатков не пустые при первом кадре.
      await Future.wait([
        productStore.loadProducts(force: true).catchError((_) {}),
        productStore.loadNomenclatureForce(dataEstablishmentId).catchError((_) {}),
      ]);

      if (establishment != null &&
          establishment.isBranch &&
          establishment.parentEstablishmentId != null &&
          establishment.parentEstablishmentId!.isNotEmpty) {
        await productStore
            .loadNomenclatureForBranch(
              establishment.id,
              establishment.dataEstablishmentId,
            )
            .catchError((_) {});
      }

      await TechCardTranslationCache.loadForEstablishment(dataEstablishmentId);
      final lang = localization.currentLanguageCode;

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

      if (!TechCard.translationOverlaySessionMatches(dataEstablishmentId, lang)) {
        final fromDb = await translationService
            .fetchTechCardDishNameTranslationsForTargetLanguage(
          techCardIds: ids.toList(),
          targetLanguage: lang,
        );
        final overlay = await translationService
            .ensureMissingTechCardDishNameTranslations(
          techCards: cards,
          targetLanguage: lang,
          existingFromDatabase: fromDb,
        );
        TechCard.setTranslationOverlay(overlay,
            languageCode: lang, merge: true);
        TechCard.markTranslationOverlaySession(dataEstablishmentId, lang);
        await TechCardTranslationCache.saveForEstablishment(dataEstablishmentId);
      }

      // Остальное в фоне: сотрудники, документы, iiko, снимки — без повторной загрузки каталога.
      if (establishment != null) {
        unawaited(
          Future<void>(() async {
            await Future<void>.delayed(Duration.zero);
            await EstablishmentLocalHydrationService.instance.runFullHydration(
              establishmentId: establishment.id,
              dataEstablishmentId: dataEstablishmentId,
              productStore: productStore,
              establishment: establishment,
              includeCatalog: false,
            );
          }),
        );
      }
    } catch (e, st) {
      devLog('EstablishmentDataWarmupService: $e $st');
    }
  }

  void resetSession() {
    _chain = Future<void>.value();
    TechCard.clearTranslationOverlay();
    EstablishmentLocalHydrationService.instance.stopPeriodicSync();
  }
}
