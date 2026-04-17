import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_manager_supabase.dart';

enum UnitSystem { metric, imperial }

const _unitSystemKeyPrefix = 'restodocks_unit_system';

class UnitSystemPreferenceService extends ChangeNotifier {
  static final UnitSystemPreferenceService _instance =
      UnitSystemPreferenceService._internal();
  factory UnitSystemPreferenceService() => _instance;
  UnitSystemPreferenceService._internal();

  UnitSystem _unitSystem = UnitSystem.metric;
  bool _initialized = false;
  String? _loadedScopeKey;

  UnitSystem get unitSystem => _unitSystem;
  bool get isMetric => _unitSystem == UnitSystem.metric;
  bool get isImperial => _unitSystem == UnitSystem.imperial;
  bool get initialized => _initialized;

  String _storageKey() {
    final estId = AccountManagerSupabase().establishment?.id.trim();
    if (estId != null && estId.isNotEmpty) {
      return '${_unitSystemKeyPrefix}_est_$estId';
    }
    final uid = Supabase.instance.client.auth.currentUser?.id.trim();
    if (uid == null || uid.isEmpty) return _unitSystemKeyPrefix;
    return '${_unitSystemKeyPrefix}_$uid';
  }

  Future<void> ensureScopeSynced() async {
    final key = _storageKey();
    if (_loadedScopeKey == key && _initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key)?.trim().toLowerCase();
      _unitSystem = raw == 'imperial' ? UnitSystem.imperial : UnitSystem.metric;
      _loadedScopeKey = key;
    } catch (_) {
      _unitSystem = UnitSystem.metric;
      _loadedScopeKey = key;
    }
    if (_initialized) notifyListeners();
  }

  Future<void> initialize() async {
    await ensureScopeSynced();
    _initialized = true;
  }

  Future<void> setUnitSystem(UnitSystem value) async {
    await ensureScopeSynced();
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
