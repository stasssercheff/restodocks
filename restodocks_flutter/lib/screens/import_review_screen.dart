import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

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

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  List<ModerationItem> _byCategory(ModerationCategory cat) =>
      _items.where((i) => i.category == cat && i.approved).toList();

  void _approveAll() {
    setState(() {
      _items = _items.map((i) => i.copyWith(approved: true)).toList();
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

    setState(() => _saving = true);
    var created = 0;
    var updated = 0;

    try {
      for (final item in _items) {
        if (!item.approved) continue;

        if (item.existingProductId != null) {
          if (item.displayPrice != null) {
            await store.addToNomenclature(est.id, item.existingProductId!);
            await store.setEstablishmentPrice(est.id, item.existingProductId!, item.displayPrice!, defCur);
            updated++;
          }
        } else {
          final product = Product.create(
            name: item.displayName,
            category: 'imported',
            basePrice: item.displayPrice ?? 0.0,
            currency: item.displayPrice != null ? defCur : null,
          );
          await store.addProduct(product);
          await store.addToNomenclature(est.id, product.id);
          if (item.displayPrice != null && item.displayPrice! > 0) {
            await store.setEstablishmentPrice(est.id, product.id, item.displayPrice!, defCur);
          }
          created++;
        }
      }

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created > 0 || updated > 0
                  ? 'Сохранено: $created новых, $updated обновлено'
                  : loc.t('no_changes'),
            ),
          ),
        );
        context.go('/nomenclature');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  String _categoryTitle(ModerationCategory cat, LocalizationService loc) {
    switch (cat) {
      case ModerationCategory.nameFix:
        return loc.t('moderation_name_fix') ?? 'Исправление названий';
      case ModerationCategory.priceAnomaly:
        return loc.t('moderation_price_anomaly') ?? 'Проверка цен';
      case ModerationCategory.priceUpdate:
        return loc.t('moderation_price_update') ?? 'Обновление цен';
      case ModerationCategory.newProduct:
        return loc.t('moderation_new') ?? 'Новые продукты';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();

    final approved = _items.where((i) => i.approved).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('import_review_title') ?? 'Модерация импорта'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _approveAll,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(loc.t('accept_all') ?? 'Принять всё'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Chip(
                  label: Text('$approved / ${_items.length}'),
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
              ],
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
          child: FilledButton(
            onPressed: _saving || approved == 0 ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(loc.t('save') ?? 'Сохранить'),
          ),
        ),
      ),
    );
  }

  Widget? _buildSubtitle(ModerationItem item, ThemeData theme) {
    final parts = <String>[];
    if (item.displayPrice != null) {
      final showCurrent = item.existingProductId != null && item.existingPrice != null &&
          item.existingPriceFromEstablishment &&
          (item.existingPrice! - item.displayPrice!).abs() > 0.01;
      if (showCurrent) {
        parts.add('Новая цена: ${item.displayPrice} (сейчас: ${item.existingPrice})');
      } else {
        parts.add('Цена: ${item.displayPrice}');
      }
    } else if (item.existingProductId != null && item.existingPrice != null && item.existingPriceFromEstablishment) {
      parts.add('В базе: ${item.existingPrice}');
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
