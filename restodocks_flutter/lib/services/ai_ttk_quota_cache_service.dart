import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'account_manager_supabase.dart';

class AiTtkQuotaCacheService {
  AiTtkQuotaCacheService._();
  static final AiTtkQuotaCacheService instance = AiTtkQuotaCacheService._();

  final Map<String, int> _remainingByEstablishment = <String, int>{};

  int? readCachedRemaining(String establishmentId) {
    final key = establishmentId.trim();
    if (key.isEmpty) return null;
    return _remainingByEstablishment[key];
  }

  Future<int?> preloadForCurrentSession({bool force = false}) async {
    final account = AccountManagerSupabase();
    if (!_canCreateTtkWithAi(account)) return null;
    final establishmentId = _resolveAiQuotaEstablishmentId(account);
    if (establishmentId == null || establishmentId.isEmpty) return null;
    if (!force) {
      final cached = _remainingByEstablishment[establishmentId];
      if (cached != null) return cached;
    }
    return refreshForEstablishment(establishmentId, account: account);
  }

  Future<int?> refreshForEstablishment(
    String establishmentId, {
    AccountManagerSupabase? account,
  }) async {
    final resolved = establishmentId.trim();
    if (resolved.isEmpty) return null;
    final acc = account ?? AccountManagerSupabase();
    if (!_canCreateTtkWithAi(acc)) {
      _remainingByEstablishment.remove(resolved);
      return null;
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ai-create-tech-card',
        body: <String, dynamic>{
          'establishmentId': resolved,
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
      _remainingByEstablishment[resolved] = remaining;
      return remaining;
    } catch (e, st) {
      devLog('AiTtkQuotaCacheService.refreshForEstablishment: $e $st');
      return _remainingByEstablishment[resolved];
    }
  }

  void clearForEstablishment(String establishmentId) {
    final key = establishmentId.trim();
    if (key.isEmpty) return;
    _remainingByEstablishment.remove(key);
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
