
/// Пункт меню ресторана
class MenuItem {
  final String id;
  final String name;
  final String category;
  final double price;
  final String currency;
  final String establishmentId;

  // Данные из ТТК
  final String? techCardId;
  final double? calories; // ккал на 100г
  final double? protein; // г на 100г
  final double? fat; // г на 100г
  final double? carbs; // г на 100г
  final double portionWeight; // вес порции в граммах

  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.currency,
    required this.establishmentId,
    this.techCardId,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.portionWeight = 100,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'price': price,
    'currency': currency,
    'establishmentId': establishmentId,
    'techCardId': techCardId,
    'calories': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    'portionWeight': portionWeight,
  };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    price: (json['price'] as num).toDouble(),
    currency: json['currency'] as String,
    establishmentId: json['establishmentId'] as String,
    techCardId: json['techCardId'] as String?,
    calories: json['calories'] != null ? (json['calories'] as num).toDouble() : null,
    protein: json['protein'] != null ? (json['protein'] as num).toDouble() : null,
    fat: json['fat'] != null ? (json['fat'] as num).toDouble() : null,
    carbs: json['carbs'] != null ? (json['carbs'] as num).toDouble() : null,
    portionWeight: json['portionWeight'] != null ? (json['portionWeight'] as num).toDouble() : 100,
  );

  /// Создание пункта меню из ТТК
  factory MenuItem.fromTechCard({
    required String techCardId,
    required String dishName,
    required String category,
    required double price,
    required String currency,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required double portionWeight,
    required String establishmentId,
  }) {
    return MenuItem(
      id: 'menu_${techCardId}_${DateTime.now().millisecondsSinceEpoch}',
      name: dishName,
      category: category,
      price: price,
      currency: currency,
      establishmentId: establishmentId,
      techCardId: techCardId,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      portionWeight: portionWeight,
    );
  }

  /// Получение локализованного имени
  String getLocalizedName(String lang) => name;

  /// Калории на порцию
  double get caloriesPerPortion => calories != null ? (calories! * portionWeight / 100) : 0;

  /// Белки на порцию
  double get proteinPerPortion => protein != null ? (protein! * portionWeight / 100) : 0;

  /// Жиры на порцию
  double get fatPerPortion => fat != null ? (fat! * portionWeight / 100) : 0;

  /// Углеводы на порцию
  double get carbsPerPortion => carbs != null ? (carbs! * portionWeight / 100) : 0;
}