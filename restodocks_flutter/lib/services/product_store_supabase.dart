import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/nomenclature_item.dart';
import 'supabase_service.dart';

/// Сервис управления продуктами с использованием Supabase
class ProductStoreSupabase {
  static final ProductStoreSupabase _instance = ProductStoreSupabase._internal();
  factory ProductStoreSupabase() => _instance;
  ProductStoreSupabase._internal();

  final SupabaseService _supabase = SupabaseService();
  List<Product> _allProducts = [];
  List<String> _categories = [];
  bool _isLoading = false;

  // Кэш цен заведения: productId -> (price, currency)
  final Map<String, (double?, String?)?> _priceCache = {};

  // Геттеры
  List<Product> get allProducts => _allProducts;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;

  /// Загрузка продуктов из Supabase
  Future<void> loadProducts() async {
    if (_isLoading) return;

    _isLoading = true;

    try {
      print('DEBUG ProductStore: Loading products from database...');
      final data = await _supabase.client
          .from('products')
          .select()
          .order('name');

      print('DEBUG ProductStore: Loaded ${data.length} products from database');
      _allProducts = (data as List)
          .map((json) => Product.fromJson(json))
          .toList();
      print('DEBUG ProductStore: Parsed ${_allProducts.length} products successfully');

      // Обновляем категории
      _categories = _allProducts
          .map((product) => product.category)
          .toSet()
          .toList()
        ..sort();

      // Products loaded successfully
    } catch (e) {
      // Error loading products
    } finally {
      _isLoading = false;
    }
  }

  /// Получить продукты с фильтрами
  List<Product> getProducts({
    String? category,
    bool? glutenFree,
    bool? lactoseFree,
    String? searchText,
    String? department,
  }) {
    var filtered = _allProducts;

    // Фильтр по категории
    if (category != null && category.isNotEmpty) {
      filtered = filtered.where((product) => product.category == category).toList();
    }

    // Фильтр по аллергенам: показываем продукты, не помеченные как содержащие (null не исключаем)
    if (glutenFree == true) {
      filtered = filtered.where((product) => product.suitableForGlutenFreeFilter).toList();
    }

    if (lactoseFree == true) {
      filtered = filtered.where((product) => product.suitableForLactoseFreeFilter).toList();
    }

    // Поиск по тексту
    if (searchText != null && searchText.isNotEmpty) {
      final searchLower = searchText.toLowerCase();
      filtered = filtered.where((product) {
        if (product.name.toLowerCase().contains(searchLower)) return true;
        if (product.category.toLowerCase().contains(searchLower)) return true;
        final n = product.names;
        if (n != null) {
          for (final v in n.values) {
            if (v.toLowerCase().contains(searchLower)) return true;
          }
        }
        return false;
      }).toList();
    }

    return filtered;
  }

  /// Получить продукты по категории
  List<Product> getProductsInCategory(String category) {
    return _allProducts.where((product) => product.category == category).toList();
  }

  /// Поиск продуктов по тексту
  List<Product> searchProducts(String searchText) {
    return getProducts(searchText: searchText);
  }

  /// Найти продукт по ID
  Product? findProductById(String id) {
    return _allProducts.where((product) => product.id == id).firstOrNull;
  }

  /// Добавить новый продукт
  Future<void> addProduct(Product product) async {
    try {
      print('DEBUG ProductStore: Adding product "${product.name}" to database...');
      final response = await _supabase.insertData('products', product.toJson());
      print('DEBUG ProductStore: Insert response: $response');

      // Если получили данные обратно, используем их
      if (response != null && response.containsKey('id')) {
        final created = Product.fromJson(response);
        _allProducts.add(created);
        print('DEBUG ProductStore: Product added successfully, total products: ${_allProducts.length}');

        if (!_categories.contains(created.category)) {
          _categories.add(created.category);
          _categories.sort();
        }
      } else {
        // Если не получили данные, добавляем локально созданный продукт
        print('DEBUG ProductStore: No response data, adding locally created product');
        _allProducts.add(product);
        if (!_categories.contains(product.category)) {
          _categories.add(product.category);
          _categories.sort();
        }
      }
    } catch (e) {
      print('DEBUG ProductStore: Error adding product: $e');
      // Error adding product
      rethrow;
    }
  }

  /// Обновить продукт
  Future<void> updateProduct(Product updatedProduct) async {
    try {
      await _supabase.updateData(
        'products',
        updatedProduct.toJson(),
        'id',
        updatedProduct.id,
      );

      final index = _allProducts.indexWhere((product) => product.id == updatedProduct.id);
      if (index != -1) {
        _allProducts[index] = updatedProduct;
      }
    } catch (e) {
      // Error updating product
      rethrow;
    }
  }

