import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Сервис управления аккаунтами, аутентификацией и данными компании
class AccountManager {
  static final AccountManager _instance = AccountManager._internal();
  factory AccountManager() => _instance;
  AccountManager._internal();

  Establishment? _establishment;
  Employee? _currentEmployee;
  String? _currentEstablishmentId;

  // Геттеры
  Establishment? get establishment => _establishment;
  Employee? get currentEmployee => _currentEmployee;
  String? get currentEstablishmentId => _currentEstablishmentId;

  /// Инициализация сервиса
  Future<void> initialize() async {
    await _loadPersistedData();
  }

  /// Создание нового заведения
  Future<Establishment> createEstablishment({
    required String name,
    String? address,
    String? phone,
    String? email,
  }) async {
    final establishment = Establishment.create(
      name: name,
      ownerId: '', // Будет установлен при регистрации владельца
      address: address,
      phone: phone,
      email: email,
    );

    _establishment = establishment;
    _currentEstablishmentId = establishment.id;

    await _saveEstablishment(establishment);
    await _saveCurrentEstablishmentId(establishment.id);

    return establishment;
  }

  /// Поиск заведения по названию
  Future<Establishment?> findEstablishmentByName(String name) async {
    // В данной реализации используем SharedPreferences
    // В реальном приложении здесь был бы запрос к базе данных
    final prefs = await SharedPreferences.getInstance();
    final establishmentsJson = prefs.getStringList('establishments') ?? [];

    for (final jsonStr in establishmentsJson) {
      try {
        final establishment = Establishment.fromJson(jsonStr as Map<String, dynamic>);
        if (establishment.name.toLowerCase() == name.toLowerCase()) {
          return establishment;
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return null;
  }

  /// Поиск заведения по PIN-коду
  Future<Establishment?> findEstablishmentByPinCode(String pinCode) async {
    final prefs = await SharedPreferences.getInstance();
    final establishmentsJson = prefs.getStringList('establishments') ?? [];

    for (final jsonStr in establishmentsJson) {
      try {
        final establishment = Establishment.fromJson(jsonStr as Map<String, dynamic>);
        if (establishment.verifyPinCode(pinCode)) {
          return establishment;
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return null;
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
    final employee = Employee.create(
      fullName: fullName,
      email: email,
      password: password,
      department: department,
      section: section,
      roles: roles,
      establishmentId: company.id,
    );

    // Обновляем establishment с ownerId, если это владелец
    if (roles.contains('owner')) {
      final updatedEstablishment = company.copyWith(ownerId: employee.id);
      _establishment = updatedEstablishment;
      await _saveEstablishment(updatedEstablishment);
    }

    await _saveEmployee(employee);
    return employee;
  }

  /// Поиск сотрудника по email и паролю
  Future<Employee?> findEmployeeByEmailAndPassword({
    required String email,
    required String password,
    required Establishment company,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final employeesJson = prefs.getStringList('employees') ?? [];

    for (final jsonStr in employeesJson) {
      try {
        final employee = Employee.fromJson(jsonStr as Map<String, dynamic>);
        if (employee.email == email &&
            employee.password == password &&
            employee.establishmentId == company.id &&
            employee.isActive) {
          return employee;
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return null;
  }

  /// Поиск сотрудника по персональному PIN
  Future<Employee?> findEmployeeByPersonalPin(String pin, Establishment company) async {
    final prefs = await SharedPreferences.getInstance();
    final employeesJson = prefs.getStringList('employees') ?? [];

    for (final jsonStr in employeesJson) {
      try {
        final employee = Employee.fromJson(jsonStr as Map<String, dynamic>);
        if (employee.personalPin == pin &&
            employee.establishmentId == company.id &&
            employee.isActive) {
          return employee;
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return null;
  }

  /// Вход в систему
  Future<void> login(Employee employee, Establishment establishment) async {
    _currentEmployee = employee;
    _establishment = establishment;
    _currentEstablishmentId = establishment.id;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('current_employee_id', employee.id);
    await prefs.setString('current_establishment_id', establishment.id);
  }

  /// Выход из системы
  Future<void> logout() async {
    _currentEmployee = null;
    _establishment = null;
    _currentEstablishmentId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('current_employee_id');
    await prefs.remove('current_establishment_id');
  }

  /// Проверка, авторизован ли пользователь
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') ?? false;
  }

  /// Получить всех сотрудников компании
  Future<List<Employee>> getEmployeesForEstablishment(String establishmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final employeesJson = prefs.getStringList('employees') ?? [];
    final employees = <Employee>[];

    for (final jsonStr in employeesJson) {
      try {
        final employee = Employee.fromJson(jsonStr as Map<String, dynamic>);
        if (employee.establishmentId == establishmentId) {
          employees.add(employee);
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return employees;
  }

  /// Обновить данные сотрудника
  Future<void> updateEmployee(Employee employee) async {
    await _saveEmployee(employee);

    // Обновляем текущего сотрудника, если это он
    if (_currentEmployee?.id == employee.id) {
      _currentEmployee = employee;
    }
  }

  /// Обновить данные заведения
  Future<void> updateEstablishment(Establishment establishment) async {
    _establishment = establishment;
    await _saveEstablishment(establishment);
  }

  // Вспомогательные методы для сохранения данных

  Future<void> _saveEstablishment(Establishment establishment) async {
    final prefs = await SharedPreferences.getInstance();
    final establishmentsJson = prefs.getStringList('establishments') ?? [];

    // Удаляем старую версию
    establishmentsJson.removeWhere((jsonStr) {
      try {
        final est = Establishment.fromJson(jsonStr as Map<String, dynamic>);
        return est.id == establishment.id;
      } catch (e) {
        return false;
      }
    });

    // Добавляем новую версию
    establishmentsJson.add(establishment.toJson().toString());
    await prefs.setStringList('establishments', establishmentsJson);
  }

  Future<void> _saveEmployee(Employee employee) async {
    final prefs = await SharedPreferences.getInstance();
    final employeesJson = prefs.getStringList('employees') ?? [];

    // Удаляем старую версию
    employeesJson.removeWhere((jsonStr) {
      try {
        final emp = Employee.fromJson(jsonStr as Map<String, dynamic>);
        return emp.id == employee.id;
      } catch (e) {
        return false;
      }
    });

    // Добавляем новую версию
    employeesJson.add(employee.toJson().toString());
    await prefs.setStringList('employees', employeesJson);
  }

  Future<void> _saveCurrentEstablishmentId(String establishmentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_establishment_id', establishmentId);
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();

    // Загружаем ID текущего заведения
    _currentEstablishmentId = prefs.getString('current_establishment_id');

    // Загружаем текущее заведение
    if (_currentEstablishmentId != null) {
      final establishmentsJson = prefs.getStringList('establishments') ?? [];
      for (final jsonStr in establishmentsJson) {
        try {
          final establishment = Establishment.fromJson(jsonStr as Map<String, dynamic>);
          if (establishment.id == _currentEstablishmentId) {
            _establishment = establishment;
            break;
          }
        } catch (e) {
          // Игнорируем некорректные данные
        }
      }
    }

    // Загружаем текущего сотрудника
    final currentEmployeeId = prefs.getString('current_employee_id');
    if (currentEmployeeId != null) {
      final employeesJson = prefs.getStringList('employees') ?? [];
      for (final jsonStr in employeesJson) {
        try {
          final employee = Employee.fromJson(jsonStr as Map<String, dynamic>);
          if (employee.id == currentEmployeeId) {
            _currentEmployee = employee;
            break;
          }
        } catch (e) {
          // Игнорируем некорректные данные
        }
      }
    }
  }
}