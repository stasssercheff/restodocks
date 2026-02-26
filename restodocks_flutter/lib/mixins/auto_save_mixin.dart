import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/draft_storage_service.dart';
import '../services/web_lifecycle_saver_stub.dart'
    if (dart.library.html) '../services/web_lifecycle_saver_web.dart' as web_lifecycle;

/// Mixin для автосохранения состояния экрана
mixin AutoSaveMixin<T extends StatefulWidget> on State<T> {
  final DraftStorageService _draftStorage = DraftStorageService();

  /// Ключ для сохранения (должен быть переопределен в классе)
  String get draftKey;

  /// Метод для получения текущего состояния (должен быть переопределен)
  Map<String, dynamic> getCurrentState();

  /// Метод для восстановления состояния (должен быть переопределен)
  Future<void> restoreState(Map<String, dynamic> data);

  Timer? _saveTimer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeAutoSave();

    // Восстановить состояние при инициализации
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _restoreDraft();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Инициализировать автосохранение
  void _initializeAutoSave() {
    WidgetsBinding.instance.addObserver(_LifecycleObserver(
      onPaused: _handleAppPaused,
      onResumed: _handleAppResumed,
    ));
    if (kIsWeb) {
      web_lifecycle.registerWebLifecycleSaver(() => _saveDraft());
    }
  }

  /// Восстановить черновик
  Future<void> _restoreDraft() async {
    if (!mounted) return;

    try {
      final hasDraft = await _hasDraft();
      if (hasDraft) {
        final data = await _loadDraft();
        if (data != null && mounted) {
          await restoreState(data);
          _isInitialized = true;
          debugPrint('Draft restored for $draftKey');
        }
      } else {
        _isInitialized = true;
      }
    } catch (e) {
      debugPrint('Failed to restore draft: $e');
      _isInitialized = true;
    }
  }

  /// Запланировать сохранение с задержкой (данные намертво в localStorage)
  void scheduleSave() {
    if (!_isInitialized) return;

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _saveDraft();
      }
    });
  }

  /// Сохранить черновик немедленно
  Future<void> saveImmediately() async {
    if (!_isInitialized) return;
    await _saveDraft();
  }

  /// Очистить черновик
  Future<void> clearDraft() async {
    await _clearDraft();
  }

  /// Есть ли черновик
  Future<bool> hasDraft() async {
    return await _hasDraft();
  }

  // Приватные методы для работы с хранилищем

  Future<void> _saveDraft() async {
    try {
      final data = getCurrentState();
      await _saveToStorage(data);
    } catch (e) {
      debugPrint('Failed to save draft: $e');
    }
  }

  Future<Map<String, dynamic>?> _loadDraft() async {
    return await _loadFromStorage();
  }

  Future<void> _clearDraft() async {
    await _clearFromStorage();
  }

  Future<bool> _hasDraft() async {
    return await _hasInStorage();
  }

  // Методы, которые должны быть реализованы в зависимости от типа

  Future<void> _saveToStorage(Map<String, dynamic> data) async {
    if (draftKey == 'inventory') {
      await _draftStorage.saveInventoryDraft(data);
    } else if (draftKey == 'checklist') {
      await _draftStorage.saveChecklistDraft(data);
    } else if (draftKey.startsWith('checklist_edit_')) {
      final id = draftKey.replaceFirst('checklist_edit_', '');
      await _draftStorage.saveChecklistEditDraft(id, data);
    } else if (draftKey.startsWith('checklist_fill_')) {
      final id = draftKey.replaceFirst('checklist_fill_', '');
      await _draftStorage.saveChecklistFillDraft(id, data);
    }
  }

  Future<Map<String, dynamic>?> _loadFromStorage() async {
    if (draftKey == 'inventory') {
      return await _draftStorage.loadInventoryDraft();
    } else if (draftKey == 'checklist') {
      return await _draftStorage.loadChecklistDraft();
    } else if (draftKey.startsWith('checklist_edit_')) {
      final id = draftKey.replaceFirst('checklist_edit_', '');
      return await _draftStorage.loadChecklistEditDraft(id);
    } else if (draftKey.startsWith('checklist_fill_')) {
      final id = draftKey.replaceFirst('checklist_fill_', '');
      return await _draftStorage.loadChecklistFillDraft(id);
    }
    return null;
  }

  Future<void> _clearFromStorage() async {
    if (draftKey == 'inventory') {
      await _draftStorage.clearInventoryDraft();
    } else if (draftKey == 'checklist') {
      await _draftStorage.clearChecklistDraft();
    } else if (draftKey.startsWith('checklist_edit_')) {
      final id = draftKey.replaceFirst('checklist_edit_', '');
      await _draftStorage.clearChecklistEditDraft(id);
    } else if (draftKey.startsWith('checklist_fill_')) {
      final id = draftKey.replaceFirst('checklist_fill_', '');
      await _draftStorage.clearChecklistFillDraft(id);
    }
  }

  Future<bool> _hasInStorage() async {
    if (draftKey == 'inventory') {
      return await _draftStorage.hasInventoryDraft();
    } else if (draftKey == 'checklist') {
      return await _draftStorage.hasChecklistDraft();
    } else if (draftKey.startsWith('checklist_edit_')) {
      final data = await _loadFromStorage();
      return data != null;
    } else if (draftKey.startsWith('checklist_fill_')) {
      final data = await _loadFromStorage();
      return data != null;
    }
    return false;
  }

  // Обработчики жизненного цикла

  void _handleAppPaused() {
    // Приложение уходит в фон - сохранить немедленно
    if (mounted && _isInitialized) {
      _saveDraft();
    }
  }

  void _handleAppResumed() {
    // Приложение возвращается - ничего не делаем
  }
}

/// Наблюдатель жизненного цикла приложения
class _LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onPaused;
  final VoidCallback onResumed;

  _LifecycleObserver({
    required this.onPaused,
    required this.onResumed,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        onPaused();
        break;
      case AppLifecycleState.resumed:
        onResumed();
        break;
      default:
        break;
    }
  }
}