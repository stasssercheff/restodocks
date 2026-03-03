import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'secure_storage_service.dart';
import 'supabase_service.dart';

const _keyEmployeeId = 'restodocks_employee_id';
const _keyEstablishmentId = 'restodocks_establishment_id';
const _keyRememberPin = 'restodocks_remember_pin';
const _keyRememberEmail = 'restodocks_remember_email';
const _keyRememberPassword = 'restodocks_remember_password';

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
  Future<void> initialize() async {
    // Если уже инициализирован и авторизован — не повторяем дорогую инициализацию.
    // Это предотвращает лишние задержки при повторных вызовах из GoRouter redirect.
    if (_initialized && isLoggedInSync) return;
    print('🔐 AccountManager: Starting initialization...');
    await _secureStorage.initialize();

    await _tryRestoreSession();
    if (isLoggedInSync) { _initialized = true; return; }

    // Retry: при hard refresh Supabase Auth может ещё не успеть прочитать localStorage.
    await Future.delayed(const Duration(milliseconds: 400));
    await _tryRestoreSession();
    _initialized = true;
    if (isLoggedInSync) return;

    print('🔐 AccountManager: No stored session and not authenticated');
  }

  Future<void> _tryRestoreSession() async {
    final employeeId = await _secureStorage.get(_keyEmployeeId);
    final establishmentId = await _secureStorage.get(_keyEstablishmentId);
    print('🔐 AccountManager: Storage - employee: $employeeId, establishment: $establishmentId, auth: ${_supabase.isAuthenticated}');

    // 1. Сначала проверяем Supabase Auth — приоритет для пользователей с auth
    if (_supabase.isAuthenticated) {
      print('🔐 AccountManager: Supabase Auth session found, loading user data...');
      final ok = await _loadCurrentUserFromAuth();
      if (ok) {
        print('🔐 AccountManager: User data loaded from Auth, logged in: $isLoggedInSync');
        await _checkPromoAccess();
        return;
      }
    }

    // 2. Иначе — восстановление из хранилища (legacy)
    if (employeeId != null && establishmentId != null) {
      print('🔐 AccountManager: Restoring session from storage...');
      await _restoreSession(employeeId, establishmentId);
      print('🔐 AccountManager: Session restored, logged in: $isLoggedInSync');
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
        print('🔐 AccountManager: Promo code expired for establishment $estId — logging out');
        await logout();
      }
    } catch (e) {
      print('🔐 AccountManager: _checkPromoAccess error (ignored): $e');
      // Не блокируем доступ при ошибке сети
    }
  }

  Future<void> _restoreSession(String employeeId, String establishmentId) async {
    try {
      print('🔐 AccountManager: Loading employee data for ID: $employeeId');
      final employeeDataRaw = await _supabase.client
          .from('employees')
          .select()
          .eq('id', employeeId)
          .eq('is_active', true)
          .limit(1)
          .single();

      print('🔐 AccountManager: Employee data loaded successfully');
      final empData = Map<String, dynamic>.from(employeeDataRaw);
      empData['password'] = empData['password_hash'] ?? '';
      _currentEmployee = Employee.fromJson(empData);
      onPreferredLanguageLoaded?.call(_currentEmployee!.preferredLanguage);

      print('🔐 AccountManager: Loading establishment data for ID: $establishmentId');
      final estData = await _supabase.client
          .from('establishments')
          .select()
          .eq('id', establishmentId)
          .limit(1)
          .single();

      print('🔐 AccountManager: Establishment data loaded successfully');
      _establishment = Establishment.fromJson(estData);

      print('🔐 AccountManager: Session restored successfully');
    } catch (e) {
      print('❌ AccountManager: Error restoring session: $e');
      print('🔍 AccountManager: This might be RLS policy issue');
      await _clearStoredSession();
      _currentEmployee = null;
      _establishment = null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.remove(_keyEmployeeId);
    await _secureStorage.remove(_keyEstablishmentId);
  }

  /// Список заведений владельца (owner_id = auth.uid)
  Future<List<Establishment>> getEstablishmentsForOwner() async {
    try {
      final data = await _supabase.client.rpc('get_establishments_for_owner');
      if (data == null) return [];
      final list = data as List;
      return list.map((e) => Establishment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      print('AccountManager: getEstablishmentsForOwner error: $e');
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
      print('AccountManager: getBranchesForEstablishment error: $e');
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
      print('Ошибка поиска заведения: $e');
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
      print('Ошибка поиска заведения по PIN: $e');
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
    print('Invitation link: $invitationLink'); // Временно выводим в консоль

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

      print('Test employees deleted successfully');
    } catch (e) {
      print('Error deleting test employees: $e');
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
    // Владелец добавляет (authenticated) → create_employee_for_company.
    // Саморегистрация (anon) → create_employee_self_register.
    final rpcName = _supabase.isAuthenticated ? 'create_employee_for_company' : 'create_employee_self_register';
    final params = <String, dynamic>{
      'p_auth_user_id': authUserId,
      'p_establishment_id': company.id,
      'p_full_name': fullName,
      'p_surname': surname ?? '',
      'p_email': email,
      'p_department': department,
      'p_section': section ?? '',
      'p_roles': roles,
    };
    if (rpcName == 'create_employee_for_company' && ownerAccessLevel != null) {
      params['p_owner_access_level'] = ownerAccessLevel;
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
    print('DEBUG: signUpToSupabaseAuth called with email: $emailTrim');

    // Сначала попробуем войти - вдруг пользователь уже существует
    try {
      print('DEBUG: Attempting signIn first...');
      final signInRes = await _supabase.signInWithEmail(emailTrim, password);
      if (_supabase.currentUser != null) {
        print('DEBUG: User already exists, signed in: ${_supabase.currentUser!.id}');
        return (userId: _supabase.currentUser!.id, hasSession: signInRes.session != null);
      }
    } catch (signInError) {
      print('DEBUG: signIn failed: $signInError');
      // Продолжаем к signUp
    }

    // Если вход не удался, пробуем зарегистрировать нового пользователя
    try {
      print('DEBUG: Attempting signUp...');
      final redirectUrl = _getEmailRedirectUrl();
      final res = await _supabase.signUpWithEmail(emailTrim, password, emailRedirectTo: redirectUrl);
      final uid = res.user?.id ?? _supabase.currentUser?.id;
      final hasSession = res.session != null;
      print('DEBUG: signUp completed, userId: $uid, hasSession: $hasSession');
      return (userId: uid, hasSession: hasSession);
    } catch (signUpError) {
      print('DEBUG: signUpWithEmail failed: $signUpError');

      // Если signUp тоже не удался из-за "user already exists", попробуем войти еще раз
      if (signUpError.toString().contains('already') || signUpError.toString().contains('exists')) {
        try {
          print('DEBUG: signUp failed with "already exists", trying signIn again...');
          final signInRes = await _supabase.signInWithEmail(emailTrim, password);
          if (_supabase.currentUser != null) {
            return (userId: _supabase.currentUser!.id, hasSession: signInRes.session != null);
          }
        } catch (finalSignInError) {
          print('DEBUG: Final signIn also failed: $finalSignInError');
        }
      }

      rethrow;
    }
  }

  /// URL для редиректа после подтверждения email. Web: Uri.base.origin; мобильные: production URL.
  static String? _getEmailRedirectUrl() {
    if (kIsWeb) {
      try {
        final u = Uri.base;
        if (u.host.isNotEmpty && u.scheme.startsWith('http')) {
          return u.origin;
        }
      } catch (_) {}
    }
    return 'https://www.restodocks.com';
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

  /// Создание владельца через RPC (обход RLS при Confirm Email — нет сессии после signUp)
  /// [ownerAccessLevel] — 'view_only' для co-owner при >1 заведении у пригласившего
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

  /// Вход по email и паролю: сначала Supabase Auth, при отсутствии — legacy (employees.password_hash)
  Future<({Employee employee, Establishment establishment})?> findEmployeeByEmailAndPasswordGlobal({
    required String email,
    required String password,
  }) async {
    final emailTrim = email.trim();
    final passwordTrimmed = password.trim();
    if (emailTrim.isEmpty) return null;

    // 1. Пробуем Supabase Auth (для новых учёток)
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

        // Вход в Auth успешен, но employee нет — пробуем авто-исправление (владелец без записи)
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
          if (kDebugMode) debugPrint('🔐 fix_owner_without_employee failed: $fixErr');
        }

        await _supabase.signOut();
        throw Exception('employee_not_found');
      }
    } catch (authErr) {
      if (authErr is Exception && authErr.toString().contains('employee_not_found')) {
        rethrow;
      }
      if (kDebugMode) {
        debugPrint('🔐 Login: Supabase Auth failed: $authErr');
      }
      try {
        await _supabase.signOut();
      } catch (_) { /* игнор при ошибке выхода */ }
    }

    // 2. Legacy: проверка password_hash через Edge Function на сервере
    return _findEmployeeByPasswordHashViaEdgeFunction(emailTrim, passwordTrimmed);
  }

  /// Legacy: BCrypt-проверка пароля через Edge Function authenticate-employee.
  /// password_hash никогда не покидает сервер — клиент получает только данные сотрудника.
  Future<({Employee employee, Establishment establishment})?> _findEmployeeByPasswordHashViaEdgeFunction(
    String email,
    String password,
  ) async {
    try {
      if (kDebugMode) debugPrint('🔐 Login: Legacy — calling authenticate-employee Edge Function');

      final res = await _supabase.client.functions.invoke(
        'authenticate-employee',
        body: {'email': email, 'password': password},
      );

      if (res.status == 401) {
        if (kDebugMode) debugPrint('🔐 Login: Legacy — invalid credentials (401)');
        return null;
      }

      if (res.status != 200) {
        if (kDebugMode) debugPrint('🔐 Login: Legacy — Edge Function error: ${res.status}');
        return null;
      }

      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) {
        if (kDebugMode) debugPrint('🔐 Login: Legacy — error: ${data['error']}');
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

      if (kDebugMode) debugPrint('🔐 Login: Legacy — success for ${employee.email}');
      return (employee: employee, establishment: establishment);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('🔐 Login: Legacy Edge Function error: $e');
        debugPrint('🔐 Login: Stack: $st');
      }
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
      final res = await _supabase.client.functions.invoke(
        'authenticate-employee',
        body: {
          'email': email.trim(),
          'password': password.trim(),
          'establishment_id': company.id,
        },
      );

      if (res.status != 200) return null;
      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;

      final empRaw = data['employee'];
      if (empRaw == null) return null;

      final empData = Map<String, dynamic>.from(empRaw as Map);
      empData['password'] = '';
      empData['password_hash'] = '';
      return Employee.fromJson(empData);
    } catch (e) {
      if (kDebugMode) debugPrint('🔐 findEmployeeByEmailAndPassword error: $e');
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
    print('🔐 AccountManager: Setting current user - employee: ${employee.id}, establishment: ${establishment.id}');
    _currentEmployee = employee;
    _establishment = establishment;
    onPreferredLanguageLoaded?.call(employee.preferredLanguage);

    print('🔐 AccountManager: Saving to secure storage...');
    await _secureStorage.set(_keyEmployeeId, employee.id);
    await _secureStorage.set(_keyEstablishmentId, establishment.id);
    print('🔐 AccountManager: Data saved to secure storage');

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
      print('Ошибка получения сотрудников: $e');
      return [];
    }
  }

  /// Шеф-повара заведения (для инвентаризации: кабинет + email).
  Future<List<Employee>> getExecutiveChefsForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('establishment_id', establishmentId)
          .eq('is_active', true);

      final all = (data as List).map((json) => Employee.fromJson(json)).toList();
      return all.where((e) => e.roles.contains('executive_chef')).toList();
    } catch (e) {
      print('Ошибка получения шеф-поваров: $e');
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
        if (_isPaymentColumnError(e)) {
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
        } else {
          rethrow;
        }
      }

      if (_currentEmployee?.id == employee.id) {
        _currentEmployee = employee;
      }
    } catch (e) {
      print('Ошибка обновления сотрудника: $e');
      rethrow;
    }
  }

  /// Удаление сотрудника
  Future<void> deleteEmployee(String employeeId) async {
    try {
      print('🗑️ AccountManager: Deleting employee $employeeId...');
      await _supabase.client
          .from('employees')
          .delete()
          .eq('id', employeeId);
      print('✅ AccountManager: Employee deleted successfully');
    } catch (e) {
      print('❌ AccountManager: Failed to delete employee: $e');
      rethrow;
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

  /// Обновить данные заведения
  Future<void> updateEstablishment(Establishment establishment) async {
    try {
      await _supabase.updateData(
        'establishments',
        establishment.toJson(),
        'id',
        establishment.id,
      );

      _establishment = establishment;
      notifyListeners(); // Обновить символ валюты в номенклатуре и др.
    } catch (e) {
      print('Ошибка обновления заведения: $e');
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
      print('AccountManager: savePreferredLanguage error: $e');
    }
  }

  /// Загрузка employee и establishment по Supabase Auth (auth_user_id = auth.uid())
  Future<bool> _loadCurrentUserFromAuth() async {
    try {
      final authUserId = _supabase.currentUser?.id;
      if (authUserId == null) return false;

      final list = await _supabase.client
          .from('employees')
          .select()
          .eq('id', authUserId)
          .eq('is_active', true)
          .limit(1);

      if (list == null || (list as List).isEmpty) return false;

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
      print('🔐 AccountManager: _loadCurrentUserFromAuth error: $e');
      return false;
    }
  }
}