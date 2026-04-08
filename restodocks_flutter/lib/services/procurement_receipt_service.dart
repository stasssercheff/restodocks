import 'dart:convert';

import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Документы приёмки поставок (таблица procurement_receipt_documents).
class ProcurementReceiptService {
  ProcurementReceiptService._();
  static final ProcurementReceiptService instance = ProcurementReceiptService._();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'procurement_receipt_documents';

  Future<Map<String, dynamic>?> saveViaEdge({
    required String establishmentId,
    required String createdByEmployeeId,
    required Map<String, dynamic> payload,
    String? sourceOrderDocumentId,
    List<Map<String, dynamic>>? priceApprovalLines,
    String? nomenclatureEstablishmentId,
  }) async {
    try {
      final res = await _supabase.client.functions.invoke(
        'save-procurement-receipt',
        body: {
          'establishmentId': establishmentId,
          'createdByEmployeeId': createdByEmployeeId,
          'payload': payload,
          if (sourceOrderDocumentId != null && sourceOrderDocumentId.isNotEmpty)
            'sourceOrderDocumentId': sourceOrderDocumentId,
          if (priceApprovalLines != null && priceApprovalLines.isNotEmpty)
            'priceApprovalLines': priceApprovalLines,
          if (nomenclatureEstablishmentId != null &&
              nomenclatureEstablishmentId.isNotEmpty)
            'nomenclatureEstablishmentId': nomenclatureEstablishmentId,
        },
      );
      final data = res.data;
      if (res.status != 200 || data == null) {
        final err = data is Map ? (data['error'] ?? res.data) : res.data;
        devLog('save-procurement-receipt error: $err');
        return null;
      }
      final ok = data is Map && data['ok'] == true;
      final id = data is Map ? data['id'] as String? : null;
      if (!ok || id == null) return null;
      return getById(id);
    } catch (e) {
      devLog('ProcurementReceiptService.saveViaEdge: $e');
      return null;
    }
  }

  /// Обновить JSON payload документа приёмки (например подтверждение руководством).
  Future<bool> updatePayload(String documentId, Map<String, dynamic> payload) async {
    try {
      await _supabase.client.from(_table).update({
        'payload': payload,
      }).eq('id', documentId);
      return true;
    } catch (e) {
      devLog('ProcurementReceiptService.updatePayload: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      return data != null ? Map<String, dynamic>.from(data as Map) : null;
    } catch (e) {
      devLog('ProcurementReceiptService.getById: $e');
      return null;
    }
  }

  /// Список приёмок (по одной строке на логический документ — дедупликация по payload).
  Future<List<Map<String, dynamic>>> listDeduped(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false);
      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return _dedupeByPayload(list);
    } catch (e) {
      devLog('ProcurementReceiptService.listDeduped: $e');
      return [];
    }
  }
}

List<Map<String, dynamic>> _dedupeByPayload(List<Map<String, dynamic>> rows) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final doc in rows) {
    final p = doc['payload'];
    final key = p is Map ? jsonEncode(p) : doc['id'].toString();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(doc);
  }
  return out;
}
