import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
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
      final data = await _supabase.client
          .from('products')
          .select()
          .order('name');

      _allProducts = (data as List)
          .map((json) => Product.fromJson(json))
          .toList();

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
      final response = await _supabase.insertData('products', product.toJson());
      final created = Product.fromJson(response);
      _allProducts.add(created);

      if (!_categories.contains(created.category)) {
        _categories.add(created.category);
        _categories.sort();
      }
    } catch (e) {
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
    try {
      final data = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency')
          .eq('establishment_id', establishmentId);

      _nomenclatureIds = {};
      for (final item in data as List) {
        final productId = item['product_id'] as String;
        _nomenclatureIds.add(productId);

        // Кэшируем цены
        final cacheKey = '${establishmentId}_$productId';
        if (item['price'] != null) {
          _priceCache[cacheKey] = ((item['price'] as num).toDouble(), item['currency'] as String?);
        } else {
          _priceCache[cacheKey] = null;
        }
      }
    } catch (e) {
      // Error loading nomenclature
      _nomenclatureIds = {};
    }
  }

  /// Добавить продукт в номенклатуру
  Future<void> addToNomenclature(String establishmentId, String productId) async {
    try {
      await _supabase.client.from('establishment_products').upsert(
        {'establishment_id': establishmentId, 'product_id': productId},
        onConflict: 'establishment_id,product_id',
      );
      _nomenclatureIds.add(productId);
    } catch (e) {
      // Error adding to nomenclature
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
  }

  /// Продукты в номенклатуре заведения
  List<Product> getNomenclatureProducts(String establishmentId) {
    return _allProducts.where((p) => _nomenclatureIds.contains(p.id)).toList();
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