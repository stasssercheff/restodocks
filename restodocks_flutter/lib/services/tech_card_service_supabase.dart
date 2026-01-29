import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'supabase_service.dart';

/// Сервис управления технологическими картами с использованием Supabase
class TechCardServiceSupabase {
  static final TechCardServiceSupabase _instance = TechCardServiceSupabase._internal();
  factory TechCardServiceSupabase() => _instance;
  TechCardServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

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

    final techCardData = Map<String, dynamic>.from(techCard.toJson())
      ..remove('id');
    final response = await _supabase.insertData('tech_cards', techCardData);
    final createdTechCard = TechCard.fromJson(response);

    for (final ingredient in techCard.ingredients) {
      final ingredientData = Map<String, dynamic>.from(ingredient.toJson());
      ingredientData.remove('id');
      ingredientData['tech_card_id'] = createdTechCard.id;
      await _supabase.insertData('tt_ingredients', ingredientData);
    }

    return createdTechCard;
  }

  /// Получение всех ТТК для заведения
  Future<List<TechCard>> getTechCardsForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('tech_cards')
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false);

      final techCards = <TechCard>[];

      for (final techCardJson in data) {
        final techCard = TechCard.fromJson(techCardJson);

        // Загружаем ингредиенты для этой ТТК
        final ingredientsData = await _supabase.client
            .from('tt_ingredients')
            .select()
            .eq('tech_card_id', techCard.id);

        final ingredients = (ingredientsData as List)
            .map((json) => TTIngredient.fromJson(json))
            .toList();

        techCards.add(techCard.copyWith(ingredients: ingredients));
      }

      return techCards;
    } catch (e) {
      print('Ошибка получения ТТК: $e');
      return [];
    }
  }

  /// Поиск ТТК по ID
  Future<TechCard?> getTechCardById(String techCardId) async {
    try {
      final techCardData = await _supabase.client
          .from('tech_cards')
          .select()
          .eq('id', techCardId)
          .limit(1)
          .single();

      final techCard = TechCard.fromJson(techCardData);

      // Загружаем ингредиенты
      final ingredientsData = await _supabase.client
          .from('tt_ingredients')
          .select()
          .eq('tech_card_id', techCardId);

      final ingredients = (ingredientsData as List)
          .map((json) => TTIngredient.fromJson(json))
          .toList();

      return techCard.copyWith(ingredients: ingredients);
    } catch (e) {
      print('Ошибка получения ТТК: $e');
      return null;
    }
  }

  /// Поиск ТТК по названию блюда
  Future<List<TechCard>> searchTechCards(String query, String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('tech_cards')
          .select()
          .eq('establishment_id', establishmentId)
          .or('dish_name.ilike.%$query%,category.ilike.%$query%')
          .order('dish_name');

      final techCards = <TechCard>[];

      for (final techCardJson in data) {
        final techCard = TechCard.fromJson(techCardJson);

        // Загружаем ингредиенты
        final ingredientsData = await _supabase.client
            .from('tt_ingredients')
            .select()
            .eq('tech_card_id', techCard.id);

        final ingredients = (ingredientsData as List)
            .map((json) => TTIngredient.fromJson(json))
            .toList();

        techCards.add(techCard.copyWith(ingredients: ingredients));
      }

      return techCards;
    } catch (e) {
      print('Ошибка поиска ТТК: $e');
      return [];
    }
  }

  /// Сохранение ТТК
  Future<void> saveTechCard(TechCard techCard) async {
    try {
      // Обновляем ТТК
      await _supabase.updateData(
        'tech_cards',
        techCard.toJson(),
        'id',
        techCard.id,
      );

      // Удаляем старые ингредиенты
      await _supabase.client
          .from('tt_ingredients')
          .delete()
          .eq('tech_card_id', techCard.id);

      for (final ingredient in techCard.ingredients) {
        final ingredientData = Map<String, dynamic>.from(ingredient.toJson());
        ingredientData.remove('id');
        ingredientData['tech_card_id'] = techCard.id;
        await _supabase.insertData('tt_ingredients', ingredientData);
      }
    } catch (e) {
      print('Ошибка сохранения ТТК: $e');
      rethrow;
    }
  }

  /// Обновление ТТК
  Future<void> updateTechCard(TechCard techCard) async {
    await saveTechCard(techCard);
  }

  /// Удаление ТТК
  Future<void> deleteTechCard(String techCardId) async {
    try {
      // Удаление ингредиентов произойдет автоматически из-за CASCADE
      await _supabase.deleteData('tech_cards', 'id', techCardId);
    } catch (e) {
      print('Ошибка удаления ТТК: $e');
      rethrow;
    }
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

  /// Получение ТТК, созданных конкретным пользователем
  Future<List<TechCard>> getTechCardsByCreator(String creatorId) async {
    try {
      final data = await _supabase.client
          .from('tech_cards')
          .select()
          .eq('created_by', creatorId)
          .order('created_at', ascending: false);

      final techCards = <TechCard>[];

      for (final techCardJson in data) {
        final techCard = TechCard.fromJson(techCardJson);

        // Загружаем ингредиенты
        final ingredientsData = await _supabase.client
            .from('tt_ingredients')
            .select()
            .eq('tech_card_id', techCard.id);

        final ingredients = (ingredientsData as List)
            .map((json) => TTIngredient.fromJson(json))
            .toList();

        techCards.add(techCard.copyWith(ingredients: ingredients));
      }

      return techCards;
    } catch (e) {
      print('Ошибка получения ТТК по создателю: $e');
      return [];
    }
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
}