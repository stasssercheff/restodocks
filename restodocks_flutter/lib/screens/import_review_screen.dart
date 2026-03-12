import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран модерации импорта: просмотр и подтверждение перед записью в БД.
/// Режим отложенной модерации — без диалогов на каждую строку.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({super.key, required this.items});

  final List<ModerationItem> items;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late List<ModerationItem> _items;
  bool _saving = false;
  final Map<int, TextEditingController> _priceControllers = {};
  int _saveProgress = 0;
  int _saveTotal = 0;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  @override
  void dispose() {
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleAll() {
    final allApproved = _items.every((i) => i.approved);
    setState(() {
      _items = _items.map((i) => i.copyWith(approved: !allApproved)).toList();
    });
  }

  void _approveAllPriceUpdates() {
    setState(() {
      _items = _items.map((i) => i.category == ModerationCategory.priceUpdate
          ? i.copyWith(approved: true) : i).toList();
    });
  }

  void _deselectAllPriceUpdates() {
    setState(() {
      _items = _items.map((i) => i.category == ModerationCategory.priceUpdate
          ? i.copyWith(approved: false) : i).toList();
    });
  }

  void _toggle(int index, bool value) {
    setState(() {
      _items[index] = _items[index].copyWith(approved: value);
    });
  }

  void _updatePrice(int index, double? value) {
    setState(() {
      _items[index] = _items[index].copyWith(price: value);
    });
  }

  /// Сохранить только продукты, которых ещё нет в номенклатуре (новые).
  void _saveOnlyNew() => _save(onlyNew: true);

  Future<void> _save({bool onlyNew = false}) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final loc = context.read<LocalizationService>();

    if (est == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: заведение не найдено. Перезайдите в аккаунт.'), duration: Duration(seconds: 6)),
      );
      return;
    }

    final store = context.read<ProductStoreSupabase>();
    final defCur = est.defaultCurrency ?? 'RUB';
    final toSave = onlyNew
        ? _items.where((i) => i.approved && i.existingProductId == null).toList()
        : _items.where((i) => i.approved).toList();
    setState(() {
      _saving = true;
      _saveTotal = toSave.length;
      _saveProgress = 0;
    });
    var created = 0;
    var updated = 0;

    devLog('💾 ImportReview: starting save, ${toSave.length} items, est=${est.id}');
    try {
      for (final item in toSave) {
        if (!mounted) return;

        if (item.existingProductId != null) {
          final newPrice = item.displayPrice ?? item.price;
          final ep = store.getEstablishmentPrice(item.existingProductId!, est.id);
          final price = newPrice ?? ep?.$1;
          final cur = item.currency ?? defCur;
          // Связь продукт ↔ заведение — чтобы ТТК подтягивала цену
          await store.addToNomenclature(
            est.id,
            item.existingProductId!,
            price: price,
            currency: cur,
          );
          if (newPrice != null) updated++;
        } else {
          final cur = item.currency ?? defCur;
          devLog('💾 ImportReview: creating new product "${item.displayName}"');
          double? calories;
          double? protein;
          double? fat;
          double? carbs;
          bool? containsGluten;
          bool? containsLactose;
          try {
            final nutrition = await NutritionApiService.fetchNutrition(item.displayName);
            if (nutrition != null && nutrition.hasData) {
              calories = nutrition.calories;
              protein = nutrition.protein;
              fat = nutrition.fat;
              carbs = nutrition.carbs;
              containsGluten = nutrition.containsGluten;
              containsLactose = nutrition.containsLactose;
            }
          } catch (_) {}
          final product = Product.create(
            name: item.displayName,
            category: 'imported',
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs,
            containsGluten: containsGluten,
            containsLactose: containsLactose,
            basePrice: null,
            currency: item.displayPrice != null ? cur : null,
          );
          devLog('💾 ImportReview: addProduct id=${product.id}');
          final savedProduct = await store.addProduct(product);
          devLog('💾 ImportReview: addToNomenclature id=${savedProduct.id}');
          await store.addToNomenclature(
            est.id,
            savedProduct.id,
            price: item.displayPrice,
            currency: item.displayPrice != null ? cur : null,
          );
          devLog('💾 ImportReview: ✅ saved "${item.displayName}"');
          created++;
        }

        if (mounted) setState(() => _saveProgress++);
      }

      devLog('💾 ImportReview: all saved. created=$created updated=$updated. Reloading...');
      await store.loadProducts(force: true);
      await store.loadNomenclature(est.dataEstablishmentId);
      devLog('💾 ImportReview: reload done, navigating to nomenclature');

      if (mounted) {
        setState(() {
          _saving = false;
          _saveProgress = 0;
          _saveTotal = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created > 0 || updated > 0
                  ? 'Сохранено: $created новых, $updated обновлено'
                  : loc.t('no_changes'),
            ),
          ),
        );
        context.go('/nomenclature?refresh=1');
      }
    } catch (e, st) {
      devLog('❌ ImportReview: save error: $e\n$st');
      if (mounted) {
        setState(() {
          _saving = false;
          _saveProgress = 0;
          _saveTotal = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();

    final approved = _items.where((i) => i.approved).length;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('import_review_title') ?? 'Модерация импорта'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              loc.t('import_review_hint') ??
                  'Проверьте данные перед сохранением. Запись в базу произойдёт только после подтверждения.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          // Строка с кнопками цен (слева) + чекбокс "выбрать/снять все" (справа, над чекбоксами продуктов)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                if (_items.any((i) => i.category == ModerationCategory.priceUpdate)) ...[
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final priceUpdateItems = _items.where((i) => i.category == ModerationCategory.priceUpdate).toList();
                        final allApproved = priceUpdateItems.isNotEmpty && priceUpdateItems.every((i) => i.approved);
                        final noneApproved = priceUpdateItems.every((i) => !i.approved);
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.tonal(
                              onPressed: _saving ? null : _approveAllPriceUpdates,
                              style: FilledButton.styleFrom(
                                backgroundColor: allApproved ? theme.colorScheme.primaryContainer : null,
                                foregroundColor: allApproved ? theme.colorScheme.onPrimaryContainer : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (allApproved) ...[
                                    Icon(Icons.check_circle, size: 18, color: theme.colorScheme.onPrimaryContainer),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(loc.t('apply_all_price_updates') ?? 'Принять все обновления цен'),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _saving ? null : _deselectAllPriceUpdates,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: noneApproved ? theme.colorScheme.surfaceContainerHighest : null,
                                foregroundColor: noneApproved ? theme.colorScheme.onSurface : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (noneApproved) ...[
                                    Icon(Icons.cancel_outlined, size: 18, color: theme.colorScheme.onSurface),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(loc.t('deselect_price_updates') ?? 'Снять обновления цен'),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ] else
                  const Spacer(),
                // Чекбокс "выбрать/снять все" — справа, точно над колонкой чекбоксов продуктов
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Checkbox(
                    value: approved == _items.length
                        ? true
                        : approved == 0
                            ? false
                            : null,
                    tristate: true,
                    onChanged: _saving ? null : (_) => _toggleAll(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final isNew = item.existingProductId == null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        value: item.approved,
                        onChanged: (v) => _toggle(i, v ?? true),
                        title: Text(
                          item.displayName,
                          style: theme.textTheme.bodyLarge,
                        ),
                        subtitle: _buildSubtitle(item, theme),
                        secondary: _categoryChip(item.category, theme),
                      ),
                      if (isNew)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(
                            children: [
                              Text(
                                loc.t('price_per_kg_computed') ?? 'Цена за кг',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: _priceControllers.putIfAbsent(
                                    i,
                                    () => TextEditingController(
                                      text: item.displayPrice?.toStringAsFixed(0) ?? '',
                                    ),
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    hintText: '-',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                  onChanged: (v) {
                                    final n = double.tryParse(v.replaceFirst(',', '.'));
                                    _updatePrice(i, n);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving && _saveTotal > 0) ...[
                LinearProgressIndicator(
                  value: _saveProgress / _saveTotal,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_saveProgress / $_saveTotal',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving || approved == 0 ? null : () => _save(),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(loc.t('save') ?? 'Сохранить'),
              ),
              if (_items.any((i) => i.existingProductId == null)) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _saving || _items.where((i) => i.approved && i.existingProductId == null).isEmpty
                      ? null
                      : _saveOnlyNew,
                  child: Text(loc.t('save_only_new_products') ?? 'Сохранить только новые продукты'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSubtitle(ModerationItem item, ThemeData theme) {
    final loc = context.read<LocalizationService>();
    final parts = <String>[];
    // Сопоставление с номенклатурой: явно показываем "Сопоставлено с: X" или "Новый продукт"
    if (item.existingProductId != null && item.existingProductName != null) {
      parts.add((loc.t('match_in_nomenclature') ?? 'Сопоставлено с: %s').replaceAll('%s', item.existingProductName!));
    } else {
      parts.add(loc.t('new_product_label') ?? 'Новый продукт');
    }
    final cur = ' ${Establishment.currencySymbolFor(item.currency ?? context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND')}';
    // Для priceUpdate: всегда показываем реальную старую и реальную новую цену
    if (item.category == ModerationCategory.priceUpdate &&
        item.existingProductId != null &&
        (item.existingPrice != null || item.displayPrice != null || item.price != null)) {
      final oldPrice = item.existingPrice;
      final newPrice = item.displayPrice ?? item.price;
      if (oldPrice != null && newPrice != null) {
        parts.add('Было: $oldPrice$cur → Станет: $newPrice$cur');
      } else if (newPrice != null) {
        parts.add('Новая цена: $newPrice$cur');
      } else if (oldPrice != null) {
        parts.add('Цена: $oldPrice$cur');
      }
    } else if (item.displayPrice != null) {
      final hasPriceChange = item.existingProductId != null && item.existingPrice != null &&
          (item.existingPrice! - item.displayPrice!).abs() > 0.01;
      if (hasPriceChange) {
        parts.add('Было: ${item.existingPrice}$cur → Станет: ${item.displayPrice}$cur');
      } else {
        parts.add('Цена: ${item.displayPrice}$cur');
      }
    } else if (item.existingProductId != null && item.existingPrice != null) {
      parts.add('Цена: ${item.existingPrice}$cur');
    }
    if (item.unit != null) parts.add(item.unit!);
    if (item.normalizedName != null && item.normalizedName != item.name) {
      parts.add('(${item.name})');
    }
    if (parts.isEmpty) return null;
    return Text(parts.join(' • '), style: theme.textTheme.bodySmall);
  }

  Widget _categoryChip(ModerationCategory cat, ThemeData theme) {
    Color color;
    switch (cat) {
      case ModerationCategory.nameFix:
        color = Colors.orange;
        break;
      case ModerationCategory.priceAnomaly:
        color = Colors.amber;
        break;
      case ModerationCategory.priceUpdate:
        color = Colors.blue;
        break;
      case ModerationCategory.newProduct:
        color = Colors.green;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _catShort(cat),
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  String _catShort(ModerationCategory cat) {
    switch (cat) {
      case ModerationCategory.nameFix:
        return 'Назв.';
      case ModerationCategory.priceAnomaly:
        return 'Цена';
      case ModerationCategory.priceUpdate:
        return 'Обнов.';
      case ModerationCategory.newProduct:
        return 'Нов.';
    }
  }
}
