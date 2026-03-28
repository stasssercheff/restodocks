import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyTimerSec = 'restodocks_pos_order_list_timer_sec';
const _keySubtitlePreset = 'restodocks_pos_order_list_subtitle_preset';

/// Настройки экранов списков заказов POS: интервал обновления таймера и размер подписей.
class PosOrdersDisplaySettingsService extends ChangeNotifier {
  PosOrdersDisplaySettingsService._();
  static final PosOrdersDisplaySettingsService instance =
      PosOrdersDisplaySettingsService._();
  factory PosOrdersDisplaySettingsService() => instance;

  static const List<int> allowedTimerSeconds = [10, 15, 30, 60];

  int _timerSec = 30;
  int _subtitlePreset = 2;

  int get timerIntervalSeconds {
    if (!allowedTimerSeconds.contains(_timerSec)) return 30;
    return _timerSec;
  }

  /// Множитель к `bodySmall` для подписи строки (гости, статус, таймер).
  double get listSubtitleScaleFactor {
    switch (_subtitlePreset.clamp(1, 3)) {
      case 1:
        return 0.88;
      case 3:
        return 1.14;
      default:
        return 1.0;
    }
  }

  int get subtitlePreset => _subtitlePreset.clamp(1, 3);

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getInt(_keyTimerSec) ?? 30;
      _timerSec = allowedTimerSeconds.contains(t) ? t : 30;
      _subtitlePreset = (prefs.getInt(_keySubtitlePreset) ?? 2).clamp(1, 3);
    } catch (_) {}
  }

  Future<void> setTimerIntervalSeconds(int seconds) async {
    final s = allowedTimerSeconds.contains(seconds) ? seconds : 30;
    if (_timerSec == s) return;
    _timerSec = s;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTimerSec, s);
    } catch (_) {}
  }

  Future<void> setSubtitlePreset(int preset) async {
    final p = preset.clamp(1, 3);
    if (_subtitlePreset == p) return;
    _subtitlePreset = p;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySubtitlePreset, p);
    } catch (_) {}
  }
}
