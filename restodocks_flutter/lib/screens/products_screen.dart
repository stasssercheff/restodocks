import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/nutrition_api_service.dart';
import '../services/services.dart';

/// Экран с двумя вкладками: Номенклатура (продукты заведения) и Справочник (все продукты, добавление в номенклатуру).
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

enum _CatalogSort { nameAz, nameZa, priceAsc, priceDesc }

class _ProductsScreenState extends State<ProductsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';
  String? _category;
  // Справочник: сортировка и фильтры
  _CatalogSort _catalogSort = _CatalogSort.nameAz;
  bool _filterManual = false;
  bool _filterGlutenFree = false;
  bool _filterLactoseFree = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    if (store.allProducts.isEmpty && !store.isLoading) {
      await store.loadProducts();
    }
    await store.loadNomenclature(estId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final account = context.watch<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    final canEdit = account.currentEmployee?.canEditChecklistsAndTechCards ?? false;

    var catalogList = store.getProducts(
      category: _filterManual ? 'manual' : _category,
      searchText: _query.isEmpty ? null : _query,
      glutenFree: _filterGlutenFree ? true : null,
      lactoseFree: _filterLactoseFree ? true : null,
    );
    catalogList = _sortProducts(catalogList, _catalogSort);
    final nomProducts = estId != null
        ? store.getNomenclatureProducts(estId).where((p) {
            if (_category != null && p.category != _category) return false;
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.getLocalizedName(loc.currentLanguageCode).toLowerCase().contains(q);
            }
            return true;
          }).toList()
        : <Product>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('nomenclature')),
            Text(
              _tabController.index == 0
                  ? '${nomProducts.length} в номенклатуре'
                  : '${store.allProducts.length} в справочнике',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: loc.t('nomenclature')),
            Tab(text: loc.t('product_catalog')),
          ],
          onTap: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _ensureLoaded();
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
          if (store.categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _Chip(
                    label: 'Все',
                    selected: _category == null && !_filterManual,
                    onTap: () => setState(() {
                      _category = null;
                      _filterManual = false;
                    }),
                  ),
                  ...store.categories.where((c) => c != 'misc').map((c) => _Chip(
                        label: _categoryLabel(c),
                        selected: _category == c && !_filterManual,
                        onTap: () => setState(() {
                          _category = _category == c ? null : c;
                          _filterManual = false;
                        }),
                      )),
                  if (store.allProducts.any((p) => p.category == 'manual'))
                    _Chip(
                      label: _categoryLabel('manual'),
                      selected: _filterManual,
                      onTap: () => setState(() {
                        _filterManual = !_filterManual;
                        if (_filterManual) _category = null;
                      }),
                    ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _NomenclatureTab(
                  products: nomProducts,
                  store: store,
                  estId: estId ?? '',
                  canRemove: canEdit,
                  loc: loc,
                  onRefresh: () => _ensureLoaded().then((_) => setState(() {})),
                  onSwitchToCatalog: () {
                    _tabController.animateTo(1);
                    setState(() {});
                  },
                ),
                _CatalogTab(
                  products: catalogList,
                  store: store,
                  estId: estId ?? '',
                  loc: loc,
                  sort: _catalogSort,
                  filterManual: _filterManual,
                  filterGlutenFree: _filterGlutenFree,
                  filterLactoseFree: _filterLactoseFree,
                  onSortChanged: (s) => setState(() => _catalogSort = s),
                  onFilterManualChanged: (v) => setState(() => _filterManual = v),
                  onFilterGlutenChanged: (v) => setState(() => _filterGlutenFree = v),
                  onFilterLactoseChanged: (v) => setState(() => _filterLactoseFree = v),
                  onRefresh: () => _ensureLoaded().then((_) => setState(() {})),
                  onUpload: () => _uploadFromTxt(loc),
                  onPaste: () => _showPasteDialog(loc),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _sortProducts(List<Product> list, _CatalogSort sort) {
    final copy = List<Product>.from(list);
    switch (sort) {
      case _CatalogSort.nameAz:
        copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _CatalogSort.nameZa:
        copy.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _CatalogSort.priceAsc:
        copy.sort((a, b) => (a.basePrice ?? 0).compareTo(b.basePrice ?? 0));
        break;
      case _CatalogSort.priceDesc:
        copy.sort((a, b) => (b.basePrice ?? 0).compareTo(a.basePrice ?? 0));
        break;
    }
    return copy;
  }

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное', 'manual': 'Добавлено вручную',
    };
    return map[c] ?? c;
  }

  ({String name, double? price}) _parseLine(String line) {
    final parts = line.split('\t');
    final name = parts[0].trim();
    if (name.isEmpty) return (name: '', price: null);
    if (parts.length < 2) return (name: name, price: null);
    final priceStr = parts[1]
        .replaceAll('₫', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();
    final price = double.tryParse(priceStr);
    return (name: name, price: price);
  }

  Future<void> _showPasteDialog(LocalizationService loc) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('paste_list')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.t('upload_txt_format'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText: 'Авокадо\t₫99,000\nАнчоус\t₫1,360,000\n...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(loc.t('save')),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _addProductsFromText(text, loc);
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
    if (text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл пуст')));
      return;
    }
    await _addProductsFromText(text, loc);
  }

  Future<void> _addProductsFromText(String text, LocalizationService loc) async {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final items = lines.map(_parseLine).where((r) => r.name.isNotEmpty).toList();
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет строк для добавления')));
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
            Text(loc.t('upload_confirm').replaceAll('%s', '${items.length}')),
            const SizedBox(height: 4),
            Text(
              loc.t('upload_add_to_nomenclature_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
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
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет заведения')));
      return;
    }

    var added = 0;
    var failed = 0;
    for (final item in items) {
      try {
        final product = Product(
          id: const Uuid().v4(),
          name: item.name,
          category: 'manual',
          names: {'ru': item.name, 'en': item.name},
          calories: null,
          protein: null,
          fat: null,
          carbs: null,
          unit: 'кг',
          basePrice: item.price,
          currency: item.price != null ? 'VND' : null,
        );
        await store.addProduct(product);
        await store.addToNomenclature(estId, product.id);
        added++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
    }
    await store.loadProducts();
    await store.loadNomenclature(estId);
    if (!mounted) return;
    setState(() {});
    final msg = failed == 0
        ? loc.t('upload_added').replaceAll('%s', '$added')
        : '${loc.t('upload_added').replaceAll('%s', '$added')}. ${loc.t('upload_failed').replaceAll('%s', '$failed')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _NomenclatureTab extends StatelessWidget {
  const _NomenclatureTab({
    required this.products,
    required this.store,
    required this.estId,
    required this.canRemove,
    required this.loc,
    required this.onRefresh,
    required this.onSwitchToCatalog,
  });

  final List<Product> products;
  final ProductStoreSupabase store;
  final String estId;
  final bool canRemove;
  final LocalizationService loc;
  final VoidCallback onRefresh;
  final VoidCallback onSwitchToCatalog;

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное',
    };
    return map[c] ?? c;
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '${loc.t('nomenclature')}: пусто',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('add_from_catalog'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onSwitchToCatalog,
                icon: const Icon(Icons.add),
                label: Text(loc.t('add_from_catalog')),
              ),
            ],
          ),
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
            title: Text(p.getLocalizedName(loc.currentLanguageCode)),
            subtitle: Text(
              (p.category == 'misc' || p.category == 'manual')
                  ? '${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}'
                  : '${_categoryLabel(p.category)} · ${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: canRemove
                ? IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    tooltip: loc.t('remove_from_nomenclature'),
                    onPressed: () => _confirmRemove(context, p),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('remove_from_nomenclature')),
        content: Text(
          loc.t('remove_from_nomenclature_confirm').replaceAll('%s', p.getLocalizedName(loc.currentLanguageCode)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await store.removeFromNomenclature(estId, p.id);
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({
    required this.products,
    required this.store,
    required this.estId,
    required this.loc,
    required this.sort,
    required this.filterManual,
    required this.filterGlutenFree,
    required this.filterLactoseFree,
    required this.onSortChanged,
    required this.onFilterManualChanged,
    required this.onFilterGlutenChanged,
    required this.onFilterLactoseChanged,
    required this.onRefresh,
    required this.onUpload,
    required this.onPaste,
  });

  final List<Product> products;
  final ProductStoreSupabase store;
  final String estId;
  final LocalizationService loc;
  final _CatalogSort sort;
  final bool filterManual;
  final bool filterGlutenFree;
  final bool filterLactoseFree;
  final void Function(_CatalogSort) onSortChanged;
  final void Function(bool) onFilterManualChanged;
  final void Function(bool) onFilterGlutenChanged;
  final void Function(bool) onFilterLactoseChanged;
  final VoidCallback onRefresh;
  final VoidCallback onUpload;
  final VoidCallback onPaste;

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное', 'manual': 'Добавлено вручную',
    };
    return map[c] ?? c;
  }

  Future<void> _addAllToNomenclature(BuildContext context, List<Product> list) async {
    try {
      for (final p in list) {
        await store.addToNomenclature(estId, p.id);
      }
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('add_all_done').replaceAll('%s', '${list.length}'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notInNom = products.where((p) => !store.isInNomenclature(p.id)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: onPaste,
                tooltip: loc.t('paste_list_tooltip'),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file),
                onPressed: onUpload,
                tooltip: loc.t('upload_list_tooltip'),
              ),
              PopupMenuButton<_CatalogSort>(
                icon: const Icon(Icons.sort),
                tooltip: 'Сортировка',
                onSelected: onSortChanged,
                itemBuilder: (_) => [
                  PopupMenuItem(value: _CatalogSort.nameAz, child: Text(loc.t('sort_name_az'))),
                  PopupMenuItem(value: _CatalogSort.nameZa, child: Text(loc.t('sort_name_za'))),
                  PopupMenuItem(value: _CatalogSort.priceAsc, child: Text(loc.t('sort_price_asc'))),
                  PopupMenuItem(value: _CatalogSort.priceDesc, child: Text(loc.t('sort_price_desc'))),
                ],
              ),
              FilterChip(
                label: Text(loc.t('filter_gluten_free'), style: const TextStyle(fontSize: 11)),
                selected: filterGlutenFree,
                onSelected: onFilterGlutenChanged,
              ),
              FilterChip(
                label: Text(loc.t('filter_lactose_free'), style: const TextStyle(fontSize: 11)),
                selected: filterLactoseFree,
                onSelected: onFilterLactoseChanged,
              ),
            ],
          ),
        ),
        if (notInNom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton.tonalIcon(
              onPressed: () => _addAllToNomenclature(context, notInNom),
              icon: const Icon(Icons.add_circle, size: 20),
              label: Text(loc.t('add_all_to_nomenclature').replaceAll('%s', '${notInNom.length}')),
            ),
          ),
        Expanded(
          child: store.allProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Справочник пуст',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Загрузите список или вставьте текст (название + таб + цена).',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onUpload,
                          icon: const Icon(Icons.upload_file),
                          label: Text(loc.t('upload_list')),
                        ),
                      ],
                    ),
                  ),
                )
              : products.isEmpty
                  ? Center(
                      child: Text(
                        'По запросу ничего не найдено',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: products.length,
                      itemBuilder: (_, i) {
                        final p = products[i];
                        final inNom = store.isInNomenclature(p.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: inNom
                                  ? Colors.green.shade100
                                  : Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(
                                inNom ? Icons.check : Icons.add,
                                color: inNom ? Colors.green : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(p.getLocalizedName(loc.currentLanguageCode)),
                            subtitle: Text(
                              p.category == 'misc'
                                  ? '${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}'
                                  : '${_categoryLabel(p.category)} · ${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((p.calories == null || p.calories == 0) &&
                                    (p.protein == null && p.fat == null && p.carbs == null))
                                  IconButton(
                                    icon: const Icon(Icons.cloud_download),
                                    tooltip: loc.t('load_kbju_from_web'),
                                    onPressed: () => _fetchKbju(context, p),
                                  ),
                                if (inNom)
                                  Chip(
                                    label: Text(loc.t('nomenclature'), style: const TextStyle(fontSize: 11)),
                                  )
                                else
                                  FilledButton.tonal(
                                    onPressed: () => _addToNomenclature(context, p),
                                    child: Text(loc.t('add_to_nomenclature')),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _addToNomenclature(BuildContext context, Product p) async {
    try {
      await store.addToNomenclature(estId, p.id);
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _fetchKbju(BuildContext context, Product p) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('Поиск КБЖУ...')));
    final result = await NutritionApiService.fetchNutrition(p.getLocalizedName(loc.currentLanguageCode));
    if (!context.mounted) return;
    if (result == null || !result.hasData) {
      scaffold.showSnackBar(const SnackBar(content: Text('КБЖУ не найдены')));
      return;
    }
    try {
      final updated = p.copyWith(
        calories: result.calories ?? p.calories,
        protein: result.protein ?? p.protein,
        fat: result.fat ?? p.fat,
        carbs: result.carbs ?? p.carbs,
      );
      await store.updateProduct(updated);
      onRefresh();
      scaffold.showSnackBar(SnackBar(
        content: Text(
          'КБЖУ: ${result.calories?.round() ?? 0} ккал, Б ${result.protein?.round() ?? 0} / Ж ${result.fat?.round() ?? 0} / У ${result.carbs?.round() ?? 0}',
        ),
      ));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
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
