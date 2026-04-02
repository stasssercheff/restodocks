import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import '../services/account_manager_supabase.dart';
import '../utils/dev_log.dart';

class PendingOwnerRole {
  static const _kPrefix = 'pending_owner_role:';

  static String _keyForEmail(String email) =>
      '$_kPrefix${email.trim().toLowerCase()}';

  static Future<void> saveForEmail(String email, String? role) async {
    final normalized = role?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'owner') {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForEmail(email), normalized);
  }

  static Future<void> clearForEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForEmail(email));
  }

  static Future<void> applyIfNeeded(AccountManagerSupabase account) async {
    final emp = account.currentEmployee;
    if (emp == null || !emp.hasRole('owner')) return;
    final email = emp.email.trim().toLowerCase();
    if (email.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_keyForEmail(email))?.trim().toLowerCase();
    if (pending == null || pending.isEmpty || pending == 'owner') return;
    if (emp.roles.contains(pending)) {
      await clearForEmail(email);
      return;
    }
    try {
      final updated = emp.copyWith(roles: <String>[...emp.roles, pending]);
      await account.updateEmployee(updated);
      await clearForEmail(email);
    } catch (e) {
      try {
        final roles = <String>[...emp.roles, pending];
        await Supabase.instance.client.rpc(
          'patch_my_employee_profile',
          params: {
            'p_patch': {
              'roles': roles,
            },
          },
        );
        // Pull fresh profile so Settings/Home reflect the newly persisted role immediately.
        await account.initialize(forceRetryFromAuth: true);
        await clearForEmail(email);
      } catch (e2) {
        devLog('PendingOwnerRole.applyIfNeeded: $e / rpc fallback: $e2');
      }
    }
  }
}
