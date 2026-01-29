import 'package:equatable/equatable.dart';

import 'tt_ingredient.dart';

/// Технологическая карта (ТТК)
class TechCard extends Equatable {
  final String id;
  final String dishName;
  final Map<String, String>? dishNameLocalized;
  final String category;
  final double portionWeight; // вес порции в граммах
  final double yield; // выход готового блюда в граммах
  final List<TTIngredient> ingredients;
  final String establishmentId;
  final String createdBy; // ID сотрудника-создателя
  final DateTime createdAt;
  final DateTime updatedAt;

  const TechCard({
    required this.id,
    required this.dishName,
    this.dishNameLocalized,
    required this.category,
    required this.portionWeight,
    required this.yield,
    required this.ingredients,
    required this.establishmentId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Фабричный конструктор для создания из JSON
  factory TechCard.fromJson(Map<String, dynamic> json) {
    return TechCard(
      id: json['id'] as String,
      dishName: json['dish_name'] as String,
      dishNameLocalized: (json['dish_name_localized'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as String),
      ),
      category: json['category'] as String,
      portionWeight: (json['portion_weight'] as num).toDouble(),
      yield: (json['yield'] as num).toDouble(),
      ingredients: [], // Загружается отдельно через сервис
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Конвертация в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dish_name': dishName,
      'dish_name_localized': dishNameLocalized,
      'category': category,
      'portion_weight': portionWeight,
      'yield': yield,
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Создание копии с изменениями
  TechCard copyWith({
    String? id,
    String? dishName,
    Map<String, String>? dishNameLocalized,
    String? category,
    double? portionWeight,
    double? yield,
    List<TTIngredient>? ingredients,
    String? establishmentId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TechCard(
      id: id ?? this.id,
      dishName: dishName ?? this.dishName,
      dishNameLocalized: dishNameLocalized ?? this.dishNameLocalized,
      category: category ?? this.category,
      portionWeight: portionWeight ?? this.portionWeight,
      yield: yield ?? this.yield,
      ingredients: ingredients ?? this.ingredients,
      establishmentId: establishmentId ?? this.establishmentId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Локализованное название блюда
  String getLocalizedDishName(String languageCode) {
    if (dishNameLocalized != null && dishNameLocalized!.containsKey(languageCode)) {
      return dishNameLocalized![languageCode]!;
    }
    return dishName;
  }

  /// Общий вес брутто всех ингредиентов
  double get totalGrossWeight {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.grossWeight);
  }

  /// Общий вес нетто всех ингредиентов
  double get totalNetWeight {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.netWeight);
  }

  /// Общие калории
  double get totalCalories {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.finalCalories);
  }

  /// Общий белок
  double get totalProtein {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.finalProtein);
  }

  /// Общие жиры
  double get totalFat {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.finalFat);
  }

  /// Общие углеводы
  double get totalCarbs {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.finalCarbs);
  }

  /// Общая стоимость
  double get totalCost {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.cost);
  }

  /// КБЖУ на порцию
  double get caloriesPerPortion => portionWeight > 0 ? totalCalories / portionWeight * 100 : 0;
  double get proteinPerPortion => portionWeight > 0 ? totalProtein / portionWeight * 100 : 0;
  double get fatPerPortion => portionWeight > 0 ? totalFat / portionWeight * 100 : 0;
  double get carbsPerPortion => portionWeight > 0 ? totalCarbs / portionWeight * 100 : 0;

  /// Стоимость порции
  double get costPerPortion => portionWeight > 0 ? totalCost / portionWeight * 100 : 0;

  /// Процент выхода (отношение выхода к общему весу брутто)
  double get yieldPercentage {
    return totalGrossWeight > 0 ? (yield / totalGrossWeight) * 100 : 0;
  }

  /// Добавить ингредиент
  TechCard addIngredient(TTIngredient ingredient) {
    return copyWith(
      ingredients: [...ingredients, ingredient],
      updatedAt: DateTime.now(),
    );
  }

  /// Удалить ингредиент
  TechCard removeIngredient(String ingredientId) {
    return copyWith(
      ingredients: ingredients.where((ing) => ing.id != ingredientId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// Обновить ингредиент
  TechCard updateIngredient(TTIngredient updatedIngredient) {
    final newIngredients = ingredients.map((ing) {
      return ing.id == updatedIngredient.id ? updatedIngredient : ing;
    }).toList();

    return copyWith(
      ingredients: newIngredients,
      updatedAt: DateTime.now(),
    );
  }

  /// Проверить корректность ТТК
  bool get isValid {
    return dishName.isNotEmpty &&
           ingredients.isNotEmpty &&
           portionWeight > 0 &&
           yield > 0;
  }

  /// Краткая информация о ТТК
  String get summary {
    final ingredientCount = ingredients.length;
    final calories = totalCalories.round();
    final cost = totalCost.toStringAsFixed(2);

    return '$dishName: $ingredientCount ингр., $calories ккал, $cost ₽';
  }


  @override
  List<Object?> get props => [
    id,
    dishName,
    dishNameLocalized,
    category,
    portionWeight,
    yield,
    ingredients,
    establishmentId,
    createdBy,
    createdAt,
    updatedAt,
  ];

  /// Создание новой ТТК
  factory TechCard.create({
    required String dishName,
    Map<String, String>? dishNameLocalized,
    required String category,
    required String establishmentId,
    required String createdBy,
  }) {
    final now = DateTime.now();
    return TechCard(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dishName: dishName,
      dishNameLocalized: dishNameLocalized,
      category: category,
      portionWeight: 100, // вес порции по умолчанию
      yield: 0,
      ingredients: [],
      establishmentId: establishmentId,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }
}