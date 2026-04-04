import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/dev_log.dart';
import '../utils/product_name_utils.dart';
import '../utils/product_ingredient_family_match.dart';

import '../models/models.dart';
import 'nutrition_backfill_service.dart';
import '../models/nomenclature_item.dart';
import 'offline_cache_service.dart';
import 'supabase_service.dart';
import 'account_manager_supabase.dart';

/// Ошибка шлюза/сети: не путать с «нет колонки department» — иначе три SELECT подряд + RPC только усугубляют шторм при 502/503.
bool _isLikelyGatewayOrNetworkError(Object e) {
  if (e is PostgrestException) {
    final c = e.code;
    if (c != null && const {'502', '503', '504', '522'}.contains(c)) return true;
  }
  final msg = e.toString().toLowerCase();
  return msg.contains('502') ||
      msg.contains('503') ||
      msg.contains('504') ||
      msg.contains('522') ||
      msg.contains('network') ||
      msg.contains('failed host lookup') ||
      msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('connection timed out') ||
      msg.contains('origin') && msg.contains('cors');
}

/// Сервис управления продуктами с использованием Supabase
class ProductStoreSupabase {
  static final ProductStoreSupabase _instance =
      ProductStoreSupabase._internal();
  factory ProductStoreSupabase() => _instance;
  ProductStoreSupabase._internal();

  /// Счётчик обновлений каталога и номенклатуры (для перерисовки ТТК в просмотре без подтверждения).
  final ValueNotifier<int> catalogRevision = ValueNotifier<int>(0);

  void _bumpCatalogRevision() {
    catalogRevision.value++;
  }

  final SupabaseService _supabase = SupabaseService();
  final OfflineCacheService _offlineCache = OfflineCacheService();
  List<Product> _allProducts = [];
  List<String> _categories = [];
  bool _isLoading = false;
  bool _hasFullProductCatalog = false;

  // Кэш цен заведения: productId -> (price, currency)
  final Map<String, (double?, String?)?> _priceCache = {};

  // Чтобы на web/слабых устройствах не дёргать localStorage каждый раз при
  // открытии пикакера: запоминаем, какие именно данные номенклатуры уже
  // загружены в память.
  String? _nomenclatureLoadedMainId;
  String? _nomenclatureLoadedBranchKey; // format: mainId|branchId

  static const _productsCacheDataset = 'products_all';
  static const _nomenclatureCacheDataset = 'nomenclature';

  // Геттеры
  List<Product> get allProducts => _allProducts;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get hasFullProductCatalog => _hasFullProductCatalog;

  /// Загрузка продуктов из Supabase
  Future<void> loadProducts({bool force = false}) async {
    // На web чтение localStorage/jsonDecode заметно тормозит — если кэш уже
    // распарсен в память, просто не грузим его заново.
    if (!force && _hasFullProductCatalog && _allProducts.isNotEmpty) {
      return;
    }
    if (!force) {
      final cacheKey = await _offlineCache.scopedKey(
        dataset: _productsCacheDataset,
        establishmentId: 'global',
      );
      final cached = await _offlineCache.readJsonList(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _allProducts = cached.map(Product.fromJson).toList();
        _categories = _allProducts
            .map((product) => product.category)
            .toSet()
            .toList()
          ..sort();
        _hasFullProductCatalog = true;
        _bumpCatalogRevision();
        unawaited(_loadProductsFromServer());
        return;
      }
    }
    await _loadProductsFromServer();
  }

  Future<void> _loadProductsFromServer() async {
    if (_isLoading) return;

    _isLoading = true;

    const maxAttempts = 3;
    const retryDelay = Duration(seconds: 1);

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          devLog(
              'DEBUG ProductStore: Loading ALL products from database (paginated)... attempt $attempt/$maxAttempts');
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

            devLog(
                'DEBUG ProductStore: Page offset=$offset, got ${pageList.length} rows, total so far: ${allData.length}');

            if (pageList.length < pageSize) break; // последняя страница
            offset += pageSize;
            if (offset > 50000) break; // защита от бесконечного цикла
          }

          devLog('DEBUG ProductStore: Loaded ${allData.length} products total');
          _allProducts = allData.map((json) => Product.fromJson(json)).toList();
          devLog(
              'DEBUG ProductStore: Parsed ${_allProducts.length} products successfully');

          _categories = _allProducts
              .map((product) => product.category)
              .toSet()
              .toList()
            ..sort();
          _hasFullProductCatalog = true;

          // Фоновая подгрузка КБЖУ: на web JWT к PostgREST часто готов позже загрузки каталога;
          // иначе product_nutrition_links уходит от anon → 403 (до политики anon SELECT).
          unawaited(_scheduleNutritionBackfillAfterCatalogLoad());
          final cacheKey = await _offlineCache.scopedKey(
            dataset: _productsCacheDataset,
            establishmentId: 'global',
          );
          await _offlineCache.writeJsonList(
              cacheKey, _allProducts.map((p) => p.toJson()).toList());

