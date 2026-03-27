import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivacyPolicyConsentService {
  static const String policyType = 'privacy_policy';
  static const String currentVersion = '1.0';

  bool? _cachedHasAccepted;
  String? _cachedUserId;

  SupabaseClient get _client => Supabase.instance.client;

  void clearCache() {
    _cachedHasAccepted = null;
    _cachedUserId = null;
  }

  Future<bool> hasAcceptedCurrentVersion({bool forceRefresh = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    if (!forceRefresh &&
        _cachedHasAccepted != null &&
        _cachedUserId == user.id) {
      return _cachedHasAccepted!;
    }

    final rows = await _client
        .from('user_policy_consents')
        .select('id')
        .eq('user_id', user.id)
        .eq('policy_type', policyType)
        .eq('policy_version', currentVersion)
        .limit(1);

    final accepted = rows is List && rows.isNotEmpty;
    _cachedHasAccepted = accepted;
    _cachedUserId = user.id;
    return accepted;
  }

  Future<void> acceptCurrentVersion({
    required String locale,
    String? userAgent,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('User is not authenticated');
    }

    await _client.from('user_policy_consents').upsert({
      'user_id': user.id,
      'policy_type': policyType,
      'policy_version': currentVersion,
      'accepted_at': DateTime.now().toUtc().toIso8601String(),
      'locale': locale,
      'user_agent': userAgent,
    }, onConflict: 'user_id,policy_type,policy_version');

    _cachedHasAccepted = true;
    _cachedUserId = user.id;
  }

  String readWebUserAgent() {
    if (!kIsWeb) return '';
    return '';
  }
}
