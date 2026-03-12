import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/dev_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для хранения черновиков инвентаризации и чек-листов в localStorage
class DraftStorageService {
  static const String _inventoryKey = 'draft_inventory';
  static const String _checklistKey = 'draft_checklist';

  /// Сохранить черновик инвентаризации
  Future<void> saveInventoryDraft(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(data);
      await prefs.setString(_inventoryKey, jsonString);
      devLog('Inventory draft saved: ${data.length} items');
    } catch (e) {
      devLog('Failed to save inventory draft: $e');
    }
  }

  /// Загрузить черновик инвентаризации
  Future<Map<String, dynamic>?> loadInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_inventoryKey);
      if (jsonString != null) {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        devLog('Inventory draft loaded: ${data.length} items');
        return data;
      }
    } catch (e) {
      devLog('Failed to load inventory draft: $e');
    }
    return null;
  }

  /// Удалить черновик инвентаризации
  Future<void> clearInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_inventoryKey);
      devLog('Inventory draft cleared');
    } catch (e) {
      devLog('Failed to clear inventory draft: $e');
    }
  }

  /// Проверить, есть ли черновик инвентаризации
  Future<bool> hasInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_inventoryKey);
    } catch (e) {
      return false;
    }
  }

  /// Сохранить черновик чек-листа (общий, для обратной совместимости)
  Future<void> saveChecklistDraft(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(data);
      await prefs.setString(_checklistKey, jsonString);
      devLog('Checklist draft saved: ${data.length} items');
    } catch (e) {
      devLog('Failed to save checklist draft: $e');
    }
  }

  /// Загрузить черновик чек-листа (общий)
  Future<Map<String, dynamic>?> loadChecklistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_checklistKey);
      if (jsonString != null) {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        devLog('Checklist draft loaded: ${data.length} items');
        return data;
      }
    } catch (e) {
      devLog('Failed to load checklist draft: $e');
    }
    return null;
  }

  /// Сохранить черновик редактирования чеклиста (по id)
  Future<void> saveChecklistEditDraft(String checklistId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_checklistKey}_edit_$checklistId', jsonEncode(data));
    } catch (e) {
      devLog('Failed to save checklist edit draft: $e');
    }
  }

  /// Загрузить черновик редактирования чеклиста (по id)
  Future<Map<String, dynamic>?> loadChecklistEditDraft(String checklistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('${_checklistKey}_edit_$checklistId');
      return jsonString != null ? jsonDecode(jsonString) as Map<String, dynamic>? : null;
    } catch (e) {
      return null;
    }
  }

  /// Удалить черновик редактирования чеклиста
  Future<void> clearChecklistEditDraft(String checklistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_checklistKey}_edit_$checklistId');
    } catch (_) {}
  }

  /// Сохранить черновик заполнения чеклиста (по id)
  Future<void> saveChecklistFillDraft(String checklistId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_checklistKey}_fill_$checklistId', jsonEncode(data));
    } catch (e) {
      devLog('Failed to save checklist fill draft: $e');
    }
  }

  /// Загрузить черновик заполнения чеклиста (по id)
  Future<Map<String, dynamic>?> loadChecklistFillDraft(String checklistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('${_checklistKey}_fill_$checklistId');
      return jsonString != null ? jsonDecode(jsonString) as Map<String, dynamic>? : null;
    } catch (e) {
      return null;
    }
  }

  /// Удалить черновик заполнения чеклиста
  Future<void> clearChecklistFillDraft(String checklistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_checklistKey}_fill_$checklistId');
    } catch (_) {}
  }

  // ── ТТК (создание/редактирование) ────────────────────────────────────────────

  static const String _techCardEditPrefix = 'draft_tech_card_edit_';

  Future<void> saveTechCardEditDraft(String techCardId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_techCardEditPrefix$techCardId', jsonEncode(data));
    } catch (e) {
      devLog('Failed to save tech card draft: $e');
    }
  }

  Future<Map<String, dynamic>?> loadTechCardEditDraft(String techCardId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('$_techCardEditPrefix$techCardId');
      return s != null ? jsonDecode(s) as Map<String, dynamic> : null;
    } catch (e) {
      devLog('Failed to load tech card draft: $e');
      return null;
    }
  }

  Future<void> clearTechCardEditDraft(String techCardId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_techCardEditPrefix$techCardId');
    } catch (_) {}
  }

  // ── iiko-инвентаризация ──────────────────────────────────────────────────────

  static const String _iikoInventoryKey = 'draft_iiko_inventory';

  Future<void> saveIikoInventoryDraft(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_iikoInventoryKey, jsonEncode(data));
    } catch (e) {
      devLog('Failed to save iiko draft: $e');
    }
  }

  Future<Map<String, dynamic>?> loadIikoInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_iikoInventoryKey);
      return s != null ? jsonDecode(s) as Map<String, dynamic> : null;
    } catch (e) {
      devLog('Failed to load iiko draft: $e');
      return null;
    }
  }

  Future<void> clearIikoInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_iikoInventoryKey);
    } catch (_) {}
  }

  Future<bool> hasIikoInventoryDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_iikoInventoryKey);
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────

  /// Удалить черновик чек-листа (общий)
  Future<void> clearChecklistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_checklistKey);
      devLog('Checklist draft cleared');
    } catch (e) {
      devLog('Failed to clear checklist draft: $e');
    }
  }

  /// Проверить, есть ли черновик чек-листа (общий)
  Future<bool> hasChecklistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_checklistKey);
    } catch (e) {
      return false;
    }
  }
}