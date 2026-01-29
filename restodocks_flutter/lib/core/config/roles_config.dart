/// Иерархия подразделений, цехов и должностей по ТЗ.
/// Цех → список должностей. Шеф-повар в менеджменте.

class RolesConfig {
  RolesConfig._();

  /// Кухня: цех (section) → роли. control = цех управление.
  static const Map<String, List<SectionRole>> kitchen = {
    'control': [
      SectionRole('sous_chef', false),
      SectionRole('brigadier', false),
    ],
    'hot_kitchen': [
      SectionRole('senior_cook', false),
      SectionRole('cook', false),
      SectionRole('cook_assistant', false),
    ],
    'cold_kitchen': [
      SectionRole('senior_cook', false),
      SectionRole('cook', false),
      SectionRole('cook_assistant', false),
    ],
    'grill': [
      SectionRole('senior_grill', false),
      SectionRole('grill_cook', false),
      SectionRole('grill_assistant', false),
    ],
    'pizza': [
      SectionRole('senior_pizzaiolo', false),
      SectionRole('pizzaiolo', false),
      SectionRole('pizzaiolo_assistant', false),
    ],
    'sushi': [
      SectionRole('senior_sushi', false),
      SectionRole('sushi_cook', false),
      SectionRole('sushi_assistant', false),
    ],
    'prep': [
      SectionRole('senior_prep', false),
      SectionRole('prep_cook', false),
      SectionRole('prep_assistant', false),
    ],
    'bakery': [
      SectionRole('senior_baker', false),
      SectionRole('baker', false),
      SectionRole('baker_assistant', false),
    ],
    'pastry': [
      SectionRole('pastry_chef', false),
      SectionRole('confectioner', false),
      SectionRole('confectioner_assistant', false),
    ],
    'cleaning': [
      SectionRole('dishwasher', false),
    ],
  };

  /// Бар: только роли.
  static const List<SectionRole> bar = [
    SectionRole('bartender', false),
    SectionRole('bar_back', false),
  ];

  /// Зал: только роли, без цехов.
  static const List<SectionRole> hall = [
    SectionRole('senior_waiter', false),
    SectionRole('waiter', false),
    SectionRole('runner', false),
    SectionRole('host', false),
    SectionRole('hall_cleaner', false),
  ];

  /// Менеджмент. Шеф-повар здесь.
  static const List<SectionRole> management = [
    SectionRole('executive_chef', false),
    SectionRole('bar_manager', false),
    SectionRole('floor_manager', false),
    SectionRole('general_manager', false),
  ];

  static List<String> kitchenSections() => kitchen.keys.toList();
  static List<SectionRole> kitchenRolesForSection(String section) =>
      kitchen[section] ?? [];
  static List<SectionRole> barRoles() => bar;
  static List<SectionRole> hallRoles() => hall;
  static List<SectionRole> managementRoles() => management;
}

class SectionRole {
  const SectionRole(this.roleCode, this.isPro);
  final String roleCode;
  final bool isPro;
}