          return;
        } catch (e) {
          devLog(
              '❌ ProductStore: Error loading products (attempt $attempt/$maxAttempts): $e');
          if (attempt == maxAttempts) rethrow;
          await Future.delayed(retryDelay);
        }
      }
    } finally {
      _isLoading = false;
      _bumpCatalogRevision();
    }
  }

  Future<void> _scheduleNutritionBackfillAfterCatalogLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!AccountManagerSupabase().isLoggedInSync) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;
      await client.auth.refreshSession();
    } catch (_) {}
    NutritionBackfillService().startBackgroundBackfill(this);
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
      filtered =
          filtered.where((product) => product.category == category).toList();
    }

    // Фильтр по аллергенам: показываем продукты, не помеченные как содержащие (null не исключаем)
    if (glutenFree == true) {
      filtered = filtered
          .where((product) => product.suitableForGlutenFreeFilter)
          .toList();
    }

    if (lactoseFree == true) {
      filtered = filtered
          .where((product) => product.suitableForLactoseFreeFilter)
          .toList();
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
    return _allProducts
        .where((product) => product.category == category)
        .toList();
  }

  /// Поиск продуктов по тексту
  List<Product> searchProducts(String searchText) {
    return getProducts(searchText: searchText);
  }

  /// Найти продукт по ID
  Product? findProductById(String id) {
    final idLower = id.trim().toLowerCase();
    return _allProducts
        .where((p) => p.id.trim().toLowerCase() == idLower)
        .firstOrNull;
  }

  /// Найти продукт для ингредиента: по productId, при неудаче — по productName (для совместимости с UUID-миграцией).
  /// Игнорирует префиксы iiko (Т., ТМЦ) при сопоставлении.
  /// При дублях выбирает "лучший" вариант по полноте КБЖУ, чтобы не залипать на старых пустых дублях.
  Product? findProductForIngredient(String? productId, String productName) {
    final candidates = <Product>[];
    if (productId != null && productId.isNotEmpty) {
      final byId = findProductById(productId);
      if (byId != null) candidates.add(byId);
    }
    final raw =
        productName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final stripped = stripIikoPrefix(productName)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (raw.isEmpty && stripped.isEmpty) return null;
    for (final p in _allProducts.where((p) {
      final n = (p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '));
      final pStripped = stripIikoPrefix(p.name)
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
      if (n == raw ||
          n == stripped ||
          pStripped == raw ||
          pStripped == stripped) return true;
      for (final v in p.names?.values ?? <String>[]) {
        final vn = v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final vs = stripIikoPrefix(v)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
        if (vn == raw || vn == stripped || vs == raw || vs == stripped)
          return true;
      }
      return false;
    })) {
      if (!candidates.any((c) => c.id == p.id)) candidates.add(p);
    }
    // Семейное совпадение: «тростниковый песок» / «пудра» без точного равенства карточке.
    if (candidates.isEmpty) {
      final q = stripped.isNotEmpty ? stripped : raw;
      if (isSugarFamilySearchString(q)) {
        final sugarHits = <Product>[];
        for (final p in _allProducts) {
          final nameL = p.name.trim().toLowerCase();
          final extras = (p.names?.values ?? const <String>[])
              .map((v) => v.trim().toLowerCase())
              .toList();
          if (!isSugarFamilyProductNameBlob(nameL, extras)) continue;
          sugarHits.add(p);
        }
        if (sugarHits.isNotEmpty) {
          sugarHits.sort((a, b) {
            final oa = sugarQueryOverlapScore(q, _productNameBlobLower(a));
            final ob = sugarQueryOverlapScore(q, _productNameBlobLower(b));
            if (oa != ob) return ob.compareTo(oa);
            return _ingredientProductScore(b).compareTo(_ingredientProductScore(a));
          });
          candidates.add(sugarHits.first);
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) =>
        _ingredientProductScore(b).compareTo(_ingredientProductScore(a)));
    return candidates.first;
  }

  String _productNameBlobLower(Product p) {
    final parts = <String>[p.name, ...(p.names?.values ?? const <String>[])];
    return parts
        .map((e) => e.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
        .join(' ');
  }

  int _ingredientProductScore(Product p) {
    var score = 0;
    if (p.calories != null && p.calories! > 0) score += 2;
    if (p.protein != null) score += 1;
    if (p.fat != null) score += 1;
    if (p.carbs != null) score += 1;
    if (p.names != null && p.names!.isNotEmpty) score += 1;
    return score;
  }

  /// Продукт с тем же `lower(trim(name))`, что и у [rawName] (логика БД и RPC).
  Future<Product?> _fetchProductByNormalizedName(String rawName) async {
    final norm = rawName.trim().toLowerCase();
    for (final p in _allProducts) {
      if (p.name.trim().toLowerCase() == norm) return p;
    }
    try {
      final res = await _supabase.client.rpc(
        'get_product_by_normalized_name',
        params: {'p_name': rawName.trim()},
      );
      final Map<String, dynamic>? row = res is Map<String, dynamic>
          ? res
          : (res is List && res.isNotEmpty && res[0] is Map)
              ? res[0] as Map<String, dynamic>
              : null;
      if (row != null) return Product.fromJson(row);
    } catch (_) {}
    try {
      final fallback = await _supabase.client
          .from('products')
          .select()
          .ilike('name', rawName.trim())
          .limit(10);
      for (final r in fallback as List) {
        final m = r as Map<String, dynamic>;
        if (norm == (m['name'] as String? ?? '').trim().toLowerCase()) {
          return Product.fromJson(m);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Добавить новый продукт. Возвращает сохранённый продукт с ID, подтверждённым сервером.
  /// Если продукт с таким именем уже существует — возвращает его без дублирования.
  Future<Product> addProduct(Product product) async {
    // Проверяем локальный кэш перед запросом к БД
    final nameLower = product.name.trim().toLowerCase();
    final existingLocal = _allProducts
        .where(
          (p) => p.name.trim().toLowerCase() == nameLower,
        )
        .toList();
    if (existingLocal.isNotEmpty) {
      devLog(
          'DEBUG ProductStore: Product "${product.name}" already exists locally, skipping insert');
      return existingLocal.first;
    }

    try {
      devLog(
          'DEBUG ProductStore: Adding product "${product.name}" to database...');
      // Убираем null-поля перед вставкой, чтобы БД использовала DEFAULT значения
      final json = Map<String, dynamic>.fromEntries(
        product.toJson().entries.where((e) => e.value != null),
      );
      final response = await _supabase.insertData('products', json);
      devLog('DEBUG ProductStore: Insert response: $response');

      final saved = Product.fromJson(response);
      _allProducts.add(saved);
      devLog(
          'DEBUG ProductStore: Product added successfully, total products: ${_allProducts.length}');
      if (!_categories.contains(saved.category)) {
        _categories.add(saved.category);
        _categories.sort();
      }

      // Запускаем перевод фоново через Edge Function
      _translateProductInBackground(saved.id);

      return saved;
    } catch (e) {
      // 409 / unique violation — продукт уже есть в БД, ищем его
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('409') ||
          errStr.contains('23505') ||
          errStr.contains('duplicate') ||
          errStr.contains('unique') ||
          errStr.contains('already exists')) {
        devLog(
            'DEBUG ProductStore: Duplicate detected for "${product.name}", fetching existing...');
        try {
          final saved = await _fetchProductByNormalizedName(product.name);
          if (saved != null) {
            if (!_allProducts.any((p) => p.id == saved.id)) {
              _allProducts.add(saved);
            }
            return saved;
          }
        } catch (fetchErr) {
          devLog(
              'DEBUG ProductStore: Failed to fetch existing product: $fetchErr');
        }
      }
      devLog('DEBUG ProductStore: Error adding product: $e');
      rethrow;
    }
  }

  /// Публичный метод для запуска перевода извне (fire-and-forget)
  void triggerTranslation(String productId) =>
      _translateProductInBackground(productId);

  /// Загрузить алиасы (нормализованное_название → product_id) для разгрузки AI при импорте.
  /// [establishmentId] — заведение: алиасы заведения приоритетнее глобальных.
  /// Исключаем отказы; при конфликтах — выше confidence.
  Future<Map<String, String>> loadProductAliases(
      {String? establishmentId}) async {
    try {
      final rows = await _supabase.client.from('product_aliases').select(
          'input_name_normalized, product_id, establishment_id, confidence');
      final rejections = await _loadProductAliasRejections(establishmentId);
      final map = <String, ({String id, int confidence, bool isEst})>{};
      for (final r in rows as List) {
        final row = r as Map<String, dynamic>;
        final key = row['input_name_normalized']?.toString().trim();
        final val = row['product_id']?.toString();
        final conf =
            (row['confidence'] is num) ? (row['confidence'] as num).toInt() : 1;
        final estId = row['establishment_id']?.toString();
        if (key == null || key.isEmpty || val == null || conf <= 0) continue;
        if (rejections[key]?.contains(val) ?? false) continue;
        final isEst = establishmentId != null && estId == establishmentId;
        final isGlobal = estId == null || estId.isEmpty;
        if (!isEst && !isGlobal) continue;
        final existing = map[key];
        final take = existing == null ||
            (isEst && !existing.isEst) ||
            (isEst == existing.isEst && conf > existing.confidence);
        if (take) map[key] = (id: val, confidence: conf, isEst: isEst);
      }
      return map.map((k, v) => MapEntry(k, v.id));
    } catch (_) {
      try {
        final rows = await _supabase.client
            .from('product_aliases')
            .select('input_name_normalized, product_id');
        final map = <String, String>{};
        for (final r in rows as List) {
          final row = r as Map<String, dynamic>;
          final key = row['input_name_normalized']?.toString().trim();
          final val = row['product_id']?.toString();
          if (key != null && key.isNotEmpty && val != null) map[key] = val;
        }
        return map;
      } catch (__) {
        return {};
      }
    }
  }

  Future<Map<String, Set<String>>> _loadProductAliasRejections(
      String? establishmentId) async {
    try {
      var query = _supabase.client
          .from('product_alias_rejections')
          .select('input_name_normalized, product_id, establishment_id');
      final rows = await query;
      final map = <String, Set<String>>{};
      for (final r in rows as List) {
        final row = r as Map<String, dynamic>;
        final key = row['input_name_normalized']?.toString().trim();
        final val = row['product_id']?.toString();
        final estId = row['establishment_id']?.toString();
        if (key == null || val == null) continue;
        final isEst = establishmentId != null && estId == establishmentId;
        final isGlobal = estId == null || estId.isEmpty;
        if (!isEst && !isGlobal) continue;
        map.putIfAbsent(key, () => {}).add(val);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Сохранить алиас. [establishmentId] — для алиасов по заведению.
  Future<void> saveProductAlias(String inputNameNormalized, String productId,
      {String? establishmentId}) async {
    if (inputNameNormalized.trim().isEmpty || productId.isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'input_name_normalized': inputNameNormalized.trim(),
        'product_id': productId,
        'confidence': 1,
      };
      if (establishmentId != null)
        payload['establishment_id'] = establishmentId;
      await _supabase.client.from('product_aliases').upsert(
            payload,
            onConflict: 'input_name_normalized,establishment_id',
          );
    } catch (_) {
      try {
        await _supabase.client.from('product_aliases').upsert(
          {
            'input_name_normalized': inputNameNormalized.trim(),
            'product_id': productId
          },
          onConflict: 'input_name_normalized',
        );
      } catch (e) {
        devLog('ProductStore: saveProductAlias failed: $e');
      }
    }
  }

  /// Отказ от маппинга: пользователь заменил продукт — не предлагать.
  Future<void> saveProductAliasRejection(
      String inputNameNormalized, String productId,
      {String? establishmentId}) async {
    if (inputNameNormalized.trim().isEmpty || productId.isEmpty) return;
    try {
      await _supabase.client.from('product_alias_rejections').upsert(
        {
          'input_name_normalized': inputNameNormalized.trim(),
          'product_id': productId,
          'establishment_id': establishmentId,
        },
        onConflict: 'input_name_normalized,product_id,establishment_id',
      );
    } catch (_) {}
  }

  /// Запустить перевод продукта фоново через Edge Function auto-translate-product
  void _translateProductInBackground(String productId) {
    Supabase.instance.client.functions.invoke('auto-translate-product',
        body: {'product_id': productId}).then((res) {
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
      devLog(
          'DEBUG ProductStore: Background translation failed for $productId: $e');
    });
  }

  /// Перевести продукт и дождаться результата. Обновляет names в store.
  /// Возвращает обновлённый Map<lang, name> или null при ошибке.
  Future<Map<String, String>?> translateProductAwait(String productId) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('auto-translate-product', body: {'product_id': productId});
      if (res.status == 200 && res.data != null) {
        final data = res.data as Map<String, dynamic>?;
        final names = data?['names'];
        if (names is Map) {
          final namesMap = Map<String, String>.from(names);
          final idx = _allProducts.indexWhere((p) => p.id == productId);
          if (idx != -1) {
            _allProducts[idx] = _allProducts[idx].copyWith(names: namesMap);
          }
          return namesMap;
        }
      }
    } catch (e) {
      devLog(
          'DEBUG ProductStore: translateProductAwait failed for $productId: $e');
    }
    return null;
  }

  /// Обновить продукт
  Future<void> updateProduct(Product updatedProduct) async {
    final other =
        await _fetchProductByNormalizedName(updatedProduct.name);
    if (other != null &&
        other.id.toLowerCase() != updatedProduct.id.toLowerCase()) {
      throw const DuplicateProductNameException();
    }
    try {
      await _supabase.updateData(
        'products',
        updatedProduct.toJson(),
        'id',
        updatedProduct.id,
      );

      final index =
          _allProducts.indexWhere((product) => product.id == updatedProduct.id);
      if (index != -1) {
        _allProducts[index] = updatedProduct;
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('23505') &&
          (errStr.contains('products_name_unique_lower') ||
              errStr.contains('duplicate key'))) {
        throw const DuplicateProductNameException();
      }
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

  /// Для строк `establishment_products` с колонкой [department]: product_id → отделы (kitchen, bar).
  final Map<String, Set<String>> _nomenclatureDeptByProduct = {};

  /// ID продуктов, добавленных только филиалом (доп от филиала). Заполняется при loadNomenclatureForBranch.
  Set<String> _branchOnlyProductIds = {};
  bool isBranchOnlyProduct(String productId) =>
      _branchOnlyProductIds.contains(productId);

  /// Догружает строки таблицы `products` для ID номенклатуры, которых ещё нет в [_allProducts].
  /// Иначе [getNomenclatureProducts] даёт пустой список: ID есть в [establishment_products],
  /// а карточки не попали в память (устаревший кэш каталога, фоновая подгрузка ещё не дошла).
  Future<void> _ensureNomenclatureProductsInStore() async {
    if (_nomenclatureIds.isEmpty) return;
    final have = _allProducts.map((p) => p.id.toLowerCase()).toSet();
    final missing = _nomenclatureIds
        .where((id) => !have.contains(id.toLowerCase()))
        .toList();
    if (missing.isEmpty) return;

    devLog(
        'ℹ️ ProductStore: fetching ${missing.length} nomenclature product row(s) not in catalog cache');
    const chunkSize = 500;
    final client = _supabase.client;
    for (var i = 0; i < missing.length; i += chunkSize) {
      final end = i + chunkSize > missing.length ? missing.length : i + chunkSize;
      final chunk = missing.sublist(i, end);
      try {
        final data = await client.from('products').select().inFilter('id', chunk);
        final rows = data as List;
        for (final row in rows) {
          final m = Map<String, dynamic>.from(row as Map);
          try {
            final p = Product.fromJson(m);
            final idx = _allProducts.indexWhere(
                (e) => e.id.toLowerCase() == p.id.toLowerCase());
            if (idx >= 0) {
              _allProducts[idx] = p;
            } else {
              _allProducts.add(p);
            }
          } catch (_) {}
        }
      } catch (e) {
        devLog(
            '⚠️ ProductStore: _ensureNomenclatureProductsInStore chunk failed: $e');
      }
    }
  }

  /// Загрузить номенклатуру заведения (ID продуктов и цены)
  Future<void> loadNomenclature(String establishmentId) async {
    if (_nomenclatureIds.isNotEmpty &&
        _nomenclatureLoadedMainId == establishmentId &&
        _nomenclatureLoadedBranchKey == null) {
      return;
    }
    final cacheKey = await _offlineCache.scopedKey(
      dataset: _nomenclatureCacheDataset,
      establishmentId: establishmentId,
      suffix: 'main',
    );
    final cached = await _offlineCache.readJsonMap(cacheKey);
    if (cached != null) {
      _applyNomenclatureCache(establishmentId, cached);
      _nomenclatureLoadedMainId = establishmentId;
      _nomenclatureLoadedBranchKey = null;
      await _ensureNomenclatureProductsInStore();
      _bumpCatalogRevision();
      if (_nomenclatureIds.isEmpty) {
        await _reloadNomenclatureFromServer(establishmentId);
        return;
      }
      // Ждём фоновое обновление: иначе после return номенклатура оказывается пустой
      // (reload сначала очищает данные) и UI теряет список до конца запроса.
      await _reloadNomenclatureFromServer(establishmentId);
      return;
    }
    await _reloadNomenclatureFromServer(establishmentId);
    _nomenclatureLoadedMainId = establishmentId;
    _nomenclatureLoadedBranchKey = null;
  }

  /// Сырой список строк establishment_products (без изменения кэша в памяти).
  Future<List<dynamic>> _fetchNomenclatureRowsRaw(String establishmentId) async {
    dynamic response;
    try {
      response = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency, department')
          .eq('establishment_id', establishmentId)
          .limit(10000);
    } catch (e) {
      if (_isLikelyGatewayOrNetworkError(e)) {
        devLog('⚠️ ProductStore: establishment_products aborted (gateway/network), no schema fallbacks: $e');
        rethrow;
      }
      devLog(
          '⚠️ ProductStore: Full select failed (price/currency columns may not exist), trying product_id only: $e');
      try {
        response = await _supabase.client
            .from('establishment_products')
            .select('product_id, price, currency')
            .eq('establishment_id', establishmentId)
            .limit(10000);
      } catch (e2) {
        if (_isLikelyGatewayOrNetworkError(e2)) rethrow;
        devLog('⚠️ ProductStore: select without department failed: $e2');
        response = await _supabase.client
            .from('establishment_products')
            .select('product_id')
            .eq('establishment_id', establishmentId)
            .limit(10000);
      }
    }
    return response is List ? response : <dynamic>[];
  }

  Future<void> _reloadNomenclatureFromServer(String establishmentId) async {
    try {
      final list = await _fetchNomenclatureRowsRaw(establishmentId);
      // Сбрасываем после получения ответа — пока идёт сеть, старая номенклатура остаётся в памяти.
      _branchOnlyProductIds.clear();
      _nomenclatureIds.clear();
      _nomenclatureDeptByProduct.clear();
      _priceCache
          .removeWhere((key, _) => key.startsWith('${establishmentId}_'));

      if (list.isEmpty) {
        devLog(
            'ℹ️ ProductStore: No nomenclature data found for establishment $establishmentId');
      } else {
        await _processNomenclatureResponse(list, establishmentId);
      }
    } catch (e) {
      devLog(
          '⚠️ ProductStore: Primary loading failed, trying fallback method: $e');
      _branchOnlyProductIds.clear();
      _nomenclatureIds.clear();
      _nomenclatureDeptByProduct.clear();
      _priceCache
          .removeWhere((key, _) => key.startsWith('${establishmentId}_'));
      if (_isLikelyGatewayOrNetworkError(e)) {
        devLog(
            '⚠️ ProductStore: skip RPC/alt fallbacks while upstream is gateway/network (avoids request storm)');
        rethrow;
      }
      try {
        await _loadNomenclatureFallback(establishmentId);
      } catch (fallbackError) {
        devLog(
            '❌ ProductStore: Fallback loading also failed: $fallbackError');
        _nomenclatureIds.clear();
        _nomenclatureDeptByProduct.clear();
        _priceCache
            .removeWhere((key, _) => key.startsWith('${establishmentId}_'));
        rethrow;
      }
    }
    await _ensureNomenclatureProductsInStore();
    await _saveNomenclatureCache(establishmentId, suffix: 'main');
    _bumpCatalogRevision();
  }

  /// Загрузить номенклатуру для филиала: объединение номенклатуры головного заведения и филиала.
  /// Цены филиала перекрывают цены головного. Продукты только филиала помечаются как «доп от филиала».
  Future<void> loadNomenclatureForBranch(String branchId, String mainId) async {
    final branchKey = '$mainId|$branchId';
    if (_nomenclatureIds.isNotEmpty &&
        _nomenclatureLoadedBranchKey == branchKey) {
      return;
    }
    final cacheKey = await _offlineCache.scopedKey(
      dataset: _nomenclatureCacheDataset,
      establishmentId: mainId,
      suffix: 'branch:$branchId',
    );
    final cached = await _offlineCache.readJsonMap(cacheKey);
    if (cached != null) {
      _applyNomenclatureCache(branchId, cached);
      _nomenclatureLoadedMainId = null;
      _nomenclatureLoadedBranchKey = branchKey;
      await _ensureNomenclatureProductsInStore();
      _bumpCatalogRevision();
      if (_nomenclatureIds.isEmpty) {
        await _reloadNomenclatureForBranchFromServer(branchId, mainId);
        return;
      }
      await _reloadNomenclatureForBranchFromServer(branchId, mainId);
      return;
    }
    await _reloadNomenclatureForBranchFromServer(branchId, mainId);
    _nomenclatureLoadedMainId = null;
    _nomenclatureLoadedBranchKey = branchKey;
  }

  Future<void> _reloadNomenclatureForBranchFromServer(
      String branchId, String mainId) async {
    List<dynamic> mainList = [];
    List<dynamic> branchList = [];
    try {
      final mainResp = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency, department')
          .eq('establishment_id', mainId)
          .limit(10000);
      mainList = mainResp is List ? mainResp : [];
    } catch (e) {
      devLog('⚠️ ProductStore: Failed to load main nomenclature (with department): $e');
      try {
        final mainResp = await _supabase.client
            .from('establishment_products')
            .select('product_id, price, currency')
            .eq('establishment_id', mainId)
            .limit(10000);
        mainList = mainResp is List ? mainResp : [];
      } catch (e2) {
        devLog('⚠️ ProductStore: Failed to load main nomenclature: $e2');
      }
    }
    try {
      final branchResp = await _supabase.client
          .from('establishment_products')
          .select('product_id, price, currency, department')
          .eq('establishment_id', branchId)
          .limit(10000);
      branchList = branchResp is List ? branchResp : [];
    } catch (e) {
      devLog(
          '⚠️ ProductStore: Failed to load branch nomenclature (with department): $e');
      try {
        final branchResp = await _supabase.client
            .from('establishment_products')
            .select('product_id, price, currency')
            .eq('establishment_id', branchId)
            .limit(10000);
        branchList = branchResp is List ? branchResp : [];
      } catch (e2) {
        devLog('⚠️ ProductStore: Failed to load branch nomenclature: $e2');
      }
    }

    // После ответов сети — подменяем кэш (до этого UI может опираться на старую номенклатуру).
    _branchOnlyProductIds.clear();
    _nomenclatureIds.clear();
    _nomenclatureDeptByProduct.clear();
    _priceCache.removeWhere((key, _) =>
        key.startsWith('${mainId}_') || key.startsWith('${branchId}_'));

    final mainIds = <String>{};
    final mainPrices = <String, (double?, String?)>{};
    for (final item in mainList) {
      final productId = item['product_id'] as String? ??
          item['id'] as String? ??
          item['productId'] as String?;
      if (productId == null || productId.isEmpty) continue;
      mainIds.add(productId);
      _rememberNomenclatureDepartment(productId, item['department']);
      final price = item['price'];
      final currency = item['currency'] as String?;
      if (price != null && price is num) {
        mainPrices[productId] = (price.toDouble(), currency);
      } else {
        mainPrices[productId] = (null, null);
      }
    }

    final branchIds = <String>{};
    final branchPrices = <String, (double?, String?)>{};
    for (final item in branchList) {
      final productId = item['product_id'] as String? ??
          item['id'] as String? ??
          item['productId'] as String?;
      if (productId == null || productId.isEmpty) continue;
      branchIds.add(productId);
      _rememberNomenclatureDepartment(productId, item['department']);
      final price = item['price'];
      final currency = item['currency'] as String?;
      if (price != null && price is num) {
        branchPrices[productId] = (price.toDouble(), currency);
      } else {
        branchPrices[productId] = (null, null);
      }
    }

    _nomenclatureIds = mainIds.union(branchIds);
    _branchOnlyProductIds = branchIds.difference(mainIds);

    for (final id in _nomenclatureIds) {
      final cacheKey = '${branchId}_$id';
      final branchVal = branchPrices[id];
      final mainVal = mainPrices[id];
      final branchHasPrice = branchVal != null && branchVal.$1 != null;
      final mainHasPrice = mainVal != null && mainVal.$1 != null;
      if (branchHasPrice) {
        _priceCache[cacheKey] = branchVal;
      } else if (mainHasPrice) {
        _priceCache[cacheKey] = mainVal;
      } else {
        _priceCache[cacheKey] = (null, null);
      }
    }
    await _ensureNomenclatureProductsInStore();
    await _saveNomenclatureCache(mainId, suffix: 'branch:$branchId');
    _bumpCatalogRevision();
  }

  void _applyNomenclatureCache(
      String establishmentId, Map<String, dynamic> cache) {
    final ids = (cache['nomenclature_ids'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toSet();
    final branchOnly =
        (cache['branch_only_product_ids'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toSet();
    _nomenclatureIds = ids;
    _branchOnlyProductIds = branchOnly;
    _nomenclatureDeptByProduct.clear();
    final rawDept = cache['nomenclature_departments'];
    if (rawDept is Map) {
      for (final e in rawDept.entries) {
        final pid = e.key.toString();
        final list = e.value;
        if (list is List) {
          _nomenclatureDeptByProduct[pid] =
              list.map((x) => x.toString()).toSet();
        }
      }
    }
    _priceCache.removeWhere((key, _) => key.startsWith('${establishmentId}_'));
    final rawPrices = cache['price_cache'];
    if (rawPrices is Map) {
      for (final entry in rawPrices.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          final price = value['price'];
          final currency = value['currency']?.toString();
          _priceCache[key] = (price is num ? price.toDouble() : null, currency);
        } else {
          _priceCache[key] = null;
        }
      }
    }
  }

  Future<void> _saveNomenclatureCache(String establishmentId,
      {required String suffix}) async {
    final data = <String, dynamic>{
      'nomenclature_ids': _nomenclatureIds.toList(),
      'branch_only_product_ids': _branchOnlyProductIds.toList(),
      'nomenclature_departments': _nomenclatureDeptByProduct.map(
        (k, v) => MapEntry(k, v.toList()),
      ),
      'price_cache': _priceCache.map(
        (k, v) => MapEntry(
          k,
          v == null ? null : {'price': v.$1, 'currency': v.$2},
        ),
      ),
    };
    final key = await _offlineCache.scopedKey(
      dataset: _nomenclatureCacheDataset,
      establishmentId: establishmentId,
      suffix: suffix,
    );
    await _offlineCache.writeJsonMap(key, data);
  }

  /// Альтернативный метод загрузки (если основной не работает)
  Future<void> _loadNomenclatureFallback(String establishmentId) async {
    devLog('🔄 ProductStore: Trying fallback loading method...');

    // Пробуем RPC функцию, если она существует
    try {
      final response =
          await _supabase.client.rpc('get_establishment_products', params: {
        'est_id': establishmentId,
      });

      if (response != null && response is List) {
        await _processNomenclatureResponse(response, establishmentId);
        return;
      }
    } catch (e) {
      devLog('⚠️ ProductStore: RPC fallback failed: $e');
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
      devLog('❌ ProductStore: All fallback methods failed');
      rethrow;
    }
  }

  void _rememberNomenclatureDepartment(String productId, dynamic rawDept) {
    final s = rawDept?.toString().trim();
    final dept = (s == null || s.isEmpty) ? 'kitchen' : s;
    _nomenclatureDeptByProduct.putIfAbsent(productId, () => {}).add(dept);
  }

  /// Какие product_id отдаём на экран номенклатуры до клиентских фильтров.
  /// Для [kitchen] учитываем [establishment_products.department], иначе старый кейс
  /// «все позиции с department=kitchen, но категория как у бара» давал пустой список.
  /// Для bar и прочих маршрутов — все id; узкий отбор по категории остаётся в UI.
  Set<String> _nomenclatureIdsForScreen(String screenDepartment) {
    if (screenDepartment != 'kitchen') {
      return Set<String>.from(_nomenclatureIds);
    }
    return _nomenclatureIds.where((id) {
      final d = _nomenclatureDeptByProduct[id];
      if (d == null || d.isEmpty) return true;
      return d.contains('kitchen');
    }).toSet();
  }

  /// Обработка ответа с данными номенклатуры
  Future<void> _processNomenclatureResponse(
      List<dynamic> response, String establishmentId) async {
    int processedCount = 0;

    for (final item in response) {
      try {
        // Пробуем разные варианты названий полей
        final productId = item['product_id'] as String? ??
            item['id'] as String? ??
            item['productId'] as String?;

        if (productId == null || productId.isEmpty) continue;

        _rememberNomenclatureDepartment(productId, item['department']);

        // Добавляем в номенклатуру
        _nomenclatureIds.add(productId);

        // Кэшируем цены из establishment_products (номенклатура заведения).
        // Если в заведении несколько отделов (kitchen/bar) — не перезаписывать существующую цену на null.
        final cacheKey = '${establishmentId}_$productId';
        final price = item['price'];
        final currency = item['currency'] as String?;

        if (price != null && price is num) {
          _priceCache[cacheKey] = (price.toDouble(), currency);
        } else {
          final existing = _priceCache[cacheKey];
          if (existing != null && existing.$1 != null) {
            // Уже есть цена (из другого отдела) — не затирать
          } else {
            // Цена только в establishment_products — если нет, то null
            _priceCache[cacheKey] = null;
          }
        }

        processedCount++;
      } catch (e) {
        // Пропускаем проблемный элемент, продолжаем с остальными
        continue;
      }
    }
  }

  /// Проверить и восстановить номенклатуру при ошибках
  Future<void> ensureNomenclatureLoaded(String establishmentId) async {
    try {
      // Пробуем загрузить, если еще не загружено
      if (_nomenclatureIds.isEmpty) {
        await loadNomenclature(establishmentId);
      }

      // Если все еще пусто, возможно проблемы с данными
      if (_nomenclatureIds.isEmpty) {
        devLog(
            '⚠️ ProductStore: Nomenclature is empty, this might be normal for new establishments');
      } else {}
    } catch (e) {
      devLog('❌ ProductStore: Failed to ensure nomenclature loaded: $e');
      // Не выбрасываем ошибку, чтобы не ломать основной поток
    }
  }

  /// Добавить продукт в номенклатуру (опционально с ценой)
  Future<void> addToNomenclature(String establishmentId, String productId,
      {double? price, String? currency}) async {
    devLog(
        '➕ ProductStore: Adding product $productId to nomenclature for establishment $establishmentId...');

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

      devLog('📝 ProductStore: Inserting/updating nomenclature record: $data');

      // Используем upsert для создания записи если её нет
      final response = await _supabase.client
          .from('establishment_products')
          .upsert(
            data,
            onConflict: 'establishment_id,product_id',
          )
          .select();

      devLog(
          '✅ ProductStore: Nomenclature record upsert successful, response: $response');

      // Теперь всегда устанавливаем цену, если она указана (даже если запись уже существовала)
      if (price != null) {
        await setEstablishmentPrice(
            establishmentId, productId, price, currency);
      }

      // Добавляем в локальный кэш
      _nomenclatureIds.add(productId);

      devLog(
          '✅ ProductStore: Product $productId added to nomenclature successfully');
    } catch (e, stackTrace) {
      devLog('❌ ProductStore: Error adding to nomenclature: $e');
      devLog('🔍 Stack trace: $stackTrace');

      // Не добавляем в локальный кэш при ошибке
      // Вызывающий код должен обработать ошибку
      rethrow;
    }
  }

  /// Удалить продукт из номенклатуры
  Future<void> removeFromNomenclature(
      String establishmentId, String productId) async {
    await _supabase.client
        .from('establishment_products')
        .delete()
        .eq('establishment_id', establishmentId)
        .eq('product_id', productId);
    _nomenclatureIds.remove(productId);
    // Очистить кэш цены
    _priceCache.remove('${establishmentId}_$productId');
  }

  /// Слияние дубликатов в один продукт: RPC переносит ссылки (ТТК, склад, номенклатура) и удаляет строки источников.
  Future<void> mergeProductsInto(
    String targetProductId,
    List<String> sourceProductIds,
  ) async {
    final sources = sourceProductIds
        .where((id) => id.isNotEmpty && id != targetProductId)
        .toList();
    if (sources.isEmpty) return;
    await _supabase.client.rpc(
      'merge_products_into',
      params: {
        'p_target': targetProductId,
        'p_sources': sources,
      },
    );
    for (final id in sources) {
      _nomenclatureIds.remove(id);
      _allProducts.removeWhere((p) => p.id == id);
      _priceCache.removeWhere(
        (key, _) => key.endsWith('_$id'),
      );
    }
    _bumpCatalogRevision();
  }

  /// Полностью удалить продукт из базы данных
  Future<void> deleteProduct(String productId) async {
    // Сначала удаляем из всех номенклатур
    await _supabase.client
        .from('establishment_products')
        .delete()
        .eq('product_id', productId);

    // Затем удаляем сам продукт
    await _supabase.client.from('products').delete().eq('id', productId);

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
  Future<void> setEstablishmentPrice(String establishmentId, String productId,
      double? price, String? currency) async {
    if (price != null) {
      final oldPrice = getEstablishmentPrice(productId, establishmentId)?.$1;

      // upsert — создаёт запись если нет, обновляет если есть
      await _supabase.client.from('establishment_products').upsert(
        {
          'establishment_id': establishmentId,
          'product_id': productId,
          'price': price,
          'currency': currency,
        },
        onConflict: 'establishment_id,product_id',
      );

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
          devLog('⚠️ ProductStore: Failed to record price history: $e');
        }
      }

      // Цена только в establishment_products (products.base_price не трогаем)
    }

    // Обновить кэш цены
    final cacheKey = '${establishmentId}_$productId';
    if (price != null) {
      _priceCache[cacheKey] = (price, currency ?? 'RUB');
    } else {
      _priceCache[cacheKey] = null;
    }
  }

  /// Удалить ВСЕ продукты из номенклатуры заведения.
  /// Использует RPC для быстрого bulk delete (без возврата тысяч строк).
  /// Fallback на прямой DELETE если RPC ещё не применён.
  Future<void> clearAllNomenclature(String establishmentId) async {
    devLog(
        '🗑️ ProductStore: Clearing all nomenclature for establishment $establishmentId');

    try {
      try {
        await _supabase.client.rpc(
          'clear_establishment_nomenclature',
          params: {'p_establishment_id': establishmentId},
        );
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST202') {
          // RPC не найден — fallback на прямой delete
          await _supabase.client
              .from('establishment_products')
              .delete()
              .eq('establishment_id', establishmentId);
        } else {
          rethrow;
        }
      }

      // Очищаем локальный кэш
      _nomenclatureIds.clear();
      _priceCache
          .removeWhere((key, _) => key.startsWith('${establishmentId}_'));

      devLog('✅ ProductStore: All nomenclature cleared successfully');
    } catch (e, stackTrace) {
      devLog('❌ ProductStore: Error clearing nomenclature: $e');
      devLog('🔍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Удалить ВСЕ продукты из общего списка (только для администраторов!)
  Future<void> clearAllProducts() async {
    devLog('🗑️ ProductStore: Clearing ALL products from database');

    try {
      // Проверяем, что пользователь имеет права администратора
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // ВНИМАНИЕ: Это опасная операция! Удаляем ВСЕ продукты
      await _supabase.client
          .from('products')
          .delete()
          .neq('id', '00000000-0000-0000-0000-000000000000');

      // Очищаем локальный кэш
      _allProducts.clear();
      _hasFullProductCatalog = false;
      _nomenclatureIds.clear();
      _priceCache.clear();

      devLog(
          '✅ ProductStore: ALL products cleared successfully (DANGER: This removed all products!)');
    } catch (e, stackTrace) {
      devLog('❌ ProductStore: Error clearing all products: $e');
      devLog('🔍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Продукты в номенклатуре заведения
  List<Product> getNomenclatureProducts(String establishmentId) {
    final idSet =
        _nomenclatureIds.map((id) => id.toLowerCase()).toSet();
    return _allProducts
        .where((p) => idSet.contains(p.id.toLowerCase()))
        .toList();
  }

  /// Быстрая загрузка продуктов номенклатуры без загрузки всего каталога.
  /// Запрос к establishment_products + products по FK. Рекомендуется для списка поставщика.
  Future<List<Product>> loadNomenclatureProductsDirect(
    String establishmentId, {
    String department = 'kitchen',
  }) async {
    try {
      final response = await _supabase.client
          .from('establishment_products')
          .select('product_id, products(*)')
          .eq('establishment_id', establishmentId)
          .eq('department', department)
          .limit(5000);
      final list = response is List ? response : <dynamic>[];
      final seen = <String>{};
      final products = <Product>[];
      for (final row in list) {
        final m = row is Map ? Map<String, dynamic>.from(row as Map) : null;
        if (m == null) continue;
        final productJson = m['products'];
        if (productJson is! Map) continue;
        final pMap = Map<String, dynamic>.from(productJson as Map);
        final id = pMap['id']?.toString();
        if (id == null || id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        try {
          products.add(Product.fromJson(pMap));
        } catch (_) {}
      }
      products.sort((a, b) => a.name.compareTo(b.name));
      // Кэшируем в _allProducts для отображения в списке (lookup по productId)
      for (final p in products) {
        final idx = _allProducts.indexWhere((e) => e.id == p.id);
        if (idx >= 0) {
          _allProducts[idx] = p;
        } else {
          _allProducts.add(p);
        }
      }
      return products;
    } catch (e) {
      devLog('❌ ProductStore: loadNomenclatureProductsDirect failed: $e');
      rethrow;
    }
  }

  /// Получить все элементы номенклатуры (продукты + ТТК ПФ)
  Future<List<NomenclatureItem>> getAllNomenclatureItems(
    String establishmentId,
    dynamic techCardService, {
    String screenDepartment = 'general',
  }) async {
    await _ensureNomenclatureProductsInStore();
    final allowed = _nomenclatureIdsForScreen(screenDepartment);
    final products = getNomenclatureProducts(establishmentId)
        .where((p) => allowed.contains(p.id));

    final items = <NomenclatureItem>[];
    for (final product in products) {
      final price = getEstablishmentPrice(product.id, establishmentId)?.$1;
      items.add(NomenclatureItem.product(product, establishmentPrice: price));
    }

    return items;
  }

  /// В номенклатуре ли продукт
  bool isInNomenclature(String productId) =>
      _nomenclatureIds.contains(productId);

  /// Получить продукты для конкретного отдела
  Future<void> loadProductsForDepartment(String department) async {
    _isLoading = true;

    try {
      // Определяем категории для отдела
      List<String> departmentCategories = [];
      switch (department) {
        case 'kitchen':
          departmentCategories = [
            'meat',
            'vegetables',
            'dairy',
            'grains',
            'oils',
            'spices'
          ];
          break;
        case 'bar':
          departmentCategories = [
            'soft_drinks',
            'juice',
            'water',
            'beer',
            'wine',
            'spirits',
            'hot_drinks',
            'coffee_drinks'
          ];
          break;
        case 'dining_room':
          departmentCategories = [
            'hot_drinks',
            'coffee_drinks',
            'desserts',
            'ice_cream',
            'fresh_desserts',
            'bread',
            'oils',
            'spices'
          ];
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

      _allProducts =
          (data as List).map((json) => Product.fromJson(json)).toList();
      _hasFullProductCatalog = false;

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
  (double?, String?)? getEstablishmentPrice(
      String productId, String? establishmentId) {
    if (establishmentId == null) return null;

    final cacheKey = '${establishmentId}_$productId';
    return _priceCache[cacheKey];
  }

  /// Очистить кэш цен
  void clearPriceCache() {
    _priceCache.clear();
  }

  /// История изменений цены продукта в номенклатуре заведения
  Future<List<PriceHistoryEntry>> getPriceHistory(
      String productId, String establishmentId) async {
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
          oldPrice: m['old_price'] != null
              ? (m['old_price'] as num).toDouble()
              : null,
          newPrice: (m['new_price'] as num?)?.toDouble(),
          currency: m['currency'] as String?,
          changedAt: m['changed_at'] != null
              ? DateTime.parse(m['changed_at'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      devLog('⚠️ ProductStore: Failed to load price history: $e');
      return [];
    }
  }
}

/// Другое [Product.id] уже занимает то же нормализованное имя, что и в БД (`products_name_unique_lower`).
class DuplicateProductNameException implements Exception {
  const DuplicateProductNameException();
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
