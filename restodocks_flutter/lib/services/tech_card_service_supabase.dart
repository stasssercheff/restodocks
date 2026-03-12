import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/dev_log.dart';

import '../models/models.dart';
import 'ai_service.dart';
import 'image_service.dart';
import 'product_store_supabase.dart';
import 'supabase_service.dart';
import 'tech_card_history_service.dart';

/// Bucket для фото ТТК (блюда и ПФ). Создать в Supabase Storage вручную, public.
const String kTechCardPhotosBucket = 'tech_card_photos';

/// Сервис управления технологическими картами с использованием Supabase
class TechCardServiceSupabase {
  static final TechCardServiceSupabase _instance = TechCardServiceSupabase._internal();
  factory TechCardServiceSupabase() => _instance;
  TechCardServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  /// Загрузить фото блюда/ПФ в Storage. Путь: {establishmentId}/{techCardId}/{index}.jpg
  /// Возвращает публичный URL или null при ошибке.
  Future<String?> uploadTechCardPhoto({
    required String establishmentId,
    required String techCardId,
    required int index,
    required Uint8List bytes,
  }) async {
    try {
      final compressed = await ImageService().compressToMaxBytes(bytes, maxBytes: 250 * 1024) ?? bytes;
      final path = '$establishmentId/$techCardId/$index.jpg';
      await _supabase.client.storage
          .from(kTechCardPhotosBucket)
          .uploadBinary(path, compressed, fileOptions: FileOptions(upsert: true));
      final url = _supabase.client.storage.from(kTechCardPhotosBucket).getPublicUrl(path);
      return url;
    } catch (e) {
      devLog('TechCardServiceSupabase.uploadTechCardPhoto: $e');
      return null;
    }
  }