  /// Обновить валюту у всех продуктов
  Future<void> bulkUpdateCurrency(String currency) async {
    for (final p in _allProducts) {
      final updated = p.copyWith(currency: currency);
      await updateProduct(updated);
    }
  }

  /// Удалить продукт
  Future<void> removeProduct(String productId) async {
    try {
      await _supabase.deleteData('products', 'id', productId);
      _allProducts.removeWhere((product) => product.id == productId);
    } catch (e) {
      // Error deleting product
      rethrow;
    }
  }

  /// Номенклатура заведения: ID продуктов в номенклатуре
  Set<String> _nomenclatureIds = {};
  Set<String> get nomenclatureProductIds => Set.from(_nomenclatureIds);

  /// Загрузить номенклатуру заведения (ID продуктов и цены)
  Future<void> loadNomenclature(String establishmentId) async {
    print('🔄 ProductStore: Loading nomenclature for establishment $establishmentId...');

    // Очищаем текущие данные
    _nomenclatureIds.clear();
    _priceCache.removeWhere((key, _) => key.startsWith('${establishmentId}_'));

    print('👤 ProductStore: Loading nomenclature for establishment: $establishmentId');

    // Пробуем основной метод загрузки
    try {
      await _loadNomenclatureDirect(establishmentId);
    } catch (e) {
      print('⚠️ ProductStore: Primary loading failed, trying fallback method: $e');

      // Пробуем альтернативный метод (RPC функция или упрощенный запрос)
      try {
        await _loadNomenclatureFallback(establishmentId);
      } catch (fallbackError) {
        print('❌ ProductStore: Fallback loading also failed: $fallbackError');

        // Очищаем данные при ошибке
        _nomenclatureIds.clear();
        _priceCache.removeWhere((key, _) => key.startsWith('${establishmentId}_'));

        // Можно добавить дополнительную логику обработки ошибок
        rethrow; // Перебрасываем ошибку выше
      }
    }
  }

  /// Основной метод загрузки номенклатуры
  Future<void> _loadNomenclatureDirect(String establishmentId) async {
    print('🔍 ProductStore: Making query to establishment_products...');
    print('🔍 ProductStore: establishment_id = $establishmentId');

    // Пробуем загрузить данные номенклатуры
    final response = await _supabase.client
        .from('establishment_products')
        .select('product_id, price, currency')
        .eq('establishment_id', establishmentId);

    print('📊 ProductStore: Raw response received, length: ${response.length}');
    print('📊 ProductStore: Response type: ${response.runtimeType}');
    print('📊 ProductStore: Response: $response');

    if (response.isEmpty) {
      print('ℹ️ ProductStore: No nomenclature data found for establishment $establishmentId');
      return;
    }

    // Обрабатываем полученные данные
    await _processNomenclatureResponse(response, establishmentId);
  }

  /// Альтернативный метод загрузки (если основной не работает)
  Future<void> _loadNomenclatureFallback(String establishmentId) async {
    print('🔄 ProductStore: Trying fallback loading method...');

    // Пробуем RPC функцию, если она существует
    try {
      final response = await _supabase.client.rpc('get_establishment_products', params: {
        'est_id': establishmentId,
      });

      if (response != null && response is List) {
        await _processNomenclatureResponse(response, establishmentId);
        return;
      }
    } catch (e) {
      print('⚠️ ProductStore: RPC fallback failed: $e');
    }

    // Если RPC не работает, пробуем упрощенный запрос без RLS
    try {
      // Временный обход RLS (если это разрешено)
      final response = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency')
          .eq('establishment_id', establishmentId)
          .limit(1000); // Ограничиваем для безопасности

      await _processNomenclatureResponse(response, establishmentId);
    } catch (e) {
      print('❌ ProductStore: All fallback methods failed');
      rethrow;
    }
  }

