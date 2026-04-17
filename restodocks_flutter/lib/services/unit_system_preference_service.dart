import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UnitSystem { metric, imperial }

const _unitSystemKeyPrefix = 'restodocks_unit_system';

class UnitSystemPreferenceService extends ChangeNotifier {
  static final UnitSystemPreferenceService _instance =
      UnitSystemPreferenceService._internal();
  factory UnitSystemPreferenceService() => _instance;
  UnitSystemPreferenceService._internal();

  UnitSystem _unitSystem = UnitSystem.metric;
  bool _initialized = false;

  UnitSystem get unitSystem => _unitSystem;
  bool get isMetric => _unitSystem == UnitSystem.metric;
  bool get isImperial => _unitSystem == UnitSystem.imperial;
  bool get initialized => _initialized;

  String _storageKey() {
    final uid = Supabase.instance.client.auth.currentUser?.id?.trim();
    if (uid == null || uid.isEmpty) return _unitSystemKeyPrefix;
    return '${_unitSystemKeyPrefix}_$uid';
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey())?.trim().toLowerCase();
      _unitSystem = raw == 'imperial' ? UnitSystem.imperial : UnitSystem.metric;
    } catch (_) {
      _unitSystem = UnitSystem.metric;
    }
    _initialized = true;
  }

  Future<void> setUnitSystem(UnitSystem value) async {
    if (_unitSystem == value) return;
    _unitSystem = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey(),
        value == UnitSystem.imperial ? 'imperial' : 'metric',
      );
    } catch (_) {}
  }
}
