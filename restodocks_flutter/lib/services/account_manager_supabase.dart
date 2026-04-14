import 'package:dio/dio.dart';
import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart'
    as supabase_url;

import '../core/clear_hash_stub.dart'
    if (dart.library.html) '../core/clear_hash_web.dart' as clear_hash;
import '../core/subscription_entitlements.dart';
import '../core/pending_co_owner_registration.dart';
import '../core/public_app_origin.dart';
import '../models/models.dart';
import '../utils/dev_log.dart';
import 'account_ui_sync_service.dart';
import 'ai_service_supabase.dart';
import 'establishment_data_warmup_service.dart';
import 'establishment_local_hydration_service.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';
import 'translation_service.dart';
import 'local_snapshot_store.dart';
import 'tech_card_translation_cache.dart';
import 'offline_cache_service.dart';
import 'realtime_sync_service.dart';
import 'pos_dining_layout_service.dart';
import 'edge_function_http.dart';
import 'email_service.dart';
import 'secure_storage_service.dart';
import 'supabase_service.dart';
import 'fcm_push_service.dart';
import 'localization_service.dart';

const _keyEmployeeId = 'restodocks_employee_id';
const _keyEstablishmentId = 'restodocks_establishment_id';

const _strictLegacyAuthSession =
    bool.fromEnvironment('AUTH_STRICT_SESSION', defaultValue: true);
const _keyRememberPin = 'restodocks_remember_pin';
const _keyRememberEmail = 'restodocks_remember_email';
const _keyRememberPassword = 'restodocks_remember_password';