  /// Обработка ответа с данными номенклатуры
  Future<void> _processNomenclatureResponse(List<dynamic> response, String establishmentId) async {
    print('🔍 ProductStore: Processing response with ${response.length} items');
    print('🔍 ProductStore: First item raw: ${response.isNotEmpty ? response.first : 'no items'}');
    print('🔍 ProductStore: First item keys: ${response.isNotEmpty ? response.first.keys.toList() : 'no items'}');

    int processedCount = 0;

    for (final item in response) {
      try {
        print('🔍 ProductStore: Processing item: $item');
        print('🔍 ProductStore: Item type: ${item.runtimeType}');
        print('🔍 ProductStore: Item keys: ${item.keys.toList()}');

        // Пробуем разные варианты названий полей
        final productId = item['product_id'] as String? ??
                         item['id'] as String? ??
                         item['productId'] as String?;

        if (productId == null || productId.isEmpty) {
          print('⚠️ ProductStore: Skipping item with null/empty product_id/id/productId');
          print('⚠️ ProductStore: Available keys: ${item.keys.toList()}');
          continue;
        }

        // Добавляем в номенклатуру
        _nomenclatureIds.add(productId);

        // Кэшируем цены (если есть)
        final cacheKey = '${establishmentId}_$productId';
        final price = item['price'];
        final currency = item['currency'] as String?;

        if (price != null && price is num) {
          _priceCache[cacheKey] = (price.toDouble(), currency);
        } else {
          _priceCache[cacheKey] = null;
        }

        processedCount++;
      } catch (e) {
        print('⚠️ ProductStore: Error processing item: $e, item: $item');
        continue; // Продолжаем с другими элементами
      }
    }

    print('✅ ProductStore: Nomenclature loaded successfully: $processedCount products, cache size: ${_priceCache.length}');
  }

  /// Проверить и восстановить номенклатуру при ошибках
  Future<void> ensureNomenclatureLoaded(String establishmentId) async {
    print('🔄 ProductStore: Ensuring nomenclature is loaded for $establishmentId...');

    try {
      // Пробуем загрузить, если еще не загружено
      if (_nomenclatureIds.isEmpty) {
        await loadNomenclature(establishmentId);
      }

      // Если все еще пусто, возможно проблемы с данными
      if (_nomenclatureIds.isEmpty) {
        print('⚠️ ProductStore: Nomenclature is empty, this might be normal for new establishments');
      } else {
        print('✅ ProductStore: Nomenclature verified: ${_nomenclatureIds.length} products');
      }
    } catch (e) {
      print('❌ ProductStore: Failed to ensure nomenclature loaded: $e');
      // Не выбрасываем ошибку, чтобы не ломать основной поток
    }
  }

  /// Добавить продукт в номенклатуру
  Future<void> addToNomenclature(String establishmentId, String productId) async {
    print('➕ ProductStore: Adding product $productId to nomenclature for establishment $establishmentId...');

    // Валидация входных данных
    if (establishmentId.isEmpty || productId.isEmpty) {
      throw ArgumentError('establishmentId and productId cannot be empty');
    }

    try {
      // Создаем запись в establishment_products
      final data = {
        'establishment_id': establishmentId,
        'product_id': productId,
        'created_at': DateTime.now().toIso8601String(),
      };

      print('📝 ProductStore: Inserting data: $data');

      final response = await _supabase.client
          .from('establishment_products')
          .upsert(
            data,
            onConflict: 'establishment_id,product_id',
          )
          .select();

      print('✅ ProductStore: Nomenclature upsert successful, response: $response');

      // Добавляем в локальный кэш
      _nomenclatureIds.add(productId);

      print('✅ ProductStore: Product $productId added to nomenclature successfully');

    } catch (e, stackTrace) {
      print('❌ ProductStore: Error adding to nomenclature: $e');
      print('🔍 Stack trace: $stackTrace');

      // Не добавляем в локальный кэш при ошибке
      // Вызывающий код должен обработать ошибку
      rethrow;
    }
  }

  /// Удалить продукт из номенклатуры
  Future<void> removeFromNomenclature(String establishmentId, String productId) async {
    await _supabase.client
        .from('establishment_products')
        .delete()
        .eq('establishment_id', establishmentId)
        .eq('product_id', productId);
    _nomenclatureIds.remove(productId);
    // Очистить кэш цены
    _priceCache.remove('${establishmentId}_$productId');
  }

  /// Полностью удалить продукт из базы данных
  Future<void> deleteProduct(String productId) async {
    // Сначала удаляем из всех номенклатур
    await _supabase.client
        .from('establishment_products')
        .delete()
        .eq('product_id', productId);

    // Затем удаляем сам продукт
    await _supabase.client
        .from('products')
        .delete()
        .eq('id', productId);

    // Очистить кэш
    _priceCache.removeWhere((key, value) => key.contains(productId));
    _allProducts.removeWhere((product) => product.id == productId);
  }

  /// Получить список ID продуктов в номенклатуре заведения
  List<String> getNomenclatureIdsForEstablishment(String establishmentId) {
    return _nomenclatureIds.where((id) {
      // Проверяем, есть ли цена для этого продукта в этом заведении
      return _priceCache.containsKey('${establishmentId}_$id');
    }).toList();
  }

