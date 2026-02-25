import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_model.dart';
import 'supabase_service.dart';

const _keyPrefix = 'restodocks_schedule_';
const _table = 'establishment_schedule_data';

/// Загружает график: приоритет Supabase, fallback SharedPreferences с миграцией в Supabase.
Future<ScheduleModel> loadSchedule(String establishmentId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';

  // 1. Пробуем Supabase
  try {
    final supabase = SupabaseService().client;
    final res = await supabase
        .from(_table)
        .select('data')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (res != null && res['data'] != null) {
      final json = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
      if (json != null && json.isNotEmpty) {
        return ScheduleModel.fromJson(json);
      }
    }
  } catch (_) {
    // Ошибка сети — fallback на локальные данные
  }

  // 2. Fallback: SharedPreferences
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    return _defaultSchedule();
  }
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final model = ScheduleModel.fromJson(json);
    // Миграция: переносим в Supabase при первой загрузке (fire-and-forget)
    unawaited(_migrateToSupabase(establishmentId, json));
    return model;
  } catch (_) {
    return _defaultSchedule();
  }
}

/// Сохраняет график в Supabase; при ошибке — в SharedPreferences (fallback).
Future<bool> saveSchedule(String establishmentId, ScheduleModel model) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final json = model.toJson();
  final jsonStr = jsonEncode(json);

  try {
    final supabase = SupabaseService().client;
    final existing = await supabase
        .from(_table)
        .select('id')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (existing != null) {
      await supabase
          .from(_table)
          .update({'data': json, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('establishment_id', establishmentId);
    } else {
      await supabase.from(_table).insert({
        'establishment_id': establishmentId,
        'data': json,
      });
    }
    await prefs.setString(key, jsonStr); // Локальный бэкап
    return true;
  } catch (_) {
    return prefs.setString(key, jsonStr); // Fallback при отсутствии сети
  }
}

Future<void> _migrateToSupabase(String establishmentId, Map<String, dynamic> json) async {
  try {
    await SupabaseService().client.from(_table).upsert(
      {
        'establishment_id': establishmentId,
        'data': json,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'establishment_id',
    );
  } catch (_) {}
}

ScheduleModel _defaultSchedule() {
  final now = DateTime.now();
  return ScheduleModel(
    sections: ScheduleModel.defaultSections,
    startDate: DateTime(now.year, 1, 1),
    numWeeks: 208,
  );
}
