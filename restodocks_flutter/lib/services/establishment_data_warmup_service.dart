import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'establishment_local_hydration_service.dart';
import 'localization_service.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';
import 'tech_card_translation_cache.dart';
import 'translation_service.dart';

/// Синхронизация данных заведения с устройством.
///
/// **iOS / Android:** не «прогрев», а **полное локальное зеркало** — каталог, номенклатура,
/// ТТК, снимки SQLite, сотрудники и т.д. через [EstablishmentLocalHydrationService.runFullHydration].
/// Работа без сети опирается на эти копии; при появлении сети [runBackgroundDeltaSync] подтягивает
/// в основном **дельту** (редко полный каталог — по TTL кэша).
///
/// **Web:** прежняя цепочка без полного await зеркала.
class EstablishmentDataWarmupService {
  EstablishmentDataWarmupService._();
  static final EstablishmentDataWarmupService instance =
      EstablishmentDataWarmupService._();

  Future<void> _chain = Future<void>.value();

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
      final techCardScopeIds = _techCardWarmupEstablishmentIds(
        dataEstablishmentId: dataEstablishmentId,
        establishment: establishment,
      );
      if (establishment != null) {
        // Гарантируем систематическое фоновое обновление после каждого входа.
        EstablishmentLocalHydrationService.instance.ensurePeriodicSyncStarted();
      }

      if (!kIsWeb && establishment != null) {
        await EstablishmentLocalHydrationService.instance.runFullHydration(
          establishmentId: establishment.id,
          dataEstablishmentId: dataEstablishmentId,
          productStore: productStore,
          establishment: establishment,
          includeCatalog: true,
        );
        final warmCards = await _warmTechCardsScopes(
          techCards: techCards,
          scopeEstablishmentIds: techCardScopeIds,
        );
        await _syncTechCardTranslationsForCards(
          cards: warmCards,
          sessionEstablishmentId: dataEstablishmentId,
          techCards: techCards,
          translationService: translationService,
          localization: localization,
        );
        return;
      }

      await Future.wait([
        productStore.loadProducts(force: true).catchError((_) {}),
        productStore
            .loadNomenclatureForce(dataEstablishmentId)
            .catchError((_) {}),
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

      final warmCards = await _warmTechCardsScopes(
        techCards: techCards,
        scopeEstablishmentIds: techCardScopeIds,
      );
      await _syncTechCardTranslationsForCards(
        cards: warmCards,
        sessionEstablishmentId: dataEstablishmentId,
        techCards: techCards,
        translationService: translationService,
        localization: localization,
      );

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
        unawaited(EstablishmentLocalHydrationService.instance.runBackgroundDeltaSync());
      }
    } catch (e, st) {
      devLog('EstablishmentDataWarmupService: $e $st');
    }
  }

  List<String> _techCardWarmupEstablishmentIds({
    required String dataEstablishmentId,
    Establishment? establishment,
  }) {
    final ids = <String>{dataEstablishmentId.trim()};
    if (establishment != null &&
        establishment.isBranch &&
        establishment.id.trim().isNotEmpty) {
      ids.add(establishment.id.trim());
    }
    ids.removeWhere((e) => e.isEmpty);
    return ids.toList();
  }

  Future<List<TechCard>> _warmTechCardsScopes({
    required TechCardServiceSupabase techCards,
    required List<String> scopeEstablishmentIds,
  }) async {
    // Веб: не тянем `*, tt_ingredients(*)` на всё заведение при входе — только лёгкие строки tech_cards,
    // страницами (меньше фриза главной и быстрее первый заход в ТТК).
    if (kIsWeb) {
      try {
        final out = await techCards.loadAllTechCardsShallowFromNetworkPaged(
          scopeEstablishmentIds,
          pageSize: 100,
        );
        techCards.stashWebShallowPrefetchForScopes(scopeEstablishmentIds, out);
        return out;
      } catch (_) {
        return [];
      }
    }
    final byId = <String, TechCard>{};
    for (final estId in scopeEstablishmentIds) {
      try {
        final cards = await techCards.getTechCardsForEstablishment(
          estId,
          includeIngredients: true,
        );
        for (final tc in cards) {
          byId[tc.id] = tc;
        }
      } catch (_) {}
    }
    return byId.values.toList();
  }

  Future<void> _syncTechCardTranslationsForCards({
    required List<TechCard> cards,
    required String sessionEstablishmentId,
    required TechCardServiceSupabase techCards,
    required TranslationService translationService,
    required LocalizationService localization,
  }) async {
    await TechCardTranslationCache.loadForEstablishment(sessionEstablishmentId);
    final lang = localization.currentLanguageCode;
    if (cards.isEmpty) {
      final fallback = await techCards.getTechCardsForEstablishment(
        sessionEstablishmentId,
        includeIngredients: true,
      );
      cards = fallback;
    }
    final ids = <String>{};
    for (final tc in cards) {
      ids.add(tc.id);
      for (final ing in tc.ingredients) {
        final sid = ing.sourceTechCardId?.trim();
        if (sid != null && sid.isNotEmpty) ids.add(sid);
      }
    }
    if (!TechCard.translationOverlaySessionMatches(sessionEstablishmentId, lang)) {
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
      TechCard.markTranslationOverlaySession(sessionEstablishmentId, lang);
      await TechCardTranslationCache.saveForEstablishment(sessionEstablishmentId);
    }
  }

  void resetSession() {
    _chain = Future<void>.value();
    TechCard.clearTranslationOverlay();
    TechCardServiceSupabase().clearWebShallowPrefetch();
    EstablishmentLocalHydrationService.instance.stopPeriodicSync();
  }
}
