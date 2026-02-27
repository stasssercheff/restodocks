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

  /// Сохранить только продукты, которых ещё нет в номенклатуре (новые).
  void _saveOnlyNew() => _save(onlyNew: true);

  Future<void> _save({bool onlyNew = false}) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
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

    try {
      for (final item in toSave) {
        if (!mounted) return;

        if (item.existingProductId != null) {
          // Продукт уже существует в базе — обновляем цену И добавляем в номенклатуру если ещё нет
          final newPrice = item.displayPrice ?? item.price;
          final cur = item.currency ?? defCur;

          // Убедимся что продукт есть в номенклатуре заведения
          if (!store.isInNomenclature(item.existingProductId!)) {
            await store.addToNomenclature(
              est.id,
              item.existingProductId!,
              price: newPrice,
              currency: newPrice != null ? cur : null,
            );
          } else if (newPrice != null) {
            await store.setEstablishmentPrice(est.id, item.existingProductId!, newPrice, cur);
          }
          updated++;
        } else {
          final cur = item.currency ?? defCur;
          final nameLower = item.displayName.trim().toLowerCase();

          // Дедупликация: проверяем не существует ли продукт с таким именем
          final existingInStore = store.allProducts.where(
            (p) => p.name.trim().toLowerCase() == nameLower,
          ).toList();

          if (existingInStore.isNotEmpty) {
            // Продукт есть в глобальной базе — просто добавляем в номенклатуру
            final existingId = existingInStore.first.id;
            if (!store.isInNomenclature(existingId)) {
              await store.addToNomenclature(
                est.id,
                existingId,
                price: item.displayPrice,
                currency: item.displayPrice != null ? cur : null,
              );
            } else if (item.displayPrice != null) {
              await store.setEstablishmentPrice(est.id, existingId, item.displayPrice!, cur);
            }
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
        }

        if (mounted) {
          setState(() => _saveProgress++);
        }
      }

      await store.loadProducts();
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
          // Заголовок с «выбрать/снять все» — checkbox над столбцом чекбоксов у продуктов
          CheckboxListTile(
            value: approved == _items.length
                ? true
                : approved == 0
                    ? false
                    : null,
            tristate: true,
            onChanged: _saving ? null : (_) => _toggleAll(),
            title: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${loc.t('accept_all') ?? 'Принять всё'} / ${loc.t('deselect_all') ?? 'Снять все'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_items.any((i) => i.category == ModerationCategory.priceUpdate))
                  Builder(
                    builder: (context) {
                      final priceUpdateItems = _items.where((i) => i.category == ModerationCategory.priceUpdate).toList();
                      final allApproved = priceUpdateItems.isNotEmpty && priceUpdateItems.every((i) => i.approved);
                      return FilterChip(
                        label: Text(loc.t('apply_all_price_updates') ?? 'Принять все обновления цен'),
                        selected: allApproved,
                        onSelected: _saving ? null : (_) => allApproved ? _deselectAllPriceUpdates() : _approveAllPriceUpdates(),
                        avatar: Icon(
                          allApproved ? Icons.price_check : Icons.price_change_outlined,
                          size: 18,
                        ),
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
              ],
            ),
          ),
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