  /// Установить цену продукта в номенклатуре заведения
  Future<void> setEstablishmentPrice(String establishmentId, String productId, double? price, String? currency) async {
    await _supabase.client.from('establishment_products').upsert(
      {
        'establishment_id': establishmentId,
        'product_id': productId,
        'price': price,
        'currency': currency,
      },
      onConflict: 'establishment_id,product_id',
    );

    // Обновить кэш
    final cacheKey = '${establishmentId}_$productId';
    if (price != null && currency != null) {
      _priceCache[cacheKey] = (price, currency);
    } else {
      _priceCache[cacheKey] = null;
    }
  }

  /// Удалить ВСЕ продукты из номенклатуры заведения
  Future<void> clearAllNomenclature(String establishmentId) async {
    print('🗑️ ProductStore: Clearing all nomenclature for establishment $establishmentId');

    try {
      // Удаляем все записи из establishment_products для этого заведения
      await _supabase.client
          .from('establishment_products')
          .delete()
          .eq('establishment_id', establishmentId);

      // Очищаем локальный кэш
      _nomenclatureIds.clear();
      _priceCache.removeWhere((key, _) => key.startsWith('${establishmentId}_'));

      print('✅ ProductStore: All nomenclature cleared successfully');

    } catch (e, stackTrace) {
      print('❌ ProductStore: Error clearing nomenclature: $e');
      print('🔍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Удалить ВСЕ продукты из общего списка (только для администраторов!)
  Future<void> clearAllProducts() async {
    print('🗑️ ProductStore: Clearing ALL products from database');

    try {
      // Проверяем, что пользователь имеет права администратора
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // ВНИМАНИЕ: Это опасная операция! Удаляем ВСЕ продукты
      await _supabase.client.from('products').delete().neq('id', '00000000-0000-0000-0000-000000000000');

      // Очищаем локальный кэш
      _allProducts.clear();
      _nomenclatureIds.clear();
      _priceCache.clear();

      print('✅ ProductStore: ALL products cleared successfully (DANGER: This removed all products!)');

    } catch (e, stackTrace) {
      print('❌ ProductStore: Error clearing all products: $e');
      print('🔍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Продукты в номенклатуре заведения
  List<Product> getNomenclatureProducts(String establishmentId) {
    return _allProducts.where((p) => _nomenclatureIds.contains(p.id)).toList();
  }

  /// Получить все элементы номенклатуры (продукты + ТТК ПФ)
  Future<List<NomenclatureItem>> getAllNomenclatureItems(String establishmentId, dynamic techCardService) async {
    final products = getNomenclatureProducts(establishmentId);

    // Загружаем ТТК с типом ПФ для этого заведения
    final techCards = await techCardService.getTechCardsForEstablishment(establishmentId);
    final semiFinishedTechCards = techCards.where((tc) => tc.isSemiFinished).toList();

    final items = <NomenclatureItem>[];

    // Добавляем продукты
    for (final product in products) {
      items.add(NomenclatureItem.product(product));
    }

    // Добавляем ТТК ПФ
    for (final techCard in semiFinishedTechCards) {
      items.add(NomenclatureItem.techCard(techCard));
    }

    return items;
  }

  /// В номенклатуре ли продукт
  bool isInNomenclature(String productId) => _nomenclatureIds.contains(productId);

  /// Получить продукты для конкретного отдела
  Future<void> loadProductsForDepartment(String department) async {
    _isLoading = true;

    try {
      // Определяем категории для отдела
      List<String> departmentCategories = [];
      switch (department) {
        case 'kitchen':
          departmentCategories = ['meat', 'vegetables', 'dairy', 'grains', 'oils', 'spices'];
          break;
        case 'bar':
          departmentCategories = ['soft_drinks', 'juice', 'water', 'beer', 'wine', 'spirits', 'hot_drinks', 'coffee_drinks'];
          break;
        case 'dining_room':
          departmentCategories = ['hot_drinks', 'coffee_drinks', 'desserts', 'ice_cream', 'fresh_desserts', 'bread', 'oils', 'spices'];
          break;
      }

      if (departmentCategories.isEmpty) {
        await loadProducts();
        return;
      }

      final data = await _supabase.client
          .from('products')
          .select()
          .inFilter('category', departmentCategories)
          .order('name');

      _allProducts = (data as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _categories = _allProducts
          .map((product) => product.category)
          .toSet()
          .toList()
        ..sort();

    } catch (e) {
      // Error loading products for department
    } finally {
      _isLoading = false;
    }
  }

  /// Получить цену продукта для конкретного заведения
  /// Возвращает (price, currency) или null если цена не установлена
  (double?, String?)? getEstablishmentPrice(String productId, String? establishmentId) {
    if (establishmentId == null) return null;

    final cacheKey = '${establishmentId}_$productId';
    return _priceCache[cacheKey];
  }

  /// Очистить кэш цен
  void clearPriceCache() {
    _priceCache.clear();
  }
}