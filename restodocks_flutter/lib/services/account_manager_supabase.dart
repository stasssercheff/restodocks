import 'package:dio/dio.dart';
import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart'
    as supabase_url;

import '../core/clear_hash_stub.dart'
    if (dart.library.html) '../core/clear_hash_web.dart' as clear_hash;
import '../core/public_app_origin.dart';
import '../models/models.dart';
import '../utils/dev_log.dart';
import 'establishment_data_warmup_service.dart';
import 'tech_card_translation_cache.dart';
import 'offline_cache_service.dart';
import 'realtime_sync_service.dart';
import 'pos_dining_layout_service.dart';
import 'edge_function_http.dart';
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

/// Сервис управления аккаунтами с использованием Supabase
class AccountManagerSupabase extends ChangeNotifier {
  static final Random _secureRandom = Random.secure();

  static String _generateSecureInvitationToken() {
    final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static final AccountManagerSupabase _instance =
      AccountManagerSupabase._internal();
  factory AccountManagerSupabase() => _instance;
  AccountManagerSupabase._internal();

  final SupabaseService _supabase = SupabaseService();
  final SecureStorageService _secureStorage = SecureStorageService();
  final OfflineCacheService _offlineCache = OfflineCacheService();
  final RealtimeSyncService _realtimeSync = RealtimeSyncService();
  Establishment? _establishment;
  Employee? _currentEmployee;
  bool _initialized = false;

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

  /// Предпочитаемый язык пользователя
  String get preferredLanguage => _currentEmployee?.preferredLanguage ?? 'ru';

  /// Подписка Pro/Premium на заведении (без учёта 72 ч trial).
  bool get hasPaidProSubscription => _establishment?.hasPaidProAccess ?? false;

  /// Pro/Premium или активное окно 72 ч (см. establishments.pro_trial_ends_at).
  bool get hasProSubscription => _establishment?.hasEffectiveProAccess ?? false;

  /// Co-owner с view_only: только просмотр (при >1 заведении у пригласившего)
  bool get isViewOnlyOwner => _currentEmployee?.isViewOnlyOwner ?? false;

  /// ID заведения для данных (номенклатура, ТТК). Для филиала — родитель.
  String? get dataEstablishmentId => _establishment?.dataEstablishmentId;

  /// Авторизован ли пользователь (своя сессия employees или восстановленная из хранилища)
  bool get isLoggedInSync => _currentEmployee != null && _establishment != null;

  /// Инициализация сервиса
  /// Supabase восстанавливает сессию из localStorage при Supabase.initialize() в main().
  /// При F5/hard refresh Auth может восстанавливаться асинхронно — делаем retry.
  /// [forceRetryFromAuth] — true при переходе по ссылке confirm (getSessionFromUrl уже вызван).
  Future<void> initialize({bool forceRetryFromAuth = false}) async {
    if (forceRetryFromAuth) _initialized = false;
    // Если уже инициализирован и авторизован — не повторяем дорогую инициализацию.
    if (_initialized && isLoggedInSync) return;
    devLog('🔐 AccountManager: Starting initialization...');
    await _secureStorage.initialize();

    await _tryRestoreSession();
    if (isLoggedInSync) {
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
        await _checkPromoAccess();
        return;
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
      await _checkPromoAccess();
    }
  }

  /// Проверяет не истёк ли промокод заведения. Если истёк — разлогинивает.
  Future<void> _checkPromoAccess() async {
    final estId = _establishment?.id;
    if (estId == null) return;
    try {
      final result = await _supabase.client.rpc(
        'check_establishment_access',
        params: {'p_establishment_id': estId},
      );
      if (result == 'expired') {
        devLog(
            '🔐 AccountManager: Promo code expired for establishment $estId — logging out');
        await logout();
      }
    } catch (e) {
      devLog('🔐 AccountManager: _checkPromoAccess error (ignored): $e');
      // Не блокируем доступ при ошибке сети
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
    try {
      final v = await _supabase.client.rpc(
        'get_effective_max_additional_establishments_for_owner',
      );
      if (v == null) return 999;
      if (v is int) return v > 0 ? v : 999;
      if (v is double) return v.toInt() > 0 ? v.toInt() : 999;
      final n = int.tryParse(v.toString());
      return (n != null && n > 0) ? n : 999;
    } catch (_) {
      try {
        final v = await _supabase.client.rpc(
          'get_platform_config',
          params: {'p_key': 'max_establishments_per_owner'},
        );
        if (v == null) return 999;
        if (v is int) return v > 0 ? v : 999;
        if (v is double) return v.toInt() > 0 ? v.toInt() : 999;
        final s = v.toString();
        final n = int.tryParse(s);
        return (n != null && n > 0) ? n : 999;
      } catch (_) {
        return 999;
      }
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
    final params = <String, dynamic>{
      'p_name': name,
      'p_address': address,
      'p_phone': phone,
      'p_email': email,
      'p_pin_code': pinCode,
    };
    if (parentEstablishmentId != null && parentEstablishmentId.isNotEmpty) {
      params['p_parent_establishment_id'] = parentEstablishmentId;
    }
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

  /// Филиалы заведения (для шефа — фильтр ТТК по филиалам)
  Future<List<Establishment>> getBranchesForEstablishment(
      String establishmentId) async {
    try {
      final data = await _supabase.client.rpc(
        'get_branches_for_establishment',
        params: {'p_establishment_id': establishmentId},
      );
      if (data == null) return [];
      final list = data as List;
      return list
          .map((e) =>
              Establishment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      devLog('AccountManager: getBranchesForEstablishment error: $e');
      return [];
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
    return est;
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

    final establishmentsCount = await getEstablishmentsForOwner();
    final isViewOnlyOwner = establishmentsCount.length > 1;

    final token = _generateSecureInvitationToken();
    final invitationData = {
      'establishment_id': establishmentId,
      'invited_email': email,
      'invited_by': currentEmployee.id,
      'invitation_token': token,
      'status': 'pending',
      'is_view_only_owner': isViewOnlyOwner,
    };

    await _supabase.insertData('co_owner_invitations', invitationData);

    // Отправка email с ссылкой (здесь должна быть интеграция с email сервисом)
    final invitationLink =
        'https://yourapp.com/accept-co-owner-invitation?token=$token';
    devLog('Invitation link: $invitationLink'); // Временно выводим в консоль

    // TODO: Интегрировать с email сервисом для отправки приглашения
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
      final res = await _supabase.signUpWithEmail(emailTrim, password,
          emailRedirectTo: redirectUrl);
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
  }) async {
    final res = await _supabase.signUpWithEmail(
      email.trim(),
      password,
      emailRedirectTo: _getEmailRedirectUrl(interfaceLanguageCode),
    );
    final uid = res.user?.id ?? _supabase.currentUser?.id;
    final hasSession = res.session != null;
    return (userId: uid, hasSession: hasSession);
  }

  /// Сохранить pending owner — employee создастся после confirm (когда user в auth.users).
  Future<void> savePendingOwnerRegistration({
    required String authUserId,
    required Establishment establishment,
    required String fullName,
    String? surname,
    required String email,
    required List<String> roles,
    String preferredLanguage = 'ru',
  }) async {
    var lang = preferredLanguage.trim().toLowerCase();
    if (!LocalizationService.isSupportedLanguageCode(lang)) lang = 'ru';
    await _supabase.client.rpc(
      'save_pending_owner_registration',
      params: {
        'p_auth_user_id': authUserId,
        'p_establishment_id': establishment.id,
        'p_full_name': fullName,
        'p_surname': surname ?? '',
        'p_email': email,
        'p_roles': roles,
        'p_preferred_language': lang,
      },
    );
  }

  /// Завершить регистрацию владельца (authenticated, после confirm). Возвращает null если pending нет.
  Future<({Employee employee, Establishment establishment})?>
      completePendingOwnerRegistration() async {
    if (!_supabase.isAuthenticated) return null;
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
    notifyListeners();
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
    await FcmPushService.unregisterBeforeLogout();
    final est = _establishment;
    if (est != null) {
      await TechCardTranslationCache.clearForEstablishment(est.dataEstablishmentId);
    }
    EstablishmentDataWarmupService.instance.resetSession();
    await _realtimeSync.stop();
    await _offlineCache.clearCurrentUserCache();
    await _supabase.signOut();
    await _clearStoredSession();
    _currentEmployee = null;
    _establishment = null;
    _initialized = false;
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
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('establishment_id', establishmentId);

      return (data as List).map((json) => Employee.fromJson(json)).toList();
    } catch (e) {
      devLog('Ошибка получения сотрудников: $e');
      return [];
    }
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

  /// Сохранить выбранный язык в профиле сотрудника (preferred_language в Supabase).
  /// Вызывается при смене языка из UI, чтобы язык сохранялся между сессиями и браузерами.
  Future<void> savePreferredLanguage(String languageCode) async {
    final emp = _currentEmployee;
    if (emp == null) return;
    try {
      await _supabase.client
          .from('employees')
          .update({'preferred_language': languageCode}).eq('id', emp.id);
      _currentEmployee = emp.copyWith(preferredLanguage: languageCode);
    } catch (e) {
      devLog('AccountManager: savePreferredLanguage error: $e');
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
        var completed = await completePendingOwnerRegistration();
        if (completed == null) {
          completed = await _tryFixOwnerWithoutEmployee();
        }
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
      DateTime? exp;
      final rawExp = m['expires_at'];
      if (rawExp != null) {
        exp = DateTime.tryParse(rawExp.toString());
      }
      return EstablishmentPromoInfo(code: code, expiresAt: exp);
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
    await _checkPromoAccess();
  }
}

/// Данные промокода, выданного заведению при регистрации с кодом из админки.
class EstablishmentPromoInfo {
  const EstablishmentPromoInfo({
    this.code,
    this.expiresAt,
    this.loadFailed = false,
  });

  final String? code;
  final DateTime? expiresAt;
  final bool loadFailed;

  bool get hasPromo => !loadFailed && code != null && code!.isNotEmpty;
}
