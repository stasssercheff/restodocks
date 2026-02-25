import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_model.dart';

const _keyPrefix = 'restodocks_schedule_';

Future<ScheduleModel> loadSchedule(String establishmentId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    final now = DateTime.now();
    return ScheduleModel(
      sections: ScheduleModel.defaultSections,
      startDate: DateTime(now.year, 1, 1),
      numWeeks: 208, // 4 года — будущие даты не ограничены
    );
  }
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ScheduleModel.fromJson(json);
  } catch (_) {
    final now = DateTime.now();
    // Начинаем с 1 января текущего года вместо понедельника текущей недели
    return ScheduleModel(startDate: DateTime(now.year, 1, 1), numWeeks: 208);
  }
}

/// Возвращает true при успешном сохранении.
Future<bool> saveSchedule(String establishmentId, ScheduleModel model) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final jsonStr = jsonEncode(model.toJson());
  return prefs.setString(key, jsonStr);
}
