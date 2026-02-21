import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'ai_service.dart';
import 'supabase_service.dart';

/// Сервис управления технологическими картами с использованием Supabase
class TechCardServiceSupabase {
  static final TechCardServiceSupabase _instance = TechCardServiceSupabase._internal();
  factory TechCardServiceSupabase() => _instance;
  TechCardServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  /// Payload для вставки в tt_ingredients. Только колонки из схемы БД.
  /// Убираем: id, price_per_kg, cost_currency, gramsPerPiece — их нет в tt_ingredients.
  static Map<String, dynamic> _ingredientPayloadForDb(TTIngredient ingredient) {
    final data = Map<String, dynamic>.from(ingredient.toJson());
    data.remove('id');
    data.remove('price_per_kg');
    data.remove('cost_currency');
    data.remove('gramsPerPiece'); // camelCase в toJson, колонка может отсутствовать
    data.remove('grams_per_piece');
    data.removeWhere((key, value) => value == null);
    return data;
  }

  /// Создание новой технологической карты
  Future<TechCard> createTechCard({
    required String dishName,
    Map<String, String>? dishNameLocalized,
    required String category,
    String? section,
    bool isSemiFinished = true,
    required String establishmentId,
    required String createdBy,
  }) async {
    final techCard = TechCard.create(
      dishName: dishName,
      dishNameLocalized: dishNameLocalized,
      category: category,
      section: section,
      isSemiFinished: isSemiFinished,
      establishmentId: establishmentId,
      createdBy: createdBy,
    );

    final techCardData = Map<String, dynamic>.from(techCard.toJson())
      ..remove('id')
      ..remove('section'); // колонка section может отсутствовать в схеме БД
    final response = await _supabase.insertData('tech_cards', techCardData);
    final createdTechCard = TechCard.fromJson(response);

    for (final ingredient in techCard.ingredients) {
      final ingredientData = _ingredientPayloadForDb(ingredient);
      ingredientData['tech_card_id'] = createdTechCard.id;
      await _supabase.insertData('tt_ingredients', ingredientData);
    }

    return createdTechCard;
  }

  /// Получение всех ТТК для заведения
  Future<List<TechCard>> getTechCardsForEstablishment(String establishmentId) async {
    try {
      print('🍽️ TechCardService: Loading tech cards for establishment: $establishmentId');
      print('👤 TechCardService: Current user: ${Supabase.instance.client.auth.currentUser?.email}');

      final data = await _supabase.client
          .from('tech_cards')
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false);

      print('🍽️ TechCardService: Query returned ${data?.length ?? 0} tech cards');
      print('🍽️ TechCardService: Raw data sample: ${data?.take(1) ?? 'null'}');

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
      final payload = Map<String, dynamic>.from(techCard.toJson());
      payload.remove('section'); // колонка section может отсутствовать в схеме БД
      await _supabase.updateData(
        'tech_cards',
        payload,
        'id',
        techCard.id,
      );

      // Удаляем старые ингредиенты
      await _supabase.client
          .from('tt_ingredients')
          .delete()
          .eq('tech_card_id', techCard.id);

      for (final ingredient in techCard.ingredients) {
        final ingredientData = _ingredientPayloadForDb(ingredient);
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

  /// Создание ТТК из результата распознавания ИИ (пакетный импорт).
  Future<TechCard> createTechCardFromRecognitionResult({
    required String establishmentId,
    required String createdBy,
    required TechCardRecognitionResult result,
    required String category,
    String languageCode = 'ru',
  }) async {
    final name = result.dishName?.trim().isNotEmpty == true ? result.dishName!.trim() : 'Без названия';
    final created = await createTechCard(
      dishName: name,
      category: category,
      isSemiFinished: result.isSemiFinished ?? true,
      establishmentId: establishmentId,
      createdBy: createdBy,
    );
    final ingredients = <TTIngredient>[];
    for (final line in result.ingredients) {
      if (line.productName.trim().isEmpty) continue;
      final gross = line.grossGrams ?? 0.0;
      final net = line.netGrams ?? line.grossGrams ?? gross;
      final unit = line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
      final wastePct = (line.primaryWastePct ?? 0).clamp(0.0, 99.9);
      ingredients.add(TTIngredient(
        id: '${DateTime.now().millisecondsSinceEpoch}_${ingredients.length}',
        productId: null,
        productName: line.productName.trim(),
        grossWeight: gross > 0 ? gross : 100,
        netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
        unit: unit,
        primaryWastePct: wastePct,
        cookingLossPctOverride: line.cookingLossPct != null ? line.cookingLossPct!.clamp(0.0, 99.9) : null,
        isNetWeightManual: line.netGrams != null,
        finalCalories: 0,
        finalProtein: 0,
        finalFat: 0,
        finalCarbs: 0,
        cost: 0,
      ));
    }
    final yieldVal = ingredients.fold<double>(0.0, (s, i) => s + i.netWeight);
    final techMap = <String, String>{languageCode: result.technologyText?.trim() ?? ''};
    final withIngredients = created.copyWith(
      ingredients: ingredients,
      technologyLocalized: techMap,
    );
    final updated = TechCard.withYieldValue(withIngredients, yieldVal > 0 ? yieldVal : 100);
    await saveTechCard(updated);
    return updated;
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

  /// Получить все технологические карты
  Future<List<TechCard>> getAllTechCards() async {
    final response = await _supabase.client
        .from('tech_cards')
        .select('''
          *,
          tt_ingredients (
            *
          )
        ''');

    final techCards = <TechCard>[];
    for (final row in response) {
      try {
        techCards.add(TechCard.fromJson(row));
      } catch (e) {
        // Игнорируем проблемные записи
        continue;
      }
    }

    return techCards;
  }
}