String _dateOnly(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Строка похожа на UUID (8-4-4-4-12 hex). Нормализуйте в lower-case перед RPC, иначе дубли в in-flight.
bool _looksLikeEstablishmentUuid(String raw) {
  final s = raw.trim();
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(s);
}

/// Сервис управления аккаунтами с использованием Supabase
class AccountManagerSupabase extends ChangeNotifier {
  static final AccountManagerSupabase _instance =
      AccountManagerSupabase._internal();
  factory AccountManagerSupabase() => _instance;
  AccountManagerSupabase._internal();

  final SupabaseService _supabase = SupabaseService();
  final SecureStorageService _secureStorage = SecureStorageService();
  final OfflineCacheService _offlineCache = OfflineCacheService();
  final RealtimeSyncService _realtimeSync = RealtimeSyncService();

  /// Список сотрудников заведения в памяти (мобильный клиент): меньше повторных SELECT по экранам.
  final Map<String, ({DateTime at, List<Employee> list})> _employeesListCache = {};

  /// Один in-flight `check_establishment_access` на заведение (таймер + resume + гидратация не штормят RPC).
  final Map<String, Future<void>> _syncEstablishmentAccessInflight = {};

  static Duration _employeesMemoryTtl() =>
      kIsWeb ? const Duration(minutes: 20) : const Duration(hours: 6);
  Establishment? _establishment;
  Employee? _currentEmployee;
  bool _initialized = false;
  bool _supportSessionActive = false;
  bool _supportAccessTablesUnavailable = false;
  bool _checkEstablishmentAccessRpcUnavailable = false;

  bool _looksLikeMissingSupportAccessSchema(PostgrestException e) {
    final msg = '${e.message} ${e.details} ${e.hint}'.toLowerCase();
    return e.code == '42P01' ||
        msg.contains('support_access_audit_log') ||
        msg.contains('support_access_event_log') ||
        msg.contains('could not find the table') ||
        (msg.contains('relation') && msg.contains('does not exist'));
  }

  bool _looksLikeMissingCheckAccessRpc(PostgrestException e) {
    final msg = '${e.message} ${e.details} ${e.hint}'.toLowerCase();
    return e.code == 'PGRST202' ||
        (msg.contains('check_establishment_access') &&
            (msg.contains('does not exist') ||
                msg.contains('schema cache') ||
                msg.contains('no function matches')));
  }

  /// Callback вызывается после загрузки профиля — применяет preferred_language к LocalizationService.
  void Function(String languageCode)? onPreferredLanguageLoaded;

  /// Последняя техническая ошибка при входе (для отладки на restodocks.com)
  String? lastLoginError;

  /// Доступ к SupabaseService
  SupabaseService get supabase => _supabase;

  /// Убираем avatar_url из payload только при вставке в контекстах, где колонки нет.
  /// При updateEmployee колонка avatar_url уже добавлена миграцией — сохраняем.
  static void _stripAvatarFromPayload(Map<String, dynamic> data) {
    data.remove('avatar_url');
    data.remove('avatarUrl');
  }

  // Геттеры
  Establishment? get establishment => _establishment;
  Employee? get currentEmployee => _currentEmployee;
  bool get supportSessionActive => _supportSessionActive;

  /// Предпочитаемый язык пользователя
  String get preferredLanguage => _currentEmployee?.preferredLanguage ?? 'ru';

  /// Подписка Pro/Premium на заведении (без учёта 72 ч trial).
  bool get hasPaidProSubscription => _establishment?.hasPaidProAccess ?? false;

  /// Pro/Premium или активное окно 72 ч (см. establishments.pro_trial_ends_at).
  bool get hasProSubscription => _establishment?.hasEffectiveProAccess ?? false;

  /// Бесплатный Lite после окончания триала (ограниченный функционал).
  bool get isLiteTier =>
      SubscriptionEntitlements.from(_establishment).isLiteTier;

  SubscriptionEntitlements get subscriptionEntitlements =>
      SubscriptionEntitlements.from(_establishment);

  /// Активное окно 72 ч без оплаченного Pro — лимиты триала (инвентаризация, импорт ТТК).
  bool get isTrialOnlyWithoutPaid {
    final e = _establishment;
    if (e == null) return false;
    return e.isProTrialWindowActive && !e.hasPaidProAccess;
  }

  /// Co-owner с view_only: только просмотр (при >1 заведении у пригласившего)
  bool get isViewOnlyOwner => _currentEmployee?.isViewOnlyOwner ?? false;

  /// ID заведения для данных (номенклатура, ТТК). Для филиала — родитель.
  String? get dataEstablishmentId => _establishment?.dataEstablishmentId;

  /// Авторизован ли пользователь (своя сессия employees или восстановленная из хранилища)
  bool get isLoggedInSync => _currentEmployee != null && _establishment != null;

  /// Сессия Auth есть, но employee ещё нет: owner-first — ждём экран создания первого заведения.
  bool _needsCompanyRegistration = false;
  bool get needsCompanyRegistration => _needsCompanyRegistration;

  /// После owner-first signUp со сессией: заведение ещё не создано (до шага company-details).
  void markNeedsCompanyRegistration() {
    _needsCompanyRegistration = true;
    notifyListeners();
  }

  /// Инициализация сервиса
  /// Supabase восстанавливает сессию из localStorage при Supabase.initialize() в main().
  /// При F5/hard refresh Auth может восстанавливаться асинхронно — делаем retry.
  /// [forceRetryFromAuth] — true при переходе по ссылке confirm (getSessionFromUrl уже вызван).
  Future<void> initialize({bool forceRetryFromAuth = false}) async {
    if (forceRetryFromAuth) _initialized = false;
    if (forceRetryFromAuth) _needsCompanyRegistration = false;
    // Если уже инициализирован и авторизован — не повторяем дорогую инициализацию.
    if (_initialized && isLoggedInSync) return;
    devLog('🔐 AccountManager: Starting initialization...');
    await _secureStorage.initialize();

    await _tryRestoreSession();
    if (isLoggedInSync) {
      await refreshSupportSessionState();
      unawaited(
        _bindRealtimeSync().catchError((Object e, StackTrace st) {
          devLog('🔐 AccountManager: _bindRealtimeSync at init: $e $st');
        }),
      );
      _initialized = true;
      return;
    }

    // Retry: при hard refresh Supabase Auth может ещё не успеть прочитать localStorage.
    await Future.delayed(const Duration(milliseconds: 400));
    await _tryRestoreSession();
    _initialized = true;
    if (isLoggedInSync) {
      await refreshSupportSessionState();
      unawaited(
        _bindRealtimeSync().catchError((Object e, StackTrace st) {
          devLog('🔐 AccountManager: _bindRealtimeSync at init (retry): $e $st');
        }),
      );
      return;
    }

    devLog('🔐 AccountManager: No stored session and not authenticated');
  }

  Future<void> _tryRestoreSession() async {
    final employeeId = await _secureStorage.get(_keyEmployeeId);
    final establishmentId = await _secureStorage.get(_keyEstablishmentId);
    devLog(
        '🔐 AccountManager: Storage - employee: $employeeId, establishment: $establishmentId, auth: ${_supabase.isAuthenticated}');

    // 1. Сначала проверяем Supabase Auth — приоритет для пользователей с auth
    if (_supabase.isAuthenticated) {
      devLog(
          '🔐 AccountManager: Supabase Auth session found, loading user data...');
      var ok = await _loadCurrentUserFromAuth();
      if (!ok) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        ok = await _loadCurrentUserFromAuth();
      }
      if (!ok) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        ok = await _loadCurrentUserFromAuth();
      }
      if (ok) {
        devLog(
            '🔐 AccountManager: User data loaded from Auth, logged in: $isLoggedInSync');
        await syncEstablishmentAccessFromServer();
        return;
      }
      // Owner-first: JWT есть, employee ещё нет — ждём шаг «создать заведение».
      try {
        final pending = await _supabase.client
            .rpc('owner_has_pending_registration_without_company');
        if (pending == true) {
          _needsCompanyRegistration = true;
          devLog(
              '🔐 AccountManager: Auth without employee — pending owner, needs company registration',
          );
          return;
        }
      } catch (e) {
        devLog('🔐 AccountManager: owner_has_pending_registration_without_company: $e');
      }
      // JWT есть в Keychain, а сотрудник/RLS не сходятся — «зомби»-сессия: мешает входу по паролю.
      devLog(
          '🔐 AccountManager: Auth without employee profile — signOut, clear stored ids');
      try {
        await _supabase.signOut();
      } catch (e) {
        devLog('🔐 AccountManager: signOut after failed auth load: $e');
      }
      await _clearStoredSession();
    }

    // 2. Иначе — восстановление из хранилища (legacy)
    if (employeeId != null && establishmentId != null) {
      devLog('🔐 AccountManager: Restoring session from storage...');
      await _restoreSession(employeeId, establishmentId);
      devLog('🔐 AccountManager: Session restored, logged in: $isLoggedInSync');
      await syncEstablishmentAccessFromServer();
    }
  }

  /// Синхронизация тарифа заведения: отключённый/истёкший промокод снимает только Pro (`subscription_type` / trial),
  /// вход и работа на free остаются. RPC может вернуть `expired` на старых БД — [logout] не вызываем.
  /// Вызывать после входа, при возврате приложения на передний план и после применения промокода.
  Future<void> syncEstablishmentAccessFromServer() async {
    final rawId = _establishment?.id.trim();
    if (rawId == null || rawId.isEmpty) return;
    if (!_looksLikeEstablishmentUuid(rawId)) {
      devLog(
        '🔐 AccountManager: syncEstablishmentAccessFromServer skip (invalid uuid): $rawId',
      );
      return;
    }
    final estId = rawId.toLowerCase();

    final inflight = _syncEstablishmentAccessInflight[estId];
    if (inflight != null) return inflight;

    final run = _runSyncEstablishmentAccess(estId);
    _syncEstablishmentAccessInflight[estId] = run;
    try {
      await run;
    } finally {
      final cur = _syncEstablishmentAccessInflight[estId];
      if (identical(cur, run)) {
        _syncEstablishmentAccessInflight.remove(estId);
      }
    }
  }

  Future<void> _runSyncEstablishmentAccess(String estId) async {
    if (_checkEstablishmentAccessRpcUnavailable) {
      await refreshCurrentEstablishmentFromServer();
      return;
    }
    try {
      final result = await _supabase.client.rpc(
        'check_establishment_access',
        params: {'p_establishment_id': estId},
      );
      if (result == 'expired') {
        devLog(
            '🔐 AccountManager: check_establishment_access=expired (legacy) $estId — refresh establishment only, no logout');
      }
      await refreshCurrentEstablishmentFromServer();
    } catch (e, st) {
      if (e is PostgrestException) {
        if (_looksLikeMissingCheckAccessRpc(e)) {
          _checkEstablishmentAccessRpcUnavailable = true;
          devLog(
            '🔐 AccountManager: check_establishment_access unavailable; '
            'fallback to refreshCurrentEstablishmentFromServer only',
          );
          await refreshCurrentEstablishmentFromServer();
          return;
        }
        devLog(
          '🔐 AccountManager: syncEstablishmentAccessFromServer PostgREST '
          'code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
        );
      } else {
        devLog(
          '🔐 AccountManager: syncEstablishmentAccessFromServer error (ignored): $e $st',
        );
      }
    }
  }

  Future<void> _restoreSession(
      String employeeId, String establishmentId) async {
    try {
      devLog('🔐 AccountManager: Loading employee data for ID: $employeeId');
      final employeeDataRaw = await _supabase.client
          .from('employees')
          .select()
          .eq('id', employeeId)
          .eq('is_active', true)
          .limit(1)
          .single();

      devLog('🔐 AccountManager: Employee data loaded successfully');
      final empData = Map<String, dynamic>.from(employeeDataRaw);
      empData['password'] = empData['password_hash'] ?? '';
      _currentEmployee = Employee.fromJson(empData);
      onPreferredLanguageLoaded?.call(_currentEmployee!.preferredLanguage);

      devLog(
          '🔐 AccountManager: Loading establishment data for ID: $establishmentId');
      final estData = await _supabase.client
          .from('establishments')
          .select()
          .eq('id', establishmentId)
          .limit(1)
          .single();

      devLog('🔐 AccountManager: Establishment data loaded successfully');
      _establishment = Establishment.fromJson(estData);

      devLog('🔐 AccountManager: Session restored successfully');
    } catch (e) {
      devLog('❌ AccountManager: Error restoring session: $e');
      devLog('🔍 AccountManager: This might be RLS policy issue');
      await _clearStoredSession();
      _currentEmployee = null;
      _establishment = null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.remove(_keyEmployeeId);
    await _secureStorage.remove(_keyEstablishmentId);
  }

  /// Максимум дополнительных заведений на владельца (глобальная настройка ± переопределения по заведениям в БД).
  Future<int> getMaxEstablishmentsPerOwner() async {
    int normalize(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v >= 0 ? v : 0;
      if (v is double) return v.toInt() >= 0 ? v.toInt() : 0;
      final n = int.tryParse(v.toString());
      return (n != null && n >= 0) ? n : 0;
    }

    int globalCap = 0;
    try {
      globalCap = normalize(await _supabase.client.rpc(
        'get_effective_max_additional_establishments_for_owner',
      ));
    } catch (_) {
      try {
        globalCap = normalize(await _supabase.client.rpc(
          'get_platform_config',
          params: {'p_key': 'max_establishments_per_owner'},
        ));
      } catch (_) {
        globalCap = 0;
      }
    }

    // Клиентский пересчёт лимита, чтобы UI совпадал с серверной логикой add_establishment_for_owner.
    try {
      final list = await getEstablishmentsForOwner();
      final now = DateTime.now();
      final hasOwnerTrial = list.any(
        (e) => e.proTrialEndsAt != null && e.proTrialEndsAt!.isAfter(now),
      );
      final promo = await getEstablishmentPromoForOwner();
      final hasPaidAccess =
          list.any((e) => e.hasPaidProAccess) || promo.isPromoGrantActive;

      int branchPacks = 0;
      try {
        final rows = await _supabase.client
            .from('owner_entitlement_addons')
            .select('branch_slot_packs')
            .limit(1);
        if (rows is List && rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map);
          branchPacks = normalize(row['branch_slot_packs']);
        }
      } catch (_) {
        branchPacks = 0;
      }

      // Если RPC промокода не вернул пакеты, но они уже начислены в entitlement-таблицы,
      // учитываем фактическое значение владельца.
      if (promo.grantsBranchSlotPacks > branchPacks) {
        branchPacks = promo.grantsBranchSlotPacks;
      }

      if (hasOwnerTrial) {
        return globalCap < 2 ? globalCap : 2;
      }
      if (hasPaidAccess) {
        final paidCap = branchPacks >= 2 ? branchPacks : 2;
        return paidCap < globalCap ? paidCap : globalCap;
      }
      return 0;
    } catch (_) {
      return globalCap;
    }
  }

  /// Список заведений владельца (owner_id = auth.uid)
  Future<List<Establishment>> getEstablishmentsForOwner() async {
    try {
      final data = await _supabase.client.rpc('get_establishments_for_owner');
      if (data == null) return [];
      final list = data as List;
      return list
          .map((e) =>
              Establishment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      devLog('AccountManager: getEstablishmentsForOwner error: $e');
      return [];
    }
  }

  /// Добавить заведение существующим владельцем (без регистрации владельца)
  /// [parentEstablishmentId] — если задан, создаётся филиал указанного основного заведения
  Future<Establishment> addEstablishmentForOwner({
    required String name,
    String? address,
    String? phone,
    String? email,
    String? pinCode,
    String? parentEstablishmentId,
  }) async {
    // Всегда передаём p_parent_establishment_id (в т.ч. null), иначе PostgREST не выбирает
    // перегрузку между (5) и (6) аргументами (PGRST203).
    final params = <String, dynamic>{
      'p_name': name,
      'p_address': address,
      'p_phone': phone,
      'p_email': email,
      'p_pin_code': pinCode,
      'p_parent_establishment_id': (parentEstablishmentId != null &&
              parentEstablishmentId.isNotEmpty)
          ? parentEstablishmentId
          : null,
    };
    final raw = await _supabase.client.rpc(
      'add_establishment_for_owner',
      params: params,
    );
    final response = Map<String, dynamic>.from(raw as Map);
    response['owner_id'] = response['owner_id']?.toString() ?? '';
    response['parent_establishment_id'] =
        response['parent_establishment_id']?.toString();
    final created = Establishment.fromJson(response);
    return created;
  }

  /// Заявка на копирование данных между заведениями владельца (см. письмо со ссылкой).
  Future<Map<String, dynamic>> requestEstablishmentDataClone({
    required String sourceEstablishmentId,
    required String targetEstablishmentId,
    required String sourcePin,
    required String targetPin,
    required bool copyNomenclature,
    required bool copyTechCards,
    required bool copyOrderLists,
  }) async {
    final raw = await _supabase.client.rpc(
      'request_establishment_data_clone',
      params: {
        'p_source_establishment_id': sourceEstablishmentId,
        'p_target_establishment_id': targetEstablishmentId,
        'p_source_pin': sourcePin,
        'p_target_pin': targetPin,
        'p_options': {
          'nomenclature': copyNomenclature,
          'tech_cards': copyTechCards,
          'order_lists': copyOrderLists,
        },
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Подтверждение копирования по токену из письма (допускается без сессии).
  Future<Map<String, dynamic>> confirmEstablishmentDataClone(String token) async {
    final raw = await _supabase.client.rpc(
      'confirm_establishment_data_clone',
      params: {'p_token': token.trim()},
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Отправка письма через Edge Function [send-email] (после [requestEstablishmentDataClone]).
  Future<void> sendEstablishmentCloneConfirmationEmail({
    required String to,
    required String subject,
    required String htmlBody,
  }) async {
    final res = await postEdgeFunctionWithRetry(
      'send-email',
      {'to': to, 'subject': subject, 'html': htmlBody},
    );
    if (res.status < 200 || res.status >= 300) {
      throw Exception(
        res.data?['error']?.toString() ?? 'send_email_failed',
      );
    }
  }

  /// Переключение на другое заведение (для владельца с несколькими заведениями)
  Future<void> switchEstablishment(Establishment establishment) async {
    _establishment = establishment;
    await _secureStorage.set(_keyEstablishmentId, establishment.id);
    unawaited(
      _bindRealtimeSync().catchError((Object e, StackTrace st) {
        devLog('🔐 AccountManager: _bindRealtimeSync after switch: $e $st');
      }),
    );
    notifyListeners();
  }

  /// Создание нового заведения
  /// [pinCode] — если задан, используется как PIN (иначе генерируется).
  Future<Establishment> createEstablishment({
    required String name,
    String? pinCode,
    String? address,
    String? phone,
    String? email,
  }) async {
    final establishment = Establishment.create(
      name: name,
      ownerId: '', // владелец появится после регистрации на следующем шаге
      pinCode: pinCode,
      address: address,
      phone: phone,
      email: email,
    );

    final data = establishment.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at')
      ..remove('owner_id')
      ..remove('subscription_type');
    final raw = await _supabase.insertData('establishments', data);
    final response = Map<String, dynamic>.from(raw);
    response['owner_id'] = response['owner_id']?.toString() ?? '';
    final createdEstablishment = Establishment.fromJson(response);

    _establishment = createdEstablishment;
    try {
      await PosDiningLayoutService.instance
          .ensureDefaultDiningLayoutIfEmpty(createdEstablishment.id);
    } catch (e, st) {
      devLog('createEstablishment: default dining layout $e $st');
    }
    return createdEstablishment;
  }

  /// Регистрация без промокода: 72 ч trial (pro_trial_ends_at на сервере), затем free до подписки/промокода.
  Future<Establishment> registerCompanyWithoutPromo({
    required String name,
    required String address,
    required String pinCode,
  }) async {
    final res = await _supabase.client.rpc(
      'register_company_without_promo',
      params: {
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_pin_code': pinCode.trim().toUpperCase(),
      },
    );
    final raw = res as Map<String, dynamic>?;
    if (raw == null) {
      throw Exception('register_company_without_promo returned null');
    }
    final m = Map<String, dynamic>.from(raw);
    m['owner_id'] = m['owner_id']?.toString() ?? '';
    final est = Establishment.fromJson(m);
    _establishment = est;
    // Дефолтный стол создаётся в register_company_without_promo (SECURITY DEFINER);
    // до входа владельца клиент anon — RLS на pos_dining_tables недоступен.
    registerMetadataBestEffort(est.id);
    return est;
  }

  /// Регистрация компании только через RPC с проверкой промокода (защищённый путь).
  /// Выбрасывает исключение с сообщением PROMO_INVALID, PROMO_USED, PROMO_NOT_STARTED, PROMO_EXPIRED при ошибке валидации.
  Future<Establishment> registerCompanyWithPromo({
    required String promoCode,
    required String name,
    required String address,
    required String pinCode,
  }) async {
    final res = await _supabase.client.rpc(
      'register_company_with_promo',
      params: {
        'p_code': promoCode.trim().toUpperCase(),
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_pin_code': pinCode.trim().toUpperCase(),
      },
    );
    final raw = res as Map<String, dynamic>?;
    if (raw == null)
      throw Exception('register_company_with_promo returned null');
    final m = Map<String, dynamic>.from(raw);
    m['owner_id'] = m['owner_id']?.toString() ?? '';
    final est = Establishment.fromJson(m);
    _establishment = est;
    // Дефолтный стол — в register_company_with_promo (см. registerCompanyWithoutPromo).
    registerMetadataBestEffort(est.id);
    return est;
  }

  /// Лимиты первых 72 ч (ТЗ): счётчики выгрузки инвентаризации / импорта ТТК. Для оплаты или после триала — no-op на сервере.
  Future<void> trialIncrementUsageOrThrow({
    required String establishmentId,
    required String kind,
    int delta = 1,
  }) async {
    try {
      await _supabase.client.rpc(
        'trial_increment_usage',
        params: {
          'p_establishment_id': establishmentId,
          'p_kind': kind,
          'p_delta': delta,
        },
      );
    } on PostgrestException catch (e) {
      // На старой/частично мигрированной БД не блокируем экспорт/импорт из-за счётчиков триала.
      devLog(
        'trial_increment_usage: PostgREST error code=${e.code} '
        'message=${e.message}; skip trial usage increment',
      );
      return;
    }
  }

  /// Счётчик импортированных в триале карточек ТТК (для предпроверки лимита 10 за 72 ч).
  Future<int> fetchTrialTtkImportCardsUsed(String establishmentId) async {
    final row = await _supabase.client
        .from('establishment_trial_usage')
        .select('ttk_import_cards')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (row == null) return 0;
    final v = row['ttk_import_cards'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  /// Лимит «сохранение на устройстве» в первые 72 ч: 3 на каждый вид документа.
  Future<void> trialIncrementDeviceSaveOrThrow({
    required String establishmentId,
    required String docKind,
  }) async {
    await trialIncrementUsageOrThrow(
      establishmentId: establishmentId,
      kind: 'device_save:${docKind.trim().toLowerCase()}',
      delta: 1,
    );
  }

  /// Первое заведение после шага «только владелец» (сессия auth, pending без establishment_id).
  /// Возвращает тот же jsonb, что complete_pending_owner_registration (employee + establishment).
  Future<Map<String, dynamic>> registerFirstEstablishmentWithoutPromo({
    required String name,
    required String address,
    required String pinCode,
  }) async {
    final res = await _supabase.client.rpc(
      'register_first_establishment_without_promo',
      params: {
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_pin_code': pinCode.trim().toUpperCase(),
      },
    );
    if (res is! Map) {
      throw Exception('register_first_establishment_without_promo: invalid response');
    }
    return Map<String, dynamic>.from(res);
  }

  /// То же с промокодом (owner-first).
  Future<Map<String, dynamic>> registerFirstEstablishmentWithPromo({
    required String promoCode,
    required String name,
    required String address,
    required String pinCode,
  }) async {
    final res = await _supabase.client.rpc(
      'register_first_establishment_with_promo',
      params: {
        'p_code': promoCode.trim().toUpperCase(),
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_pin_code': pinCode.trim().toUpperCase(),
      },
    );
    if (res is! Map) {
      throw Exception('register_first_establishment_with_promo: invalid response');
    }
    return Map<String, dynamic>.from(res);
  }

  /// Выполнить вход после [registerFirstEstablishment*] (ответ RPC = employee + establishment).
  Future<void> loginFromOwnerFirstEstablishmentResult(
    Map<String, dynamic> rpcResult, {
    String? interfaceLanguageCode,
  }) async {
    final empRaw = rpcResult['employee'];
    final estRaw = rpcResult['establishment'];
    if (empRaw == null || estRaw == null) {
      throw Exception('loginFromOwnerFirstEstablishmentResult: missing employee/establishment');
    }
    final empData = Map<String, dynamic>.from(empRaw as Map);
    empData['password'] = '';
    empData['password_hash'] = '';
    final employee = Employee.fromJson(empData);
    final establishment =
        Establishment.fromJson(Map<String, dynamic>.from(estRaw as Map));
    _needsCompanyRegistration = false;
    await login(
      employee,
      establishment,
      interfaceLanguageCode: interfaceLanguageCode,
    );
  }

  /// IP/гео при регистрации компании (Edge register-metadata). Не блокирует UX; ошибки не пробрасываются.
  /// HTTP POST с явным anon (как send-registration-email): invoke иногда шлёт битый JWT → 401 на Edge.
  void registerMetadataBestEffort(String establishmentId) {
    unawaited(
      (() async {
        try {
          await postEdgeFunctionWithRetry(
            'register-metadata',
            {'establishment_id': establishmentId},
            maxRetries: 1,
            bearerAlwaysAnon: true,
          );
        } catch (_) {}
      })(),
    );
  }

  /// Поиск заведения по названию
  Future<Establishment?> findEstablishmentByName(String name) async {
    try {
      final data = await _supabase.client
          .from('establishments')
          .select()
          .ilike('name', name)
          .limit(1)
          .single();

      return Establishment.fromJson(data);
    } catch (e) {
      devLog('Ошибка поиска заведения: $e');
      return null;
    }
  }

  /// Поиск заведения по PIN-коду
  Future<Establishment?> findEstablishmentByPinCode(String pinCode) async {
    try {
      final cleanPin = pinCode.trim().toUpperCase();
      final data = await _supabase.client
          .from('establishments')
          .select()
          .eq('pin_code', cleanPin)
          .limit(1)
          .single();

      return Establishment.fromJson(data);
    } catch (e) {
      devLog('Ошибка поиска заведения по PIN: $e');
      return null;
    }
  }

  /// Проверка: занят ли email в данном заведении (чтобы исключить дубли)
  Future<bool> isEmailTakenInEstablishment(
      String email, String establishmentId) async {
    try {
      final list = await _supabase.client
          .from('employees')
          .select('id')
          .eq('email', email.trim())
          .eq('establishment_id', establishmentId)
          .limit(1);
      return list != null && (list as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Проверка, занят ли email глобально (во всех заведениях)
  Future<bool> isEmailTakenGlobally(String email) async {
    try {
      final list = await _supabase.client
          .from('employees')
          .select('id')
          .eq('email', email.trim())
          .limit(1);
      return list != null && (list as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Отправка приглашения соучредителю
  /// Если у владельца >1 заведения — co-owner получает только просмотр (is_view_only_owner)
  Future<void> inviteCoOwner(String email, String establishmentId) async {
    final currentEmployee = this.currentEmployee;
    if (currentEmployee == null || !currentEmployee.hasRole('owner')) {
      throw Exception('Only owners can send co-owner invitations');
    }

    final raw = await _supabase.client.rpc(
      'create_co_owner_invitation',
      params: {
        'p_establishment_id': establishmentId,
        'p_invited_email': email.trim(),
      },
    );
    final map = Map<String, dynamic>.from(raw as Map);
    final token = map['invitation_token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('create_co_owner_invitation: no token in response');
    }

    // Тот же origin, что и для emailRedirect: на вебе — текущий хост (бэта vs прод), иначе define/config.
    final invitationLink =
        '$publicAppOriginForEmailRedirect/accept-co-owner-invitation?token=${Uri.encodeComponent(token)}';
    devLog('Invitation link: $invitationLink');

    final estName = _establishment?.id == establishmentId
        ? _establishment?.name
        : null;
    final emailResult = await EmailService().sendCoOwnerInvitationEmail(
      to: email.trim(),
      invitationLink: invitationLink,
      establishmentName: estName,
    );
    if (!emailResult.ok) {
      throw Exception(
        emailResult.error ?? 'Не удалось отправить письмо с приглашением',
      );
    }
  }

  /// Удалить тестовые записи сотрудников (использовать только для разработки!)
  Future<void> deleteTestEmployees() async {
    try {
      // Удаляем сотрудников, у которых нет ролей 'owner' и establishment_id указывает на несуществующие заведения
      // Или сотрудников с email содержащими 'test', 'demo', etc.
      await _supabase.client
          .from('employees')
          .delete()
          .or('email.ilike.%test%,email.ilike.%demo%,email.ilike.%example%')
          .neq('roles', ['owner']); // Не удаляем владельцев

      devLog('Test employees deleted successfully');
    } catch (e) {
      devLog('Error deleting test employees: $e');
      rethrow;
    }
  }

  /// Регистрация сотрудника в компании
  /// [authUserId] — ID из Supabase Auth (обязательно: employees.id = auth.users.id).
  /// [ownerAccessLevel] — для co-owner: 'view_only' если у пригласившего >1 заведения
  Future<Employee> createEmployeeForCompany({
    required Establishment company,
    required String fullName,
    String? surname,
    required String email,
    required String password,
    required String department,
    String? section,
    required List<String> roles,
    String? authUserId,
    String? ownerAccessLevel,
    DateTime? birthday,
  }) async {
    if (authUserId == null || authUserId.isEmpty) {
      throw Exception(
          'employees.id = auth.users.id — требуется authUserId от signUp');
    }

    // Владелец — через create_owner_employee (вызов без сессии после Confirm Email)
    if (roles.contains('owner')) {
      return createOwnerEmployeeViaRpc(
        authUserId: authUserId,
        establishment: company,
        fullName: fullName,
        surname: surname,
        email: email,
        roles: roles,
        ownerAccessLevel: ownerAccessLevel,
      );
    }

    // Обычный сотрудник: RLS требует id = auth.uid(), при Confirm Email сессии нет — через RPC.
    // Владелец добавляет другого человека → create_employee_for_company (caller = owner).
    // Саморегистрация (RegisterScreen с PIN): create_employee_self_register.
    // Признаки саморегистрации: auth.uid() == p_auth_user_id ИЛИ нет загруженного owner (isLoggedInSync).
    final isSelfRegistration =
        _supabase.currentUser?.id == authUserId || !isLoggedInSync;
    final rpcName = (_supabase.isAuthenticated && !isSelfRegistration)
        ? 'create_employee_for_company'
        : 'create_employee_self_register';
    final params = <String, dynamic>{
      'p_auth_user_id': authUserId,
      'p_establishment_id': company.id,
      'p_full_name': fullName,
      'p_surname': surname ?? '',
      'p_email': email,
      'p_department': department,
      'p_section': section ?? '',
      'p_roles': roles,
      'p_birthday': birthday != null ? _dateOnly(birthday) : null,
    };
    if (rpcName == 'create_employee_for_company') {
      params['p_owner_access_level'] = ownerAccessLevel ?? 'full';
    }
    final res = await _supabase.client.rpc(rpcName, params: params);
    final data = Map<String, dynamic>.from(res as Map);
    data['password'] = '';
    data['password_hash'] = '';
    return Employee.fromJson(data);
  }

  /// Регистрация в Supabase Auth (для сотрудников). Возвращает (userId, hasSession).
  Future<({String? userId, bool hasSession})> signUpToSupabaseAuth(
    String email,
    String password, {
    String? interfaceLanguageCode,
  }) async {
    final emailTrim = email.trim();
    devLog('DEBUG: signUpToSupabaseAuth called with email: $emailTrim');

    // Сначала попробуем войти - вдруг пользователь уже существует
    try {
      devLog('DEBUG: Attempting signIn first...');
      final signInRes = await _supabase.signInWithEmail(emailTrim, password);
      if (_supabase.currentUser != null) {
        devLog(
            'DEBUG: User already exists, signed in: ${_supabase.currentUser!.id}');
        return (
          userId: _supabase.currentUser!.id,
          hasSession: signInRes.session != null
        );
      }
    } catch (signInError) {
      devLog('DEBUG: signIn failed: $signInError');
      // Продолжаем к signUp
    }

    // Если вход не удался, пробуем зарегистрировать нового пользователя
    try {
      devLog('DEBUG: Attempting signUp...');
      final redirectUrl = _getEmailRedirectUrl(interfaceLanguageCode);
      final lang = (interfaceLanguageCode ?? 'en').trim().toLowerCase();
      final res = await _supabase.signUpWithEmail(emailTrim, password,
          emailRedirectTo: redirectUrl,
          data: {'interface_language': lang});
      final uid = res.user?.id ?? _supabase.currentUser?.id;
      final hasSession = res.session != null;
      devLog('DEBUG: signUp completed, userId: $uid, hasSession: $hasSession');
      return (userId: uid, hasSession: hasSession);
    } catch (signUpError) {
      devLog('DEBUG: signUpWithEmail failed: $signUpError');

      // Если signUp тоже не удался из-за "user already exists", попробуем войти еще раз
      if (signUpError.toString().contains('already') ||
          signUpError.toString().contains('exists')) {
        try {
          devLog(
              'DEBUG: signUp failed with "already exists", trying signIn again...');
          final signInRes =
              await _supabase.signInWithEmail(emailTrim, password);
          if (_supabase.currentUser != null) {
            return (
              userId: _supabase.currentUser!.id,
              hasSession: signInRes.session != null
            );
          }
        } catch (finalSignInError) {
          devLog('DEBUG: Final signIn also failed: $finalSignInError');
        }
      }

      rethrow;
    }
  }

  /// URL для редиректа после подтверждения. Должен совпадать с Supabase Auth → Redirect URLs.
  static String _getEmailRedirectUrl([String? languageCode]) {
    final base = publicAppOriginForEmailRedirect;
    final lang = languageCode?.trim().toLowerCase();
    if (lang != null &&
        lang.isNotEmpty &&
        LocalizationService.isSupportedLanguageCode(lang)) {
      return '$base/auth/confirm?lang=$lang';
    }
    return '$base/auth/confirm';
  }

  /// Регистрация владельца в Supabase Auth (employees.id = auth.users.id — создаём auth первым)
  /// Возвращает (auth user id, есть ли сессия).
  /// При Confirm Email session = null — пользователь должен подтвердить почту.
  Future<({String? userId, bool hasSession})> signUpWithEmailForOwner(
    String email,
    String password, {
    String? interfaceLanguageCode,
    String? positionRole,
  }) async {
    final normalizedPosition = positionRole?.trim().toLowerCase();
    final lang = (interfaceLanguageCode ?? 'en').trim().toLowerCase();
    final res = await _supabase.signUpWithEmail(
      email.trim(),
      password,
      emailRedirectTo: _getEmailRedirectUrl(interfaceLanguageCode),
      data: {
        'interface_language': lang,
        if (normalizedPosition != null &&
            normalizedPosition.isNotEmpty &&
            normalizedPosition != 'owner')
          'position_role': normalizedPosition,
      },
    );
    final uid = res.user?.id ?? _supabase.currentUser?.id;
    final hasSession = res.session != null;
    return (userId: uid, hasSession: hasSession);
  }

  /// Сохранить pending owner — employee создастся после confirm (когда user в auth.users).
  /// [establishment] null — сценарий owner-first (заведение создаётся на следующем шаге).
  Future<void> savePendingOwnerRegistration({
    required String authUserId,
    Establishment? establishment,
    required String fullName,
    String? surname,
    required String email,
    required List<String> roles,
    String preferredLanguage = 'ru',
  }) async {
    var lang = preferredLanguage.trim().toLowerCase();
    if (!LocalizationService.isSupportedLanguageCode(lang)) lang = 'ru';
    final params = <String, dynamic>{
      'p_auth_user_id': authUserId,
      'p_full_name': fullName,
      'p_surname': surname ?? '',
      'p_email': email,
      'p_roles': roles,
      'p_preferred_language': lang,
      'p_position_role': roles
          .map((r) => r.trim().toLowerCase())
          .firstWhere((r) => r.isNotEmpty && r != 'owner', orElse: () => ''),
    };
    if (establishment != null) {
      params['p_establishment_id'] = establishment.id;
    }
    await _supabase.client.rpc(
      'save_pending_owner_registration',
      params: params,
    );
  }

  /// Pending owner-first: заведение ещё не создано — не вызывать [completePendingOwnerRegistration] (иначе 400 на старой БД без миграции).
  Future<bool> _pendingOwnerAwaitingCompanyOnly(String authUserId) async {
    try {
      final row = await _supabase.client
          .from('pending_owner_registrations')
          .select('establishment_id')
          .eq('auth_user_id', authUserId)
          .maybeSingle();
      if (row == null) return false;
      final dynamic e = row['establishment_id'];
      return e == null || (e is String && e.isEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Завершить регистрацию владельца (authenticated, после confirm). Возвращает null если pending нет.
  Future<({Employee employee, Establishment establishment})?>
      completePendingOwnerRegistration() async {
    if (!_supabase.isAuthenticated) return null;
    try {
      final res =
          await _supabase.client.rpc('complete_pending_owner_registration');
      if (res == null) return null;
      final m = Map<String, dynamic>.from(res as Map);
      final emp = m['employee'];
      final est = m['establishment'];
      if (emp == null || est == null) return null;
      final empData = Map<String, dynamic>.from(emp);
      empData['password'] = '';
      empData['password_hash'] = '';
      return (
        employee: Employee.fromJson(empData),
        establishment: Establishment.fromJson(Map<String, dynamic>.from(est)),
      );
    } catch (e, st) {
      devLog('completePendingOwnerRegistration: $e\n$st');
      return null;
    }
  }

  /// Fallback: создать employee для auth user через fix_owner_without_employee (когда complete_pending не сработал).
  Future<({Employee employee, Establishment establishment})?>
      _tryFixOwnerWithoutEmployee() async {
    if (!_supabase.isAuthenticated) return null;
    final email = _supabase.currentUser?.email?.trim();
    if (email == null || email.isEmpty) return null;
    try {
      final res = await _supabase.client
          .rpc('fix_owner_without_employee', params: {'p_email': email});
      if (res == null) return null;
      final empData = Map<String, dynamic>.from(res as Map);
      empData['password'] = '';
      empData['password_hash'] = '';
      final employee = Employee.fromJson(empData);
      final estData = await _supabase.client
          .from('establishments')
          .select()
          .eq('id', employee.establishmentId)
          .limit(1)
          .single();
      return (
        employee: employee,
        establishment: Establishment.fromJson(estData),
      );
    } catch (e) {
      devLog('🔐 fix_owner_without_employee fallback: $e');
      return null;
    }
  }

  /// Создание владельца через RPC — только для co-owner (create_employee_for_company), не для первичной регистрации.
  Future<Employee> createOwnerEmployeeViaRpc({
    required String authUserId,
    required Establishment establishment,
    required String fullName,
    String? surname,
    required String email,
    required List<String> roles,
    String? ownerAccessLevel,
  }) async {
    final params = <String, dynamic>{
      'p_auth_user_id': authUserId,
      'p_establishment_id': establishment.id,
      'p_full_name': fullName,
      'p_surname': surname ?? '',
      'p_email': email,
      'p_roles': roles,
    };
    if (ownerAccessLevel != null)
      params['p_owner_access_level'] = ownerAccessLevel;
    final res =
        await _supabase.client.rpc('create_owner_employee', params: params);
    final data = Map<String, dynamic>.from(res as Map);
    data['password'] = '';
    data['password_hash'] = '';
    return Employee.fromJson(data);
  }

  /// Вход по email и паролю: сначала Supabase Auth, затем legacy fallback (Edge Function).
  /// Это убирает ложные 401 от legacy для аккаунтов, уже привязанных к auth.users.
  Future<({Employee employee, Establishment establishment})?>
      findEmployeeByEmailAndPasswordGlobal({
    required String email,
    required String password,
  }) async {
    final emailTrim = email.trim();
    final passwordTrimmed = password.trim();
    lastLoginError = null;
    if (emailTrim.isEmpty) return null;

    // «Зомби»-сессия после confirm/выхода: JWT есть, профиль не готов — мешает следующему входу.
    if (_supabase.isAuthenticated) {
      try {
        await _supabase.signOut();
        devLog('🔐 Login: cleared existing Supabase session before password sign-in');
      } catch (e) {
        devLog('🔐 Login: pre-signOut failed (ignored): $e');
      }
    }

    // 1. Пробуем Supabase Auth (учётки в auth.users)
    try {
      await _supabase.signInWithEmail(emailTrim, passwordTrimmed);
      if (_supabase.isAuthenticated) {
        final authUserId = _supabase.currentUser!.id;
        // Как в _loadCurrentUserFromAuth: id = auth.uid() или auth_user_id (legacy→auth).
        final list = await _supabase.client
            .from('employees')
            .select()
            .or('id.eq.$authUserId,auth_user_id.eq.$authUserId')
            .eq('is_active', true)
            .limit(1);

        if (list != null && (list as List).isNotEmpty) {
          final empData = Map<String, dynamic>.from((list as List).first);
          empData['password'] = empData['password_hash'] ?? '';
          final employee = Employee.fromJson(empData);
          final estData = await _supabase.client
              .from('establishments')
              .select()
              .eq('id', employee.establishmentId)
              .limit(1)
              .single();
          final establishment = Establishment.fromJson(estData);
          return (employee: employee, establishment: establishment);
        }

        if (!await _pendingOwnerAwaitingCompanyOnly(authUserId)) {
          final completedPending = await completePendingOwnerRegistration();
          if (completedPending != null) {
            return completedPending;
          }
        }

        try {
          final fixRes = await _supabase.client.rpc(
              'fix_owner_without_employee',
              params: {'p_email': emailTrim});
          if (fixRes != null) {
            final empData = Map<String, dynamic>.from(fixRes as Map);
            empData['password'] = empData['password_hash'] ?? '';
            final employee = Employee.fromJson(empData);
            final estData = await _supabase.client
                .from('establishments')
                .select()
                .eq('id', employee.establishmentId)
                .limit(1)
                .single();
            final establishment = Establishment.fromJson(estData);
            return (employee: employee, establishment: establishment);
          }
        } catch (fixErr) {
          devLog('🔐 fix_owner_without_employee failed: $fixErr');
        }

        // Owner-first: email подтверждён, заведение ещё не создано — не signOut и не SQL-скрипт.
        try {
          final pendingNoCompany = await _supabase.client
              .rpc('owner_has_pending_registration_without_company');
          if (pendingNoCompany == true) {
            _needsCompanyRegistration = true;
            lastLoginError = 'needs_company_registration';
            devLog(
              '🔐 Login: pending owner without establishment — session kept, go to company registration',
            );
            return null;
          }
        } catch (e) {
          devLog('🔐 owner_has_pending_registration_without_company: $e');
        }

        // Fallback: тот же признак, что и RPC, но прямой SELECT (старый деплой RPC / сбой).
        try {
          final pendingRow = await _supabase.client
              .from('pending_owner_registrations')
              .select('establishment_id')
              .eq('auth_user_id', authUserId)
              .maybeSingle();
          final dynamic estRaw = pendingRow?['establishment_id'];
          final bool noEstablishmentYet = pendingRow != null &&
              (estRaw == null ||
                  (estRaw is String && estRaw.isEmpty));
          if (noEstablishmentYet) {
            _needsCompanyRegistration = true;
            lastLoginError = 'needs_company_registration';
            devLog(
              '🔐 Login: pending without establishment (table select) — company registration',
            );
            return null;
          }
        } catch (e) {
          devLog('🔐 pending_owner_registrations select: $e');
        }

        // Админка удалила заведение: сотрудник исчез, pending мог уже не существовать — восстановить owner-first.
        try {
          final ensured = await _supabase.client
              .rpc('ensure_owner_first_pending_after_admin_wipe');
          if (ensured == true) {
            _needsCompanyRegistration = true;
            lastLoginError = 'needs_company_registration';
            devLog(
              '🔐 Login: restored pending after admin wipe — company registration',
            );
            return null;
          }
        } catch (e) {
          devLog('🔐 ensure_owner_first_pending_after_admin_wipe: $e');
        }

        await _supabase.signOut();
        throw Exception('employee_not_found');
      }
    } catch (authErr) {
      if (authErr is Exception &&
          authErr.toString().contains('employee_not_found')) {
        rethrow;
      }
      if (authErr is AuthException &&
          authErr.code == 'supabase_login_unavailable') {
        lastLoginError = 'login_service_unavailable';
        devLog(
            '🔐 Login: Supabase Auth unavailable (web), skip legacy authenticate-employee');
        return null;
      }
      // Логируем всегда — иначе в prod (kDebugMode=false) не увидим причину
      lastLoginError =
          'Auth: ${authErr.toString().replaceAll(RegExp(r'\s+'), ' ')}';
      devLog('🔐 Login: Supabase Auth failed: $authErr');
      if (authErr.toString().contains('Invalid login credentials')) {
        devLog(
            '🔐 Login: (Invalid credentials → пробуем legacy authenticate-employee)');
      } else if (authErr.toString().toLowerCase().contains('cors') ||
          authErr.toString().toLowerCase().contains('network')) {
        devLog(
            '🔐 Login: (CORS/сеть? Добавь restodocks.com в Supabase Auth Redirect URLs и API CORS)');
      }
      try {
        await _supabase.signOut();
      } catch (_) {/* ignore */}
    }

    // 2. Legacy: password_hash через Edge Function (employees без auth.users)
    return _findEmployeeByPasswordHashViaEdgeFunction(
        emailTrim, passwordTrimmed);
  }

  /// Вызов Edge Function authenticate-employee через raw HTTP (обход Safari cross-origin
  /// POST body issues с supabase functions.invoke — body иногда не уходит).
  /// Retry при 401/5xx/сети — proxy/маршрутизация может обрывать первый запрос.
  Future<({int status, Map<String, dynamic>? data})>
      _invokeAuthenticateEmployeeHttp(
    Map<String, dynamic> body,
  ) async {
    const maxRetries = 3;
    const retryDelays = [
      600,
      1200
    ]; // ms, увеличенные задержки при proxy/маршрутизации

    final url =
        '${supabase_url.getSupabaseBaseUrl()}/functions/v1/authenticate-employee';
    final anonKey = supabase_url.getSupabaseAnonKey();
    final dio = Dio(BaseOptions(
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true, // не бросать на 4xx
    ));

    ({int status, Map<String, dynamic>? data}) lastResult =
        (status: 0, data: null);

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: retryDelays[attempt - 1]));
        devLog('🔐 authenticate-employee retry $attempt/$maxRetries');
      }
      try {
        final resp = await dio.post(url, data: body);
        final data = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : (resp.data is Map
                ? Map<String, dynamic>.from(resp.data as Map)
                : null);
        lastResult = (status: resp.statusCode ?? 0, data: data);

        // 4xx — бизнес-ответ. Не retry, чтобы не маскировать неверные креды.
        if (resp.statusCode != null &&
            resp.statusCode! >= 400 &&
            resp.statusCode! < 500) {
          return lastResult;
        }
        // 2xx — успех
        if (resp.statusCode != null &&
            resp.statusCode! >= 200 &&
            resp.statusCode! < 300) {
          return lastResult;
        }
        // 5xx — retry
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final data = e.response?.data;
        final map = data is Map<String, dynamic>
            ? data
            : (data is Map ? Map<String, dynamic>.from(data as Map) : null);
        lastResult = (status: status, data: map);
        // 4xx — не retry
        if (status >= 400 && status < 500) return lastResult;
        // сеть/5xx — retry (последняя попытка вернёт этот результат)
      }
    }
    return lastResult;
  }

  Future<bool> _ensureSupabaseSessionAfterLegacy(
      String email, String password) async {
    const maxAttempts = 3;
    const retryDelays = [350, 900];

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: retryDelays[attempt - 1]));
        devLog('🔐 Legacy->Auth session retry $attempt/$maxAttempts');
      }
      try {
        await _supabase.signInWithEmail(email.trim(), password);
        if (_supabase.isAuthenticated) return true;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isInvalidCreds = msg.contains('invalid login credentials');
        if (isInvalidCreds) return false;
      }
    }
    return _supabase.isAuthenticated;
  }

  /// Legacy: BCrypt-проверка пароля через Edge Function authenticate-employee.
  /// password_hash никогда не покидает сервер — клиент получает только данные сотрудника.
  Future<({Employee employee, Establishment establishment})?>
      _findEmployeeByPasswordHashViaEdgeFunction(
    String email,
    String password,
  ) async {
    try {
      devLog(
          '🔐 Login: Legacy fallback — calling authenticate-employee (HTTP)');

      final res = await _invokeAuthenticateEmployeeHttp(
          {'email': email, 'password': password});

      if (res.status == 401) {
        lastLoginError = (lastLoginError != null ? '$lastLoginError → ' : '') +
            'Legacy: 401 invalid credentials';
        devLog('🔐 Login: Legacy — invalid credentials (401)');
        return null;
      }

      if (res.status != 200) {
        String msg = 'Legacy: ${res.status}';
        if (res.data is Map) {
          final d = res.data as Map;
          msg = (d['message'] ?? d['error'] ?? msg).toString();
        }
        lastLoginError =
            (lastLoginError != null ? '$lastLoginError → ' : '') + msg;
        devLog(
            '🔐 Login: Legacy — Edge Function error: ${res.status}, data=${res.data}');
        return null;
      }

      final data = res.data;
      if (data == null) return null;
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) {
        devLog('🔐 Login: Legacy — error: ${data['error']}');
        return null;
      }

      final empRaw = data['employee'];
      final estRaw = data['establishment'];
      if (empRaw == null || estRaw == null) return null;

      final empData = Map<String, dynamic>.from(empRaw as Map);
      empData['password'] = '';
      empData['password_hash'] = '';
      final employee = Employee.fromJson(empData);
      final establishment =
          Establishment.fromJson(Map<String, dynamic>.from(estRaw as Map));

      // После legacy-входа всегда пытаемся поднять Supabase Auth session (JWT для RLS).
      final needsAuthSession = data['authUserCreated'] == true;
      if (needsAuthSession) {
        final sessionReady =
            await _ensureSupabaseSessionAfterLegacy(email, password);
        if (sessionReady) {
          devLog(
              '🔐 Login: Legacy → Supabase Auth session established for ${employee.email}');
        } else {
          lastLoginError =
              (lastLoginError != null ? '$lastLoginError → ' : '') +
                  'Legacy: session_not_ready';
          devLog(
              '🔐 Login: Legacy authenticated, but Auth session was not established');
          if (_strictLegacyAuthSession) {
            return null;
          }
        }
      }

      devLog('🔐 Login: Legacy — success for ${employee.email}');
      return (employee: employee, establishment: establishment);
    } catch (e, st) {
      lastLoginError = (lastLoginError != null ? '$lastLoginError → ' : '') +
          'Legacy exception: $e';
      devLog('🔐 Login: Legacy Edge Function threw: $e');
      rethrow;
    }
  }

  /// Поиск сотрудника по email и паролю (в рамках заведения) — через Edge Function
  Future<Employee?> findEmployeeByEmailAndPassword({
    required String email,
    required String password,
    required Establishment company,
  }) async {
    try {
      final res = await _invokeAuthenticateEmployeeHttp({
        'email': email.trim(),
        'password': password.trim(),
        'establishment_id': company.id,
      });

      if (res.status != 200) return null;
      final data = res.data;
      if (data == null || data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final empRaw = data['employee'];
      if (empRaw == null) return null;

      final empData = Map<String, dynamic>.from(empRaw as Map);
      empData['password'] = '';
      empData['password_hash'] = '';
      return Employee.fromJson(empData);
    } catch (e) {
      devLog('🔐 findEmployeeByEmailAndPassword error: $e');
      return null;
    }
  }

  /// Обновить текущего сотрудника в памяти после PATCH в БД (без повторной загрузки).
  void mergeCurrentEmployeeInMemory(Employee updated) {
    if (_currentEmployee?.id != updated.id) return;
    _currentEmployee = updated;
    notifyListeners();
  }

  /// Вход в систему
  /// [rememberCredentials] — сохранить PIN, email и пароль для автозаполнения
  Future<void> login(
    Employee employee,
    Establishment establishment, {
    bool rememberCredentials = false,
    String? pin,
    String? email,
    String? password,
    /// Язык, выбранный на экране входа/регистрации до авторизации; сохраняется в профиль.
    String? interfaceLanguageCode,
  }) async {
    _needsCompanyRegistration = false;
    devLog(
        '🔐 AccountManager: Setting current user - employee: ${employee.id}, establishment: ${establishment.id}');
    _currentEmployee = employee;
    _establishment = establishment;

    final ui = interfaceLanguageCode?.trim().toLowerCase();
    final useUiLang = ui != null &&
        ui.isNotEmpty &&
        LocalizationService.supportedLocales.any((l) => l.languageCode == ui);

    if (useUiLang) {
      _currentEmployee = _currentEmployee!.copyWith(preferredLanguage: ui);
      onPreferredLanguageLoaded?.call(ui);
      unawaited(LocalizationService().markLocaleChoiceFromAuthFlow());
      unawaited(savePreferredLanguage(ui));
    } else {
      onPreferredLanguageLoaded?.call(employee.preferredLanguage);
    }

    devLog('🔐 AccountManager: Saving to secure storage...');
    await _secureStorage.set(_keyEmployeeId, employee.id);
    await _secureStorage.set(_keyEstablishmentId, establishment.id);
    devLog('🔐 AccountManager: Data saved to secure storage');
    // Не блокировать UI: realtime/WebSocket на web иногда подвисает — иначе вечный спиннер на «Войти».
    unawaited(
      _bindRealtimeSync().catchError((Object e, StackTrace st) {
        devLog('🔐 AccountManager: _bindRealtimeSync after login: $e $st');
      }),
    );

    if (rememberCredentials && email != null && password != null) {
      await _secureStorage.set(_keyRememberEmail, email);
      await _secureStorage.set(_keyRememberPassword, password);
    } else {
      await _secureStorage.remove(_keyRememberEmail);
      await _secureStorage.remove(_keyRememberPassword);
    }
    await syncEstablishmentAccessFromServer();
    await refreshSupportSessionState();
    if (!isLoggedInSync) {
      return;
    }
    final empUi = _currentEmployee;
    if (empUi != null) {
      unawaited(AccountUiSyncService.instance.applyAfterLogin(empUi));
    }
    notifyListeners();

    if (!kIsWeb && isLoggedInSync && _establishment != null) {
      final est = _establishment!;
      final dataId = est.dataEstablishmentId.trim();
      if (dataId.isNotEmpty) {
        EstablishmentLocalHydrationService.instance.ensurePeriodicSyncStarted();
        unawaited(
          EstablishmentDataWarmupService.instance.runForEstablishment(
            dataEstablishmentId: dataId,
            techCards: TechCardServiceSupabase(),
            productStore: ProductStoreSupabase(),
            translationService: TranslationService(
              aiService: AiServiceSupabase(),
              supabase: SupabaseService(),
            ),
            localization: LocalizationService(),
            establishment: est,
          ),
        );
      }
    }
  }

  /// Загрузить сохранённые учётные данные (для автозаполнения формы входа)
  Future<({String? pin, String? email, String? password})>
      loadRememberedCredentials() async {
    await _secureStorage.initialize();
    final pin = await _secureStorage.get(_keyRememberPin);
    final email = await _secureStorage.get(_keyRememberEmail);
    final password = await _secureStorage.get(_keyRememberPassword);
    return (pin: pin, email: email, password: password);
  }

  /// Выход из системы
  Future<void> logout() async {
    await LocalizationService.clearPinnedLocaleOnLogout();
    await FcmPushService.unregisterBeforeLogout();
    final est = _establishment;
    if (est != null) {
      await TechCardTranslationCache.clearForEstablishment(est.dataEstablishmentId);
      await LocalSnapshotStore.instance.clearEstablishment(est.id);
    }
    EstablishmentDataWarmupService.instance.resetSession();
    _employeesListCache.clear();
    await _realtimeSync.stop();
    await _offlineCache.clearCurrentUserCache();
    await _supabase.signOut();
    await _clearStoredSession();
    _currentEmployee = null;
    _establishment = null;
    _initialized = false;
    _needsCompanyRegistration = false;
    _supportSessionActive = false;
    if (kIsWeb) {
      clear_hash.clearHashFromUrl();
    }
    notifyListeners();
  }

  Future<void> _bindRealtimeSync() async {
    final est = _establishment;
    if (est == null) return;
    await _realtimeSync.startForEstablishment(
      establishmentId: est.id,
      dataEstablishmentId: est.dataEstablishmentId,
    );
  }

  /// Проверка, авторизован ли пользователь
  Future<bool> isLoggedIn() async {
    return isLoggedInSync;
  }

  /// Получить всех сотрудников компании
  Future<List<Employee>> getEmployeesForEstablishment(
      String establishmentId) async {
    final hit = _employeesListCache[establishmentId];
    if (hit != null &&
        DateTime.now().difference(hit.at) <= _employeesMemoryTtl()) {
      return List<Employee>.from(hit.list);
    }
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('establishment_id', establishmentId);

      final list =
          (data as List).map((json) => Employee.fromJson(json)).toList();
      _employeesListCache[establishmentId] = (at: DateTime.now(), list: list);
      return list;
    } catch (e) {
      devLog('Ошибка получения сотрудников: $e');
      if (!kIsWeb) {
        try {
          final raw = await LocalSnapshotStore.instance
              .get('$establishmentId:employees');
          if (raw != null && raw.isNotEmpty) {
            final data = jsonDecode(raw) as List<dynamic>;
            final list = data
                .map((j) =>
                    Employee.fromJson(Map<String, dynamic>.from(j as Map)))
                .toList();
            _employeesListCache[establishmentId] =
                (at: DateTime.now(), list: list);
            return List<Employee>.from(list);
          }
        } catch (_) {}
      }
      return [];
    }
  }

  /// Прогрев кэша сотрудников после входа (мобильный общий сценарий).
  Future<void> warmEmployeesCache(String establishmentId) async {
    await getEmployeesForEstablishment(establishmentId);
  }

  /// Шеф-повара/су-шеф/владельцы заведения (для инвентаризации: кабинет + email).
  /// Приоритет: executive_chef, sous_chef, owner — чтобы хотя бы один получатель был.
  Future<List<Employee>> getExecutiveChefsForEstablishment(
      String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('establishment_id', establishmentId)
          .eq('is_active', true);

      final all =
          (data as List).map((json) => Employee.fromJson(json)).toList();
      final execChefs =
          all.where((e) => e.roles.contains('executive_chef')).toList();
      if (execChefs.isNotEmpty) return execChefs;
      final sousChefs =
          all.where((e) => e.roles.contains('sous_chef')).toList();
      if (sousChefs.isNotEmpty) return sousChefs;
      final owners = all.where((e) => e.roles.contains('owner')).toList();
      return owners;
    } catch (e) {
      devLog('Ошибка получения шеф-поваров: $e');
      return [];
    }
  }

  /// RLS: UPDATE по id; если 0 строк — цепочка fallback (см. [_employeesUpdateWithRlsFallback]).
  static bool _isEmployeesZeroRowSaveError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('employees') &&
        (s.contains('не удалось сохранить') || s.contains('нет доступа'));
  }

  /// Обновить данные сотрудника (пароль не обновляется — используйте отдельный поток смены пароля).
  /// avatar_url сохраняется в Supabase Storage (bucket avatars) — данные не зависят от деплоя.
  Future<void> updateEmployee(Employee employee) async {
    try {
      var employeeData = Map<String, dynamic>.from(employee.toJson())
        ..remove('password')
        ..remove('password_hash')
        ..remove('id')
        ..remove('created_at');
      // id / created_at не PATCH — только WHERE; иначе PostgREST обновляет по id в URL.
      // avatar_url сохраняем — колонка добавлена миграцией supabase_migration_employee_avatar.sql

      // В Beta схема БД может отставать (часть колонок отсутствует).
      // Делаем последовательный retry: выкидываем группы полей и повторяем update,
      // чтобы базовые данные сотрудника всё равно сохранялись.
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          await _employeesUpdateWithRlsFallback(employee.id, employeeData);
          break;
        } catch (e) {
          final before = employeeData.length;
          if (_isBirthdayColumnError(e)) {
            employeeData = Map<String, dynamic>.from(employeeData)
              ..remove('birthday');
          } else if (_isSchemaColumnError(e)) {
            employeeData = Map<String, dynamic>.from(employeeData)
              ..remove('can_edit_own_schedule');
          } else if (_isGettingStartedShownColumnError(e)) {
            employeeData = Map<String, dynamic>.from(employeeData)
              ..remove('getting_started_shown');
          } else if (_isPaymentColumnError(e)) {
            employeeData = Map<String, dynamic>.from(employeeData)
              ..remove('payment_type')
              ..remove('rate_per_shift')
              ..remove('hourly_rate');
          } else if (_isEmploymentColumnError(e)) {
            employeeData = Map<String, dynamic>.from(employeeData)
              ..remove('employment_status')
              ..remove('employment_start_date')
              ..remove('employment_end_date');
          } else {
            rethrow;
          }
          // Если на этом шаге ничего не убрали — не зацикливаемся.
          if (employeeData.length == before) rethrow;
          // Идём на следующий attempt с урезанным payload.
          if (attempt == 5) rethrow;
        }
      }

      _employeesListCache.remove(employee.establishmentId);

      if (_currentEmployee?.id == employee.id) {
        _currentEmployee = employee;
        notifyListeners();
      }
    } catch (e) {
      devLog('Ошибка обновления сотрудника: $e');
      rethrow;
    }
  }

  /// Сначала UPDATE … WHERE id = …; при 0 строк — RPC link, затем auth_user_id, id=JWT, or-фильтр.
  Future<void> _employeesUpdateWithRlsFallback(
    String employeeId,
    Map<String, dynamic> employeeData,
  ) async {
    final uid = _supabase.currentUser?.id;

    try {
      await _supabase.client.rpc('ensure_employee_auth_link');
    } catch (e) {
      devLog('ensure_employee_auth_link: $e (игнор если функция ещё не в БД)');
    }

    try {
      await _supabase.updateData(
        'employees',
        employeeData,
        'id',
        employeeId,
      );
      return;
    } catch (e) {
      if (uid == null || !_isEmployeesZeroRowSaveError(e)) rethrow;
    }

    Future<bool> runUpdate(Future<dynamic> Function() run) async {
      final resp = await run();
      final list = resp is List ? resp : <dynamic>[];
      return list.isNotEmpty;
    }

    final authId = uid;

    if (await runUpdate(() => _supabase.client
        .from('employees')
        .update(employeeData)
        .eq('auth_user_id', authId)
        .select())) {
      return;
    }

    if (employeeId != authId &&
        await runUpdate(() => _supabase.client
            .from('employees')
            .update(employeeData)
            .eq('id', authId)
            .select())) {
      return;
    }

    final orFilter = 'id.eq.$employeeId,auth_user_id.eq.$authId';
    if (await runUpdate(() => _supabase.client
        .from('employees')
        .update(employeeData)
        .or(orFilter)
        .select())) {
      return;
    }

    // Последний шаг: RPC SECURITY DEFINER — только для своей строки сотрудника (сессия).
    if (_currentEmployee?.id == employeeId) {
      try {
        await _supabase.client.rpc(
          'patch_my_employee_profile',
          params: {'p_patch': employeeData},
        );
        return;
      } catch (e, st) {
        devLog('patch_my_employee_profile: $e $st');
      }
    }

    throw Exception(
      'Не удалось сохранить профиль (employees). '
      'Попросите администратора применить миграцию '
      '20260430261000_patch_my_employee_profile_rpc '
      '(RPC patch_my_employee_profile) и предыдущие миграции по employees.',
    );
  }

  /// Удаление сотрудника (прямой DELETE — оставляет auth.users, email нельзя переиспользовать)
  @Deprecated('Use deleteEmployeeWithPin for full deletion and email reuse')
  Future<void> deleteEmployee(String employeeId) async {
    try {
      devLog('🗑️ AccountManager: Deleting employee $employeeId...');
      await _supabase.client.from('employees').delete().eq('id', employeeId);
      devLog('✅ AccountManager: Employee deleted successfully');
    } catch (e) {
      devLog('❌ AccountManager: Failed to delete employee: $e');
      rethrow;
    }
  }

  /// Удаление сотрудника с подтверждением PIN. Удаляет employees + auth.users (email можно переиспользовать).
  /// Создаёт уведомление для руководителей.
  Future<void> deleteEmployeeWithPin({
    required String employeeId,
    required String pinCode,
  }) async {
    final res = await _supabase.client.functions.invoke(
      'delete-employee',
      body: {
        'employee_id': employeeId,
        'pin_code': pinCode.trim().toUpperCase(),
      },
    );
    if (res.status != 200) {
      final err = (res.data is Map && (res.data as Map)['error'] != null)
          ? (res.data as Map)['error'].toString()
          : 'HTTP ${res.status}';
      throw Exception(err);
    }
  }

  bool _isPaymentColumnError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('payment_type') ||
        msg.contains('rate_per_shift') ||
        msg.contains('hourly_rate') ||
        msg.contains('pgrst204') ||
        (msg.contains('column') &&
            (msg.contains('exist') ||
                msg.contains('found') ||
                msg.contains('does not')));
  }

  bool _isEmploymentColumnError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('employment_status') ||
        msg.contains('employment_start_date') ||
        msg.contains('employment_end_date');
  }

  bool _isSchemaColumnError(Object e) {
    return e.toString().toLowerCase().contains('can_edit_own_schedule');
  }

  bool _isGettingStartedShownColumnError(Object e) {
    return e.toString().toLowerCase().contains('getting_started_shown');
  }

  bool _isBirthdayColumnError(Object e) {
    return e.toString().toLowerCase().contains('birthday');
  }

  /// Удалить заведение (владелец). Проверяет PIN и email.
  Future<void> deleteEstablishment({
    required String establishmentId,
    required String pinCode,
    required String email,
  }) async {
    await _supabase.client.rpc(
      'delete_establishment_by_owner',
      params: {
        'p_establishment_id': establishmentId,
        'p_pin_code': pinCode.trim().toUpperCase(),
        'p_email': email.trim(),
      },
    );
    // Обновить локальное состояние
    if (_establishment?.id == establishmentId) {
      _establishment = null;
      final list = await getEstablishmentsForOwner();
      if (list.isNotEmpty) {
        _establishment = list.first;
        await _secureStorage.set(_keyEstablishmentId, _establishment!.id);
      } else {
        await _secureStorage.remove(_keyEstablishmentId);
      }
    }
    notifyListeners();
  }

  /// Удаление аккаунта владельца: RPC удаляет все заведения и данные, Edge — auth.users.
  Future<void> deleteOwnerAccount({
    required String email,
    required String password,
    required Map<String, String> pinsByEstablishmentId,
  }) async {
    final authRes = await _supabase.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (authRes.user == null) {
      throw Exception('Invalid email or password');
    }
    final pinsJson = <String, dynamic>{};
    pinsByEstablishmentId.forEach((k, v) {
      pinsJson[k] = v.trim().toUpperCase();
    });
    await _supabase.client.rpc(
      'delete_owner_account_data',
      params: {
        'p_email': email.trim(),
        'p_pins': pinsJson,
      },
    );
    final res = await _supabase.client.functions.invoke(
      'purge-owner-auth',
      body: const {},
    );
    if (res.status != 200) {
      final err = (res.data is Map && (res.data as Map)['error'] != null)
          ? (res.data as Map)['error'].toString()
          : 'HTTP ${res.status}';
      throw Exception(err);
    }
    await logout();
  }

  /// Обновить данные заведения
  Future<void> updateEstablishment(Establishment establishment) async {
    try {
      // Обновляем напрямую — toJson() может включать поля, которые не обновляются
      await _supabase.client
          .from('establishments')
          .update({
            'name': establishment.name,
            'address': establishment.address,
            'inn_bin': establishment.innBin,
            'legal_name': establishment.legalName,
            'ogrn_ogrnip': establishment.ogrnOgrnip,
            'kpp': establishment.kpp,
            'bank_rs': establishment.bankRs,
            'bank_bik': establishment.bankBik,
            'bank_name': establishment.bankName,
            'director_fio': establishment.directorFio,
            'director_position': establishment.directorPosition,
            'default_currency': establishment.defaultCurrency,
            'updated_at': establishment.updatedAt.toIso8601String(),
          })
          .eq('id', establishment.id)
          .select();

      _establishment = establishment;
      notifyListeners(); // Обновить символ валюты в номенклатуре и др.
    } catch (e) {
      devLog('Ошибка обновления заведения: $e');
      rethrow; // Пробросить, чтобы UI мог показать ошибку
    }
  }

  /// Только `support_access_enabled` — не смешивать с [updateEstablishment], чтобы на БД
  /// без миграции `20260403150000_establishment_support_access.sql` не ломались валюта и реквизиты.
  Future<void> updateEstablishmentSupportAccess({
    required String establishmentId,
    required bool enabled,
  }) async {
    final now = DateTime.now();
    await _supabase.client
        .from('establishments')
        .update({
          'support_access_enabled': enabled,
          'updated_at': now.toIso8601String(),
        })
        .eq('id', establishmentId)
        .select();
    try {
      final me = _currentEmployee;
      await _supabase.client.from('support_access_event_log').insert({
        'establishment_id': establishmentId,
        'event_type': enabled
            ? 'owner_enabled_access'
            : 'owner_disabled_access',
        'account_login': me?.email,
      });
    } catch (_) {}
    if (_establishment?.id == establishmentId) {
      _establishment = _establishment!.copyWith(
        supportAccessEnabled: enabled,
        updatedAt: now,
      );
    }
    notifyListeners();
  }

  DateTime? _lastReconcilePreferredLanguageAt;
  String? _lastReconcilePreferredLanguageCode;

  /// Сохранить выбранный язык в профиле сотрудника (preferred_language в Supabase).
  /// Вызывается при смене языка из UI, чтобы язык сохранялся между сессиями и браузерами.
  ///
  /// [fromReconcile]: при рассинхроне устройство↔сервер — не дёргать RPC десятки раз подряд (лог 400).
  Future<void> savePreferredLanguage(
    String languageCode, {
    bool fromReconcile = false,
  }) async {
    final emp = _currentEmployee;
    if (emp == null) return;
    final code = languageCode.trim().toLowerCase();
    if (fromReconcile) {
      final now = DateTime.now();
      if (_lastReconcilePreferredLanguageCode == code &&
          _lastReconcilePreferredLanguageAt != null &&
          now.difference(_lastReconcilePreferredLanguageAt!) <
              const Duration(seconds: 25)) {
        return;
      }
    }
    Future<void> applyRpcOrRows(dynamic res, List<dynamic>? rows) async {
      if (fromReconcile) {
        _lastReconcilePreferredLanguageAt = DateTime.now();
        _lastReconcilePreferredLanguageCode = code;
      }
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        m['password'] = m['password_hash'] ?? '';
        _currentEmployee = Employee.fromJson(m);
      } else if (rows != null && rows.isNotEmpty) {
        final m = Map<String, dynamic>.from(rows.first as Map);
        m['password'] = m['password_hash'] ?? '';
        _currentEmployee = Employee.fromJson(m);
      } else {
        _currentEmployee = emp.copyWith(preferredLanguage: code);
      }
      await LocalizationService().markLocaleChoiceFromAuthFlow();
      notifyListeners();
    }

    try {
      final res = await _supabase.client.rpc(
        'patch_my_employee_profile',
        params: {
          'p_patch': {'preferred_language': code},
        },
      );
      await applyRpcOrRows(res, null);
    } catch (e, st) {
      if (e is PostgrestException) {
        devLog(
          'AccountManager: savePreferredLanguage PostgREST ${e.code} '
          'message=${e.message} details=${e.details} hint=${e.hint}',
        );
      } else {
        devLog('AccountManager: savePreferredLanguage error: $e $st');
      }
      // Fallback: прямой UPDATE по строке сотрудника (RLS), если RPC 400/др.
      try {
        final authId = _supabase.currentUser?.id;
        if (authId == null) return;
        final rows = await _supabase.client
            .from('employees')
            .update({'preferred_language': code})
            .or('id.eq.$authId,auth_user_id.eq.$authId')
            .select();
        await applyRpcOrRows(null, rows);
      } catch (e2, st2) {
        devLog('AccountManager: savePreferredLanguage fallback UPDATE: $e2 $st2');
      }
    }
  }

  /// Загрузка employee и establishment по Supabase Auth (auth_user_id = auth.uid())
  Future<bool> _loadCurrentUserFromAuth() async {
    try {
      final authUserId = _supabase.currentUser?.id;
      if (authUserId == null) return false;

      // employees.id = auth.uid() (owners) или employees.auth_user_id = auth.uid() (legacy→auth)
      final rawList = await _supabase.client
          .from('employees')
          .select()
          .or('id.eq.$authUserId,auth_user_id.eq.$authUserId')
          .eq('is_active', true);

      final rows = rawList is List ? rawList : <dynamic>[];
      if (rows.isEmpty) {
        ({Employee employee, Establishment establishment})? completed;
        if (!await _pendingOwnerAwaitingCompanyOnly(authUserId)) {
          completed = await completePendingOwnerRegistration();
        }
        completed ??= await PendingCoOwnerRegistration.tryComplete(this);
        completed ??= await _tryFixOwnerWithoutEmployee();
        if (completed != null) {
          _currentEmployee = completed.employee;
          _establishment = completed.establishment;
          onPreferredLanguageLoaded?.call(_currentEmployee!.preferredLanguage);
          await _secureStorage.set(_keyEmployeeId, _currentEmployee!.id);
          await _secureStorage.set(_keyEstablishmentId, _establishment!.id);
          notifyListeners();
          return true;
        }
        return false;
      }

      Map<String, dynamic> picked;
      if (rows.length == 1) {
        picked = Map<String, dynamic>.from(rows.first as Map);
      } else {
        final preferred = rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((m) => m['id']?.toString() == authUserId)
            .toList();
        picked = preferred.isNotEmpty
            ? preferred.first
            : Map<String, dynamic>.from(rows.first as Map);
        devLog(
          '🔐 AccountManager: ${rows.length} employee rows for auth user — '
          'using id=${picked['id']}',
        );
      }

      final employeeData = picked;
      employeeData['password'] = employeeData['password_hash'] ?? '';
      _currentEmployee = Employee.fromJson(employeeData);
      onPreferredLanguageLoaded?.call(_currentEmployee!.preferredLanguage);

      // Владелец может иметь несколько заведений — используем сохранённое текущее или первое
      if (_currentEmployee!.hasRole('owner')) {
        final list = await getEstablishmentsForOwner();
        if (list.isNotEmpty) {
          final storedId = await _secureStorage.get(_keyEstablishmentId);
          final match = storedId != null
              ? list.where((e) => e.id == storedId).firstOrNull
              : null;
          _establishment = match ?? list.first;
        } else {
          final estData = await _supabase.client
              .from('establishments')
              .select()
              .eq('id', _currentEmployee!.establishmentId)
              .limit(1)
              .single();
          _establishment = Establishment.fromJson(estData);
        }
      } else {
        final estData = await _supabase.client
            .from('establishments')
            .select()
            .eq('id', _currentEmployee!.establishmentId)
            .limit(1)
            .single();
        _establishment = Establishment.fromJson(estData);
      }

      await _secureStorage.set(_keyEmployeeId, _currentEmployee!.id);
      await _secureStorage.set(_keyEstablishmentId, _establishment!.id);
      return true;
    } catch (e) {
      devLog('🔐 AccountManager: _loadCurrentUserFromAuth error: $e');
      return false;
    }
  }

  /// Промокод, привязанный к заведению при регистрации (если вводили код). Только для собственника.
  Future<EstablishmentPromoInfo> getEstablishmentPromoForOwner() async {
    final est = _establishment;
    final emp = _currentEmployee;
    if (est == null || emp == null || !emp.hasRole('owner')) {
      return const EstablishmentPromoInfo();
    }
    final authUid = _supabase.client.auth.currentUser?.id;
    if (authUid == null || est.ownerId != authUid) {
      // Avoid noisy 400 from owner-only RPC when current auth session
      // does not match establishment.owner_id (e.g., delegated owner role).
      return const EstablishmentPromoInfo();
    }
    try {
      final res = await _supabase.client.rpc(
        'get_establishment_promo_for_owner',
        params: {'p_establishment_id': est.id},
      );
      if (res == null) return const EstablishmentPromoInfo();
      final List rows = res is List ? res as List : [res];
      if (rows.isEmpty) return const EstablishmentPromoInfo();
      final m = Map<String, dynamic>.from(rows.first as Map);
      final code = m['code']?.toString();
      final rawExp = m['expires_at'] ?? m['ExpiresAt'];
      final exp = _parseRpcTimestamp(rawExp);
      final rawDis = m['is_disabled'];
      final isDisabled = rawDis == true || rawDis == 1;
      final grantType = m['grants_subscription_type']?.toString().trim();
      final estTierFallback = _establishment?.subscriptionType?.trim();
      final resolvedGrantType = (grantType != null && grantType.isNotEmpty)
          ? grantType
          : (estTierFallback != null && estTierFallback.isNotEmpty
              ? estTierFallback
              : null);
      int empPacks = _parseRpcInt(
        m['grants_employee_slot_packs'] ??
            m['employee_slot_packs'] ??
            m['employee_packs'] ??
            m['grants_employee_packs'],
      );
      int branchPacks = _parseRpcInt(
        m['grants_branch_slot_packs'] ??
            m['branch_slot_packs'] ??
            m['additional_establishment_packs'] ??
            m['grants_additional_establishment_packs'],
      );
      final additiveOnly = _parseRpcBool(m['grants_additive_only']);
      int? promoMaxEmployees;
      final rawMaxEmp = m['max_employees'];
      if (rawMaxEmp != null) {
        final n = _parseRpcInt(rawMaxEmp, -1);
        if (n >= 0) promoMaxEmployees = n;
      }
      final noteRaw = m['promo_template_note']?.toString().trim();
      final promoTemplateNote =
          noteRaw != null && noteRaw.isNotEmpty ? noteRaw : null;

      // Фолбэк на фактические entitlement-пакеты, если старый RPC не отдал grants_* поля.
      if (empPacks <= 0) {
        try {
          final rows = await _supabase.client
              .from('establishment_entitlement_addons')
              .select('employee_slot_packs')
              .eq('establishment_id', est.id)
              .limit(1);
          if (rows is List && rows.isNotEmpty) {
            final row = Map<String, dynamic>.from(rows.first as Map);
            empPacks = _parseRpcInt(row['employee_slot_packs']);
          }
        } catch (_) {}
      }
      if (branchPacks <= 0) {
        try {
          final rows = await _supabase.client
              .from('owner_entitlement_addons')
              .select('branch_slot_packs')
              .limit(1);
          if (rows is List && rows.isNotEmpty) {
            final row = Map<String, dynamic>.from(rows.first as Map);
            branchPacks = _parseRpcInt(row['branch_slot_packs']);
          }
        } catch (_) {}
      }

      return EstablishmentPromoInfo(
        code: code,
        expiresAt: exp,
        isDisabled: isDisabled,
        grantsSubscriptionType: resolvedGrantType,
        grantsEmployeeSlotPacks: empPacks,
        grantsBranchSlotPacks: branchPacks,
        grantsAdditiveOnly: additiveOnly,
        promoMaxEmployees: promoMaxEmployees,
        promoTemplateNote: promoTemplateNote,
      );
    } catch (e, st) {
      devLog('getEstablishmentPromoForOwner: $e $st');
      return const EstablishmentPromoInfo(loadFailed: true);
    }
  }

  /// Обновить текущее заведение из БД (после применения промокода и т.п.).
  Future<void> refreshCurrentEstablishmentFromServer() async {
    final id = _establishment?.id;
    if (id == null) return;
    try {
      final estData = await _supabase.client
          .from('establishments')
          .select()
          .eq('id', id)
          .limit(1)
          .single();
      _establishment = Establishment.fromJson(estData);
      await refreshSupportSessionState();
      notifyListeners();
    } catch (e, st) {
      devLog('refreshCurrentEstablishmentFromServer: $e $st');
    }
  }

  /// Применить админский промокод к текущему заведению (настройки PRO). Только владелец.
  /// Ошибки: PROMO_*, ESTABLISHMENT_HAS_PROMO (текст в сообщении исключения).
  Future<void> applyPromoToEstablishmentForOwner(String rawCode) async {
    final est = _establishment;
    final emp = _currentEmployee;
    if (est == null || emp == null || !emp.hasRole('owner')) {
      throw Exception('apply_promo_forbidden');
    }
    await _supabase.client.rpc(
      'apply_promo_to_establishment_for_owner',
      params: {
        'p_establishment_id': est.id,
        'p_code': rawCode.trim().toUpperCase(),
      },
    );
    await refreshCurrentEstablishmentFromServer();
    await syncEstablishmentAccessFromServer();
  }

  /// Проверить, есть ли активный сеанс техподдержки по текущему заведению.
  Future<void> refreshSupportSessionState() async {
    final estId = _establishment?.id;
    final emp = _currentEmployee;
    if (estId == null || emp == null || !emp.hasRole('owner')) {
      _supportSessionActive = false;
      return;
    }
    if (_supportAccessTablesUnavailable) {
      _supportSessionActive = false;
      return;
    }
    try {
      final rows = await _supabase.client
          .from('support_access_audit_log')
          .select('id')
          .eq('establishment_id', estId)
          .isFilter('ended_at', null)
          .order('started_at', ascending: false)
          .limit(1);
      final next = rows is List && rows.isNotEmpty;
      if (next != _supportSessionActive) {
        _supportSessionActive = next;
        notifyListeners();
      }
    } on PostgrestException catch (e) {
      if (_looksLikeMissingSupportAccessSchema(e)) {
        _supportAccessTablesUnavailable = true;
      }
      // На старой БД таблицы может не быть — не ломаем UI.
      _supportSessionActive = false;
    } catch (_) {
      _supportAccessTablesUnavailable = true;
      _supportSessionActive = false;
    }
  }

  /// Журнал входов/выходов системной поддержки для собственника.
  Future<List<Map<String, dynamic>>> loadSupportAccessAuditLog({
    int limit = 100,
  }) async {
    final estId = _establishment?.id;
    final emp = _currentEmployee;
    if (estId == null || emp == null || !emp.hasRole('owner')) return const [];
    if (_supportAccessTablesUnavailable) return const [];
    try {
      final rows = await _supabase.client
          .from('support_access_event_log')
          .select(
              'id, event_type, support_operator_login, account_login, created_at')
          .eq('establishment_id', estId)
          .order('created_at', ascending: false)
          .limit(limit);
      if (rows is! List) return const [];
      return rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      if (_looksLikeMissingSupportAccessSchema(e)) {
        _supportAccessTablesUnavailable = true;
      }
      return const [];
    } catch (_) {
      _supportAccessTablesUnavailable = true;
      return const [];
    }
  }
}

