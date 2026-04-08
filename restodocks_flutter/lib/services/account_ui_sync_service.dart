import 'dart:async';

import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../utils/dev_log.dart';
import 'localization_service.dart';
import 'owner_view_preference_service.dart';
import 'supabase_service.dart';
import 'theme_service.dart';

/// Синхронизация настроек отображения учётной записи с профилем `employees`:
/// язык, тема, режим «собственник / должность» и др. — изменение на одном устройстве
/// подтягивается при входе и при возврате в приложение на других устройствах.
class AccountUiSyncService {
  AccountUiSyncService._();
  static final AccountUiSyncService instance = AccountUiSyncService._();

  final SupabaseService _supabase = SupabaseService();

  /// После RPC `patch_my_employee_profile` — обновить кэш текущего сотрудника.
  void Function(Employee employee)? onEmployeeMerged;

  void _notifyMerge(dynamic res) {
    if (res is! Map) return;
    final m = Map<String, dynamic>.from(res);
    m['password'] = m['password_hash'] ?? '';
    try {
      final emp = Employee.fromJson(m);
      onEmployeeMerged?.call(emp);
    } catch (e, st) {
      devLog('AccountUiSync merge parse: $e $st');
    }
  }

  /// Применить данные с сервера к локальному UI (без записи в БД).
  Future<void> applyRemoteToLocal(Employee e) async {
    await ThemeService().applyFromServer(e.uiTheme);
    await OwnerViewPreferenceService().applyFromServer(e.uiViewAsOwner);
    // Account is the source of truth for display settings across devices.
    // Do not push local/browser language back to profile on login.
    await _applyPreferredLanguage(e.preferredLanguage);
  }

  /// После входа / загрузки профиля: подтянуть сервер → локально, при пустых колонках — записать текущие prefs на сервер.
  Future<void> applyAfterLogin(Employee e) async {
    await applyRemoteToLocal(e);
    await seedServerIfNeeded(e);
  }

  Future<void> _applyPreferredLanguage(String raw) async {
    final p = raw.trim().toLowerCase();
    if (p.isEmpty) return;
    if (!LocalizationService.supportedLocales.any((l) => l.languageCode == p)) {
      return;
    }
    final loc = LocalizationService();
    if (loc.currentLanguageCode != p) {
      await loc.setLocale(Locale(p));
    }
  }

  Future<void> seedServerIfNeeded(Employee e) async {
    if (!_supabase.isAuthenticated) return;
    final patch = <String, dynamic>{};
    if (e.uiTheme == null) {
      patch['ui_theme'] = ThemeService().isDark ? 'dark' : 'light';
    }
    if (e.uiViewAsOwner == null) {
      patch['ui_view_as_owner'] = OwnerViewPreferenceService().viewAsOwner;
    }
    if (patch.isEmpty) return;
    try {
      final res = await _supabase.client.rpc(
        'patch_my_employee_profile',
        params: {'p_patch': patch},
      );
      _notifyMerge(res);
    } catch (e) {
      devLog('AccountUiSync seedServerIfNeeded: $e');
    }
  }

  Future<void> persistThemeFromUser(ThemeMode mode) async {
    if (!_supabase.isAuthenticated) return;
    try {
      final res = await _supabase.client.rpc(
        'patch_my_employee_profile',
        params: {
          'p_patch': {
            'ui_theme': mode == ThemeMode.dark ? 'dark' : 'light',
          },
        },
      );
      _notifyMerge(res);
    } catch (e) {
      devLog('AccountUiSync persistTheme: $e');
    }
  }

  Future<void> persistViewAsOwnerFromUser(bool value) async {
    if (!_supabase.isAuthenticated) return;
    try {
      final res = await _supabase.client.rpc(
        'patch_my_employee_profile',
        params: {
          'p_patch': {'ui_view_as_owner': value},
        },
      );
      _notifyMerge(res);
    } catch (e) {
      devLog('AccountUiSync persistViewAsOwner: $e');
    }
  }

  /// Обновить профиль с сервера (тема/язык/роль в данных) при возврате в приложение.
  Future<void> refreshEmployeeProfileFromServer() async {
    if (!_supabase.isAuthenticated) return;
    final uid = _supabase.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _supabase.client
          .from('employees')
          .select()
          .or('id.eq.$uid,auth_user_id.eq.$uid')
          .eq('is_active', true)
          .limit(1);
      if (rows.isEmpty) return;
      final m = Map<String, dynamic>.from(rows.first as Map);
      m['password'] = m['password_hash'] ?? '';
      final emp = Employee.fromJson(m);
      onEmployeeMerged?.call(emp);
      await applyRemoteToLocal(emp);
    } catch (e) {
      devLog('AccountUiSync refresh: $e');
    }
  }
}
