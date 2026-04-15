import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import 'account_manager_supabase.dart';
import 'product_store_supabase.dart';
import 'nutrition_profile_resolver.dart';

const _keyLastRun = 'nutrition_backfill_last_run_ms';
const _keyProcessedToday = 'nutrition_backfill_processed_today';
const _keyProcessedDate = 'nutrition_backfill_processed_date'; // YYYY-MM-DD
const _minIntervalHours = 1;
const _maxPerRun = 10;
const _delayBetweenRequests = Duration(seconds: 2);
const _maxPerDay = 50;
const _catchUpMaxPerRun = 200;
const _catchUpBatchSize = 25;
const _catchUpDelayBetweenRequests = Duration(milliseconds: 350);

/// Фоновая подгрузка КБЖУ для продуктов без калорий.
/// Запускается после загрузки продуктов, не чаще раза в час, до 50 продуктов в сутки.
class NutritionBackfillService {
  static final NutritionBackfillService _instance = NutritionBackfillService._();
  factory NutritionBackfillService() => _instance;
  NutritionBackfillService._();

  bool _running = false;
  bool _catchUpRunning = false;

  /// Запустить фоновую подгрузку (неблокирующе).
  void startBackgroundBackfill(ProductStoreSupabase store) {
    if (_running) return;
    unawaited(_runBackfill(store));
  }

  /// Догоняющий проход без суточных/часовых лимитов:
  /// пытаемся заполнить максимум старых пропусков за один запуск.
  void startCatchUpBackfill(ProductStoreSupabase store) {
    if (_running || _catchUpRunning) return;
    unawaited(_runCatchUpBackfill(store));
  }

  Future<void> _runBackfill(ProductStoreSupabase store) async {
    if (_running) return;
    // Глобальный каталог продуктов может грузиться до входа; nutrition_* под RLS только для сессии.
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null || client.auth.currentUser == null) {
      return;
    }
    final am = AccountManagerSupabase();
    if (!am.isLoggedInSync) return;
    final dataEst = am.dataEstablishmentId?.trim();
    if (dataEst == null || dataEst.isEmpty) return;
    _running = true;
    try {
      try {
        await client.auth.refreshSession();
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final lastRunMs = prefs.getInt(_keyLastRun);
      if (lastRunMs != null) {
        final lastRun = DateTime.fromMillisecondsSinceEpoch(lastRunMs);
        if (now.difference(lastRun).inHours < _minIntervalHours) return;
      }
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final savedDate = prefs.getString(_keyProcessedDate);
      var processedToday = prefs.getInt(_keyProcessedToday) ?? 0;
      if (savedDate != todayStr) {
        processedToday = 0;
        await prefs.setString(_keyProcessedDate, todayStr);
        await prefs.setInt(_keyProcessedToday, 0);
      }
      if (processedToday >= _maxPerDay) return;

      final candidates = store.allProducts
          .where((p) => _needsKbju(p))
          .take(_maxPerRun)
          .toList();
      if (candidates.isEmpty) return;

      await prefs.setInt(_keyLastRun, now.millisecondsSinceEpoch);

      var updated = 0;
      for (final p in candidates) {
        try {
          final did = await NutritionProfileResolver().resolveAndApplyMissingNutrition(
            store: store,
            product: p,
            reason: 'missing_fields',
          );
          if (did) updated++;
        } catch (_) {}
        await Future.delayed(_delayBetweenRequests);
      }

      if (updated > 0) {
        final newProcessed = (prefs.getInt(_keyProcessedToday) ?? 0) + updated;
        await prefs.setInt(_keyProcessedToday, newProcessed);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runCatchUpBackfill(ProductStoreSupabase store) async {
    if (_running || _catchUpRunning) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null || client.auth.currentUser == null) {
      return;
    }
    final am = AccountManagerSupabase();
    if (!am.isLoggedInSync) return;
    final dataEst = am.dataEstablishmentId?.trim();
    if (dataEst == null || dataEst.isEmpty) return;
    _catchUpRunning = true;
    try {
      try {
        await client.auth.refreshSession();
      } catch (_) {}
      final attemptedIds = <String>{};
      var processed = 0;

      while (processed < _catchUpMaxPerRun) {
        final candidates = store.allProducts
            .where((p) => _needsKbju(p) && !attemptedIds.contains(p.id))
            .take(_catchUpBatchSize)
            .toList();
        if (candidates.isEmpty) break;

        for (final p in candidates) {
          attemptedIds.add(p.id);
          try {
            final did =
                await NutritionProfileResolver().resolveAndApplyMissingNutrition(
              store: store,
              product: p,
              reason: 'catch_up_missing_fields',
            );
            if (did) processed++;
          } catch (_) {}
          await Future.delayed(_catchUpDelayBetweenRequests);
          if (processed >= _catchUpMaxPerRun) break;
        }
      }
    } finally {
      _catchUpRunning = false;
    }
  }

  bool _needsKbju(Product p) {
    if (p.kbjuManuallyConfirmed) return false;
    return (p.calories == null || p.calories == 0) ||
        p.protein == null ||
        p.fat == null ||
        p.carbs == null;
  }

  /// Сбросить счётчик «за сегодня» (например, в полночь).
  static Future<void> resetDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProcessedToday);
  }
}