/// Данные промокода, выданного заведению при регистрации с кодом из админки.
class EstablishmentPromoInfo {
  const EstablishmentPromoInfo({
    this.code,
    this.expiresAt,
    this.loadFailed = false,
    this.isDisabled = false,
    this.grantsSubscriptionType,
    this.grantsEmployeeSlotPacks = 0,
    this.grantsBranchSlotPacks = 0,
    this.grantsAdditiveOnly = false,
    this.promoMaxEmployees,
    this.promoTemplateNote,
  });

  final String? code;
  final DateTime? expiresAt;
  final bool loadFailed;

  /// Промокод отключён в админке ([is_disabled]); доступ блокируется на сервере.
  final bool isDisabled;

  /// Шаблон из `promo_codes.grants_subscription_type` (pro, ultra, …).
  final String? grantsSubscriptionType;

  /// Пакеты по +5 к лимиту сотрудников.
  final int grantsEmployeeSlotPacks;

  /// Пакеты дополнительных заведений (филиалов).
  final int grantsBranchSlotPacks;

  /// Только начисление пакетов без смены тарифа.
  final bool grantsAdditiveOnly;

  /// Опциональный лимит сотрудников из шаблона промокода (`max_employees`).
  final int? promoMaxEmployees;

  /// Примечание из `promo_codes.note` (админка).
  final String? promoTemplateNote;

  bool get hasPromo => !loadFailed && code != null && code!.isNotEmpty;

  /// Промокод реально даёт Pro: не отключён, не истёк; в БД у промокода всегда есть [expires_at].
  bool get isPromoGrantActive {
    if (loadFailed) return false;
    final c = code?.trim();
    if (c == null || c.isEmpty) return false;
    if (isDisabled) return false;
    final exp = expiresAt;
    if (exp == null) return false;
    if (!exp.isAfter(DateTime.now())) return false;
    return true;
  }
}

DateTime? _parseRpcTimestamp(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

int _parseRpcInt(dynamic raw, [int defaultValue = 0]) {
  if (raw == null) return defaultValue;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? defaultValue;
}

bool _parseRpcBool(dynamic raw, [bool defaultValue = false]) {
  if (raw == true || raw == 1) return true;
  if (raw == false || raw == 0) return false;
  return defaultValue;
}
