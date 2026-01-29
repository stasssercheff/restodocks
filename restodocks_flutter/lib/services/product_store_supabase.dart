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

      print('✅ Загружено ${_allProducts.length} продуктов из Supabase');
    } catch (e) {
      print('❌ Ошибка загрузки продуктов: $e');
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

    // Фильтр по аллергенам
    if (glutenFree == true) {
      filtered = filtered.where((product) => product.isGlutenFree).toList();
    }

    if (lactoseFree == true) {
      filtered = filtered.where((product) => product.isLactoseFree).toList();
    }

    // Поиск по тексту
    if (searchText != null && searchText.isNotEmpty) {
      final searchLower = searchText.toLowerCase();
      filtered = filtered.where((product) {
        return product.name.toLowerCase().contains(searchLower) ||
               product.getLocalizedName('ru').toLowerCase().contains(searchLower) ||
               product.category.toLowerCase().contains(searchLower);
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
      print('Ошибка добавления продукта: $e');
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
      print('Ошибка обновления продукта: $e');
      rethrow;
    }
  }

  /// Удалить продукт
  Future<void> removeProduct(String productId) async {
    try {
      await _supabase.deleteData('products', 'id', productId);
      _allProducts.removeWhere((product) => product.id == productId);
    } catch (e) {
      print('Ошибка удаления продукта: $e');
      rethrow;
    }
  }

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
      print('Ошибка загрузки продуктов для отдела $department: $e');
    } finally {
      _isLoading = false;
    }
  }
}