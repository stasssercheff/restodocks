import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Номенклатура: список продуктов (до 1000+). Поиск, фильтр по категории.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  Future<void> _ensureLoaded() async {
    final store = context.read<ProductStoreSupabase>();
    if (store.allProducts.isEmpty && !store.isLoading) {
      await store.loadProducts();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final products = store.getProducts(
      category: _category,
      searchText: _query.isEmpty ? null : _query,
    );
    final categories = store.categories;
    final total = store.allProducts.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('nomenclature')),
            Text(
              '${loc.t('products')} · $total ${_plural(total)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: store.isLoading ? null : () => _uploadFromTxt(loc),
            tooltip: loc.t('upload_list_tooltip'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: store.isLoading ? null : () async {
              await store.loadProducts();
              if (mounted) setState(() {});
            },
            tooltip: loc.t('refresh'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _Chip(
                    label: 'Все',
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  ...categories.map((c) => _Chip(
                        label: _categoryLabel(c),
                        selected: _category == c,
                        onTap: () => setState(() => _category = _category == c ? null : c),
                      )),
                ],
              ),
            ),
          Expanded(
            child: store.isLoading && store.allProducts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildList(loc, products, total),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFromTxt(LocalizationService loc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл пуст или нет строк')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('upload_list')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.t('upload_confirm').replaceAll('%s', '${lines.length}')),
            const SizedBox(height: 8),
            Text(
              loc.t('upload_txt_format'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.t('save'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final store = context.read<ProductStoreSupabase>();
    var added = 0;
    var failed = 0;
    for (final name in lines) {
      try {
        final product = Product(
          id: const Uuid().v4(),
          name: name,
          category: 'misc',
          names: {'ru': name, 'en': name},
          calories: null,
          protein: null,
          fat: null,
          carbs: null,
          unit: 'кг',
        );
        await store.addProduct(product);
        added++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
    }

    await store.loadProducts();
    if (!mounted) return;
    setState(() {});
    final msg = failed == 0
        ? loc.t('upload_added').replaceAll('%s', '$added')
        : '${loc.t('upload_added').replaceAll('%s', '$added')}. ${loc.t('upload_failed').replaceAll('%s', '$failed')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'наименование';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'наименования';
    return 'наименований';
  }

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи',
      'fruits': 'Фрукты',
      'meat': 'Мясо',
      'seafood': 'Рыба',
      'dairy': 'Молочное',
      'grains': 'Крупы',
      'bakery': 'Выпечка',
      'pantry': 'Бакалея',
      'spices': 'Специи',
      'beverages': 'Напитки',
      'eggs': 'Яйца',
      'legumes': 'Бобовые',
      'nuts': 'Орехи',
      'misc': 'Разное',
    };
    return map[c] ?? c;
  }

  Widget _buildList(LocalizationService loc, List<Product> products, int total) {
    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '${loc.t('nomenclature')}: нет продуктов',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Выполните seed_products.sql в Supabase (см. SETUP_SUPABASE.md).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await context.read<ProductStoreSupabase>().loadProducts();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh),
                label: Text(loc.t('refresh')),
              ),
            ],
          ),
        ),
      );
    }

    if (products.isEmpty) {
      return Center(
        child: Text(
          'По запросу ничего не найдено',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                (i + 1).toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Text(p.name),
            subtitle: Text(
              '${_categoryLabel(p.category)} · ${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
