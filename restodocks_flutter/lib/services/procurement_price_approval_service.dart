import '../models/models.dart';
import '../utils/dev_log.dart';
import 'product_store_supabase.dart';
import 'supabase_service.dart';

/// Согласование изменения цен в номенклатуре по факту закупки (приёмка уже сохранена; очередь во входящих для шефа).
class ProcurementPriceApprovalService {
  ProcurementPriceApprovalService._();
  static final ProcurementPriceApprovalService instance =
      ProcurementPriceApprovalService._();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'procurement_price_approval_requests';

  Future<Map<String, dynamic>?> getById(String id) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      return data != null ? Map<String, dynamic>.from(data as Map) : null;
    } catch (e) {
      devLog('ProcurementPriceApprovalService.getById: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listPending(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('establishment_id', establishmentId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return list;
    } catch (e) {
      devLog('ProcurementPriceApprovalService.listPending: $e');
      return [];
    }
  }

  /// Применить цены к выбранным позициям и закрыть заявку.
  Future<void> applySelected({
    required Map<String, dynamic> row,
    required List<String> productIds,
    required String resolverEmployeeId,
    required ProductStoreSupabase store,
  }) async {
    if (productIds.isEmpty) {
      throw Exception('no_products_selected');
    }
    final status = row['status']?.toString();
    if (status != 'pending') {
      throw Exception('already_resolved');
    }
    final nomEst = row['nomenclature_establishment_id']?.toString();
    if (nomEst == null || nomEst.isEmpty) {
      throw Exception('missing_nomenclature_establishment');
    }
    final lines = row['lines'];
    if (lines is! List) {
      throw Exception('invalid_lines');
    }
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) throw Exception('missing_id');

    final idSet = productIds.toSet();

    for (final raw in lines) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final pid = m['productId']?.toString();
      if (pid == null || !idSet.contains(pid)) continue;
      final newP = (m['newPricePerUnit'] as num?)?.toDouble();
      if (newP == null) continue;
      final cur = m['currency']?.toString() ?? 'RUB';
      await store.setEstablishmentPrice(nomEst, pid, newP, cur);
    }

    await _supabase.client.from(_table).update({
      'status': 'applied',
      'resolved_at': DateTime.now().toUtc().toIso8601String(),
      'resolved_by_employee_id': resolverEmployeeId,
    }).eq('id', id).eq('status', 'pending');
  }

  Future<void> cancel({
    required String approvalId,
    required String resolverEmployeeId,
  }) async {
    await _supabase.client.from(_table).update({
      'status': 'cancelled',
      'resolved_at': DateTime.now().toUtc().toIso8601String(),
      'resolved_by_employee_id': resolverEmployeeId,
    }).eq('id', approvalId).eq('status', 'pending');
  }

  /// Кто видит заявку на согласование цен во входящих.
  static bool canSeePriceApproval(Employee e, String department) {
    if (e.hasRole('owner') || e.hasRole('general_manager')) return true;
    final d = department.toLowerCase();
    if (d == 'bar') {
      return e.hasRole('bar_manager') ||
          e.hasRole('executive_chef') ||
          e.hasRole('sous_chef');
    }
    return e.hasRole('executive_chef') || e.hasRole('sous_chef');
  }

  /// Согласование цен на устройстве при приёмке (без записи во входящие).
  static bool canApproveOnReceiptDevice(Employee e, String department) {
    return canSeePriceApproval(e, department);
  }
}
