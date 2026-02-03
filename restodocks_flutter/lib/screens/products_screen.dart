import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/culinary_units.dart';
import '../models/models.dart';
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
  // Фильтры номенклатуры
  _CatalogSort _nomSort = _CatalogSort.nameAz;
  bool _nomFilterGlutenFree = false;
  bool _nomFilterLactoseFree = false;

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
    var nomProducts = estId != null
        ? store.getNomenclatureProducts(estId).where((p) {
            if (_category != null && p.category != _category) return false;
            if (_nomFilterGlutenFree && !p.isGlutenFree) return false;
            if (_nomFilterLactoseFree && !p.isLactoseFree) return false;
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.getLocalizedName(loc.currentLanguageCode).toLowerCase().contains(q);
            }
            return true;
          }).toList()
        : <Product>[];
    nomProducts = _sortProducts(nomProducts, _nomSort);

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
            icon: const Icon(Icons.attach_money),
            onPressed: account.establishment != null ? () => _showCurrencyDialog(context, loc, account, store) : null,
            tooltip: loc.t('default_currency'),
          ),
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
                  sort: _nomSort,
                  filterGlutenFree: _nomFilterGlutenFree,
                  filterLactoseFree: _nomFilterLactoseFree,
                  onSortChanged: (s) => setState(() => _nomSort = s),
                  onFilterGlutenChanged: (v) => setState(() => _nomFilterGlutenFree = v),
                  onFilterLactoseChanged: (v) => setState(() => _nomFilterLactoseFree = v),
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
    final defCur = account.establishment?.defaultCurrency ?? 'VND';
    final sourceLang = loc.currentLanguageCode;
    final allLangs = LocalizationService.productLanguageCodes;
    for (final item in items) {
      try {
        var names = <String, String>{for (final c in allLangs) c: item.name};
        if (items.length <= 5) {
          final translated = await TranslationService.translateToAll(item.name, sourceLang, allLangs);
          if (translated.isNotEmpty) names = translated;
        }
        final product = Product(
          id: const Uuid().v4(),
          name: item.name,
          category: 'manual',
          names: names,
          calories: null,
          protein: null,
          fat: null,
          carbs: null,
          unit: 'g',
          basePrice: item.price,
          currency: item.price != null ? defCur : null,
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

  void _showCurrencyDialog(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase account,
    ProductStoreSupabase store,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CurrencySettingsDialog(
        establishment: account.establishment!,
        store: store,
        loc: loc,
        onSaved: (Establishment updated) async {
          await account.updateEstablishment(updated);
          if (context.mounted) setState(() {});
        },
        onApplyToAll: (currency) async {
          await store.bulkUpdateCurrency(currency);
          await store.loadProducts();
          if (context.mounted) setState(() {});
        },
      ),
    );
  }
}

class _NomenclatureTab extends StatelessWidget {
  const _NomenclatureTab({
    required this.products,
    required this.store,
    required this.estId,
    required this.canRemove,
    required this.loc,
    required this.sort,
    required this.filterGlutenFree,
    required this.filterLactoseFree,
    required this.onSortChanged,
    required this.onFilterGlutenChanged,
    required this.onFilterLactoseChanged,
    required this.onRefresh,
    required this.onSwitchToCatalog,
  });

  final List<Product> products;
  final ProductStoreSupabase store;
  final String estId;
  final bool canRemove;
  final LocalizationService loc;
  final _CatalogSort sort;
  final bool filterGlutenFree;
  final bool filterLactoseFree;
  final void Function(_CatalogSort) onSortChanged;
  final void Function(bool) onFilterGlutenChanged;
  final void Function(bool) onFilterLactoseChanged;
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

  bool _needsKbju(Product p) =>
      (p.calories == null || p.calories == 0) && p.protein == null && p.fat == null && p.carbs == null;

  bool _needsTranslation(Product p) {
    final allLangs = LocalizationService.productLanguageCodes;
    final n = p.names;
    if (n == null || n.isEmpty) return true;
    if (allLangs.any((c) => (n[c] ?? '').trim().isEmpty)) return true;
    // Ручные продукты с одинаковым текстом во всех языках — не переведены
    if (p.category == 'manual') {
      final vals = allLangs.map((c) => (n[c] ?? '').trim()).where((s) => s.isNotEmpty).toSet();
      if (vals.length <= 1) return true;
    }
    return false;
  }

  Future<void> _loadKbjuForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadKbjuProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  Future<void> _loadTranslationsForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadTranslationsProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _NomenclatureEmpty(
        loc: loc,
        onSwitchToCatalog: onSwitchToCatalog,
      );
    }

    final needsKbju = products.where((p) => p.category == 'manual' && _needsKbju(p)).toList();
    final needsTranslation = products.where(_needsTranslation).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              PopupMenuButton<_CatalogSort>(
                icon: const Icon(Icons.sort),
                tooltip: loc.t('sort_name_az').split(' ').take(2).join(' '),
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
        if (needsKbju.isNotEmpty || needsTranslation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (needsKbju.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadKbjuForAll(context, needsKbju),
                    icon: const Icon(Icons.cloud_download, size: 20),
                    label: Text(loc.t('load_kbju_for_all').replaceAll('%s', '${needsKbju.length}')),
                  ),
                if (needsTranslation.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadTranslationsForAll(context, needsTranslation),
                    icon: const Icon(Icons.translate, size: 20),
                    label: Text(loc.t('translate_names_for_all').replaceAll('%s', '${needsTranslation.length}')),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: loc.t('edit_product'),
                        onPressed: () => _showEditProduct(context, p),
                      ),
                      if (canRemove)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          tooltip: loc.t('remove_from_nomenclature'),
                          onPressed: () => _confirmRemove(context, p),
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

  void _showEditProduct(BuildContext context, Product p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditDialog(
        product: p,
        store: store,
        loc: loc,
        onSaved: onRefresh,
      ),
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

class _NomenclatureEmpty extends StatelessWidget {
  const _NomenclatureEmpty({
    required this.loc,
    required this.onSwitchToCatalog,
  });

  final LocalizationService loc;
  final VoidCallback onSwitchToCatalog;

  @override
  Widget build(BuildContext context) {
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
}

class _AddAllProgressDialog extends StatefulWidget {
  const _AddAllProgressDialog({
    required this.list,
    required this.store,
    required this.estId,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final String estId;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_AddAllProgressDialog> createState() => _AddAllProgressDialogState();
}

class _AddAllProgressDialogState extends State<_AddAllProgressDialog> {
  int _done = 0;
  bool _finished = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      if (_error != null) break;
      try {
        await widget.store.addToNomenclature(widget.estId, p.id);
        if (!mounted) return;
        setState(() => _done++);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e);
        widget.onError(e);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('add_all_to_nomenclature').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '$_done / $total',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Ошибка: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadKbjuProgressDialog extends StatefulWidget {
  const _LoadKbjuProgressDialog({
    required this.list,
    required this.store,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_LoadKbjuProgressDialog> createState() => _LoadKbjuProgressDialogState();
}

class _LoadKbjuProgressDialogState extends State<_LoadKbjuProgressDialog> {
  int _done = 0;
  int _updated = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      try {
        final result = await NutritionApiService.fetchNutrition(p.getLocalizedName(widget.loc.currentLanguageCode));
        if (!mounted) return;
        if (result != null && result.hasData) {
          final updated = p.copyWith(
            calories: result.calories ?? p.calories,
            protein: result.protein ?? p.protein,
            fat: result.fat ?? p.fat,
            carbs: result.carbs ?? p.carbs,
          );
          await widget.store.updateProduct(updated);
          if (!mounted) return;
          setState(() => _updated++);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('load_kbju_for_all').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text('$_done / $total', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadTranslationsProgressDialog extends StatefulWidget {
  const _LoadTranslationsProgressDialog({
    required this.list,
    required this.store,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_LoadTranslationsProgressDialog> createState() => _LoadTranslationsProgressDialogState();
}

class _LoadTranslationsProgressDialogState extends State<_LoadTranslationsProgressDialog> {
  int _done = 0;
  int _updated = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final allLangs = LocalizationService.productLanguageCodes;
    for (final p in widget.list) {
      try {
        final source = p.names?['ru'] ?? p.names?['en'] ?? p.name;
        if (source.trim().isEmpty) {
          setState(() => _done++);
          continue;
        }
        final missing = allLangs.where((c) => (p.names?[c] ?? '').trim().isEmpty).toList();
        if (missing.isEmpty) {
          setState(() => _done++);
          continue;
        }
        final sourceLang = p.names?['ru'] != null && (p.names!['ru'] ?? '').trim().isNotEmpty
            ? 'ru'
            : (p.names?['en'] != null && (p.names!['en'] ?? '').trim().isNotEmpty ? 'en' : 'ru');
        final merged = Map<String, String>.from(p.names ?? {});
        for (final target in missing) {
          if (target == sourceLang) continue;
          final tr = await TranslationService.translate(source, sourceLang, target);
          if (tr != null && tr.trim().isNotEmpty) merged[target] = tr;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (merged.length > (p.names?.length ?? 0)) {
          final updated = p.copyWith(names: merged);
          await widget.store.updateProduct(updated);
          if (!mounted) return;
          setState(() => _updated++);
        }
      } catch (e) {
        widget.onError(e);
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('translate_names_for_all').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text('$_done / $total', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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

  Future<void> _loadKbjuForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadKbjuProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  Future<void> _addAllToNomenclature(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddAllProgressDialog(
        list: list,
        store: store,
        estId: estId,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(loc.t('add_all_done').replaceAll('%s', '${list.length}'))),
            );
          }
        },
        onError: (e) {
          Navigator.of(ctx).pop();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          }
        },
      ),
    );
  }

  bool _needsKbju(Product p) =>
      (p.calories == null || p.calories == 0) && p.protein == null && p.fat == null && p.carbs == null;

  bool _needsTranslation(Product p) {
    final allLangs = LocalizationService.productLanguageCodes;
    final n = p.names;
    if (n == null || n.isEmpty) return true;
    if (allLangs.any((c) => (n[c] ?? '').trim().isEmpty)) return true;
    // Ручные продукты с одинаковым текстом во всех языках — не переведены
    if (p.category == 'manual') {
      final vals = allLangs.map((c) => (n[c] ?? '').trim()).where((s) => s.isNotEmpty).toSet();
      if (vals.length <= 1) return true;
    }
    return false;
  }

  Future<void> _loadTranslationsForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadTranslationsProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final notInNom = products.where((p) => !store.isInNomenclature(p.id)).toList();
    final needsKbju = store.allProducts.where((p) => p.category == 'manual' && _needsKbju(p)).toList();
    final needsTranslation = store.allProducts.where(_needsTranslation).toList();
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
        if (needsKbju.isNotEmpty || needsTranslation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (needsKbju.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadKbjuForAll(context, needsKbju),
                    icon: const Icon(Icons.cloud_download, size: 20),
                    label: Text(loc.t('load_kbju_for_all').replaceAll('%s', '${needsKbju.length}')),
                  ),
                if (needsTranslation.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadTranslationsForAll(context, needsTranslation),
                    icon: const Icon(Icons.translate, size: 20),
                    label: Text(loc.t('translate_names_for_all').replaceAll('%s', '${needsTranslation.length}')),
                  ),
              ],
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
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: loc.t('edit_product'),
                                  onPressed: () => _showEditProduct(context, p),
                                ),
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

  void _showEditProduct(BuildContext context, Product p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditDialog(
        product: p,
        store: store,
        loc: loc,
        onSaved: onRefresh,
      ),
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
    scaffold.showSnackBar(SnackBar(content: Text(loc.t('kbju_searching'))));
    final result = await NutritionApiService.fetchNutrition(p.getLocalizedName(loc.currentLanguageCode));
    if (!context.mounted) return;
    if (result == null || !result.hasData) {
      scaffold.showSnackBar(SnackBar(content: Text(loc.t('kbju_not_found'))));
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
      var fmt = loc.t('kbju_result_format');
      fmt = fmt.replaceFirst('%s', '${result.calories?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.protein?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.fat?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.carbs?.round() ?? 0}');
      final msg = fmt;
      scaffold.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('${loc.t('error_short')}: $e')));
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

/// Карточка продукта — редактирование единицы измерения, КБЖУ, стоимости
class _ProductEditDialog extends StatefulWidget {
  const _ProductEditDialog({
    required this.product,
    required this.store,
    required this.loc,
    required this.onSaved,
  });

  final Product product;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onSaved;

  static const _currencies = ['RUB', 'USD', 'EUR', 'VND'];

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _wastePctController;
  late String _unit;
  late String _currency;
  late bool _containsGluten;
  late bool _containsLactose;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p.name);
    _priceController = TextEditingController(text: p.basePrice?.toString() ?? '');
    _caloriesController = TextEditingController(text: p.calories?.toString() ?? '');
    _proteinController = TextEditingController(text: p.protein?.toString() ?? '');
    _fatController = TextEditingController(text: p.fat?.toString() ?? '');
    _carbsController = TextEditingController(text: p.carbs?.toString() ?? '');
    _wastePctController = TextEditingController(text: p.primaryWastePct?.toStringAsFixed(1) ?? '0');
    final unitMap = {'кг': 'kg', 'г': 'g', 'шт': 'pcs', 'л': 'l', 'мл': 'ml'};
    _unit = unitMap[p.unit] ?? p.unit ?? 'g';
    if (!CulinaryUnits.all.any((e) => e.id == _unit)) _unit = 'g';
    _currency = p.currency ?? 'VND';
    _containsGluten = p.containsGluten ?? false;
    _containsLactose = p.containsLactose ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _wastePctController.dispose();
    super.dispose();
  }

  double? _parseNum(String v) {
    final s = v.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('product_name_required'))));
      return;
    }
    final curLang = widget.loc.currentLanguageCode;
    final allLangs = LocalizationService.productLanguageCodes;
    final merged = Map<String, String>.from(widget.product.names ?? {});
    merged[curLang] = name;
    for (final c in allLangs) {
      merged.putIfAbsent(c, () => name);
    }
    final updated = widget.product.copyWith(
      name: name,
      names: merged,
      basePrice: _parseNum(_priceController.text),
      currency: _currency,
      unit: _unit,
      primaryWastePct: _parseNum(_wastePctController.text)?.clamp(0.0, 99.9),
      calories: _parseNum(_caloriesController.text),
      protein: _parseNum(_proteinController.text),
      fat: _parseNum(_fatController.text),
      carbs: _parseNum(_carbsController.text),
      containsGluten: _containsGluten,
      containsLactose: _containsLactose,
    );
    try {
      await widget.store.updateProduct(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('product_saved'))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.loc.currentLanguageCode;
    return AlertDialog(
      title: Text(widget.loc.t('edit_product')),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('product_name'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _unit,
                decoration: InputDecoration(
                  labelText: widget.loc.t('unit'),
                  border: const OutlineInputBorder(),
                ),
                items: CulinaryUnits.all.map((e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(lang == 'ru' ? e.ru : e.en),
                )).toList(),
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wastePctController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('waste_pct'),
                  hintText: '0',
                  border: const OutlineInputBorder(),
                  helperText: widget.loc.t('waste_pct_product_hint'),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: widget.loc.t('price'),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: InputDecoration(
                        labelText: widget.loc.t('currency'),
                        border: const OutlineInputBorder(),
                      ),
                      items: _ProductEditDialog._currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(widget.loc.t('kbju_per_100g'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      decoration: InputDecoration(labelText: 'ккал', border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _proteinController,
                      decoration: InputDecoration(labelText: 'Б', border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _fatController,
                      decoration: InputDecoration(labelText: 'Ж', border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsController,
                      decoration: InputDecoration(labelText: 'У', border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: !_containsGluten,
                onChanged: (v) => setState(() => _containsGluten = !(v ?? true)),
                title: Text(widget.loc.t('filter_gluten_free'), style: const TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: !_containsLactose,
                onChanged: (v) => setState(() => _containsLactose = !(v ?? true)),
                title: Text(widget.loc.t('filter_lactose_free'), style: const TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.loc.t('cancel'))),
        FilledButton(onPressed: _save, child: Text(widget.loc.t('save'))),
      ],
    );
  }
}

/// Диалог настройки валюты заведения
class _CurrencySettingsDialog extends StatefulWidget {
  const _CurrencySettingsDialog({
    required this.establishment,
    required this.store,
    required this.loc,
    required this.onSaved,
    required this.onApplyToAll,
  });

  final Establishment establishment;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final Future<void> Function(Establishment) onSaved;
  final Future<void> Function(String) onApplyToAll;

  static const _presetCurrencies = ['RUB', 'USD', 'EUR', 'VND', 'GBP'];

  @override
  State<_CurrencySettingsDialog> createState() => _CurrencySettingsDialogState();
}

class _CurrencySettingsDialogState extends State<_CurrencySettingsDialog> {
  late String _currency;
  bool _useCustom = false;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currency = widget.establishment.defaultCurrency;
    _useCustom = !_CurrencySettingsDialog._presetCurrencies.contains(_currency);
    if (_useCustom) _customController.text = _currency;
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String get _effectiveCurrency => _useCustom
      ? _customController.text.trim().toUpperCase().isEmpty ? 'RUB' : _customController.text.trim().toUpperCase()
      : _currency;

  Future<void> _saveAsDefault() async {
    final c = _effectiveCurrency;
    final updated = widget.establishment.copyWith(
      defaultCurrency: c,
      updatedAt: DateTime.now(),
    );
    await widget.onSaved(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('currency_saved'))));
  }

  Future<void> _applyToAll() async {
    final c = _effectiveCurrency;
    await widget.onApplyToAll(c);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.loc.t('currency_applied_to_all').replaceAll('%s', widget.store.allProducts.length.toString()))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.loc.t('default_currency')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _useCustom,
            onChanged: (v) => setState(() => _useCustom = v ?? false),
            title: Text(widget.loc.t('custom_currency'), style: const TextStyle(fontSize: 14)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_useCustom)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _customController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('currency_code'),
                  hintText: 'UAH, KZT, THB...',
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _CurrencySettingsDialog._presetCurrencies.contains(_currency) ? _currency : _CurrencySettingsDialog._presetCurrencies.first,
              decoration: InputDecoration(labelText: widget.loc.t('currency'), border: const OutlineInputBorder()),
              items: _CurrencySettingsDialog._presetCurrencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          const SizedBox(height: 16),
          Text(
            widget.loc.t('currency_apply_hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.loc.t('cancel'))),
        FilledButton.tonal(
          onPressed: _applyToAll,
          child: Text(widget.loc.t('apply_currency_to_all')),
        ),
        FilledButton(onPressed: _saveAsDefault, child: Text(widget.loc.t('save'))),
      ],
    );
  }
}
