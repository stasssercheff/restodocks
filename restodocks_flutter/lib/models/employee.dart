import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'employee.g.dart';

/// Роли сотрудников
enum EmployeeRole {
  owner('owner', 'Владелец'),
  executiveChef('executive_chef', 'Шеф-повар'),
  sousChef('sous_chef', 'Су-шеф'),
  cook('cook', 'Повар'),
  brigadier('brigadier', 'Бригадир'),
  bartender('bartender', 'Бармен'),
  waiter('waiter', 'Официант');

  const EmployeeRole(this.code, this.displayName);
  final String code;
  final String displayName;

  static EmployeeRole? fromCode(String code) {
    return EmployeeRole.values.where((role) => role.code == code).firstOrNull;
  }
}

/// Отделы сотрудников
enum EmployeeDepartment {
  kitchen('kitchen', 'Кухня'),
  bar('bar', 'Бар'),
  diningRoom('dining_room', 'Зал'),
  management('management', 'Управление');

  const EmployeeDepartment(this.code, this.displayName);
  final String code;
  final String displayName;

  static EmployeeDepartment? fromCode(String code) {
    return EmployeeDepartment.values.where((dept) => dept.code == code).firstOrNull;
  }
}

/// Секции кухни
enum KitchenSection {
  hotKitchen('hot_kitchen', 'Горячий цех'),
  coldKitchen('cold_kitchen', 'Холодный цех'),
  grill('grill', 'Гриль'),
  pizza('pizza', 'Пицца'),
  sushi('sushi', 'Суши'),
  prep('prep', 'Заготовки'),
  pastry('pastry', 'Кондитерский'),
  bakery('bakery', 'Пекарня'),
  cleaning('cleaning', 'Уборка');

  const KitchenSection(this.code, this.displayName);
  final String code;
  final String displayName;

  static KitchenSection? fromCode(String code) {
    return KitchenSection.values.where((section) => section.code == code).firstOrNull;
  }
}

/// Модель сотрудника
@JsonSerializable()
class Employee extends Equatable {
  @JsonKey(name: 'id')
  final String id;

  @JsonKey(name: 'full_name')
  final String fullName;

  @JsonKey(name: 'email')
  final String email;

  @JsonKey(name: 'password_hash')
  final String password;

  @JsonKey(name: 'department')
  final String department; // EmployeeDepartment.code

  @JsonKey(name: 'section')
  final String? section; // KitchenSection.code (только для кухни)

  @JsonKey(name: 'roles')
  final List<String> roles; // EmployeeRole.code

  @JsonKey(name: 'establishment_id')
  final String establishmentId;

  @JsonKey(name: 'personal_pin')
  final String? personalPin;

  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;

  @JsonKey(name: 'subscription_plan')
  final String? subscriptionPlan; // 'free', 'pro', etc.

  @JsonKey(name: 'preferred_language')
  final String preferredLanguage; // 'ru', 'en', 'de', 'fr', 'es'

  /// Тип оплаты: 'per_shift' — за смену, 'hourly' — почасовая.
  @JsonKey(name: 'payment_type')
  final String? paymentType;

  /// Стоимость ставки (за смену), если payment_type == 'per_shift'.
  @JsonKey(name: 'rate_per_shift')
  final double? ratePerShift;

  /// Стоимость часа, если payment_type == 'hourly'.
  @JsonKey(name: 'hourly_rate')
  final double? hourlyRate;

