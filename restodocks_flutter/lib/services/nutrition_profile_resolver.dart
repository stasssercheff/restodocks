import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import 'account_manager_supabase.dart';
import 'ai_service_supabase.dart';
import 'nutrition_api_service.dart';
import 'product_store_supabase.dart';
import '../utils/dev_log.dart';
import '../utils/product_name_utils.dart';

/// Resolve nutrition data for a product via "shadow matching" to nutrition_profiles.
///
/// Goal:
/// - Do NOT change user-visible product names.
/// - Fill missing legacy KBJU fields in `products` to keep current calculations intact.
/// - Build `nutrition_profiles` + aliases + links for stable future re-matching.
class NutritionProfileResolver {
  final SupabaseClient _client = Supabase.instance.client;
  final AiServiceSupabase _ai = AiServiceSupabase();

  /// После первой ошибки «таблицы нет / не в schema cache» не дёргаем nutrition-таблицы
  /// до перезагрузки приложения (иначе десятки 404 в консоли на Pages без миграций).
  static bool _nutritionRelationsUnavailable = false;

  static bool _isMissingNutritionRelationError(Object e) {
    if (e is PostgrestException) {
      final code = e.code;
      if (code == 'PGRST205' || code == '42P01') return true;
      final blob =
          '${e.code ?? ''} ${e.message} ${e.details ?? ''} ${e.hint ?? ''}'
              .toLowerCase();
      if (blob.contains('pgrst205') ||
          blob.contains('42p01') ||
          blob.contains('does not exist') ||
          blob.contains('schema cache') ||
          blob.contains('could not find the table')) {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('pgrst205') ||
        s.contains('42p01') ||
        s.contains('could not find the table');
  }

  /// Anon или JWT ещё не подтянут на web: RLS не даёт SELECT → 403 / 42501.
  /// После неудачного refresh выставляем [_nutritionRelationsUnavailable], чтобы не спамить 403.
  static bool _isNutritionLinksAccessDenied(Object e) {
    if (e is PostgrestException) {
      final code = (e.code ?? '').toUpperCase();
      if (code == '42501') return true;
      final blob =
          '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();
      if (blob.contains('permission denied') ||
          blob.contains('not authorized') ||
          blob.contains('jwt')) {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('statuscode: 403') ||
        (s.contains('403') && s.contains('forbidden'));
  }

  /// Normalize input to a deterministic key for alias/profile lookup.
  /// Keep it conservative: remove obvious noise (units/quantities/prefixes), but don't rewrite semantics.
  String normalizeNutritionKey(String input) {
    var s = stripIikoPrefix(input).trim().toLowerCase();

    // Remove common quantity+unit patterns (e.g. "1кг", "250 г", "2 шт").
    s = s.replaceAll(
        RegExp(r'\b\d+(?:[.,]\d+)?\s*(кг|г|шт|мл|л|уп|пач)\b'), ' ');

    // Remove standalone units & service tokens.
    s = s
        .replaceAll(
            RegExp(r'\bкг\b|\bг\b|\bшт\b|\bмл\b|\bл\b|\bуп\b|\bпач\b'), ' ')
        .replaceAll(
            RegExp(r'\bзаказ\b|\bпоставка\b|\bпартия\b|\bупаковка\b'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
            ' '); // punctuation -> space

    // Collapse whitespace.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  bool _needsCalories(Product p) => p.calories == null || p.calories == 0;
  bool _needsProtein(Product p) => p.protein == null;
  bool _needsFat(Product p) => p.fat == null;
  bool _needsCarbs(Product p) => p.carbs == null;
  bool _needsGluten(Product p) => p.containsGluten == null;
  bool _needsLactose(Product p) => p.containsLactose == null;

  bool needsAnyNutrition(Product p) {
    if (p.kbjuManuallyConfirmed) return false;
    return _needsCalories(p) ||
        _needsProtein(p) ||
        _needsFat(p) ||
        _needsCarbs(p);
  }

  Future<bool> resolveAndApplyMissingNutrition({
    required ProductStoreSupabase store,
    required Product product,
    required String reason,
  }) async {
    if (_client.auth.currentSession == null ||
        _client.auth.currentUser == null) {
      return false;
    }
    final am = AccountManagerSupabase();
    if (!am.isLoggedInSync) return false;
    if (_client.auth.currentSession == null) return false;
    final dataEst = am.dataEstablishmentId?.trim();
    if (dataEst == null || dataEst.isEmpty) return false;
    if (!needsAnyNutrition(product)) return false;

    final missingCalories = _needsCalories(product);
    final missingProtein = _needsProtein(product);
    final missingFat = _needsFat(product);
    final missingCarbs = _needsCarbs(product);
    final missingGluten = _needsGluten(product);
    final missingLactose = _needsLactose(product);

    final ruName = product.getLocalizedName('ru').trim();
    final anyName = ruName.isNotEmpty ? ruName : product.name.trim();

    if (_nutritionRelationsUnavailable) return false;

    try {
      // 1) Existing link -> profile -> apply.
      dynamic linkRow;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          linkRow = await _client
              .from('product_nutrition_links')
              .select(
                  'nutrition_profile_id, match_type, match_confidence, match_source')
              .eq('product_id', product.id)
              .limit(1);
          break;
        } catch (e) {
          if (_isMissingNutritionRelationError(e)) {
            _nutritionRelationsUnavailable = true;
            devLog(
              'NutritionProfileResolver: product_nutrition_links unavailable, '
              'skipping nutrition backfill until reload (apply DB migration if needed)',
            );
            return false;
          }
          if (_isNutritionLinksAccessDenied(e)) {
            if (attempt == 0) {
              try {
                await _client.auth.refreshSession();
                await Future<void>.delayed(const Duration(milliseconds: 450));
              } catch (_) {}
              continue;
            }
            devLog(
              'NutritionProfileResolver: product_nutrition_links access denied '
              '(anon or session not ready): $e',
            );
            // Один раз на сессию: иначе десятки 403 в консоли на web (RLS / миграция anon SELECT).
            _nutritionRelationsUnavailable = true;
            return false;
          }
          rethrow;
        }
      }
      if (linkRow is List && linkRow.isNotEmpty) {
        final m = Map<String, dynamic>.from(linkRow.first as Map);
        final profileId = m['nutrition_profile_id']?.toString();
        if (profileId != null && profileId.isNotEmpty) {
          final profile = await _fetchNutritionProfile(profileId);
          if (profile != null) {
            final did = await _applyProfileToProductIfMissing(
              store: store,
              product: product,
              profile: profile,
              allowCalories: missingCalories,
              allowProtein: missingProtein,
              allowFat: missingFat,
              allowCarbs: missingCarbs,
              allowGluten: missingGluten,
              allowLactose: missingLactose,
            );
            if (did) return true;
          }
        }
      }

      // 2) Alias lookup -> profile -> link + apply.
      final candidateKeys = <String>{
        normalizeNutritionKey(anyName),
        normalizeNutritionKey(product.name),
      }.where((k) => k.isNotEmpty).toList();

      for (final key in candidateKeys) {
        final aliasRow = await _client
            .from('nutrition_aliases')
            .select('nutrition_profile_id')
            .eq('normalized_input', key)
            .limit(1);
        if (aliasRow is! List || aliasRow.isEmpty) continue;
        final profileId = aliasRow.first['nutrition_profile_id']?.toString();
        if (profileId == null || profileId.isEmpty) continue;

        final profile = await _fetchNutritionProfile(profileId);
        if (profile == null) continue;

        final did = await _applyProfileToProductIfMissing(
          store: store,
          product: product,
          profile: profile,
          allowCalories: missingCalories,
          allowProtein: missingProtein,
          allowFat: missingFat,
          allowCarbs: missingCarbs,
          allowGluten: missingGluten,
          allowLactose: missingLactose,
        );

        // Always create/update link after successful resolution.
        await _upsertProductLink(
          productId: product.id,
          profileId: profileId,
          matchType: 'exact_alias',
          matchSource: 'nutrition_aliases:$reason',
          matchConfidence: 0.85,
          normalizedQuery: key,
          inputSnapshot: anyName,
        );

        return did;
      }

      // 3) No alias/profile: AI-normalize to canonical name, then create profile.
      final normalizedNames = await _tryAiNormalizeSingle(anyName);
      final canonicalName =
          normalizedNames.isNotEmpty ? normalizedNames.first : anyName;
      final canonicalKey = normalizeNutritionKey(canonicalName);
      if (canonicalKey.isEmpty) return false;

      final profile = await _getOrCreateNutritionProfileFromCanonicalName(
        canonicalName: canonicalName,
        canonicalKey: canonicalKey,
      );

      final did = await _applyProfileToProductIfMissing(
        store: store,
        product: product,
        profile: profile,
        allowCalories: missingCalories,
        allowProtein: missingProtein,
        allowFat: missingFat,
        allowCarbs: missingCarbs,
        allowGluten: missingGluten,
        allowLactose: missingLactose,
      );

      await _upsertProductLink(
        productId: product.id,
        profileId: profile['id'] as String,
        matchType: 'ai',
        matchSource: 'openfoodfacts:$reason',
        matchConfidence: 0.7,
        normalizedQuery: normalizeNutritionKey(anyName),
        inputSnapshot: anyName,
      );

      // Teach aliases for next time (so system works better for "opaque" names).
      for (final key in candidateKeys) {
        await _upsertNutritionAlias(
          normalizedInput: key,
          profileId: profile['id'] as String,
          confidence: 0.7,
        );
      }

      return did;
    } catch (e) {
      devLog(
          'NutritionProfileResolver: resolve failed for "${product.name}": $e');
      return false;
    }
  }

  Future<List<String>> _tryAiNormalizeSingle(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final normalized = await _ai.normalizeProductNames([trimmed]);
      return normalized.where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _fetchNutritionProfile(String profileId) async {
    final rows = await _client
        .from('nutrition_profiles')
        .select(
            'id, canonical_key, calories, protein, fat, carbs, contains_gluten, contains_lactose, confidence, status')
        .eq('id', profileId)
        .limit(1);
    if (rows is List && rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchNutritionProfileByCanonicalKey(
      String canonicalKey) async {
    final rows = await _client
        .from('nutrition_profiles')
        .select(
            'id, canonical_key, calories, protein, fat, carbs, contains_gluten, contains_lactose, confidence, status')
        .eq('canonical_key', canonicalKey)
        .limit(1);
    if (rows is List && rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>> _getOrCreateNutritionProfileFromCanonicalName({
    required String canonicalName,
    required String canonicalKey,
  }) async {
    final existing = await _client
        .from('nutrition_profiles')
        .select(
            'id, calories, protein, fat, carbs, contains_gluten, contains_lactose, status')
        .eq('canonical_key', canonicalKey)
        .limit(1);
    if (existing is List && existing.isNotEmpty) {
      final first = Map<String, dynamic>.from(existing.first as Map);
      final hasAny = (first['calories'] != null &&
              (first['calories'] as num).toDouble() > 0) ||
          (first['protein'] != null &&
              (first['protein'] as num).toDouble() > 0) ||
          (first['fat'] != null && (first['fat'] as num).toDouble() > 0) ||
          (first['carbs'] != null && (first['carbs'] as num).toDouble() > 0);
      if (hasAny) return first;
      // else: refresh by fetching external nutrition again
    }

    final nutrition = await NutritionApiService.fetchNutrition(canonicalName);
    if (nutrition == null || !nutrition.hasData) {
      // Create empty-but-existing profile to keep links/aliases stable.
      final id = const Uuid().v4();
      try {
        final inserted = await _client
            .from('nutrition_profiles')
            .insert({
              'id': id,
              'canonical_name': canonicalName,
              'canonical_name_ru': canonicalName,
              'canonical_key': canonicalKey,
              'status': 'external_unverified',
            })
            .select()
            .single();
        return Map<String, dynamic>.from(inserted as Map);
      } on PostgrestException catch (e) {
        // Race condition: another request created same canonical_key first.
        if (e.code == '23505' || e.code == '409') {
          final existingByKey =
              await _fetchNutritionProfileByCanonicalKey(canonicalKey);
          if (existingByKey != null) return existingByKey;
        }
        rethrow;
      }
    }

    final saneCal = NutritionApiService.saneCaloriesForProduct(
        canonicalName, nutrition.calories);
    if (existing is List && existing.isNotEmpty) {
      final profileId =
          Map<String, dynamic>.from(existing.first as Map)['id'].toString();
      await _client.from('nutrition_profiles').update({
        'canonical_name': canonicalName,
        'canonical_name_ru': canonicalName,
        'canonical_key': canonicalKey,
        'calories': saneCal ?? nutrition.calories,
        'protein': nutrition.protein,
        'fat': nutrition.fat,
        'carbs': nutrition.carbs,
        'contains_gluten': nutrition.containsGluten,
        'contains_lactose': nutrition.containsLactose,
        'source': 'openfoodfacts',
        'source_ref': 'world.openfoodfacts.org',
        'confidence': 0.7,
        'status': 'external_unverified',
        'last_verified_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', profileId);

      final profile = await _fetchNutritionProfile(profileId);
      if (profile != null) return profile;
    }

    final id = const Uuid().v4();
    try {
      await _client
          .from('nutrition_profiles')
          .insert({
            'id': id,
            'canonical_name': canonicalName,
            'canonical_name_ru': canonicalName,
            'canonical_key': canonicalKey,
            'calories': saneCal ?? nutrition.calories,
            'protein': nutrition.protein,
            'fat': nutrition.fat,
            'carbs': nutrition.carbs,
            'contains_gluten': nutrition.containsGluten,
            'contains_lactose': nutrition.containsLactose,
            'source': 'openfoodfacts',
            'source_ref': 'world.openfoodfacts.org',
            'confidence': 0.7,
            'status': 'external_unverified',
            'last_verified_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
    } on PostgrestException catch (e) {
      // Race condition: another request created same canonical_key first.
      if (e.code == '23505' || e.code == '409') {
        final existingByKey =
            await _fetchNutritionProfileByCanonicalKey(canonicalKey);
        if (existingByKey != null) return existingByKey;
      }
      rethrow;
    }

    final profile = await _fetchNutritionProfile(id);
    if (profile != null) return profile;

    // Fallback: select by canonical_key.
    final rows = await _client
        .from('nutrition_profiles')
        .select()
        .eq('canonical_key', canonicalKey)
        .limit(1);
    if (rows is List && rows.isNotEmpty)
      return Map<String, dynamic>.from(rows.first as Map);

    throw Exception(
        'Failed to create nutrition profile for canonical_key=$canonicalKey');
  }

  Future<bool> _applyProfileToProductIfMissing({
    required ProductStoreSupabase store,
    required Product product,
    required Map<String, dynamic> profile,
    required bool allowCalories,
    required bool allowProtein,
    required bool allowFat,
    required bool allowCarbs,
    required bool allowGluten,
    required bool allowLactose,
  }) async {
    // Only fill missing fields; keep legacy values untouched if present.
    final calories = profile['calories'] != null
        ? (profile['calories'] as num).toDouble()
        : null;
    final protein = profile['protein'] != null
        ? (profile['protein'] as num).toDouble()
        : null;
    final fat =
        profile['fat'] != null ? (profile['fat'] as num).toDouble() : null;
    final carbs =
        profile['carbs'] != null ? (profile['carbs'] as num).toDouble() : null;

    final containsGluten = profile['contains_gluten'] as bool?;
    final containsLactose = profile['contains_lactose'] as bool?;

    final updated = product.copyWith(
      calories:
          allowCalories && calories != null && calories > 0 ? calories : null,
      protein: allowProtein ? protein : null,
      fat: allowFat ? fat : null,
      carbs: allowCarbs ? carbs : null,
      containsGluten: allowGluten ? containsGluten : null,
      containsLactose: allowLactose ? containsLactose : null,
    );

    final didChange = updated != product;
    if (!didChange) return false;

    await store.updateProduct(updated);
    return true;
  }

  Future<void> _upsertNutritionAlias({
    required String normalizedInput,
    required String profileId,
    required double confidence,
  }) async {
    if (normalizedInput.trim().isEmpty || profileId.trim().isEmpty) return;
    await _client.from('nutrition_aliases').upsert(
      {
        'normalized_input': normalizedInput.trim(),
        'nutrition_profile_id': profileId.trim(),
        'confidence': confidence,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'normalized_input',
    );
  }

  Future<void> _upsertProductLink({
    required String productId,
    required String profileId,
    required String matchType,
    required String matchSource,
    required double matchConfidence,
    required String normalizedQuery,
    required String inputSnapshot,
  }) async {
    if (productId.trim().isEmpty || profileId.trim().isEmpty) return;

    await _client.from('product_nutrition_links').upsert(
      {
        'product_id': productId.trim(),
        'nutrition_profile_id': profileId.trim(),
        'match_type': matchType,
        'match_source': matchSource,
        'match_confidence': matchConfidence,
        'normalized_query': normalizedQuery,
        'input_name_snapshot': inputSnapshot,
        'last_checked_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'product_id',
    );
  }
}
