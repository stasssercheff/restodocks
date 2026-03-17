import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'secure_storage_service.dart';
import 'supabase_service.dart';

const _keyEmployeeId = 'restodocks_employee_id';
const _keyEstablishmentId = 'restodocks_establishment_id';

const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE',
);
const _keyRememberPin = 'restodocks_remember_pin';
const _keyRememberEmail = 'restodocks_remember_email';
const _keyRememberPassword = 'restodocks_remember_password';

String _dateOnly(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Сервис управления аккаунтами с использованием Supabase
class AccountManagerSupabase extends ChangeNotifier {
  static final AccountManagerSupabase _instance = AccountManagerSupabase._internal();
  factory AccountManagerSupabase() => _instance;
  AccountManagerSupabase._internal();

  final SupabaseService _supabase = SupabaseService();
  final SecureStorageService _secureStorage = SecureStorageService();
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

  /// Есть ли PRO подписка
  bool get hasProSubscription => _establishment?.subscriptionType == 'pro' || _establishment?.subscriptionType == 'premium';

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
    if (isLoggedInSync) { _initialized = true; return; }

    // Retry: при hard refresh Supabase Auth может ещё не успеть прочитать localStorage.
    await Future.delayed(const Duration(milliseconds: 400));
    await _tryRestoreSession();
    _initialized = true;
    if (isLoggedInSync) return;

    devLog('🔐 AccountManager: No stored session and not authenticated');
  }

  Future<void> _tryRestoreSession() async {
    final employeeId = await _secureStorage.get(_keyEmployeeId);
    final establishmentId = await _secureStorage.get(_keyEstablishmentId);
    devLog('🔐 AccountManager: Storage - employee: $employeeId, establishment: $establishmentId, auth: ${_supabase.isAuthenticated}');

    // 1. Сначала проверяем Supabase Auth — приоритет для пользователей с auth
    if (_supabase.isAuthenticated) {
      devLog('🔐 AccountManager: Supabase Auth session found, loading user data...');
      final ok = await _loadCurrentUserFromAuth();
      if (ok) {
        devLog('🔐 AccountManager: User data loaded from Auth, logged in: $isLoggedInSync');
        await _checkPromoAccess();
        return;
      }
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
        devLog('🔐 AccountManager: Promo code expired for establishment $estId — logging out');
        await logout();
      }
    } catch (e) {
      devLog('🔐 AccountManager: _checkPromoAccess error (ignored): $e');
      // Не блокируем доступ при ошибке сети
    }
  }

  Future<void> _restoreSession(String employeeId, String establishmentId) async {
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

      devLog('🔐 AccountManager: Loading establishment data for ID: $establishmentId');
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

  /// Максимум дополнительных заведений на владельца (из platform_config)
  Future<int> getMaxEstablishmentsPerOwner() async {
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

  /// Список заведений владельца (owner_id = auth.uid)
  Future<List<Establishment>> getEstablishmentsForOwner() async {
    try {
      final data = await _supabase.client.rpc('get_establishments_for_owner');
      if (data == null) return [];
      final list = data as List;
      return list.map((e) => Establishment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
    response['parent_establishment_id'] = response['parent_establishment_id']?.toString();
    final created = Establishment.fromJson(response);
    return created;
  }

  /// Филиалы заведения (для шефа — фильтр ТТК по филиалам)
  Future<List<Establishment>> getBranchesForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client.rpc(
        'get_branches_for_establishment',
        params: {'p_establishment_id': establishmentId},
      );
      if (data == null) return [];
      final list = data as List;
      return list.map((e) => Establishment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      devLog('AccountManager: getBranchesForEstablishment error: $e');
      return [];
    }
  }

  /// Переключение на другое заведение (для владельца с несколькими заведениями)
  Future<void> switchEstablishment(Establishment establishment) async {
    _establishment = establishment;
    await _secureStorage.set(_keyEstablishmentId, establishment.id);
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
    return createdEstablishment;
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
    if (raw == null) throw Exception('register_company_with_promo returned null');
    final m = Map<String, dynamic>.from(raw);
    m['owner_id'] = m['owner_id']?.toString() ?? '';
    final est = Establishment.fromJson(m);
    _establishment = est;
    return est;
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
  Future<bool> isEmailTakenInEstablishment(String email, String establishmentId) async {
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

    final token = DateTime.now().millisecondsSinceEpoch.toString();
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
    final invitationLink = 'https://yourapp.com/accept-co-owner-invitation?token=$token';
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
      throw Exception('employees.id = auth.users.id — требуется authUserId от signUp');
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
    final isSelfRegistration = _supabase.currentUser?.id == authUserId || !isLoggedInSync;
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
  Future<({String? userId, bool hasSession})> signUpToSupabaseAuth(String email, String password) async {
    final emailTrim = email.trim();
    devLog('DEBUG: signUpToSupabaseAuth called with email: $emailTrim');

    // Сначала попробуем войти - вдруг пользователь уже существует
    try {
      devLog('DEBUG: Attempting signIn first...');
      final signInRes = await _supabase.signInWithEmail(emailTrim, password);
      if (_supabase.currentUser != null) {
        devLog('DEBUG: User already exists, signed in: ${_supabase.currentUser!.id}');
        return (userId: _supabase.currentUser!.id, hasSession: signInRes.session != null);
      }
    } catch (signInError) {
      devLog('DEBUG: signIn failed: $signInError');
      // Продолжаем к signUp
    }

    // Если вход не удался, пробуем зарегистрировать нового пользователя
    try {
      devLog('DEBUG: Attempting signUp...');
      final redirectUrl = _getEmailRedirectUrl();
      final res = await _supabase.signUpWithEmail(emailTrim, password, emailRedirectTo: redirectUrl);
      final uid = res.user?.id ?? _supabase.currentUser?.id;
      final hasSession = res.session != null;
      devLog('DEBUG: signUp completed, userId: $uid, hasSession: $hasSession');
      return (userId: uid, hasSession: hasSession);
    } catch (signUpError) {
      devLog('DEBUG: signUpWithEmail failed: $signUpError');

      // Если signUp тоже не удался из-за "user already exists", попробуем войти еще раз
      if (signUpError.toString().contains('already') || signUpError.toString().contains('exists')) {
        try {
          devLog('DEBUG: signUp failed with "already exists", trying signIn again...');
          final signInRes = await _supabase.signInWithEmail(emailTrim, password);
          if (_supabase.currentUser != null) {
            return (userId: _supabase.currentUser!.id, hasSession: signInRes.session != null);
          }
        } catch (finalSignInError) {
          devLog('DEBUG: Final signIn also failed: $finalSignInError');
        }
      }

      rethrow;
    }
  }

  /// URL для редиректа после подтверждения. Всегда production — Supabase требует точного совпадения с Redirect URLs.
  static String _getEmailRedirectUrl() {
    return 'https://restodocks.com';
  }

  /// Регистрация владельца в Supabase Auth (employees.id = auth.users.id — создаём auth первым)
  /// Возвращает (auth user id, есть ли сессия).
  /// При Confirm Email session = null — пользователь должен подтвердить почту.
  Future<({String? userId, bool hasSession})> signUpWithEmailForOwner(String email, String password) async {
    final res = await _supabase.signUpWithEmail(
      email.trim(),
      password,
      emailRedirectTo: _getEmailRedirectUrl(),
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
  }) async {
    await _supabase.client.rpc(
      'save_pending_owner_registration',
      params: {
        'p_auth_user_id': authUserId,
        'p_establishment_id': establishment.id,
        'p_full_name': fullName,
        'p_surname': surname ?? '',
        'p_email': email,
        'p_roles': roles,
      },
    );
  }

  /// Завершить регистрацию владельца (authenticated, после confirm). Возвращает null если pending нет.
  Future<({Employee employee, Establishment establishment})?> completePendingOwnerRegistration() async {
    if (!_supabase.isAuthenticated) return null;
    final res = await _supabase.client.rpc('complete_pending_owner_registration');
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
  Future<({Employee employee, Establishment establishment})?> _tryFixOwnerWithoutEmployee() async {
    if (!_supabase.isAuthenticated) return null;
    final email = _supabase.currentUser?.email?.trim();
    if (email == null || email.isEmpty) return null;
    try {
      final res = await _supabase.client.rpc('fix_owner_without_employee', params: {'p_email': email});
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
    if (ownerAccessLevel != null) params['p_owner_access_level'] = ownerAccessLevel;
    final res = await _supabase.client.rpc('create_owner_employee', params: params);
    final data = Map<String, dynamic>.from(res as Map);
    data['password'] = '';
    data['password_hash'] = '';
    return Employee.fromJson(data);
  }

  /// Вход по email и паролю: Supabase Auth или legacy (Edge Function)
  /// На кастомном домене (restodocks.com) пробуем legacy первым — Auth иногда падает из‑за cookies/ошибок.
  Future<({Employee employee, Establishment establishment})?> findEmployeeByEmailAndPasswordGlobal({
    required String email,
    required String password,
  }) async {
    final emailTrim = email.trim();
    final passwordTrimmed = password.trim();
    lastLoginError = null;
    if (emailTrim.isEmpty) return null;

    final isCustomDomain = kIsWeb && Uri.base.host.contains('restodocks');

    // На кастомном домене: сначала legacy (обход проблем Auth на restodocks.com)
    if (isCustomDomain) {
      final legacyResult = await _findEmployeeByPasswordHashViaEdgeFunction(emailTrim, passwordTrimmed);
      if (legacyResult != null) return legacyResult;
    }

    // 1. Пробуем Supabase Auth (учётки в auth.users)
    try {
      await _supabase.signInWithEmail(emailTrim, passwordTrimmed);
      if (_supabase.isAuthenticated) {
        final authUserId = _supabase.currentUser!.id;
        final list = await _supabase.client
            .from('employees')
            .select()
            .eq('id', authUserId)
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
          final fixRes = await _supabase.client.rpc('fix_owner_without_employee', params: {'p_email': emailTrim});
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
      if (authErr is Exception && authErr.toString().contains('employee_not_found')) {
        rethrow;
      }
      // Логируем всегда — иначе в prod (kDebugMode=false) не увидим причину
      lastLoginError = 'Auth: ${authErr.toString().replaceAll(RegExp(r'\s+'), ' ')}';
      devLog('🔐 Login: Supabase Auth failed: $authErr');
      if (authErr.toString().contains('Invalid login credentials')) {
        devLog('🔐 Login: (Invalid credentials → пробуем legacy authenticate-employee)');
      } else if (authErr.toString().toLowerCase().contains('cors') || authErr.toString().toLowerCase().contains('network')) {
        devLog('🔐 Login: (CORS/сеть? Добавь restodocks.com в Supabase Auth Redirect URLs и API CORS)');
      }
      try {
        await _supabase.signOut();
      } catch (_) { /* ignore */ }
    }

    // 2. Legacy: password_hash через Edge Function (employees без auth.users)
    return _findEmployeeByPasswordHashViaEdgeFunction(emailTrim, passwordTrimmed);
  }

  /// Вызов Edge Function authenticate-employee через raw HTTP (обход Safari cross-origin
  /// POST body issues с supabase functions.invoke — body иногда не уходит).
  /// Retry при 401/5xx/сети — proxy/маршрутизация может обрывать первый запрос.
  Future<({int status, Map<String, dynamic>? data})> _invokeAuthenticateEmployeeHttp(
    Map<String, dynamic> body,
  ) async {
    const maxRetries = 3;
    const retryDelays = [600, 1200]; // ms, увеличенные задержки при proxy/маршрутизации

    final url = '${supabase_url.getSupabaseBaseUrl()}/functions/v1/authenticate-employee';
    final dio = Dio(BaseOptions(
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $_supabaseAnonKey',
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true, // не бросать на 4xx
    ));

    ({int status, Map<String, dynamic>? data}) lastResult = (status: 0, data: null);

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: retryDelays[attempt - 1]));
        devLog('🔐 authenticate-employee retry $attempt/$maxRetries');
      }
      try {
        final resp = await dio.post(url, data: body);
        final data = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : (resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null);
        lastResult = (status: resp.statusCode ?? 0, data: data);

        // 4xx (в т.ч. 401) — retry при invalid_credentials (proxy/маршрутизация может обрывать запрос)
        if (resp.statusCode != null && resp.statusCode! >= 400 && resp.statusCode! < 500) {
          if (resp.statusCode == 401 &&
              (data?['error'] == 'invalid_credentials') &&
              attempt < maxRetries - 1) {
            continue;
          }
          return lastResult;
        }
        // 2xx — успех
        if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
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

  /// Legacy: BCrypt-проверка пароля через Edge Function authenticate-employee.
  /// password_hash никогда не покидает сервер — клиент получает только данные сотрудника.
  Future<({Employee employee, Establishment establishment})?> _findEmployeeByPasswordHashViaEdgeFunction(
    String email,
    String password,
  ) async {
    try {
      devLog('🔐 Login: Legacy fallback — calling authenticate-employee (HTTP)');

      final res = await _invokeAuthenticateEmployeeHttp({'email': email, 'password': password});

      if (res.status == 401) {
        lastLoginError = (lastLoginError != null ? '$lastLoginError → ' : '') + 'Legacy: 401 invalid credentials';
        devLog('🔐 Login: Legacy — invalid credentials (401)');
        return null;
      }

      if (res.status != 200) {
        String msg = 'Legacy: ${res.status}';
        if (res.data is Map) {
          final d = res.data as Map;
          msg = (d['message'] ?? d['error'] ?? msg).toString();
        }
        lastLoginError = (lastLoginError != null ? '$lastLoginError → ' : '') + msg;
        devLog('🔐 Login: Legacy — Edge Function error: ${res.status}, data=${res.data}');
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
      final establishment = Establishment.fromJson(Map<String, dynamic>.from(estRaw as Map));

      // Если сервер создал auth user — входим в Supabase Auth для последующих запросов с JWT (RLS)
      final authUserCreated = data['authUserCreated'] == true;
      if (authUserCreated) {
        try {
          await _supabase.signInWithEmail(email.trim(), password);
          if (_supabase.isAuthenticated) {
            devLog('🔐 Login: Legacy → Supabase Auth session established for ${employee.email}');
          }
        } catch (signInErr) {
          devLog('🔐 Login: signInWithPassword after authUserCreated failed (continuing with legacy): $signInErr');
        }
      }

      devLog('🔐 Login: Legacy — success for ${employee.email}');
      return (employee: employee, establishment: establishment);
    } catch (e, st) {
      lastLoginError = (lastLoginError != null ? '$lastLoginError → ' : '') + 'Legacy exception: $e';
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

  /// Вход в систему
  /// [rememberCredentials] — сохранить PIN, email и пароль для автозаполнения
  Future<void> login(
    Employee employee,
    Establishment establishment, {
    bool rememberCredentials = false,
    String? pin,
    String? email,
    String? password,
  }) async {
    devLog('🔐 AccountManager: Setting current user - employee: ${employee.id}, establishment: ${establishment.id}');
    _currentEmployee = employee;
    _establishment = establishment;
    onPreferredLanguageLoaded?.call(employee.preferredLanguage);

    devLog('🔐 AccountManager: Saving to secure storage...');
    await _secureStorage.set(_keyEmployeeId, employee.id);
    await _secureStorage.set(_keyEstablishmentId, establishment.id);
    devLog('🔐 AccountManager: Data saved to secure storage');

    if (rememberCredentials && email != null && password != null) {
      await _secureStorage.set(_keyRememberEmail, email);
      await _secureStorage.set(_keyRememberPassword, password);
    } else {
      await _secureStorage.remove(_keyRememberEmail);
      await _secureStorage.remove(_keyRememberPassword);
    }
  }

  /// Загрузить сохранённые учётные данные (для автозаполнения формы входа)
  Future<({String? pin, String? email, String? password})> loadRememberedCredentials() async {
    await _secureStorage.initialize();
    final pin = await _secureStorage.get(_keyRememberPin);
    final email = await _secureStorage.get(_keyRememberEmail);
    final password = await _secureStorage.get(_keyRememberPassword);
    return (pin: pin, email: email, password: password);
  }

  /// Выход из системы
  Future<void> logout() async {
    await _supabase.signOut();
    await _clearStoredSession();
    _currentEmployee = null;
    _establishment = null;
  }

  /// Проверка, авторизован ли пользователь
  Future<bool> isLoggedIn() async {
    return isLoggedInSync;
  }

  /// Получить всех сотрудников компании
  Future<List<Employee>> getEmployeesForEstablishment(String establishmentId) async {
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
  Future<List<Employee>> getExecutiveChefsForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('establishment_id', establishmentId)
          .eq('is_active', true);

      final all = (data as List).map((json) => Employee.fromJson(json)).toList();
      final execChefs = all.where((e) => e.roles.contains('executive_chef')).toList();
      if (execChefs.isNotEmpty) return execChefs;
      final sousChefs = all.where((e) => e.roles.contains('sous_chef')).toList();
      if (sousChefs.isNotEmpty) return sousChefs;
      final owners = all.where((e) => e.roles.contains('owner')).toList();
      return owners;
    } catch (e) {
      devLog('Ошибка получения шеф-поваров: $e');
      return [];
    }
  }

  /// Обновить данные сотрудника (пароль не обновляется — используйте отдельный поток смены пароля).
  /// avatar_url сохраняется в Supabase Storage (bucket avatars) — данные не зависят от деплоя.
  Future<void> updateEmployee(Employee employee) async {
    try {
      var employeeData = employee.toJson()
        ..remove('password')
        ..remove('password_hash');
      // avatar_url сохраняем — колонка добавлена миграцией supabase_migration_employee_avatar.sql

      try {
        await _supabase.updateData(
          'employees',
          employeeData,
          'id',
          employee.id,
        );
      } catch (e) {
        if (_isSchemaColumnError(e)) {
          employeeData = Map<String, dynamic>.from(employeeData)
            ..remove('can_edit_own_schedule');
          await _supabase.updateData(
            'employees',
            employeeData,
            'id',
            employee.id,
          );
        } else if (_isPaymentColumnError(e)) {
          employeeData = Map<String, dynamic>.from(employeeData)
            ..remove('payment_type')
            ..remove('rate_per_shift')
            ..remove('hourly_rate');
          await _supabase.updateData(
            'employees',
            employeeData,
            'id',
            employee.id,
          );
        } else if (_isEmploymentColumnError(e)) {
          employeeData = Map<String, dynamic>.from(employeeData)
            ..remove('employment_status')
            ..remove('employment_start_date')
            ..remove('employment_end_date');
          await _supabase.updateData(
            'employees',
            employeeData,
            'id',
            employee.id,
          );
        } else {
          rethrow;
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

  /// Удаление сотрудника (прямой DELETE — оставляет auth.users, email нельзя переиспользовать)
  @Deprecated('Use deleteEmployeeWithPin for full deletion and email reuse')
  Future<void> deleteEmployee(String employeeId) async {
    try {
      devLog('🗑️ AccountManager: Deleting employee $employeeId...');
      await _supabase.client
          .from('employees')
          .delete()
          .eq('id', employeeId);
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
        (msg.contains('column') && (msg.contains('exist') || msg.contains('found') || msg.contains('does not')));
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
          .update({'preferred_language': languageCode})
          .eq('id', emp.id);
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
      var list = await _supabase.client
          .from('employees')
          .select()
          .or('id.eq.$authUserId,auth_user_id.eq.$authUserId')
          .eq('is_active', true)
          .limit(1);

      if (list == null || (list as List).isEmpty) {
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

      final employeeData = Map<String, dynamic>.from((list as List).first);
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
}