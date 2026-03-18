import 'package:shared_preferences/shared_preferences.dart';

const _keyPrefix = 'getting_started_document_read_';

/// Флаг «документ "Начало работы" прочитан» при первом входе.
/// Ключ по employeeId: один раз прочитал — больше не показываем при входе этого сотрудника.
class GettingStartedReadService {
  static Future<bool> isRead(String employeeId) async {
    if (employeeId.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix$employeeId') ?? false;
  }

  static Future<void> setRead(String employeeId) async {
    if (employeeId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$employeeId', true);
  }
}
