import 'package:shared_preferences/shared_preferences.dart';

import '../models/kitchen_bar_sales_models.dart';

SalesPlanCalendarDisplayMode _modeFromStorage(String? s) {
  return SalesPlanCalendarDisplayMode.values.firstWhere(
    (e) => e.name == s,
    orElse: () => SalesPlanCalendarDisplayMode.percent,
  );
}

/// Режим отображения календаря плана (проценты или сумма план/факт) — на устройстве.
class SalesPlanCalendarPrefsService {
  static String _key(String establishmentId) =>
      'restodocks_sales_plan_cal_mode_$establishmentId';

  static Future<SalesPlanCalendarDisplayMode> getMode(
      String establishmentId) async {
    if (establishmentId.isEmpty) {
      return SalesPlanCalendarDisplayMode.percent;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_key(establishmentId));
      return _modeFromStorage(s);
    } catch (_) {
      return SalesPlanCalendarDisplayMode.percent;
    }
  }

  static Future<void> setMode(
    String establishmentId,
    SalesPlanCalendarDisplayMode mode,
  ) async {
    if (establishmentId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(establishmentId), mode.name);
    } catch (_) {}
  }
}