  static bool _isColumnNotFoundError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('pgrst204') ||
        (msg.contains('column') && (msg.contains('find') || msg.contains('found') || msg.contains('exist')));
  }

  /// Payload для tech_cards. Убираем id, section. [includeHallFields] = false при retry после PGRST204.
  static Map<String, dynamic> _techCardPayloadForDb(TechCard techCard, {bool includeHallFields = true}) {
    final data = Map<String, dynamic>.from(techCard.toJson());
    data.remove('id');
    data.remove('section');
    if (!includeHallFields) {
      data.remove('composition_for_hall');
      data.remove('description_for_hall');
      data.remove('selling_price');
    }
    return data;
  }

  /// Payload для вставки в tt_ingredients. Только колонки из схемы БД.
  /// Убираем: id, price_per_kg, cost_currency. grams_per_piece сохраняем.
  static Map<String, dynamic> _ingredientPayloadForDb(TTIngredient ingredient) {
    final data = Map<String, dynamic>.from(ingredient.toJson());
    data.remove('id');
    data.remove('price_per_kg');
    data.remove('cost_currency');
    data.remove('gramsPerPiece'); // toJson выдаёт grams_per_piece (JsonKey)
    data.removeWhere((key, value) => value == null);
    return data;
  }

  /// Создание новой технологической карты
  Future<TechCard> createTechCard({
    required String dishName,
    Map<String, String>? dishNameLocalized,
    required String category,
    List<String> sections = const [],
    bool isSemiFinished = true,
    required String establishmentId,
    required String createdBy,
  }) async {
    final techCard = TechCard.create(
      dishName: dishName,
      dishNameLocalized: dishNameLocalized,
      category: category,
      sections: sections,
      isSemiFinished: isSemiFinished,
      establishmentId: establishmentId,
      createdBy: createdBy,
    );

    Map<String, dynamic> techCardData = _techCardPayloadForDb(techCard);
    dynamic response;
    try {
      response = await _supabase.insertData('tech_cards', techCardData);
    } catch (e) {
      if (_isColumnNotFoundError(e)) {
        techCardData = _techCardPayloadForDb(techCard, includeHallFields: false);
        response = await _supabase.insertData('tech_cards', techCardData);
      } else {
        rethrow;
      }
    }
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
      devLog('Ошибка получения ТТК: $e');
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
      devLog('Ошибка получения ТТК: $e');
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
      devLog('Ошибка поиска ТТК: $e');
      return [];
    }
  }

  /// Сохранение ТТК. При PGRST204 (колонка не найдена) повтор без composition_for_hall, description_for_hall.
  /// [changedByEmployeeId], [changedByName] — для записи в историю изменений.
  /// [skipHistory] — не записывать историю (напр. при фоновом обновлении переводов).
  Future<void> saveTechCard(
    TechCard techCard, {
    String? changedByEmployeeId,
    String? changedByName,
    bool skipHistory = false,
  }) async {
    TechCard? oldCard;
    if (!skipHistory) {
      try {
        oldCard = await getTechCardById(techCard.id);
      } catch (_) {}
    }

    Map<String, dynamic> payload = _techCardPayloadForDb(techCard);
    try {
      await _supabase.updateData(
        'tech_cards',
        payload,
        'id',
        techCard.id,
      );
    } catch (e) {
      if (_isColumnNotFoundError(e)) {
        payload = _techCardPayloadForDb(techCard, includeHallFields: false);
        await _supabase.updateData(
          'tech_cards',
          payload,
          'id',
          techCard.id,
        );
      } else {
        devLog('Ошибка сохранения ТТК: $e');
        rethrow;
      }
    }

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

    if (!skipHistory) {
      await TechCardHistoryService().saveHistory(
        techCardId: techCard.id,
        establishmentId: techCard.establishmentId,
        oldCard: oldCard,
        newCard: techCard,
        changedByEmployeeId: changedByEmployeeId,
        changedByName: changedByName,
      );
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
      devLog('Ошибка удаления ТТК: $e');
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
      devLog('Ошибка получения ТТК по создателю: $e');
      return [];
    }
  }

  static String _normalizeName(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Поиск по названию: продукт или ПФ.
  String? _findProductId(
    String productName,
    String? ingredientType,
    List<({String id, String name})> products,
    List<({String id, String name})> techCardsPf,
    Map<String, String> createdByName,
  ) {
    final norm = _normalizeName(productName);
    if (norm.isEmpty) return null;
    if (ingredientType == 'semi_finished') {
      for (final tc in techCardsPf) {
        if (_normalizeName(tc.name) == norm) return tc.id;
      }
      return createdByName[norm] ?? createdByName[productName.trim()];
    }
    if (ingredientType == 'product') {
      for (final p in products) {
        if (_normalizeName(p.name) == norm) return p.id;
      }
      return null;
    }
    for (final p in products) {
      if (_normalizeName(p.name) == norm) return p.id;
    }
    for (final tc in techCardsPf) {
      if (_normalizeName(tc.name) == norm) return tc.id;
    }
    return createdByName[norm] ?? createdByName[productName.trim()];
  }

  /// Создание ТТК из результата распознавания ИИ (пакетный импорт).
  /// [productStore] — для подтягивания цен из номенклатуры (если продукт уже есть).
  Future<TechCard> createTechCardFromRecognitionResult({
    required String establishmentId,
    required String createdBy,
    String? createdByName,
    required TechCardRecognitionResult result,
    required String category,
    List<String> sections = const ['all'],
    bool? isSemiFinishedOverride,
    String languageCode = 'ru',
    List<({String id, String name})>? productsForMapping,
    List<({String id, String name})>? techCardsPfForMapping,
    Map<String, String>? createdTechCardsByName,
    ProductStoreSupabase? productStore,
  }) async {
    final name = result.dishName?.trim().isNotEmpty == true ? result.dishName!.trim() : 'Без названия';
    final isPf = isSemiFinishedOverride ?? result.isSemiFinished ?? true;
    final products = productsForMapping ?? [];
    final techCardsPf = techCardsPfForMapping ?? [];
    final createdIdsByName = createdTechCardsByName ?? {};

    final created = await createTechCard(
      dishName: name,
      category: category,
      sections: sections,
      isSemiFinished: isPf,
      establishmentId: establishmentId,
      createdBy: createdBy,
    );

    final ingredients = <TTIngredient>[];
    for (final line in result.ingredients) {
      if (line.productName.trim().isEmpty) continue;
      String? productId;
      String? sourceTechCardId;
      if (products.isNotEmpty || techCardsPf.isNotEmpty || createdIdsByName.isNotEmpty) {
        final found = _findProductId(
          line.productName,
          line.ingredientType,
          products,
          techCardsPf,
          createdIdsByName,
        );
        if (found != null) {
          final isPfId = techCardsPf.any((t) => t.id == found) || createdIdsByName.values.contains(found);
          if (isPfId) {
            sourceTechCardId = found;
          } else {
            productId = found;
          }
        }
      }

      var gross = line.grossGrams ?? 0.0;
      var net = line.netGrams ?? line.grossGrams ?? gross;
      final unit = line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
      var wastePct = line.primaryWastePct;
      // Авторасчёт % отхода: нетто = брутто × (1 − отход/100) → отход = (1 − нетто/брутто)×100
      if (gross > 0 && net > 0 && net < gross && (wastePct == null || wastePct == 0)) {
        wastePct = (1.0 - net / gross) * 100.0;
      }
      wastePct = (wastePct ?? 0).clamp(0.0, 99.9);
      var cookingLoss = line.cookingLossPct != null ? line.cookingLossPct!.clamp(0.0, 99.9) : null;
      var output = line.outputGrams;
      // Нетто после отхода (для расчёта ужарки). Файл может дать нетто напрямую.
      final netAfterWaste = net > 0 ? net : (gross > 0 ? gross * (1.0 - wastePct / 100.0) : 0.0);
      // Авторасчёт % ужарки: выход = нетто × (1 − ужарка/100) → ужарка = (1 − выход/нетто)×100
      if (output != null && output > 0 && netAfterWaste > 0 && output < netAfterWaste && cookingLoss == null) {
        cookingLoss = (1.0 - output / netAfterWaste) * 100.0;
        cookingLoss = cookingLoss.clamp(0.0, 99.9);
      } else if (output == null && cookingLoss != null && netAfterWaste > 0) {
        output = netAfterWaste * (1.0 - cookingLoss / 100.0);
      } else if (output == null || output <= 0) {
        output = netAfterWaste;
      }
      double cost = 0;
      double? pricePerKg;
      if (productId != null && productStore != null) {
        final ep = productStore.getEstablishmentPrice(productId, establishmentId);
        final price = ep?.$1;
        if (price != null && price > 0) {
          pricePerKg = price;
          final grossG = gross > 0 ? gross : 100;
          cost = (price / 1000.0) * grossG;
        }
      }
      if (cost == 0 && line.pricePerKg != null && line.pricePerKg! > 0) {
        pricePerKg = line.pricePerKg;
        final grossG = gross > 0 ? gross : 100;
        cost = (pricePerKg! / 1000.0) * grossG;
      }
      ingredients.add(TTIngredient(
        id: '${DateTime.now().millisecondsSinceEpoch}_${ingredients.length}',
        productId: productId,
        sourceTechCardId: sourceTechCardId,
        productName: line.productName.trim(),
        grossWeight: gross > 0 ? gross : 100,
        netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
        outputWeight: output ?? net,
        unit: unit,
        primaryWastePct: wastePct,
        cookingLossPctOverride: cookingLoss,
        isNetWeightManual: line.netGrams != null,
        finalCalories: 0,
        finalProtein: 0,
        finalFat: 0,
        finalCarbs: 0,
        cost: cost,
        pricePerKg: pricePerKg,
      ));
    }
    final yieldVal = ingredients.fold<double>(0.0, (s, i) => s + i.netWeight);
    final techMap = <String, String>{languageCode: result.technologyText?.trim() ?? ''};
    final withIngredients = created.copyWith(
      ingredients: ingredients,
      technologyLocalized: techMap,
    );
    final updated = TechCard.withYieldValue(withIngredients, yieldVal > 0 ? yieldVal : 100);
    await saveTechCard(updated, changedByEmployeeId: createdBy, changedByName: createdByName);
    if (createdTechCardsByName != null) {
      createdTechCardsByName[_normalizeName(name)] = updated.id;
      createdTechCardsByName[name] = updated.id;
    }
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

  /// Перевести название ТТК на указанный язык через DeepL (translate-text edge function).
  /// Обновляет dishNameLocalized в БД и возвращает переведённое имя, либо null при ошибке.
  Future<String?> translateTechCardName(String techCardId, String dishName, String targetLang) async {
    if (targetLang == 'ru') return null;
    try {
      final res = await _supabase.client.functions.invoke(
        'translate-text',
        body: {'text': dishName.trim(), 'from': 'ru', 'to': targetLang},
      );
      final data = res.data as Map<String, dynamic>?;
      final translated = data?['translatedText'] as String?;
      if (translated == null || translated.isEmpty || translated == dishName.trim()) return null;

      // Загружаем текущие данные карты чтобы обновить только dishNameLocalized
      final rows = await _supabase.client
          .from('tech_cards')
          .select('dish_name_localized')
          .eq('id', techCardId)
          .maybeSingle();
      final existing = (rows?['dish_name_localized'] as Map<String, dynamic>?)?.cast<String, String>() ?? {};
      final updated = {...existing, 'ru': dishName.trim(), targetLang: translated};
      await _supabase.client
          .from('tech_cards')
          .update({'dish_name_localized': updated})
          .eq('id', techCardId);
      return translated;
    } catch (e) {
      devLog('TechCardServiceSupabase.translateTechCardName: $e');
      return null;
    }
  }
}