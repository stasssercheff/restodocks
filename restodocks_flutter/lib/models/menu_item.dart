import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'menu_item.g.dart';

/// Пункт меню ресторана
@JsonSerializable()
class MenuItem extends Equatable {
  final String id;
  final String name;
  final Map<String, String>? nameLocalized;
  final String category;
  final String? description;
  final Map<String, String>? descriptionLocalized;
  final double price;
  final String currency;
  final String? imageUrl;
  final bool isAvailable;
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
    this.nameLocalized,
    required this.category,
    this.description,
    this.descriptionLocalized,
    required this.price,
    required this.currency,
    this.imageUrl,
    this.isAvailable = true,
    required this.establishmentId,
    this.techCardId,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.portionWeight = 100,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);

  /// Создание пункта меню из ТТК
  factory MenuItem.fromTechCard({
    required String techCardId,
    required String dishName,
    required Map<String, String>? dishNameLocalized,
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
      nameLocalized: dishNameLocalized,
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
  String getLocalizedName(String lang) {
    return nameLocalized?[lang] ?? name;
  }

  /// Получение локализованного описания
  String? getLocalizedDescription(String lang) {
    return descriptionLocalized?[lang] ?? description;
  }

  /// Калории на порцию
  double get caloriesPerPortion => calories != null ? (calories! * portionWeight / 100) : 0;

  /// Белки на порцию
  double get proteinPerPortion => protein != null ? (protein! * portionWeight / 100) : 0;

  /// Жиры на порцию
  double get fatPerPortion => fat != null ? (fat! * portionWeight / 100) : 0;

  /// Углеводы на порцию
  double get carbsPerPortion => carbs != null ? (carbs! * portionWeight / 100) : 0;

  @override
  List<Object?> get props => [
    id,
    name,
    nameLocalized,
    category,
    description,
    descriptionLocalized,
    price,
    currency,
    imageUrl,
    isAvailable,
    establishmentId,
    techCardId,
    calories,
    protein,
    fat,
    carbs,
    portionWeight,
  ];
}