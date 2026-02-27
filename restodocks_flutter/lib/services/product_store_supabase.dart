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
  Future<void> loadProducts({bool force = false}) async {
    if (_isLoading && !force) return;
    if (_isLoading && force) {
      // Ждём окончания текущей загрузки перед новой
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    _isLoading = true;

    try {
      print('DEBUG ProductStore: Loading ALL products from database (paginated)...');
      // PostgREST ограничивает ответ 1000 строками по умолчанию.
      // Грузим постранично пока не получим все записи.
      const pageSize = 1000;
      final allData = <Map<String, dynamic>>[];
      var offset = 0;

      while (true) {
        final page = await _supabase.client
            .from('products')
            .select()
            .order('name')
            .range(offset, offset + pageSize - 1);

        final pageList = page as List;
        for (final item in pageList) {
          allData.add(item as Map<String, dynamic>);
        }

        print('DEBUG ProductStore: Page offset=$offset, got ${pageList.length} rows, total so far: ${allData.length}');

        if (pageList.length < pageSize) break; // последняя страница
        offset += pageSize;
        if (offset > 50000) break; // защита от бесконечного цикла
      }

      print('DEBUG ProductStore: Loaded ${allData.length} products total');
      _allProducts = allData.map((json) => Product.fromJson(json)).toList();
      print('DEBUG ProductStore: Parsed ${_allProducts.length} products successfully');

      _categories = _allProducts
          .map((product) => product.category)
          .toSet()
          .toList()
        ..sort();

    } catch (e) {
      print('❌ ProductStore: Error loading products: $e');
      rethrow;
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
    final idLower = id.trim().toLowerCase();
    return _allProducts.where((p) => p.id.trim().toLowerCase() == idLower).firstOrNull;
  }

  /// Найти продукт для ингредиента: по productId, при неудаче — по productName (для совместимости с UUID-миграцией)
  Product? findProductForIngredient(String? productId, String productName) {
    if (productId != null && productId.isNotEmpty) {
      final p = findProductById(productId);
      if (p != null) return p;
    }
    final nameNorm = productName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (nameNorm.isEmpty) return null;
    return _allProducts.where((p) {
      final n = (p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '));
      if (n == nameNorm) return true;
      for (final v in p.names?.values ?? <String>[]) {
        if (v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == nameNorm) return true;
      }
      return false;
    }).firstOrNull;
  }

  /// Добавить новый продукт. Возвращает сохранённый продукт с ID, подтверждённым сервером.
  /// Если продукт с таким именем уже существует — возвращает его без дублирования.
  Future<Product> addProduct(Product product) async {
    // Проверяем локальный кэш перед запросом к БД
    final nameLower = product.name.trim().toLowerCase();
    final existingLocal = _allProducts.where(
      (p) => p.name.trim().toLowerCase() == nameLower,
    ).toList();
    if (existingLocal.isNotEmpty) {
      print('DEBUG ProductStore: Product "${product.name}" already exists locally, skipping insert');
      return existingLocal.first;
    }

    try {
      print('DEBUG ProductStore: Adding product "${product.name}" to database...');
      // Убираем null-поля перед вставкой, чтобы БД использовала DEFAULT значения
      final json = Map<String, dynamic>.fromEntries(
        product.toJson().entries.where((e) => e.value != null),
      );
      final response = await _supabase.insertData('products', json);
      print('DEBUG ProductStore: Insert response: $response');

      final saved = Product.fromJson(response);
      _allProducts.add(saved);
      print('DEBUG ProductStore: Product added successfully, total products: ${_allProducts.length}');
      if (!_categories.contains(saved.category)) {
        _categories.add(saved.category);
        _categories.sort();
      }

      // Запускаем перевод фоново через Edge Function
      _translateProductInBackground(saved.id);

      return saved;
    } catch (e) {
      // Уникальный индекс сработал — продукт уже есть в БД, ищем его
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('duplicate') || errStr.contains('unique') || errStr.contains('already exists')) {
        print('DEBUG ProductStore: Duplicate detected for "${product.name}", fetching existing...');
        try {
          final existing = await _supabase.client
              .from('products')
              .select()
              .ilike('name', product.name.trim())
              .limit(1);
          if (existing.isNotEmpty) {
            final saved = Product.fromJson(existing[0] as Map<String, dynamic>);
            if (!_allProducts.any((p) => p.id == saved.id)) {
              _allProducts.add(saved);
            }
            return saved;
          }
        } catch (fetchErr) {
          print('DEBUG ProductStore: Failed to fetch existing product: $fetchErr');
        }
      }
      print('DEBUG ProductStore: Error adding product: $e');
      rethrow;
    }
  }

  /// Публичный метод для запуска перевода извне (например при добавлении в номенклатуру)
  void triggerTranslation(String productId) => _translateProductInBackground(productId);

  /// Запустить перевод продукта фоново через Edge Function auto-translate-product
  void _translateProductInBackground(String productId) {
    Supabase.instance.client.functions
        .invoke('auto-translate-product', body: {'product_id': productId})
        .then((res) {
      if (res.status == 200 && res.data != null) {
        final data = res.data as Map<String, dynamic>?;
        if (data?['updated'] == true) {
          final names = data?['names'];
          if (names is Map) {
            final idx = _allProducts.indexWhere((p) => p.id == productId);
            if (idx != -1) {
              _allProducts[idx] = _allProducts[idx].copyWith(
                names: Map<String, String>.from(names),
              );
            }
          }
        }
      }
    }).catchError((e) {
      print('DEBUG ProductStore: Background translation failed for $productId: $e');
    });
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

    dynamic response;
    try {
      response = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency')
          .eq('establishment_id', establishmentId)
          .limit(10000);
    } catch (e) {
      print('⚠️ ProductStore: Full select failed (price/currency columns may not exist), trying product_id only: $e');
      response = await _supabase.client
          .from('establishment_products')
          .select('product_id')
          .eq('establishment_id', establishmentId)
          .limit(10000);
    }

    final list = response is List ? response : <dynamic>[];
    print('📊 ProductStore: Raw response received, length: ${list.length}');

    if (list.isEmpty) {
      print('ℹ️ ProductStore: No nomenclature data found for establishment $establishmentId');
      return;
    }

    await _processNomenclatureResponse(list, establishmentId);
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

  /// Добавить продукт в номенклатуру (опционально с ценой)
  Future<void> addToNomenclature(String establishmentId, String productId, {double? price, String? currency}) async {
    print('➕ ProductStore: Adding product $productId to nomenclature for establishment $establishmentId...');

    // Валидация входных данных
    if (establishmentId.isEmpty || productId.isEmpty) {
      throw ArgumentError('establishmentId and productId cannot be empty');
    }

    try {
      // Сначала создаем/обновляем запись в establishment_products
      final data = <String, dynamic>{
        'establishment_id': establishmentId,
        'product_id': productId,
      };

      print('📝 ProductStore: Inserting/updating nomenclature record: $data');

      // Используем upsert для создания записи если её нет
      final response = await _supabase.client
          .from('establishment_products')
          .upsert(
            data,
            onConflict: 'establishment_id,product_id',
          )
          .select();

      print('✅ ProductStore: Nomenclature record upsert successful, response: $response');

      // Теперь всегда устанавливаем цену, если она указана (даже если запись уже существовала)
      if (price != null) {
        print('💰 ProductStore: Setting price for product $productId: $price $currency');
        await setEstablishmentPrice(establishmentId, productId, price, currency);
      }

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
    print('💰 ProductStore: Setting price for $productId in establishment $establishmentId: $price $currency');

    if (price != null) {
      final oldPrice = getEstablishmentPrice(productId, establishmentId)?.$1;

      // upsert — создаёт запись если нет, обновляет если есть
      await _supabase.client
          .from('establishment_products')
          .upsert(
            {
              'establishment_id': establishmentId,
              'product_id': productId,
              'price': price,
              'currency': currency,
            },
            onConflict: 'establishment_id,product_id',
          );
      print('✅ ProductStore: Price upserted in establishment_products');

      // Записываем в историю изменений (если цена изменилась)
      if (oldPrice == null || (oldPrice - price).abs() > 0.001) {
        try {
          await _supabase.client.from('product_price_history').insert({
            'establishment_id': establishmentId,
            'product_id': productId,
            'old_price': oldPrice,
            'new_price': price,
            'currency': currency ?? 'RUB',
          });
        } catch (e) {
          print('⚠️ ProductStore: Failed to record price history: $e');
        }
      }

      // Также обновляем basePrice в таблице products
      await _supabase.client
          .from('products')
          .update({'base_price': price, 'currency': currency})
          .eq('id', productId);
      print('✅ ProductStore: basePrice updated in products table');

      // Обновляем локальный кэш продукта
      final idx = _allProducts.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        _allProducts[idx] = _allProducts[idx].copyWith(basePrice: price, currency: currency);
      }
    }

    // Обновить кэш цены
    final cacheKey = '${establishmentId}_$productId';
    if (price != null) {
      _priceCache[cacheKey] = (price, currency ?? 'RUB');
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

    final items = <NomenclatureItem>[];
    for (final product in products) {
      items.add(NomenclatureItem.product(product));
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
  /// Берёт из establishment_products (карточки заведения)
  (double?, String?)? getEstablishmentPrice(String productId, String? establishmentId) {
    if (establishmentId == null) return null;

    final cacheKey = '${establishmentId}_$productId';
    return _priceCache[cacheKey];
  }

  /// Очистить кэш цен
  void clearPriceCache() {
    _priceCache.clear();
  }

  /// История изменений цены продукта в номенклатуре заведения
  Future<List<PriceHistoryEntry>> getPriceHistory(String productId, String establishmentId) async {
    try {
      final response = await _supabase.client
          .from('product_price_history')
          .select('old_price, new_price, currency, changed_at')
          .eq('establishment_id', establishmentId)
          .eq('product_id', productId)
          .order('changed_at', ascending: false)
          .limit(20);
      final list = response is List ? response : <dynamic>[];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PriceHistoryEntry(
          oldPrice: m['old_price'] != null ? (m['old_price'] as num).toDouble() : null,
          newPrice: (m['new_price'] as num?)?.toDouble(),
          currency: m['currency'] as String?,
          changedAt: m['changed_at'] != null ? DateTime.parse(m['changed_at'] as String) : null,
        );
      }).toList();
    } catch (e) {
      print('⚠️ ProductStore: Failed to load price history: $e');
      return [];
    }
  }
}

/// Запись истории изменения цены
class PriceHistoryEntry {
  final double? oldPrice;
  final double? newPrice;
  final String? currency;
  final DateTime? changedAt;

  const PriceHistoryEntry({
    this.oldPrice,
    this.newPrice,
    this.currency,
    this.changedAt,
  });
}