  @JsonKey(name: 'is_active')
  final bool isActive;

  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const Employee({
    required this.id,
    required this.fullName,
    required this.email,
    required this.password,
    required this.department,
    this.section,
    required this.roles,
    required this.establishmentId,
    this.personalPin,
    this.avatarUrl,
    this.subscriptionPlan,
    this.preferredLanguage = 'ru',
    this.paymentType,
    this.ratePerShift,
    this.hourlyRate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Создание копии с изменениями
  Employee copyWith({
    String? id,
    String? fullName,
    String? email,
    String? password,
    String? department,
    String? section,
    List<String>? roles,
    String? establishmentId,
    String? personalPin,
    String? avatarUrl,
    String? preferredLanguage,
    String? paymentType,
    double? ratePerShift,
    double? hourlyRate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      password: password ?? this.password,
      department: department ?? this.department,
      section: section ?? this.section,
      roles: roles ?? this.roles,
      establishmentId: establishmentId ?? this.establishmentId,
      personalPin: personalPin ?? this.personalPin,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      paymentType: paymentType ?? this.paymentType,
      ratePerShift: ratePerShift ?? this.ratePerShift,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Основная роль сотрудника
  EmployeeRole? get primaryRole {
    if (roles.isEmpty) return null;
    return EmployeeRole.fromCode(roles.first);
  }

  /// Отдел сотрудника
  EmployeeDepartment? get employeeDepartment => EmployeeDepartment.fromCode(department);

  /// Секция кухни (если применимо)
  KitchenSection? get kitchenSection => section != null ? KitchenSection.fromCode(section!) : null;

  /// Проверка, имеет ли сотрудник определенную роль
  bool hasRole(String roleCode) {
    return roles.contains(roleCode);
  }

  /// Проверка, имеет ли сотрудник определенную роль из enum
  bool hasRoleType(EmployeeRole role) {
    return hasRole(role.code);
  }

  /// Может ли управлять графиком (владелец, шеф-повар, су-шеф, менеджеры)
  bool get canManageSchedule {
    return hasRole('owner') ||
           hasRole('executive_chef') ||
           hasRole('sous_chef') ||
           hasRole('manager');
  }

  /// Редактирование графика: только шеф-повар и су-шеф
  bool get canEditSchedule {
    return hasRole('executive_chef') || hasRole('sous_chef');
  }

  /// Создание и редактирование чеклистов, ТТК, карточек блюд: только шеф-повар и су-шеф
  bool get canEditChecklistsAndTechCards {
    return hasRole('executive_chef') || hasRole('sous_chef');
  }

  /// Может ли просматривать отдел (в зависимости от роли и отдела)
  bool canViewDepartment(String departmentCode) {
    // Владелец может видеть все
    if (hasRole('owner')) return true;

    // Руководители отделов могут видеть свой отдел
    if (department == departmentCode) return true;

    // Специальные разрешения
    switch (departmentCode) {
      case 'kitchen':
        return hasRole('executive_chef') || hasRole('sous_chef');
      case 'bar':
        return hasRole('bar_manager');
      case 'dining_room':
        return hasRole('floor_manager');
      case 'management':
        return hasRole('owner') ||
               hasRole('manager') ||
               hasRole('general_manager') ||
               hasRole('assistant_manager') ||
               hasRole('executive_chef') ||
               hasRole('bar_manager') ||
               hasRole('floor_manager');
      default:
        return false;
    }
  }

  /// Отображаемое имя роли (первая роль)
  String get roleDisplayName {
    if (roles.isEmpty) return 'Сотрудник';

    final primaryRole = EmployeeRole.fromCode(roles.first);
    if (primaryRole != null) {
      return primaryRole.displayName;
    }

    return roles.first;
  }

  /// Имеет ли сотрудник PRO подписку
  bool get hasProSubscription => subscriptionPlan == 'pro' || subscriptionPlan == 'premium';

  /// Тип подписки (free/pro)
  String get subscriptionType => subscriptionPlan ?? 'free';

  /// Все роли через запятую для отображения в профиле (например: Владелец, Шеф-повар)
  String get rolesDisplayText {
    if (roles.isEmpty) return 'Сотрудник';
    final names = roles
        .map((code) => EmployeeRole.fromCode(code)?.displayName ?? code)
        .toList();
    return names.join(', ');
  }

  /// Отображаемое имя отдела
  String get departmentDisplayName {
    final dept = employeeDepartment;
    if (dept != null) {
      return dept.displayName;
    }
    return department;
  }

  /// Отображаемое имя секции (если есть)
  String? get sectionDisplayName {
    final sect = kitchenSection;
    return sect?.displayName;
  }

  /// Полное отображаемое имя с должностью
  String get displayNameWithRole {
    return '$fullName (${roleDisplayName})';
  }

  /// JSON сериализация
  factory Employee.fromJson(Map<String, dynamic> json) => _$EmployeeFromJson(json);
  Map<String, dynamic> toJson() => _$EmployeeToJson(this);

  @override
  List<Object?> get props => [
    id,
    fullName,
    email,
    password,
    department,
    section,
    roles,
    establishmentId,
    personalPin,
    avatarUrl,
    preferredLanguage,
    paymentType,
    ratePerShift,
    hourlyRate,
    isActive,
    createdAt,
    updatedAt,
  ];

  /// Создание нового сотрудника
  factory Employee.create({
    required String fullName,
    required String email,
    required String password,
    required String department,
    String? section,
    required List<String> roles,
    required String establishmentId,
    String preferredLanguage = 'ru',
  }) {
    final now = DateTime.now();
    return Employee(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: fullName,
      email: email,
      password: password,
      department: department,
      section: section,
      roles: roles,
      establishmentId: establishmentId,
      preferredLanguage: preferredLanguage,
      personalPin: _generatePersonalPin(),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Генерация персонального PIN-кода (6 цифр)
  static String _generatePersonalPin() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return (random % 900000 + 100000).toString();
  }

  /// Проверка пароля
  bool verifyPassword(String inputPassword) {
    return password == inputPassword;
  }

  /// Активация/деактивация сотрудника
  Employee activate() => copyWith(isActive: true);
  Employee deactivate() => copyWith(isActive: false);
}