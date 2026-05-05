import '../models/models.dart';
import '../utils/dev_log.dart';
import '../utils/pos_order_totals.dart';
import 'pos_order_service.dart';
import 'supabase_service.dart';

/// Касса зала: смены и выдача наличных.
class PosCashHallService {
  PosCashHallService._();
  static final PosCashHallService instance = PosCashHallService._();

  final SupabaseService _supabase = SupabaseService();

  Future<PosCashShift?> fetchActiveShift(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('pos_cash_shifts')
          .select()
          .eq('establishment_id', establishmentId)
          .isFilter('ended_at', null)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      final row = list.first;
      if (row is! Map<String, dynamic>) return null;
      return PosCashShift.fromJson(Map<String, dynamic>.from(row));
    } catch (e, st) {
      devLog('PosCashHallService: fetchActiveShift $e $st');
      rethrow;
    }
  }

  Future<PosCashShift> openShift({
    required String establishmentId,
    required double openingBalance,
    required String openedByEmployeeId,
  }) async {
    final existing = await fetchActiveShift(establishmentId);
    if (existing != null) {
      throw StateError('pos_cash_shift_already_open');
    }
    final row = await _supabase.client
        .from('pos_cash_shifts')
        .insert({
          'establishment_id': establishmentId,
          'opening_balance': openingBalance,
          'opened_by_employee_id': openedByEmployeeId,
        })
        .select()
        .single();
    return PosCashShift.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<PosCashShift> closeShift({
    required String shiftId,
    required double closingBalance,
    required String closedByEmployeeId,
    String? notes,
    String? closeReportScope,
    List<String>? closeReportZones,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _supabase.client
        .from('pos_cash_shifts')
        .update({
          'ended_at': now,
          'closing_balance': closingBalance,
          'closed_by_employee_id': closedByEmployeeId,
          'notes': notes,
          if (closeReportScope != null) 'close_report_scope': closeReportScope,
          if (closeReportZones != null) 'close_report_zones': closeReportZones,
          'updated_at': now,
        })
        .eq('id', shiftId)
        .select()
        .single();
    return PosCashShift.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<PosCashDisbursement>> fetchDisbursementsForShift(
      String shiftId) async {
    try {
      final rows = await _supabase.client
          .from('pos_cash_disbursements')
          .select()
          .eq('shift_id', shiftId)
          .order('created_at', ascending: false);
      final out = <PosCashDisbursement>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          out.add(PosCashDisbursement.fromJson(
              Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('PosCashHallService: skip disbursement $e');
        }
      }
      return out;
    } catch (e, st) {
      devLog('PosCashHallService: fetchDisbursementsForShift $e $st');
      rethrow;
    }
  }

  Future<List<PosCashDisbursement>> fetchRecentDisbursements({
    required String establishmentId,
    int limit = 50,
  }) async {
    try {
      final rows = await _supabase.client
          .from('pos_cash_disbursements')
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false)
          .limit(limit);
      final out = <PosCashDisbursement>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          out.add(PosCashDisbursement.fromJson(
              Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('PosCashHallService: skip disbursement $e');
        }
      }
      return out;
    } catch (e, st) {
      devLog('PosCashHallService: fetchRecentDisbursements $e $st');
      rethrow;
    }
  }

  Future<PosCashDisbursement> addDisbursement({
    required String establishmentId,
    String? shiftId,
    required double amount,
    required String purpose,
    String? recipientEmployeeId,
    String? recipientName,
    required String createdByEmployeeId,
  }) async {
    final row = await _supabase.client.from('pos_cash_disbursements').insert({
      'establishment_id': establishmentId,
      if (shiftId != null) 'shift_id': shiftId,
      'amount': amount,
      'purpose': purpose,
      if (recipientEmployeeId != null)
        'recipient_employee_id': recipientEmployeeId,
      if (recipientName != null && recipientName.isNotEmpty)
        'recipient_name': recipientName,
      'created_by_employee_id': createdByEmployeeId,
    }).select().single();
    return PosCashDisbursement.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Наличные по закрытым счетам за период (по строкам оплат и legacy одному способу).
  Future<double> sumCashPaymentsInPeriod({
    required String establishmentId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final orders = await PosOrderService.instance.fetchClosedOrdersPaidBetween(
      establishmentId: establishmentId,
      fromUtc: fromUtc,
      toUtc: toUtc,
    );
    var cash = 0.0;
    for (final o in orders) {
      final pays =
          await PosOrderService.instance.fetchPaymentsForOrder(o.id);
      if (pays.isNotEmpty) {
        for (final p in pays) {
          if (p.paymentMethod == PosPaymentMethod.cash) {
            cash += p.amount;
          }
        }
      } else {
        final pm = o.paymentMethod;
        if (pm == PosPaymentMethod.cash) {
          final lines = await PosOrderService.instance.fetchLines(o.id);
          var menu = 0.0;
          for (final l in lines) {
            final p = l.sellingPrice;
            if (p == null) continue;
            menu += l.quantity * p;
          }
          final grand = computePosOrderTotalsRaw(
            menuSubtotal: menu,
            discountAmount: o.discountAmount,
            serviceChargePercent: o.serviceChargePercent,
            tipsAmount: o.tipsAmount,
          ).grandTotal;
          cash += grand;
        }
      }
    }
    return cash;
  }

  double sumDisbursementAmounts(List<PosCashDisbursement> list) {
    var s = 0.0;
    for (final d in list) {
      s += d.amount;
    }
    return s;
  }
}
