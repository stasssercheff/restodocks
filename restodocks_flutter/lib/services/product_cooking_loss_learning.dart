import '../models/models.dart';
import '../utils/dev_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Глобальное обучение: средний % ужарки (продукт + способ) и % отхода (продукт), общие для всех заведений.
class ProductCookingLossLearning {
  ProductCookingLossLearning._();

  static SupabaseClient get _client => Supabase.instance.client;
  static bool _recordLossRpcUnavailable = false;
  static bool _recordWasteRpcUnavailable = false;

  static bool _isRpcUnavailableError(Object e, String rpcName) {
    final msg = e.toString().toLowerCase();
    return msg.contains(rpcName.toLowerCase()) &&
        (msg.contains('404') ||
            msg.contains('does not exist') ||
            msg.contains('not found') ||
            msg.contains('pgrst'));
  }

  /// Средний % ужарки из системной БД или null — тогда UI использует дефолт способа.
  static Future<double?> getSuggestedLossPct({
    required String productId,
    required String cookingProcessId,
  }) async {
    final pid = productId.trim();
    final proc = cookingProcessId.trim();
    if (pid.isEmpty || proc.isEmpty || proc == 'custom') {
      return null;
    }
    try {
      final res = await _client.rpc(
        'get_suggested_cooking_loss_pct_global',
        params: {
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

  /// Средний % отхода (брутто→нетто) из системной БД или null.
  static Future<double?> getSuggestedWastePct({required String productId}) async {
    final pid = productId.trim();
    if (pid.isEmpty) return null;
    try {
      final res = await _client.rpc(
        'get_suggested_product_waste_pct_global',
        params: {'p_product_id': pid},
      );
      if (res == null) return null;
      if (res is num) return res.toDouble();
      return double.tryParse(res.toString());
    } catch (e, st) {
      devLog('ProductCookingLossLearning.getSuggestedWastePct: $e\n$st');
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

  static double? _wastePctForSample(TTIngredient ing) {
    if (ing.isPlaceholder) return null;
    if (ing.sourceTechCardId != null && ing.sourceTechCardId!.trim().isNotEmpty) {
      return null;
    }
    final pid = ing.productId?.trim();
    if (pid == null || pid.isEmpty) return null;
    if (ing.grossWeight <= 0) return null;
    return ing.primaryWastePct.clamp(0.0, 99.9);
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
      final procId = ing.cookingProcessId?.trim() ?? '';
      if (!_recordLossRpcUnavailable &&
          loss != null &&
          procId.isNotEmpty &&
          procId != 'custom') {
        try {
          await _client.rpc(
            'record_product_cooking_loss_sample_global',
            params: {
              'p_establishment_id': eid,
              'p_product_id': pid,
              'p_cooking_process_id': procId,
              'p_loss_pct': loss,
              'p_source': src,
            },
          );
        } catch (e, st) {
          if (_isRpcUnavailableError(
              e, 'record_product_cooking_loss_sample_global')) {
            _recordLossRpcUnavailable = true;
          }
          devLog(
            'ProductCookingLossLearning.record cooking: '
            '$pid $procId: $e\n$st',
          );
        }
      }

      final waste = _wastePctForSample(ing);
      if (!_recordWasteRpcUnavailable && waste != null) {
        try {
          await _client.rpc(
            'record_product_waste_sample_global',
            params: {
              'p_establishment_id': eid,
              'p_product_id': pid,
              'p_waste_pct': waste,
              'p_source': src,
            },
          );
        } catch (e, st) {
          if (_isRpcUnavailableError(
              e, 'record_product_waste_sample_global')) {
            _recordWasteRpcUnavailable = true;
          }
          devLog(
            'ProductCookingLossLearning.record waste: '
            '$pid: $e\n$st',
          );
        }
      }
    }
  }
}
