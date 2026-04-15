import '../models/models.dart';
import '../utils/dev_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Обучение среднему % ужарки по продукту и способу приготовления (заведение).
class ProductCookingLossLearning {
  ProductCookingLossLearning._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Среднее из БД или null — тогда UI использует дефолт способа.
  static Future<double?> getSuggestedLossPct({
    required String establishmentId,
    required String productId,
    required String cookingProcessId,
  }) async {
    final eid = establishmentId.trim();
    final pid = productId.trim();
    final proc = cookingProcessId.trim();
    if (eid.isEmpty || pid.isEmpty || proc.isEmpty || proc == 'custom') {
      return null;
    }
    try {
      final res = await _client.rpc(
        'get_suggested_cooking_loss_pct',
        params: {
          'p_establishment_id': eid,
          'p_product_id': pid,
          'p_cooking_process_id': proc,
        },
      );
      if (res == null) return null;
      if (res is num) return res.toDouble();
      return double.tryParse(res.toString());
    } catch (e, st) {
      devLog('ProductCookingLossLearning.getSuggestedLossPct: $e\n$st');
      return null;
    }
  }

  static double? _lossPctForSample(TTIngredient ing) {
    final procId = ing.cookingProcessId?.trim() ?? '';
    if (procId.isEmpty || procId == 'custom') return null;
    final proc = CookingProcess.findById(procId);
    final explicit = ing.cookingLossPctOverride;
    if (explicit != null) return explicit.clamp(0.0, 99.9);
    return proc?.weightLossPercentage;
  }

  /// Записать наблюдения после сохранения ТТК (не бросает наружу).
  static Future<void> recordSamplesFromIngredients({
    required String establishmentId,
    required List<TTIngredient> ingredients,
    required String source,
  }) async {
    final eid = establishmentId.trim();
    if (eid.isEmpty) return;
    final src = source == 'ai' ? 'ai' : 'user';
    for (final ing in ingredients) {
      if (ing.isPlaceholder) continue;
      final pid = ing.productId?.trim();
      if (pid == null || pid.isEmpty) continue;
      final loss = _lossPctForSample(ing);
      if (loss == null) continue;
      final procId = ing.cookingProcessId?.trim() ?? '';
      if (procId.isEmpty || procId == 'custom') continue;
      try {
        await _client.rpc(
          'record_product_cooking_loss_sample',
          params: {
            'p_establishment_id': eid,
            'p_product_id': pid,
            'p_cooking_process_id': procId,
            'p_loss_pct': loss,
            'p_source': src,
          },
        );
      } catch (e, st) {
        devLog(
          'ProductCookingLossLearning.recordSamplesFromIngredients: '
          '$pid $procId: $e\n$st',
        );
      }
    }
  }
}
