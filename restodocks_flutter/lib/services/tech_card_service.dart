import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Сервис управления технологическими картами
class TechCardService {
  static final TechCardService _instance = TechCardService._internal();
  factory TechCardService() => _instance;
  TechCardService._internal();

  static const String _techCardsKey = 'tech_cards';

  /// Создание новой технологической карты
  Future<TechCard> createTechCard({
    required String dishName,
    Map<String, String>? dishNameLocalized,
    required String category,
    required String establishmentId,
    required String createdBy,
  }) async {
    final techCard = TechCard.create(
      dishName: dishName,
      dishNameLocalized: dishNameLocalized,
      category: category,
      establishmentId: establishmentId,
      createdBy: createdBy,
    );

    await _saveTechCard(techCard);
    return techCard;
  }

  /// Получение всех ТТК для заведения
  Future<List<TechCard>> getTechCardsForEstablishment(String establishmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final techCardsJson = prefs.getStringList(_techCardsKey) ?? [];
    final techCards = <TechCard>[];

    for (final jsonStr in techCardsJson) {
      try {
        final techCard = TechCard.fromJson(json.decode(jsonStr));
        if (techCard.establishmentId == establishmentId) {
          techCards.add(techCard);
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return techCards;
  }

  /// Поиск ТТК по ID
  Future<TechCard?> getTechCardById(String techCardId) async {
    final prefs = await SharedPreferences.getInstance();
    final techCardsJson = prefs.getStringList(_techCardsKey) ?? [];

    for (final jsonStr in techCardsJson) {
      try {
        final techCard = TechCard.fromJson(json.decode(jsonStr));
        if (techCard.id == techCardId) {
          return techCard;
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return null;
  }

  /// Поиск ТТК по названию блюда
  Future<List<TechCard>> searchTechCards(String query, String establishmentId) async {
    final allTechCards = await getTechCardsForEstablishment(establishmentId);
    final searchLower = query.toLowerCase();

    return allTechCards.where((techCard) {
      return techCard.dishName.toLowerCase().contains(searchLower) ||
             techCard.category.toLowerCase().contains(searchLower) ||
             techCard.ingredients.any((ingredient) =>
               ingredient.productName.toLowerCase().contains(searchLower)
             );
    }).toList();
  }

  /// Сохранение ТТК
  Future<void> saveTechCard(TechCard techCard) async {
    await _saveTechCard(techCard);
  }

  /// Обновление ТТК
  Future<void> updateTechCard(TechCard techCard) async {
    await _saveTechCard(techCard);
  }

  /// Удаление ТТК
  Future<void> deleteTechCard(String techCardId) async {
    final prefs = await SharedPreferences.getInstance();
    final techCardsJson = prefs.getStringList(_techCardsKey) ?? [];

    techCardsJson.removeWhere((jsonStr) {
      try {
        final techCard = TechCard.fromJson(json.decode(jsonStr));
        return techCard.id == techCardId;
      } catch (e) {
        return false;
      }
    });

    await prefs.setStringList(_techCardsKey, techCardsJson);
  }

  /// Добавление ингредиента в ТТК
  Future<TechCard> addIngredientToTechCard({
    required String techCardId,
    required TTIngredient ingredient,
  }) async {
    final techCard = await getTechCardById(techCardId);
    if (techCard == null) {
      throw Exception('ТТК не найдена');
    }

    final updatedTechCard = techCard.addIngredient(ingredient);
    await saveTechCard(updatedTechCard);
    return updatedTechCard;
  }

  /// Обновление ингредиента в ТТК
  Future<TechCard> updateIngredientInTechCard({
    required String techCardId,
    required TTIngredient ingredient,
  }) async {
    final techCard = await getTechCardById(techCardId);
    if (techCard == null) {
      throw Exception('ТТК не найдена');
    }

    final updatedTechCard = techCard.updateIngredient(ingredient);
    await saveTechCard(updatedTechCard);
    return updatedTechCard;
  }

  /// Удаление ингредиента из ТТК
  Future<TechCard> removeIngredientFromTechCard({
    required String techCardId,
    required String ingredientId,
  }) async {
    final techCard = await getTechCardById(techCardId);
    if (techCard == null) {
      throw Exception('ТТК не найдена');
    }

    final updatedTechCard = techCard.removeIngredient(ingredientId);
    await saveTechCard(updatedTechCard);
    return updatedTechCard;
  }

  /// Расчет себестоимости блюда
  double calculateDishCost(TechCard techCard) {
    return techCard.totalCost;
  }

  /// Расчет стоимости порции
  double calculatePortionCost(TechCard techCard) {
    return techCard.costPerPortion;
  }

  /// Расчет КБЖУ на порцию
  NutritionInfo calculatePortionNutrition(TechCard techCard) {
    return NutritionInfo(
      calories: techCard.caloriesPerPortion,
      protein: techCard.proteinPerPortion,
      fat: techCard.fatPerPortion,
      carbs: techCard.carbsPerPortion,
    );
  }

  /// Получение статистики по ингредиентам
  Map<String, dynamic> getIngredientsStatistics(TechCard techCard) {
    final totalIngredients = techCard.ingredients.length;
    final totalGrossWeight = techCard.totalGrossWeight;
    final totalNetWeight = techCard.totalNetWeight;
    final weightLossPercentage = totalGrossWeight > 0
        ? ((totalGrossWeight - totalNetWeight) / totalGrossWeight) * 100
        : 0.0;

    return {
      'totalIngredients': totalIngredients,
      'totalGrossWeight': totalGrossWeight,
      'totalNetWeight': totalNetWeight,
      'weightLossPercentage': weightLossPercentage,
      'yieldPercentage': techCard.yieldPercentage,
    };
  }

  /// Экспорт ТТК в JSON
  String exportTechCardToJson(TechCard techCard) {
    return json.encode(techCard.toJson());
  }

  /// Импорт ТТК из JSON
  Future<TechCard?> importTechCardFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final techCard = TechCard.fromJson(jsonData);
      await saveTechCard(techCard);
      return techCard;
    } catch (e) {
      print('Ошибка импорта ТТК: $e');
      return null;
    }
  }

  /// Получение ТТК, созданных конкретным пользователем
  Future<List<TechCard>> getTechCardsByCreator(String creatorId) async {
    final prefs = await SharedPreferences.getInstance();
    final techCardsJson = prefs.getStringList(_techCardsKey) ?? [];
    final techCards = <TechCard>[];

    for (final jsonStr in techCardsJson) {
      try {
        final techCard = TechCard.fromJson(json.decode(jsonStr));
        if (techCard.createdBy == creatorId) {
          techCards.add(techCard);
        }
      } catch (e) {
        // Игнорируем некорректные данные
      }
    }

    return techCards;
  }

  /// Клонирование ТТК
  Future<TechCard> cloneTechCard(TechCard originalTechCard, String newCreatorId) async {
    final clonedTechCard = TechCard.create(
      dishName: '${originalTechCard.dishName} (копия)',
      dishNameLocalized: originalTechCard.dishNameLocalized,
      category: originalTechCard.category,
      establishmentId: originalTechCard.establishmentId,
      createdBy: newCreatorId,
    );

    // Копируем ингредиенты
    var updatedTechCard = clonedTechCard;
    for (final ingredient in originalTechCard.ingredients) {
      updatedTechCard = updatedTechCard.addIngredient(ingredient);
    }

    await saveTechCard(updatedTechCard);
    return updatedTechCard;
  }

  // Вспомогательные методы

  Future<void> _saveTechCard(TechCard techCard) async {
    final prefs = await SharedPreferences.getInstance();
    final techCardsJson = prefs.getStringList(_techCardsKey) ?? [];

    // Удаляем старую версию
    techCardsJson.removeWhere((jsonStr) {
      try {
        final card = TechCard.fromJson(json.decode(jsonStr));
        return card.id == techCard.id;
      } catch (e) {
        return false;
      }
    });

    // Добавляем новую версию
    techCardsJson.add(json.encode(techCard.toJson()));
    await prefs.setStringList(_techCardsKey, techCardsJson);
  }
}