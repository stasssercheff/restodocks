import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../services/product_store_supabase.dart';
import '../services/localization_service.dart';
import '../services/account_manager_supabase.dart';

/// Экран базы продуктов: просмотр и управление продуктами с КБЖУ
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _query = '';
  List<Product> _products = [];
  bool _isLoading = true;

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
        setState(() {
          _products = store.allProducts;
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

  List<Product> get _filteredProducts {
    if (_query.isEmpty) return _products;
    final query = _query.toLowerCase();
    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
             product.getLocalizedName('ru').toLowerCase().contains(query);
    }).toList();
  }

  void _showProductDetails(Product product) {
    showDialog(
      context: context,
      builder: (context) => _ProductDetailsDialog(
        product: product,
        onPriceUpdated: _loadProducts,
        onAddedToNomenclature: _loadProducts,
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
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: loc.t('upload_products'),
            onPressed: () => context.push('/products/upload'),
          ),
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

  const _ProductDetailsDialog({
    required this.product,
    required this.onPriceUpdated,
    required this.onAddedToNomenclature,
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
      ],
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      itemCount: 6, // Показываем 6 skeleton элементов
      itemBuilder: (context, index) {
        return const _ProductSkeletonItem();
      },
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