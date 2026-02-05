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
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return ScheduleModel(
      sections: ScheduleModel.defaultSections,
      startDate: DateTime(monday.year, monday.month, monday.day),
    );
  }
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ScheduleModel.fromJson(json);
  } catch (_) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return ScheduleModel(startDate: DateTime(monday.year, monday.month, monday.day));
  }
}

Future<void> saveSchedule(String establishmentId, ScheduleModel model) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  await prefs.setString(key, jsonEncode(model.toJson()));
}
