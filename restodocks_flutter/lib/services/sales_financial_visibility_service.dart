import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Доступ к колонкам себестоимости и продажной цены в отчётах продаж:
/// по умолчанию только владелец; для отдела «управление» — если включено в настройках.
class SalesFinancialVisibilityService extends ChangeNotifier {
  SalesFinancialVisibilityService._();
  static final SalesFinancialVisibilityService instance =
      SalesFinancialVisibilityService._();
  factory SalesFinancialVisibilityService() => instance;

  final Map<String, bool> _allowManagementByEstablishment = {};

  String _key(String establishmentId) =>
      'restodocks_sales_financials_management_$establishmentId';

  Future<void> initializeForEstablishment(String establishmentId) async {
    if (establishmentId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key(establishmentId));
      if (v != null) {
        _allowManagementByEstablishment[establishmentId] = v;
        notifyListeners();
      }
    } catch (_) {}
  }

  bool allowManagementFinancials(String establishmentId) {
    return _allowManagementByEstablishment[establishmentId] ?? false;
  }

  Future<void> setAllowManagementFinancials(
    String establishmentId,
    bool value,
  ) async {
    _allowManagementByEstablishment[establishmentId] = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(establishmentId), value);
    } catch (_) {}
  }
}
