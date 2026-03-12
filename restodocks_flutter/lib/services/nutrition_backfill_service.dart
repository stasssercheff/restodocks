import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import 'nutrition_api_service.dart';
import 'product_store_supabase.dart';

const _keyLastRun = 'nutrition_backfill_last_run_ms';
const _keyProcessedToday = 'nutrition_backfill_processed_today';
const _keyProcessedDate = 'nutrition_backfill_processed_date'; // YYYY-MM-DD
const _minIntervalHours = 1;
const _maxPerRun = 10;
const _delayBetweenRequests = Duration(seconds: 2);
const _maxPerDay = 50;

/// Фоновая подгрузка КБЖУ для продуктов без калорий.
/// Запускается после загрузки продуктов, не чаще раза в час, до 50 продуктов в сутки.
class NutritionBackfillService {
  static final NutritionBackfillService _instance = NutritionBackfillService._();
  factory NutritionBackfillService() => _instance;
  NutritionBackfillService._();

  bool _running = false;

  /// Запустить фоновую подгрузку (неблокирующе).
  void startBackgroundBackfill(ProductStoreSupabase store) {
    if (_running) return;
    unawaited(_runBackfill(store));
  }

  Future<void> _runBackfill(ProductStoreSupabase store) async {
    if (_running) return;
    _running = true;
    try {
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
          final name = p.getLocalizedName('ru');
          if (name.trim().isEmpty) continue;
          final result = await NutritionApiService.fetchNutrition(name);
          if (result != null && result.hasData) {
            final saneCal = NutritionApiService.saneCaloriesForProduct(name, result.calories);
            final updatedProduct = p.copyWith(
              calories: saneCal ?? result.calories,
              protein: result.protein ?? p.protein,
              fat: result.fat ?? p.fat,
              carbs: result.carbs ?? p.carbs,
              containsGluten: result.containsGluten ?? p.containsGluten,
              containsLactose: result.containsLactose ?? p.containsLactose,
            );
            await store.updateProduct(updatedProduct);
            updated++;
          }
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

  bool _needsKbju(Product p) =>
      (p.calories == null || p.calories == 0) &&
      p.protein == null &&
      p.fat == null &&
      p.carbs == null;

  /// Сбросить счётчик «за сегодня» (например, в полночь).
  static Future<void> resetDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProcessedToday);
  }
}
