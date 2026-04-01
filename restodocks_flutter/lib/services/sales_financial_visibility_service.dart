import 'package:flutter/foundation.dart';

import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Доступ к колонкам себестоимости и продажной цены: настройка заведения в Supabase (как POS).
class SalesFinancialVisibilityService extends ChangeNotifier {
  SalesFinancialVisibilityService._();
  static final SalesFinancialVisibilityService instance =
      SalesFinancialVisibilityService._();
  factory SalesFinancialVisibilityService() => instance;

  final SupabaseService _supabase = SupabaseService();
  final Map<String, bool> _allowManagementByEstablishment = {};

  Future<void> initializeForEstablishment(String establishmentId) async {
    if (establishmentId.isEmpty) return;
    try {
      final row = await _supabase.client
          .from('establishment_sales_settings')
          .select('show_financials_to_management')
          .eq('establishment_id', establishmentId)
          .maybeSingle();
      final v = row?['show_financials_to_management'];
      _allowManagementByEstablishment[establishmentId] = v == true;
      notifyListeners();
    } catch (e, st) {
      devLog('SalesFinancialVisibilityService: load $e $st');
      _allowManagementByEstablishment[establishmentId] = false;
    }
  }

  bool allowManagementFinancials(String establishmentId) {
    return _allowManagementByEstablishment[establishmentId] ?? false;
  }

  Future<void> setAllowManagementFinancials(
    String establishmentId,
    bool value,
  ) async {
    if (establishmentId.isEmpty) return;
    _allowManagementByEstablishment[establishmentId] = value;
    notifyListeners();
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.client.from('establishment_sales_settings').upsert(
        <String, dynamic>{
          'establishment_id': establishmentId,
          'show_financials_to_management': value,
          'updated_at': now,
        },
        onConflict: 'establishment_id',
      );
    } catch (e, st) {
      devLog('SalesFinancialVisibilityService: upsert $e $st');
      rethrow;
    }
  }
}
