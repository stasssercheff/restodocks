import 'package:bcrypt/bcrypt.dart';
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
class AccountManagerSupabase {
  static final AccountManagerSupabase _instance = AccountManagerSupabase._internal();
  factory AccountManagerSupabase() => _instance;
  AccountManagerSupabase._internal();

  final SupabaseService _supabase = SupabaseService();
  final SecureStorageService _secureStorage = SecureStorageService();
  Establishment? _establishment;
  Employee? _currentEmployee;

  // Геттеры
  Establishment? get establishment => _establishment;
  Employee? get currentEmployee => _currentEmployee;

  /// Авторизован ли пользователь (своя сессия employees или восстановленная из хранилища)
  bool get isLoggedInSync => _currentEmployee != null && _establishment != null;

  /// Инициализация сервиса
  Future<void> initialize() async {
    await _secureStorage.initialize();

    // 1. Восстановление сессии из безопасного хранилища (iOS/Android) или SharedPreferences (Web)
    final employeeId = await _secureStorage.get(_keyEmployeeId);
    final establishmentId = await _secureStorage.get(_keyEstablishmentId);

    if (employeeId != null && establishmentId != null) {
      await _restoreSession(employeeId, establishmentId);
      return;
    }

    // 2. Supabase Auth (если когда‑нибудь понадобится)
    if (_supabase.isAuthenticated) {
      await _loadCurrentUserData();
    }
  }

  Future<void> _restoreSession(String employeeId, String establishmentId) async {
    try {
      final employeeDataRaw = await _supabase.client
          .from('employees')
          .select()
          .eq('id', employeeId)
          .eq('is_active', true)
          .limit(1)
          .single();

      final empData = Map<String, dynamic>.from(employeeDataRaw);
      empData['password'] = empData['password_hash'] ?? '';
      _currentEmployee = Employee.fromJson(empData);

      final estData = await _supabase.client
          .from('establishments')
          .select()
          .eq('id', establishmentId)
          .limit(1)
          .single();
      _establishment = Establishment.fromJson(estData);
    } catch (e) {
      print('Ошибка восстановления сессии: $e');
      await _clearStoredSession();
      _currentEmployee = null;
      _establishment = null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.remove(_keyEmployeeId);
    await _secureStorage.remove(_keyEstablishmentId);
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
      ..remove('owner_id');
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

  /// Регистрация сотрудника в компании
  Future<Employee> createEmployeeForCompany({
    required Establishment company,
    required String fullName,
    required String email,
    required String password,
    required String department,
    String? section,
    required List<String> roles,
  }) async {
    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
    final employee = Employee.create(
      fullName: fullName,
      email: email,
      password: passwordHash,
      department: department,
      section: section,
      roles: roles,
      establishmentId: company.id,
    );

    final employeeData = employee.toJson();
    employeeData['password_hash'] = passwordHash;
    employeeData.remove('password');
    employeeData.remove('id');
    employeeData.remove('created_at');
    employeeData.remove('updated_at');

    final response = await _supabase.insertData('employees', employeeData);
    final createdEmployee = Employee.fromJson(response);

    // Обновляем establishment с ownerId, если это владелец
    if (roles.contains('owner')) {
      await _supabase.updateData(
        'establishments',
        {'owner_id': createdEmployee.id},
        'id',
        company.id,
      );
    }

    return createdEmployee;
  }

  /// Поиск сотрудника по email и паролю
  Future<Employee?> findEmployeeByEmailAndPassword({
    required String email,
    required String password,
    required Establishment company,
  }) async {
    try {
      final data = await _supabase.client
          .from('employees')
          .select()
          .eq('email', email)
          .eq('establishment_id', company.id)
          .eq('is_active', true)
          .limit(1)
          .single();

      final employeeData = Map<String, dynamic>.from(data);
      final hash = employeeData['password_hash'] as String?;
      if (hash == null || hash.isEmpty) return null;
      employeeData['password'] = hash;

      final employee = Employee.fromJson(employeeData);
      if (BCrypt.checkpw(password, hash)) return employee;
      // Миграция: раньше пароли хранились в открытом виде
      if (hash == password) {
        try {
          final newHash = BCrypt.hashpw(password, BCrypt.gensalt());
          await _supabase.updateData('employees', {'password_hash': newHash}, 'id', employee.id);
        } catch (_) { /* игнор */ }
        return employee;
      }
      return null;
    } catch (e) {
      print('Ошибка поиска сотрудника: $e');
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
    _currentEmployee = employee;
    _establishment = establishment;

    await _secureStorage.set(_keyEmployeeId, employee.id);
    await _secureStorage.set(_keyEstablishmentId, establishment.id);

    if (rememberCredentials && pin != null && email != null && password != null) {
      await _secureStorage.set(_keyRememberPin, pin);
      await _secureStorage.set(_keyRememberEmail, email);
      await _secureStorage.set(_keyRememberPassword, password);
    } else {
      await _secureStorage.remove(_keyRememberPin);
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
  Future<void> updateEmployee(Employee employee) async {
    try {
      final employeeData = employee.toJson()
        ..remove('password')
        ..remove('password_hash');

      await _supabase.updateData(
        'employees',
        employeeData,
        'id',
        employee.id,
      );

      if (_currentEmployee?.id == employee.id) {
        _currentEmployee = employee;
      }
    } catch (e) {
      print('Ошибка обновления сотрудника: $e');
    }
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
    } catch (e) {
      print('Ошибка обновления заведения: $e');
    }
  }

  /// Загрузка данных текущего пользователя
  Future<void> _loadCurrentUserData() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      // Загружаем сотрудника
      final employeeDataRaw = await _supabase.client
          .from('employees')
          .select()
          .eq('id', userId)
          .limit(1)
          .single();

      // Маппим password_hash обратно в password для модели
      final employeeData = Map<String, dynamic>.from(employeeDataRaw);
      employeeData['password'] = employeeData['password_hash'] ?? '';

      _currentEmployee = Employee.fromJson(employeeData);

      // Загружаем заведение
      if (_currentEmployee != null) {
        final establishmentData = await _supabase.client
            .from('establishments')
            .select()
            .eq('id', _currentEmployee!.establishmentId)
            .limit(1)
            .single();

        _establishment = Establishment.fromJson(establishmentData);
      }
    } catch (e) {
      print('Ошибка загрузки данных пользователя: $e');
    }
  }
}