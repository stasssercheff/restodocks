import 'package:flutter/material.dart';
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
  int _saveProgress = 0;
  int _saveTotal = 0;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
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

  Future<void> _save() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    final defCur = est.defaultCurrency ?? 'RUB';

    final toSave = _items.where((i) => i.approved).toList();
    setState(() {
      _saving = true;
      _saveTotal = toSave.length;
      _saveProgress = 0;
    });
    var created = 0;
    var updated = 0;

    try {
      for (final item in toSave) {
        if (!mounted) return;

        try {
          final cur = item.currency ?? defCur;
          if (item.existingProductId != null && item.category == ModerationCategory.priceUpdate) {
            // Обновляем цену уже существующего продукта
            final newPrice = item.displayPrice ?? item.price;
            if (newPrice != null) {
              await store.setEstablishmentPrice(est.id, item.existingProductId!, newPrice, cur);
              // Убеждаемся что продукт есть в номенклатуре
              await store.addToNomenclature(est.id, item.existingProductId!, price: newPrice, currency: cur);
              updated++;
            }
          } else if (item.existingProductId != null) {
            // Продукт уже есть в базе — просто добавляем в номенклатуру
            await store.addToNomenclature(
              est.id,
              item.existingProductId!,
              price: item.displayPrice ?? item.price,
              currency: (item.displayPrice ?? item.price) != null ? cur : null,
            );
            created++;
          } else {
            // Новый продукт — создаём и добавляем в номенклатуру
            final product = Product.create(
              name: item.displayName,
              category: 'imported',
              basePrice: item.displayPrice ?? 0.0,
              currency: item.displayPrice != null ? cur : null,
            );
            final savedProduct = await store.addProduct(product);
            await store.addToNomenclature(
              est.id,
              savedProduct.id,
              price: item.displayPrice,
              currency: item.displayPrice != null ? cur : null,
            );
            created++;
          }
        } catch (itemError) {
          print('Error saving item "${item.displayName}": $itemError');
          // Продолжаем с остальными продуктами
        }

        if (mounted) {
          setState(() => _saveProgress++);
        }
      }

      await store.loadNomenclature(est.id);

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
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveProgress = 0;
          _saveTotal = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
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
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _toggleAll,
            icon: Icon(approved == _items.length ? Icons.check_box_outlined : Icons.check_box, size: 18),
            label: Text(approved == _items.length
                ? (loc.t('deselect_all') ?? 'Снять все')
                : (loc.t('accept_all') ?? 'Принять всё')),
          ),
        ],
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
          if (_items.any((i) => i.category == ModerationCategory.priceUpdate))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Builder(
                builder: (context) {
                  final priceUpdateItems = _items.where((i) => i.category == ModerationCategory.priceUpdate).toList();
                  final allApproved = priceUpdateItems.isNotEmpty && priceUpdateItems.every((i) => i.approved);
                  final noneApproved = priceUpdateItems.every((i) => !i.approved);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                          backgroundColor: theme.colorScheme.onSurface,
                          foregroundColor: theme.colorScheme.surface,
                          side: BorderSide.none,
                        ),
                        child: const Text('Все'),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: item.approved,
                    onChanged: (v) => _toggle(i, v ?? true),
                    title: Text(
                      item.displayName,
                      style: theme.textTheme.bodyLarge,
                    ),
                    subtitle: _buildSubtitle(item, theme),
                    secondary: _categoryChip(item.category, theme),
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
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || approved == 0 ? null : _save,
                  child: _saving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text('$_saveProgress / $_saveTotal'),
                          ],
                        )
                      : Text(loc.t('save') ?? 'Сохранить'),
                ),
              ),
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
    final cur = item.currency != null ? ' ${item.currency}' : '';
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
