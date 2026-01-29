import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Сервис управления продуктами
class ProductStore {
  static final ProductStore _instance = ProductStore._internal();
  factory ProductStore() => _instance;
  ProductStore._internal();

  List<Product> _allProducts = [];
  List<String> _categories = [];
  bool _isLoading = false;

  // Геттеры
  List<Product> get allProducts => _allProducts;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;

  /// Загрузка продуктов
  Future<void> loadProducts() async {
    if (_allProducts.isNotEmpty) return;

    _isLoading = true;

    try {
      // Загружаем продукты кухни
      final kitchenProducts = await _loadProductsFromAsset('assets/products/kitchen_products.json');
      _allProducts.addAll(kitchenProducts);

      // Загружаем продукты бара
      final barProducts = await _loadProductsFromAsset('assets/products/bar_products.json');
      _allProducts.addAll(barProducts);

      // Загружаем продукты зала
      final diningRoomProducts = await _loadProductsFromAsset('assets/products/dining_room_products.json');
      _allProducts.addAll(diningRoomProducts);

      // Обновляем категории
      _categories = _allProducts
          .map((product) => product.category)
          .toSet()
          .toList()
        ..sort();

    } catch (e) {
      print('Ошибка загрузки продуктов: $e');
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

    // Фильтр по отделу
    if (department != null) {
      switch (department) {
        case 'kitchen':
          filtered = filtered.where((product) =>
            !['soft_drinks', 'juice', 'water', 'beer', 'wine', 'spirits', 'hot_drinks', 'coffee_drinks', 'desserts', 'ice_cream', 'fresh_desserts'].contains(product.category)
          ).toList();
          break;
        case 'bar':
          filtered = filtered.where((product) =>
            ['soft_drinks', 'juice', 'water', 'beer', 'wine', 'spirits', 'hot_drinks', 'coffee_drinks'].contains(product.category)
          ).toList();
          break;
        case 'dining_room':
          filtered = filtered.where((product) =>
            ['hot_drinks', 'coffee_drinks', 'desserts', 'ice_cream', 'fresh_desserts', 'bread', 'oils', 'spices'].contains(product.category)
          ).toList();
          break;
      }
    }

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
  void addProduct(Product product) {
    _allProducts.add(product);

    // Обновляем категории, если новая
    if (!_categories.contains(product.category)) {
      _categories.add(product.category);
      _categories.sort();
    }
  }

  /// Обновить продукт
  void updateProduct(Product updatedProduct) {
    final index = _allProducts.indexWhere((product) => product.id == updatedProduct.id);
    if (index != -1) {
      _allProducts[index] = updatedProduct;
    }
  }

  /// Удалить продукт
  void removeProduct(String productId) {
    _allProducts.removeWhere((product) => product.id == productId);
  }

  /// Получить продукты для конкретного отдела
  Future<void> loadProductsForDepartment(String department) async {
    _isLoading = true;

    try {
      switch (department) {
        case 'kitchen':
          _allProducts = await _loadProductsFromAsset('assets/products/kitchen_products.json');
          break;
        case 'bar':
          _allProducts = await _loadProductsFromAsset('assets/products/bar_products.json');
          break;
        case 'dining_room':
          _allProducts = await _loadProductsFromAsset('assets/products/dining_room_products.json');
          break;
        default:
          _allProducts = await _loadProductsFromAsset('assets/products/kitchen_products.json');
      }

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

  /// Загрузка продуктов из asset файла
  Future<List<Product>> _loadProductsFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final jsonData = json.decode(jsonString) as List<dynamic>;
      return jsonData.map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      print('Ошибка загрузки $assetPath: $e');
      return [];
    }
  }

  /// Очистить все продукты (для тестирования)
  void clearProducts() {
    _allProducts.clear();
    _categories.clear();
  }
}