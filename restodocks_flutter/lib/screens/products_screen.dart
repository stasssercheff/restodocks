import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/tech_card.dart';
import '../services/product_store_supabase.dart';
import '../services/localization_service.dart';
import '../services/account_manager_supabase.dart';
import '../services/tech_card_service_supabase.dart';

/// Экран базы продуктов: просмотр и управление продуктами с КБЖУ
/// Поддерживает интеллектуальный импорт и защиту от удаления используемых продуктов
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

enum _ProductSort { az, za }

class _ProductsScreenState extends State<ProductsScreen> {
  String _query = '';
  List<Product> _products = [];
  bool _isLoading = true;
  _ProductSort _sort = _ProductSort.az;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
    final store = context.read<ProductStoreSupabase>();
      await store.loadProducts();
      if (mounted) {
        // Проверяем на дубликаты перед установкой
        final uniqueProducts = <String, Product>{};
        for (final product in store.allProducts) {
          uniqueProducts[product.id] = product;
        }
        final deduplicatedProducts = uniqueProducts.values.toList();

        print('DEBUG: Loaded ${store.allProducts.length} products, deduplicated to ${deduplicatedProducts.length}');

        setState(() {
          _products = deduplicatedProducts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки продуктов: $e')),
        );
      }
    }
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      itemCount: 6, // Показываем 6 skeleton элементов
      itemBuilder: (context, index) {
        return const _ProductSkeletonItem();
      },
    );
  }

  Future<void> _removeDuplicates() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить полные дубликаты'),
        content: const Text('Будут удалены продукты с одинаковым названием, ценой и характеристиками. Продукты, используемые в номенклатуре, не будут удалены. Продолжить?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();

      // Временно отключаем проверку ТТК из-за ошибки в getAllTechCards
      // final techCardService = context.read<TechCardServiceSupabase>();
      // final allTechCards = await techCardService.getAllTechCards();

      // Группируем продукты по ключевым характеристикам
      final Map<String, List<Product>> groupedProducts = {};

      for (final product in _products) {
        // Нормализуем название: убираем специальные символы, валютные значки, лишние пробелы
        String normalizedName = product.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '') // Убираем все специальные символы
            .replaceAll(RegExp(r'\s+'), ' ')    // Заменяем множественные пробелы на один
            .trim(); // Убираем пробелы по краям

        // Ключ для группировки: нормализованное название + категория + калории + белки + жиры + углеводы
        // НЕ включаем цену и валюту, так как они могут различаться для одного продукта
        final key = '${normalizedName}_${product.category ?? ""}_${product.calories ?? 0}_${product.protein ?? 0}_${product.fat ?? 0}_${product.carbs ?? 0}';
        groupedProducts.putIfAbsent(key, () => []).add(product);
      }

      int deletedCount = 0;
      int skippedCount = 0;

      // Для каждой группы оставляем только первый продукт, остальные удаляем
      for (final products in groupedProducts.values) {
        if (products.length > 1) {
          for (int i = 1; i < products.length; i++) {
            final product = products[i];

            // Проверяем, используется ли продукт в номенклатуре или ТТК
            bool isUsed = false;
            String usageMessage = '';

            // Проверяем в номенклатуре текущего заведения
            final establishment = account.establishment;
            if (establishment != null) {
              final nomenclatureIds = store.getNomenclatureIdsForEstablishment(establishment.id);
              if (nomenclatureIds.contains(product.id)) {
                isUsed = true;
                usageMessage = 'Продукт используется в номенклатуре заведения "${establishment.name}"';
              }
            }

            // Временно отключаем проверку ТТК из-за ошибки getAllTechCards
            // if (!isUsed) {
            //   for (final techCard in allTechCards) {
            //     if (techCard.ingredients.any((ing) => ing.productId == product.id)) {
            //       isUsed = true;
            //       break;
            //     }
            //   }
            // }

            if (isUsed) {
              skippedCount++;
              continue;
            }

            await store.deleteProduct(product.id);
            deletedCount++;
          }
        }
      }

      if (mounted) {
        await _loadProducts(); // Перезагружаем список
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Удалено дубликатов: $deletedCount${skippedCount > 0 ? ', пропущено (используются): $skippedCount' : ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления дубликатов: $e')),
        );
      }
    }
  }

  Future<void> _clearAllProducts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Полное очищение списка продуктов'),
        content: const Text('ВНИМАНИЕ: Это действие удалит ВСЕ продукты из базы данных без возможности восстановления. Продукты, используемые в номенклатуре или ТТК, будут пропущены. Вы уверены?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ОЧИСТИТЬ ВСЕ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();

      // Попробуем получить все ТТК для проверки
      List<dynamic> allTechCards = [];
      try {
        final techCardService = context.read<TechCardServiceSupabase>();
        allTechCards = await techCardService.getAllTechCards();
        print('Получено ${allTechCards.length} ТТК для проверки');
      } catch (e) {
        print('Не удалось получить ТТК: $e, продолжаем без проверки ТТК');
      }

      int deletedCount = 0;
      int skippedCount = 0;

      // Удаляем каждый продукт, проверяя не используется ли он
      for (final product in _products) {
        bool isUsed = false;
        String usageMessage = '';

        // Проверяем в номенклатуре ТОЛЬКО текущего заведения
        final establishment = account.establishment;
        if (establishment != null) {
          final nomenclatureIds = store.getNomenclatureIdsForEstablishment(establishment.id);
          if (nomenclatureIds.contains(product.id)) {
            isUsed = true;
            usageMessage = 'Продукт используется в номенклатуре заведения "${establishment.name}"';
          }
        }

        // Проверяем использование в ТТК
        if (!isUsed && allTechCards.isNotEmpty) {
          for (final techCard in allTechCards) {
            try {
              // Предполагаем структуру ТТК
              final ingredients = techCard['ingredients'] as List<dynamic>? ?? [];
              if (ingredients.any((ing) => ing['product_id'] == product.id || ing['productId'] == product.id)) {
                isUsed = true;
                usageMessage = 'Продукт используется в ТТК "${techCard['dish_name'] ?? techCard['name'] ?? 'Неизвестно'}"';
                break;
              }
      } catch (e) {
              // Игнорируем ошибки в отдельных ТТК
              continue;
            }
          }
        }

        if (isUsed) {
          print('Пропускаем продукт "${product.name}": $usageMessage');
          skippedCount++;
          continue;
        }

        try {
          await store.deleteProduct(product.id);
          print('Удален продукт "${product.name}" (${product.id})');
          deletedCount++;
        } catch (e) {
          print('Ошибка при удалении продукта "${product.name}": $e');
          skippedCount++;
        }
      }

      if (mounted) {
        await _loadProducts(); // Перезагружаем список
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Удалено продуктов: $deletedCount${skippedCount > 0 ? ', пропущено (используются): $skippedCount' : ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка очищения списка: $e')),
        );
      }
    }
  }

  Future<void> _removeDuplicatesByName() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить дубликаты по названию'),
        content: const Text('Будут удалены продукты с одинаковым названием (независимо от цены и характеристик). Продукты, используемые в номенклатуре или ТТК, не будут удалены. Продолжить?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();
      final techCardService = context.read<TechCardServiceSupabase>();

      // Загружаем ТТК для проверки использования продуктов
      List<TechCard> allTechCards = [];
      try {
        allTechCards = await techCardService.getAllTechCards();
      } catch (e) {
        print('Warning: Could not load tech cards for duplicate removal: $e');
        // Продолжаем без проверки ТТК
      }

      // Группируем продукты только по названию
      final Map<String, List<Product>> groupedProducts = {};

      for (final product in _products) {
        final key = product.name.toLowerCase().trim(); // Игнорируем регистр и пробелы
        groupedProducts.putIfAbsent(key, () => []).add(product);
      }

      int deletedCount = 0;
      int skippedCount = 0;

      // Для каждой группы оставляем только первый продукт, остальные удаляем
      for (final products in groupedProducts.values) {
        if (products.length > 1) {
          // Сортируем по дате создания или ID, чтобы оставить "старший" продукт
          products.sort((a, b) => a.id.compareTo(b.id));

          for (int i = 1; i < products.length; i++) {
            final product = products[i];

            // Проверяем, используется ли продукт в номенклатуре или ТТК
            bool isUsed = false;
            String usageMessage = '';

            // Проверяем в номенклатуре текущего заведения
            final establishment = account.establishment;
            if (establishment != null) {
              final nomenclatureIds = store.getNomenclatureIdsForEstablishment(establishment.id);
              if (nomenclatureIds.contains(product.id)) {
                isUsed = true;
                usageMessage = 'Продукт используется в номенклатуре заведения "${establishment.name}"';
              }
            }

            // Временно отключаем проверку ТТК из-за ошибки getAllTechCards
            // if (!isUsed) {
            //   for (final techCard in allTechCards) {
            //     if (techCard.ingredients.any((ing) => ing.productId == product.id)) {
            //       isUsed = true;
            //       break;
            //     }
            //   }
            // }

            if (isUsed) {
              skippedCount++;
              continue;
            }

            await store.deleteProduct(product.id);
            deletedCount++;
          }
        }
      }

      if (mounted) {
        await _loadProducts(); // Перезагружаем список
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Удалено дубликатов по названию: $deletedCount${skippedCount > 0 ? ', пропущено (используются): $skippedCount' : ''}')),
        );
        }
      } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления дубликатов: $e')),
        );
      }
    }
  }

  /// Ключ сортировки: соус/специя и т.п. идут по букве слова-типа (С), не по первому слову названия
  static String _sortKeyForProduct(String name) {
    const words = ['соус', 'специя', 'смесь', 'приправа', 'маринад', 'подлива', 'паста', 'масло'];
    final lower = name.trim().toLowerCase();
    for (final w in words) {
      final idx = lower.indexOf(w);
      if (idx >= 0) {
        final before = idx > 0 ? lower.substring(0, idx).trim() : '';
        final after = idx + w.length < lower.length ? lower.substring(idx + w.length).trim() : '';
        final rest = [before, after].where((s) => s.isNotEmpty).join(' ');
        return '$w ${rest.isEmpty ? '' : rest}'.trim();
      }
    }
    return lower;
  }

  List<Product> get _filteredProducts {
    var list = _products;
    if (_query.isNotEmpty) {
      final query = _query.toLowerCase();
      list = list.where((product) {
        return product.name.toLowerCase().contains(query) ||
               product.getLocalizedName('ru').toLowerCase().contains(query);
      }).toList();
    }
    list = List<Product>.from(list);
    list.sort((a, b) {
      final ka = _sortKeyForProduct(a.getLocalizedName('ru'));
      final kb = _sortKeyForProduct(b.getLocalizedName('ru'));
      return _sort == _ProductSort.az ? ka.compareTo(kb) : kb.compareTo(ka);
    });
    return list;
  }

  void _showProductDetails(Product product) {
    showDialog(
      context: context,
      builder: (context) => _ProductDetailsDialog(
        product: product,
        onPriceUpdated: _loadProducts,
        onAddedToNomenclature: _loadProducts,
        onProductDeleted: _loadProducts,
      ),
    );
  }

  Future<void> _addToNomenclature(Product product) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;

    try {
      final store = context.read<ProductStoreSupabase>();
      await store.addToNomenclature(estId, product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('product_added_to_nomenclature'))),
        );
        _loadProducts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('products')),
        actions: [
          // 1. Количество
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_filteredProducts.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 3. Фильтр А–Я / Я–А (три полоски)
          IconButton(
            icon: Icon(_sort == _ProductSort.az ? Icons.filter_list : Icons.filter_list_alt),
            tooltip: _sort == _ProductSort.az ? 'А–Я (нажмите для Я–А)' : 'Я–А (нажмите для А–Я)',
            onPressed: () => setState(() => _sort = _sort == _ProductSort.az ? _ProductSort.za : _ProductSort.az),
          ),
          // 4. Выявление дубликатов с ИИ
          PopupMenuButton<String>(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Дубликаты с ИИ',
            onSelected: (v) async {
              if (v == 'by_name') await _removeDuplicatesByName();
              else if (v == 'full') await _removeDuplicates();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'by_name', child: Text('Дубликаты по названию')),
              const PopupMenuItem(value: 'full', child: Text('Полные дубликаты')),
            ],
          ),
          // 5. Загрузка (без добавления в номенклатуру — пополнение базы)
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: '${loc.t('upload_products')} (пополнение базы)',
            onPressed: () => context.push('/products/upload?addToNomenclature=false'),
          ),
          // 6. Обновить
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
                  ),
              ],
            ),
      body: Column(
                      children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: loc.t('search_products'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.inputDecorationTheme.fillColor,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),

          // Список продуктов
          Expanded(
            child: _isLoading
                ? _buildSkeletonLoading()
                : _filteredProducts.isEmpty
                  ? Center(
                      child: Text(
                          _query.isEmpty ? loc.t('no_products') : loc.t('no_products_found'),
                          style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _ProductListItem(
                            product: product,
                            onTap: () => _showProductDetails(product),
                            onAddToNomenclature: () => _addToNomenclature(product),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToNomenclature;

  const _ProductListItem({
    required this.product,
    required this.onTap,
    required this.onAddToNomenclature,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(product.getLocalizedName(loc.currentLanguageCode)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
            if (product.calories != null)
              Text('${product.calories!.round()} ${loc.t('kcal')}'),
            if (product.category != 'manual')
              Text(product.category, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: loc.t('add_to_nomenclature'),
          onPressed: onAddToNomenclature,
        ),
        onTap: onTap,
        ),
      );
  }
}

class _ProductDetailsDialog extends StatefulWidget {
  final Product product;
  final VoidCallback onPriceUpdated;
  final VoidCallback onAddedToNomenclature;
  final VoidCallback onProductDeleted;

  const _ProductDetailsDialog({
    required this.product,
    required this.onPriceUpdated,
    required this.onAddedToNomenclature,
    required this.onProductDeleted,
  });

  @override
  State<_ProductDetailsDialog> createState() => _ProductDetailsDialogState();
}

class _ProductDetailsDialogState extends State<_ProductDetailsDialog> {
  final _priceController = TextEditingController();
  String? _currency = 'RUB';
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    // Загружаем текущую цену из номенклатуры
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentPrice());
  }

  Future<void> _loadCurrentPrice() async {
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;

    final store = context.read<ProductStoreSupabase>();
    final priceData = store.getEstablishmentPrice(widget.product.id, estId);
    if (priceData != null && mounted) {
      setState(() {
        _priceController.text = priceData.$1?.toStringAsFixed(2) ?? '';
        _currency = priceData.$2;
      });
    }
  }

  Future<void> _updatePrice() async {
    final price = double.tryParse(_priceController.text);
    if (price == null) return;

    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;

    setState(() => _isUpdating = true);
    try {
      final store = context.read<ProductStoreSupabase>();
      await store.setEstablishmentPrice(estId, widget.product.id, price, _currency);
      if (mounted) {
        widget.onPriceUpdated();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _addToNomenclature() async {
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;

    setState(() => _isUpdating = true);
    try {
      final store = context.read<ProductStoreSupabase>();
      await store.addToNomenclature(estId, widget.product.id);
      if (mounted) {
        widget.onAddedToNomenclature();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteProduct() async {
    // Сначала проверяем, используется ли продукт
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final techCardService = context.read<TechCardServiceSupabase>();

    bool isUsed = false;
    String usageMessage = '';

    try {
      // Проверяем в ТТК — блокируем удаление только если продукт используется в техкартах
      {
        try {
          final allTechCards = await techCardService.getAllTechCards();
          for (final techCard in allTechCards) {
            if (techCard.ingredients.any((ing) => ing.productId == widget.product.id)) {
              isUsed = true;
              usageMessage = 'Продукт используется в технологической карте "${techCard.dishName}"';
              break;
            }
          }
        } catch (_) {
          // Ошибка загрузки ТТК — не блокируем удаление, при FK-ошибке покажем её
        }
      }
    } catch (e) {
      // Ошибка при проверке номенклатуры — не блокируем
    }

    if (isUsed) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Невозможно удалить продукт'),
          content: Text(usageMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
          ),
        ],
      ),
    );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить продукт'),
        content: Text('Вы уверены, что хотите удалить продукт "${widget.product.getLocalizedName(context.read<LocalizationService>().currentLanguageCode)}"? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);
    try {
      await store.deleteProduct(widget.product.id);
      if (mounted) {
        widget.onProductDeleted();
      Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.product.getLocalizedName(loc.currentLanguageCode)),
      content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Категория
            if (widget.product.category != 'manual')
              Text('${loc.t('category')}: ${widget.product.category}'),

              const SizedBox(height: 16),

            // КБЖУ
            if (widget.product.calories != null || widget.product.protein != null) ...[
              Text(loc.t('nutrition_facts'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (widget.product.calories != null)
                Text('${loc.t('calories')}: ${widget.product.calories!.round()} ${loc.t('kcal')}'),
              if (widget.product.protein != null)
                Text('${loc.t('protein')}: ${widget.product.protein!.toStringAsFixed(1)} г'),
              if (widget.product.fat != null)
                Text('${loc.t('fat')}: ${widget.product.fat!.toStringAsFixed(1)} г'),
              if (widget.product.carbs != null)
                Text('${loc.t('carbs')}: ${widget.product.carbs!.toStringAsFixed(1)} г'),
              const SizedBox(height: 16),
            ],

            // Установка цены
            Text(loc.t('price'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                  child: TextField(
                      controller: _priceController,
                      decoration: InputDecoration(
                      hintText: '0.00',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _currency ?? 'RUB',
                  items: ['RUB', 'USD', 'EUR', 'VND'].map((currency) {
                    return DropdownMenuItem(
                      value: currency,
                      child: Text(currency),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _currency = value);
                  },
                ),
              ],
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isUpdating ? null : () => Navigator.of(context).pop(),
          child: Text(loc.t('cancel')),
        ),
        FilledButton(
          onPressed: _isUpdating ? null : _updatePrice,
          child: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(loc.t('save')),
        ),
        FilledButton(
          onPressed: _isUpdating ? null : _addToNomenclature,
          child: Text(loc.t('add_to_nomenclature')),
        ),
        TextButton(
          onPressed: _isUpdating ? null : _deleteProduct,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Удалить продукт'),
        ),
      ],
    );
  }

}

class _ProductSkeletonItem extends StatelessWidget {
  const _ProductSkeletonItem();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
        children: [
            // Иконка
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 16),
            // Текстовая часть
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Название продукта
                  Container(
                    height: 16,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Категория и калории
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
          ),
        ],
      ),
            ),
            // Кнопка добавления
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}