import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'establishment.dart';

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
  cleaning('cleaning', 'Уборка'),
  banquetCatering('banquet_catering', 'Банкет / Кейтринг');

  const KitchenSection(this.code, this.displayName);
  final String code;
  final String displayName;

  static const _translations = <String, Map<String, String>>{
    'hot_kitchen':  {'ru': 'Горячий цех',    'en': 'Hot Kitchen',   'es': 'Cocina caliente', 'de': 'Warme Küche',    'fr': 'Cuisine chaude', 'tr': 'Sıcak mutfak'},
    'cold_kitchen': {'ru': 'Холодный цех',   'en': 'Cold Kitchen',  'es': 'Cocina fría',     'de': 'Kalte Küche',    'fr': 'Cuisine froide', 'tr': 'Soğuk mutfak'},
    'grill':        {'ru': 'Гриль',          'en': 'Grill',         'es': 'Parrilla',        'de': 'Grill',          'fr': 'Grill',         'tr': 'Izgara'},
    'pizza':        {'ru': 'Пицца',          'en': 'Pizza',         'es': 'Pizza',           'de': 'Pizza',          'fr': 'Pizza',         'tr': 'Pizza'},
    'sushi':        {'ru': 'Суши',           'en': 'Sushi',         'es': 'Sushi',           'de': 'Sushi',          'fr': 'Sushi',         'tr': 'Suşi'},
    'prep':         {'ru': 'Заготовки',      'en': 'Prep',          'es': 'Preparación',     'de': 'Vorbereitung',   'fr': 'Préparation',   'tr': 'Hazırlık'},
    'pastry':       {'ru': 'Кондитерский',   'en': 'Pastry',        'es': 'Pastelería',      'de': 'Konditorei',     'fr': 'Pâtisserie',    'tr': 'Tatlıcı'},
    'bakery':       {'ru': 'Пекарня',        'en': 'Bakery',        'es': 'Panadería',       'de': 'Bäckerei',       'fr': 'Boulangerie',   'tr': 'Fırın'},
    'cleaning':     {'ru': 'Уборка',         'en': 'Cleaning',      'es': 'Limpieza',        'de': 'Reinigung',      'fr': 'Nettoyage',     'tr': 'Temizlik'},
    'banquet_catering': {'ru': 'Банкет / Кейтринг', 'en': 'Banquet / Catering', 'es': 'Banquete / Catering', 'de': 'Bankett / Catering', 'fr': 'Banquet / Traiteur', 'tr': 'Banket / Catering'},
  };

  String getLocalizedName(String lang) =>
      _translations[code]?[lang] ?? _translations[code]?['en'] ?? displayName;

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

  @JsonKey(name: 'surname')
  final String? surname;

  @JsonKey(name: 'email')
  final String email;

  @JsonKey(name: 'password_hash', defaultValue: '')
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

  @JsonKey(name: 'preferred_currency')
  final String? preferredCurrency; // 'RUB', 'USD', 'VND', 'EUR', etc.

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

  /// Доступ к данным (кроме графика). При регистрации false; включает руководитель.
  @JsonKey(name: 'data_access_enabled')
  final bool dataAccessEnabled;

  /// Может ли сотрудник редактировать свой личный график (как шеф).
  @JsonKey(name: 'can_edit_own_schedule')
  final bool canEditOwnSchedule;

  /// Уровень доступа владельца: 'full' или 'view_only' (co-owner при >1 заведении)
  @JsonKey(name: 'owner_access_level')
  final String? ownerAccessLevel;

  /// Статус: permanent — постоянный, temporary — временный (цех кухни, бара, зала)
  @JsonKey(name: 'employment_status')
  final String? employmentStatus;

  /// Дата начала периода (для временных). Задаёт шеф/барменеджер/менеджер зала.
  @JsonKey(name: 'employment_start_date')
  final DateTime? employmentStartDate;

  /// Дата конца периода (для временных). После неё — только личный график.
  @JsonKey(name: 'employment_end_date')
  final DateTime? employmentEndDate;

  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const Employee({
    required this.id,
    required this.fullName,
    this.surname,
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
    this.preferredCurrency,
    this.paymentType,
    this.ratePerShift,
    this.hourlyRate,
    this.isActive = true,
    this.dataAccessEnabled = false,
    this.canEditOwnSchedule = false,
    this.ownerAccessLevel = 'full',
    this.employmentStatus = 'permanent',
    this.employmentStartDate,
    this.employmentEndDate,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Создание копии с изменениями
  Employee copyWith({
    String? id,
    String? fullName,
    String? surname,
    String? email,
    String? password,
    String? department,
    String? section,
    List<String>? roles,
    String? establishmentId,
    String? personalPin,
    String? avatarUrl,
    String? preferredLanguage,
    String? preferredCurrency,
    String? paymentType,
    double? ratePerShift,
    double? hourlyRate,
    bool? isActive,
    bool? dataAccessEnabled,
    bool? canEditOwnSchedule,
    String? ownerAccessLevel,
    String? employmentStatus,
    DateTime? employmentStartDate,
    DateTime? employmentEndDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      surname: surname ?? this.surname,
      email: email ?? this.email,
      password: password ?? this.password,
      department: department ?? this.department,
      section: section ?? this.section,
      roles: roles ?? this.roles,
      establishmentId: establishmentId ?? this.establishmentId,
      personalPin: personalPin ?? this.personalPin,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      paymentType: paymentType ?? this.paymentType,
      ratePerShift: ratePerShift ?? this.ratePerShift,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      isActive: isActive ?? this.isActive,
      dataAccessEnabled: dataAccessEnabled ?? this.dataAccessEnabled,
      canEditOwnSchedule: canEditOwnSchedule ?? this.canEditOwnSchedule,
      ownerAccessLevel: ownerAccessLevel ?? this.ownerAccessLevel,
      employmentStatus: employmentStatus ?? this.employmentStatus,
      employmentStartDate: employmentStartDate ?? this.employmentStartDate,
      employmentEndDate: employmentEndDate ?? this.employmentEndDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Основная роль сотрудника
  EmployeeRole? get primaryRole {
    if (roles.isEmpty) return null;
    return EmployeeRole.fromCode(roles.first);
  }

  /// Должность (первая не-owner роль). Собственник = дополнительная роль, должность выбирается отдельно.
  String? get positionRole {
    for (final code in roles) {
      if (code != 'owner') return code;
    }
    return null;
  }

  /// Отдел сотрудника
  EmployeeDepartment? get employeeDepartment => EmployeeDepartment.fromCode(department);

  /// Секция кухни (если применимо)
  KitchenSection? get kitchenSection => section != null ? KitchenSection.fromCode(section!) : null;

  /// Co-owner с view_only: только просмотр (когда у пригласившего >1 заведения)
  bool get isViewOnlyOwner =>
      hasRole('owner') && (ownerAccessLevel ?? 'full') == 'view_only';

  /// Временный сотрудник, у которого истёк период — доступ только к личному графику
  bool get isTemporaryAccessExpired {
    if ((employmentStatus ?? 'permanent') != 'temporary') return false;
    final end = employmentEndDate;
    if (end == null) return false;
    final now = DateTime.now().toUtc();
    return now.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59, 999));
  }

  /// Эффективный доступ к данным: false если временный и период истёк
  bool get effectiveDataAccess =>
      dataAccessEnabled && !isTemporaryAccessExpired;

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

  /// Редактирование графика: только шеф-повар и су-шеф (всех). Остальные — только свой при canEditOwnSchedule (проверяется в schedule_screen).
  bool get canEditSchedule {
    return hasRole('executive_chef') || hasRole('sous_chef');
  }

  /// Создание и редактирование чеклистов, ТТК, карточек блюд: только шеф-повар и су-шеф
  bool get canEditChecklistsAndTechCards {
    return hasRole('executive_chef') || hasRole('sous_chef');
  }

  /// Создание и редактирование документации: владелец и менеджмент (шеф, су-шеф, барменеджер, менеджер зала, управляющий)
  bool get canEditDocumentation =>
      hasRole('owner') ||
      hasRole('executive_chef') ||
      hasRole('sous_chef') ||
      hasRole('bar_manager') ||
      hasRole('floor_manager') ||
      hasRole('general_manager') ||
      department == 'management';

  /// Видит ли сотрудник конкретную ТТК кухни по цехам.
  /// sections == [] → скрыто, видят только шеф/су-шеф/владелец.
  /// sections == ['all'] → видят все (кухни и управление).
  /// sections == [...] → только сотрудники чей section входит в список.
  bool canSeeTechCard(List<String> sections) {
    // Владелец, шеф-повар, су-шеф — видят всё
    if (hasRole('owner') || hasRole('executive_chef') || hasRole('sous_chef')) return true;
    if (sections.isEmpty) return false;          // скрыто
    if (sections.contains('all')) return true;   // все цеха
    final mySection = section;                   // KitchenSection.code или null
    if (mySection == null) return false;
    return sections.contains(mySection);
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

  /// Руководство получает документы во входящих (чеклисты, заказы, инвентаризации). Линейные — только сообщения.
  bool get hasInboxDocuments =>
      hasRole('owner') ||
      hasRole('executive_chef') ||
      hasRole('sous_chef') ||
      canViewDepartment('management');

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

  /// Предпочитаемая валюта сотрудника (с fallback на RUB)
  String get currency => preferredCurrency ?? 'RUB';

  /// Символ валюты для отображения
  String get currencySymbol => Establishment.currencySymbolFor(currency);

  /// Отображаемое имя отдела

  /// Отображаемое имя секции (если есть)
  String? get sectionDisplayName {
    final sect = kitchenSection;
    return sect?.displayName;
  }

  /// Полное отображаемое имя с должностью
  String get displayNameWithRole {
    return '$fullName (${roleDisplayName})';
  }

  /// JSON сериализация (защита от null из БД/API на Web)
  factory Employee.fromJson(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json);
    final ph = m['password_hash'];
    m['password_hash'] = (ph == null || ph is! String) ? '' : ph;
    m['id'] = _str(m['id'], '');
    m['email'] = _str(m['email'], '');
    m['establishment_id'] = _str(m['establishment_id'], '');
    m['department'] = _str(m['department'], 'management');
    m['full_name'] = _str(m['full_name'], '');
    if (!m.containsKey('data_access_enabled')) m['data_access_enabled'] = false;
    if (!m.containsKey('can_edit_own_schedule')) m['can_edit_own_schedule'] = false;
    return _$EmployeeFromJson(m);
  }
  static String _str(dynamic v, String fallback) {
    if (v == null) return fallback;
    try {
      final s = v.toString();
      return s.isNotEmpty ? s : fallback;
    } catch (_) {
      return fallback;
    }
  }
  Map<String, dynamic> toJson() => _$EmployeeToJson(this);

  @override
  List<Object?> get props => [
    id,
    fullName,
    surname,
    email,
    password,
    department,
    section,
    roles,
    establishmentId,
    personalPin,
    avatarUrl,
    subscriptionPlan,
    preferredLanguage,
    preferredCurrency,
    paymentType,
    ratePerShift,
    hourlyRate,
    isActive,
    dataAccessEnabled,
    canEditOwnSchedule,
    employmentStatus,
    employmentStartDate,
    employmentEndDate,
    createdAt,
    updatedAt,
  ];

  /// Создание нового сотрудника
  factory Employee.create({
    required String fullName,
    String? surname,
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
      surname: surname,
      email: email,
      password: password,
      department: department,
      section: section,
      roles: roles,
      establishmentId: establishmentId,
      preferredLanguage: preferredLanguage,
      personalPin: _generatePersonalPin(),
      isActive: true,
      dataAccessEnabled: false,
      canEditOwnSchedule: false,
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