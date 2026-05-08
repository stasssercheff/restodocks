import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/subscription_entitlements.dart';
import '../models/models.dart';
import '../utils/dev_log.dart';
import 'account_manager_supabase.dart';

class AiTtkQuotaCacheService {
  AiTtkQuotaCacheService._();
  static final AiTtkQuotaCacheService instance = AiTtkQuotaCacheService._();

  final Map<String, int> _remainingByEstablishmentAndDepartment = <String, int>{};

  String _scopeDepartment(String department) =>
      department.trim().toLowerCase().contains('bar') ? 'bar' : 'kitchen';

  String _cacheKey(String establishmentId, String department) =>
      '${establishmentId.trim()}|${_scopeDepartment(department)}';

  int? readCachedRemaining(
    String establishmentId, {
    String department = 'kitchen',
  }) {
    final est = establishmentId.trim();
    if (est.isEmpty) return null;
    return _remainingByEstablishmentAndDepartment[_cacheKey(est, department)];
  }

  Future<int?> preloadForCurrentSession({
    bool force = false,
    String department = 'kitchen',
  }) async {
    final account = AccountManagerSupabase();
    if (!_canCreateTtkWithAi(account)) return null;
    final establishmentId = _resolveAiQuotaEstablishmentId(account);
    if (establishmentId == null || establishmentId.isEmpty) return null;
    if (!force) {
      final cached = _remainingByEstablishmentAndDepartment[
          _cacheKey(establishmentId, department)];
      if (cached != null) return cached;
    }
    return refreshForEstablishment(
      establishmentId,
      account: account,
      department: department,
    );
  }

  Future<int?> refreshForEstablishment(
    String establishmentId, {
    AccountManagerSupabase? account,
    String department = 'kitchen',
  }) async {
    final resolved = establishmentId.trim();
    if (resolved.isEmpty) return null;
    final acc = account ?? AccountManagerSupabase();
    if (!_canCreateTtkWithAi(acc)) {
      _remainingByEstablishmentAndDepartment
          .remove(_cacheKey(resolved, department));
      return null;
    }
    try {
      final scopeDepartment = _scopeDepartment(department);
      final res = await Supabase.instance.client.functions.invoke(
        'ai-create-tech-card',
        body: <String, dynamic>{
          'establishmentId': resolved,
          'department': scopeDepartment,
          'checkOnly': true,
        },
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('ai-create-tech-card checkOnly returned invalid payload');
      }
      final limit = (data['limit'] as num?)?.toInt() ?? _aiTtkQuotaLimit(acc);
      final used = (data['used'] as num?)?.toInt() ?? 0;
      final remainingFromServer = (data['remaining'] as num?)?.toInt();
      final remaining = (remainingFromServer ?? (limit - used)).clamp(0, limit);
      _remainingByEstablishmentAndDepartment[
          _cacheKey(resolved, scopeDepartment)] = remaining;
      return remaining;
    } catch (e, st) {
      devLog('AiTtkQuotaCacheService.refreshForEstablishment: $e $st');
      return _remainingByEstablishmentAndDepartment[
          _cacheKey(resolved, department)];
    }
  }

  void clearForEstablishment(
    String establishmentId, {
    String? department,
  }) {
    final key = establishmentId.trim();
    if (key.isEmpty) return;
    if (department != null) {
      _remainingByEstablishmentAndDepartment
          .remove(_cacheKey(key, department));
      return;
    }
    _remainingByEstablishmentAndDepartment
        .removeWhere((k, _) => k.startsWith('$key|'));
  }

  String? _resolveAiQuotaEstablishmentId(AccountManagerSupabase account) {
    final est = account.establishment;
    if (est == null) return null;
    final dataId = est.dataEstablishmentId.trim();
    if (dataId.isNotEmpty) return dataId;
    final id = est.id.trim();
    return id.isEmpty ? null : id;
  }

  bool _canCreateTtkWithAi(AccountManagerSupabase account) =>
      account.subscriptionEntitlements.hasProLevelOrTrial;

  int _aiTtkQuotaLimit(AccountManagerSupabase account) {
    if (account.isTrialOnlyWithoutPaid) return 3;
    final tier = account.subscriptionEntitlements.paidTier;
    return tier == AppSubscriptionTier.ultra ? 300 : 100;
  }
}
