import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../utils/number_format_utils.dart';
import '../utils/product_name_utils.dart';
import '../models/nomenclature_item.dart';
import '../services/services.dart';

class ExcelStyleTtkTable extends StatefulWidget {
  final LocalizationService loc;
  final String dishName;
  final bool isSemiFinished;
  final List<TTIngredient> ingredients;
  final bool canEdit;
  final TextEditingController? dishNameController;
  final TextEditingController? technologyController;
  final ProductStoreSupabase productStore;
  final String? establishmentId;
  final List<TechCard>? semiFinishedProducts;
  final void Function([int?]) onAdd;
  final void Function(int, TTIngredient) onUpdate;
  final void Function(int) onRemove;
  final void Function(int)? onSuggestWaste;
  final void Function(int)? onSuggestCookingLoss;
  final bool isCook; // true для поваров - скрываем стоимость
  /// Если true, блок технологии не отображается (рендерится отдельно в родителе)
  final bool hideTechnologyBlock;
  /// Вес порции (г) — вносится в итого, столбец «вес прц». При изменении вызывается callback.
  final double weightPerPortion;
  final void Function(double)? onWeightPerPortionChanged;
  /// При изменении выхода итого — масштабирование всех ингредиентов в реальном времени (без подтверждения).
  final void Function(double)? onTotalOutputChanged;
  /// При клике на ПФ-ингредиент — переход к просмотру ТТК ПФ.
  final void Function(String techCardId)? onTapPfIngredient;
  /// Родитель скроллит страницу по вертикали — без вложенного вертикального скролла таблицы.
  final bool shrinkWrap;
  /// Шапка таблицы вынесена в [compositionPinnedHeader] (закреп над скроллом страницы).
  final bool omitTableHeader;

  ExcelStyleTtkTable({
    super.key,
    required this.loc,
    required this.dishName,
    required this.isSemiFinished,
    required this.ingredients,
    required this.canEdit,
    this.dishNameController,
    this.technologyController,
    required this.productStore,
    this.establishmentId,
    this.semiFinishedProducts,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    this.onSuggestWaste,
    this.onSuggestCookingLoss,
    this.isCook = false,
    this.hideTechnologyBlock = false,
    this.weightPerPortion = 100,
    this.onWeightPerPortionChanged,
    this.onTotalOutputChanged,
    this.onTapPfIngredient,
    this.shrinkWrap = false,
    this.omitTableHeader = false,
  });

  /// Одна строка шапки состава (для закрепа над страницей; ширина как у таблицы).
  static Widget compositionPinnedHeader(LocalizationService loc) {
    Widget h(String key) => Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            loc.t(key),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 1245, maxWidth: 1245),
      child: Table(
        border: TableBorder.all(color: Colors.black, width: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(50),
          1: FixedColumnWidth(120),
          2: FixedColumnWidth(175),
          3: FixedColumnWidth(80),
          4: FixedColumnWidth(90),
          5: FixedColumnWidth(75),
          6: FixedColumnWidth(100),
          7: FixedColumnWidth(100),
          8: FixedColumnWidth(75),
          9: FixedColumnWidth(75),
          10: FixedColumnWidth(90),
          11: FixedColumnWidth(80),
          12: FixedColumnWidth(95),
          13: FixedColumnWidth(40),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: [
              h('ttk_type'),
              h('ttk_name'),
              h('ttk_product'),
              h('ttk_gross_gr'),
              h('ttk_waste_pct'),
              h('ttk_net_gr'),
              h('ttk_cooking_method'),
              h('ttk_cooking_loss_pct'),
              h('ttk_output_gr'),
              h('ttk_weight_prc'),
              h('ttk_portions_pcs'),
              h('ttk_price'),
              h('ttk_cost'),
              h(''),
            ],
          ),
        ],
      ),
    );
  }

  @override
  State<ExcelStyleTtkTable> createState() => _ExcelStyleTtkTableState();
}

class _ExcelStyleTtkTableState extends State<ExcelStyleTtkTable> {
  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  /// Для unit=шт: true если можно отображать/вводить в штуках (gramsPerPiece или fallback 50).
  static bool _usesPieces(TTIngredient ing) {
    final u = (ing.unit).toLowerCase().trim();
    if (u != 'pcs' && u != 'шт') return false;
    final gpp = ing.gramsPerPiece ?? 50;
    return gpp > 0;
  }

  String _grossDisplayText(TTIngredient ing) {
    if (ing.grossWeight == 0) return '';
    if (_usesPieces(ing)) {
      final v = CulinaryUnits.fromGrams(ing.grossWeight, ing.unit, gramsPerPiece: ing.gramsPerPiece ?? 50);
      return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    }
    return ing.grossWeight.toStringAsFixed(0);
  }

  // Контроллеры для полей ввода
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, Timer> _debounceTimers = {};

  /// Отложенный билд: сначала placeholder, тяжёлую таблицу — в след. кадре. Без замирания.
  bool _tableBuilt = false;

  /// Поэтапная подгрузка строк: первые N — сразу, остальные — в след. кадрах. Убирает 10+ сек задержку до первой реакции.
  static const int _initialRows = 20;
  static const int _chunkRows = 25;
  int _rowsToShow = _initialRows;

  /// Кэш списка продуктов для дропдауна — собирается 1 раз за билд, переиспользуется во всех ячейках.
  List<SelectableItem>? _cachedProductItems;
  Object? _cachedProductItemsKey;

  @override
  void initState() {
    super.initState();
    // Переводы — в фоне, не блокируем первую реакцию
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _ensureProductTranslations();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _tableBuilt = true);
    });
  }

  @override
  void didUpdateWidget(ExcelStyleTtkTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.establishmentId != widget.establishmentId) {
      _ensureProductTranslations();
    }
  }

  Future<void> _ensureProductTranslations() async {
    final lang = widget.loc.currentLanguageCode;
    if (lang == 'ru') return;
    final store = widget.productStore;
    final estId = widget.establishmentId;
    if (estId == null) return;
    final products = store.getNomenclatureProducts(estId);
    final missing = products.where(
      (p) => !(p.names?.containsKey(lang) == true && (p.names![lang]?.trim().isNotEmpty ?? false)),
    ).toList();
    for (final p in missing) {
      if (!mounted) break;
      try {
        await store.translateProductAwait(p.id)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  TextEditingController _getController(String key, String initialValue) {
    return _controllers[key] ??= TextEditingController(text: initialValue);
  }

  FocusNode _getFocusNode(String key) {
    return _focusNodes[key] ??= FocusNode();
  }

  /// Список продуктов+ПФ для выбора — кэшируется, чтобы не строить 20+ раз за билд.
  List<SelectableItem> _getProductItemsForDropdown() {
    final products = widget.establishmentId != null
        ? widget.productStore.getNomenclatureProducts(widget.establishmentId!)
        : <Product>[];
    final key = Object.hash(
      widget.establishmentId,
      widget.semiFinishedProducts?.length ?? 0,
      products.length,
    );
    if (_cachedProductItems != null && _cachedProductItemsKey == key) {
      return _cachedProductItems!;
    }
    final allItems = <SelectableItem>[];
    var nomenclatureProducts = products;
    if (nomenclatureProducts.isEmpty) {
      nomenclatureProducts = List.from(widget.productStore.allProducts);
    }
    final lang = widget.loc.currentLanguageCode;
    for (final product in nomenclatureProducts) {
      allItems.add(SelectableItem(
        type: 'product',
        item: product,
        displayName: product.getLocalizedName(lang),
        searchName: product.name.toLowerCase(),
      ));
    }
    if (widget.semiFinishedProducts != null) {
      for (final pf in widget.semiFinishedProducts!) {
        allItems.add(SelectableItem(
          type: 'pf',
          item: pf,
          displayName: pf.getDisplayNameInLists(widget.loc.currentLanguageCode),
          searchName: pf.dishName.toLowerCase(),
        ));
      }
    }
    final seenDisplayNames = <String>{};
    allItems.retainWhere((item) {
      if (seenDisplayNames.contains(item.displayName)) return false;
      seenDisplayNames.add(item.displayName);
      return true;
    });
    allItems.sort((a, b) {
      if (a.type != b.type) return a.type == 'product' ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    _cachedProductItems = allItems;
    _cachedProductItemsKey = key;
    return allItems;
  }

  @override
  Widget build(BuildContext context) {
    try {
      // Проверяем обязательные поля widget
      if (widget.loc == null) {
        return const Text('LocalizationService is null', style: TextStyle(color: Colors.red));
      }
      if (widget.productStore == null) {
        return const Text('ProductStore is null', style: TextStyle(color: Colors.red));
      }
      if (widget.onUpdate == null) {
        return const Text('onUpdate callback is null', style: TextStyle(color: Colors.red));
      }

      // Отложенный билд: избегаем замирания при большом числе ингредиентов.
      if (!_tableBuilt) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1245, minHeight: 200),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.loc.t('loading'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return _buildTtkTable(context);
    } catch (e, stackTrace) {
      // В случае ошибки в build показываем fallback
      return Container(
        color: Colors.red.shade100,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Error in ExcelStyleTtkTable build', style: TextStyle(color: Colors.red)),
            Text('Error: $e', style: const TextStyle(color: Colors.red, fontSize: 10)),
          ],
        ),
      );
    }
  }

  Widget _buildTtkTable(BuildContext context) {
    try {
      // Проверяем данные
      if (widget.ingredients == null) {
        return const Text('Ingredients is null', style: TextStyle(color: Colors.red));
      }

      // Строки с сохранением индексов для onUpdate (индекс в widget.ingredients)
      final indexedRows = <MapEntry<int, TTIngredient>>[];
      for (var i = 0; i < widget.ingredients.length; i++) {
        var ing = widget.ingredients[i];
        if (ing == null) {
          return Text('Ingredient at index $i is null', style: const TextStyle(color: Colors.red));
        }
        if (ing.productName.isNotEmpty && ing.outputWeight == 0) {
          ing = ing.copyWith(outputWeight: ing.netWeight * (1 - (ing.cookingLossPctOverride ?? 0) / 100));
        }
        indexedRows.add(MapEntry(i, ing));
      }
      if (indexedRows.isEmpty) {
        indexedRows.add(MapEntry(0, TTIngredient.emptyPlaceholder()));
      }

    // Добавляем строку "Итого"
    final totalOutput = indexedRows
        .map((e) => e.value)
        .where((ing) => ing.productName.isNotEmpty)
        .fold<double>(0, (s, ing) => s + ing.outputWeight);
    // Иногда из источника может прилететь отрицательная стоимость (ошибка парсинга/валюты).
    // В UI это выглядит как «-100» в итого. Для отображения не допускаем отрицательные суммы.
    final totalCost = indexedRows
        .map((e) => e.value)
        .where((ing) => ing.productName.isNotEmpty)
        .fold<double>(0, (s, ing) => s + _lineCostForTotals(ing));

    // Расчет итоговой стоимости
    // ПФ: стоимость за кг готового продукта.
    // Блюдо: стоимость за порцию = общая стоимость * (вес порции / общий выход).
    final costPerKgFinishedProduct = widget.isSemiFinished
        ? (totalOutput > 0 ? ((totalCost / totalOutput) * 1000).ceil() : 0)
        : (totalOutput > 0
            ? (totalCost * (widget.weightPerPortion / totalOutput))
            : 0);

    // Подгрузка остальных строк в следующих кадрах — убирает задержку до первой реакции
    final totalRows = indexedRows.length;
    final displayRows = widget.shrinkWrap
        ? totalRows
        : math.min(_rowsToShow, totalRows);
    if (!widget.shrinkWrap && _rowsToShow < totalRows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _rowsToShow = (_rowsToShow + _chunkRows).clamp(0, totalRows);
        });
      });
    }

    final mergedOverlayTop = widget.omitTableHeader ? 0.0 : 44.0;

    final Widget tableCore = ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 1245,
              maxWidth: 1245,
            ), // фиксируем ширину, чтобы контейнер не раздувался под доступную ширину
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Таблица: Stack для объединённой ячейки «Название»
              Stack(
                clipBehavior: Clip.none,
                children: [
              Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            columnWidths: const {
              0: FixedColumnWidth(50),   // Тип ТТК
              1: FixedColumnWidth(120),  // Название
              2: FixedColumnWidth(175),  // Продукт
              3: FixedColumnWidth(80),   // Брутто г./шт
              4: FixedColumnWidth(90),   // % отхода
              5: FixedColumnWidth(75),   // Нетто г.
              6: FixedColumnWidth(100),  // Способ приготовления
              7: FixedColumnWidth(100),  // % ужарки
              8: FixedColumnWidth(75),   // Выход г.
              9: FixedColumnWidth(75),   // вес прц
              10: FixedColumnWidth(90),  // порций(шт)
              11: FixedColumnWidth(80),  // Стоимость
              12: FixedColumnWidth(95),  // Цена за кг
              13: FixedColumnWidth(40), // Удаление
            },
            children: [
              if (!widget.omitTableHeader)
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade200),
                children: [
                  _buildHeaderCell(widget.loc.t('ttk_type')),
                  _buildHeaderCell(widget.loc.t('ttk_name')),
                  _buildHeaderCell(widget.loc.t('ttk_product')),
                  _buildHeaderCell(widget.loc.t('ttk_gross_gr')),
                  _buildHeaderCell(widget.loc.t('ttk_waste_pct')),
                  _buildHeaderCell(widget.loc.t('ttk_net_gr')),
                  _buildHeaderCell(widget.loc.t('ttk_cooking_method')),
                  _buildHeaderCell(widget.loc.t('ttk_cooking_loss_pct')),
                  _buildHeaderCell(widget.loc.t('ttk_output_gr')),
                  _buildHeaderCell(widget.loc.t('ttk_weight_prc')),
                  _buildHeaderCell(widget.loc.t('ttk_portions_pcs')),
                  _buildHeaderCell(widget.loc.t('ttk_price')),
                  _buildHeaderCell(widget.loc.t('ttk_cost')),
                  _buildHeaderCell(''), // Столбец удаления
                ],
              ),
              // Строки с данными — сначала первые N, остальные подгружаются в следующих кадрах
              ...indexedRows.take(displayRows).map((entry) {
                final rowIndex = entry.key;
                final ingredient = entry.value;
                return TableRow(
                  children: [
                    // Тип ТТК — placeholder (объединённая ячейка рисуется поверх в Stack)
                    Container(
                      height: 44,
                      color: Colors.white,
                    ),

                    // Название — placeholder (объединённая ячейка рисуется поверх в Stack)
                    Container(
                      height: 44,
                      color: Colors.white,
                    ),

                    // Продукт
                    _buildProductCell(ingredient, rowIndex),

                    // Брутто: для unit=шт — в штуках, иначе в граммах
                    _buildNumericCell(_grossDisplayText(ingredient), (value) {
                      final parsed = double.tryParse(value?.replaceFirst(',', '.') ?? '') ?? 0;
                      final gross = _usesPieces(ingredient)
                          ? CulinaryUnits.toGrams(parsed, ingredient.unit, gramsPerPiece: ingredient.gramsPerPiece ?? 50)
                          : parsed;
                      final net = gross * (1 - ingredient.primaryWastePct / 100);
                      final output = net * (1 - (ingredient.cookingLossPctOverride ?? 0) / 100);
                      final qty = _usesPieces(ingredient)
                          ? (gross / (ingredient.gramsPerPiece ?? 50))
                          : (gross / 1000.0);
                      final newCost = (ingredient.pricePerKg ?? 0) * qty;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        grossWeight: gross,
                        netWeight: net,
                        outputWeight: output,
                        cost: newCost,
                      ));
                    }, 'gross_$rowIndex'),

                    // % отхода — редактируемо; при вводе пересчёт нетто и выхода. Пусто при 0 — не удалять перед вводом.
                    _buildNumericCell(
                      ingredient.primaryWastePct == 0 ? '' : ingredient.primaryWastePct.toStringAsFixed(0),
                      (value) {
                        final wastePct = (double.tryParse(value?.replaceFirst(',', '.') ?? '') ?? 0).clamp(0.0, 99.9);
                        final gross = ingredient.grossWeight;
                        final net = gross > 0 ? gross * (1.0 - wastePct / 100.0) : 0.0;
                        final output = net * (1.0 - (ingredient.cookingLossPctOverride ?? 0) / 100.0);
                        final qty = _usesPieces(ingredient)
                            ? (gross / (ingredient.gramsPerPiece ?? 50))
                            : (gross / 1000.0);
                        final newCost = (ingredient.pricePerKg ?? 0) * qty;
                        _updateIngredient(rowIndex, ingredient.copyWith(
                          primaryWastePct: wastePct,
                          netWeight: net,
                          outputWeight: output,
                          cost: newCost,
                        ));
                      },
                      'waste_$rowIndex',
                    ),

                    // Нетто
                    _buildNumericCell(ingredient.netWeight == 0 ? '' : ingredient.netWeight.toStringAsFixed(0), (value) {
                      final net = double.tryParse(value?.replaceFirst(',', '.') ?? '') ?? 0;
                      double gross = ingredient.grossWeight;
                      double wastePct = ingredient.primaryWastePct;
                      if (net > 0) {
                        if (_usesPieces(ingredient)) {
                          // Для шт: брутто пересчитываем с округлением вверх
                          final waste = (ingredient.primaryWastePct).clamp(0.0, 99.9) / 100.0;
                          final grossNeeded = net / (1.0 - waste);
                          final gpp = ingredient.gramsPerPiece ?? 50;
                          final pieces = (gpp > 0) ? (grossNeeded / gpp).ceil().toDouble() : grossNeeded;
                          gross = pieces * gpp;
                          wastePct = gross > 0 ? ((1 - net / gross) * 100).clamp(0, 100) : ingredient.primaryWastePct;
                        } else {
                          wastePct = gross > 0 ? ((1 - net / gross) * 100).clamp(0, 100) : ingredient.primaryWastePct;
                        }
                      }
                      final output = net * (1 - (ingredient.cookingLossPctOverride ?? 0) / 100);
                      final qty = _usesPieces(ingredient)
                          ? (gross / (ingredient.gramsPerPiece ?? 50))
                          : (gross / 1000.0);
                      final newCost = (ingredient.pricePerKg ?? 0) * qty;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        grossWeight: gross,
                        netWeight: net,
                        primaryWastePct: wastePct,
                        outputWeight: output,
                        cost: newCost,
                      ));
                    }, 'net_$rowIndex'),

                    // Способ приготовления
                    _buildCookingMethodCell(ingredient, rowIndex),

                    // % ужарки. Пусто при 0 — не удалять перед вводом.
                    _buildNumericCell(
                      (ingredient.cookingLossPctOverride ?? 0) == 0 ? '' : (ingredient.cookingLossPctOverride ?? 0).toStringAsFixed(0),
                      (value) {
                      final loss = double.tryParse(value.replaceFirst(',', '.')) ?? 0;
                      final clampedLoss = loss.clamp(0.0, 99.9);
                      // При изменении % ужарки пересчитываем выход по той же логике, что нетто от отхода: выход = нетто × (1 − ужарка/100)
                      final net = ingredient.netWeight;
                      final output = net > 0 ? net * (1.0 - clampedLoss / 100.0) : 0.0;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        cookingLossPctOverride: clampedLoss,
                        outputWeight: output,
                      ));
                    }, 'cooking_loss_$rowIndex'),

                    // Выход — редактируемо; при вводе пересчёт % ужарки (как нетто → % отхода)
                    _buildNumericCell(
                      ingredient.outputWeight == 0 ? '' : ingredient.outputWeight.toStringAsFixed(0),
                      (value) {
                        final out = double.tryParse(value?.replaceFirst(',', '.') ?? '') ?? 0;
                        if (out < 0) return;
                        final net = ingredient.netWeight;
                        double lossPct = ingredient.cookingLossPctOverride ?? 0;
                        if (net > 0 && out <= net) {
                          lossPct = ((1.0 - out / net) * 100).clamp(0.0, 99.9);
                        }
                        _updateIngredient(rowIndex, ingredient.copyWith(
                          outputWeight: out,
                          cookingLossPctOverride: lossPct,
                        ));
                      },
                      'output_$rowIndex',
                    ),

                    // вес прц — пусто в строках продукта
                    _buildReadOnlyCell(''),

                    // порций(шт) — рассчитывается: outputWeight * (weightPerPortion / totalOutput)
                    _buildReadOnlyCell(_portionsPerOne(totalOutput, ingredient)),

                    // Стоимость
                    _buildCostCell(ingredient),

                    // Цена за кг
                    _buildPricePerKgCell(ingredient),

                    // Кнопка удаления
                    _buildDeleteButton(rowIndex),

                  ],
                );
              }),
              // Строка "Итого"
              TableRow(
                decoration: BoxDecoration(color: Colors.red.shade50),
                children: [
                  _buildTotalCell(widget.loc.t('ttk_total')),
                  const SizedBox.shrink(), // Тип ТТК в итоге не показываем
                  const SizedBox.shrink(), // Название (пусто)
                  const SizedBox.shrink(), // Продукт (пусто)
                  const SizedBox.shrink(), // Брутто
                  const SizedBox.shrink(), // % отхода
                  const SizedBox.shrink(), // Нетто
                  const SizedBox.shrink(), // Способ
                  // Выход г. итого: редактируемый — при изменении масштабируются все ингредиенты в реальном времени
                  widget.canEdit && widget.onTotalOutputChanged != null && totalOutput > 0
                      ? _buildNumericCell(
                          totalOutput.toStringAsFixed(0),
                          (value) {
                            final v = double.tryParse(value?.replaceFirst(',', '.') ?? '') ?? 0;
                            if (v > 0) widget.onTotalOutputChanged?.call(v);
                          },
                          'total_output',
                        )
                      : _buildTotalCell('${totalOutput.toStringAsFixed(0)}г'),
                  // вес порции — редактируемый и для ПФ (по умолчанию 100), и для блюда (по умолчанию = вес выхода итого)
                  widget.canEdit && widget.onWeightPerPortionChanged != null
                      ? _buildNumericCell(
                          widget.weightPerPortion == 0 ? '' : widget.weightPerPortion.toStringAsFixed(0),
                          (value) {
                            final v = double.tryParse(value.replaceFirst(',', '.')) ?? 0;
                            widget.onWeightPerPortionChanged?.call(v);
                          },
                          'weight_per_portion',
                        )
                      : _buildTotalCell(widget.weightPerPortion == 0 ? '' : widget.weightPerPortion.toStringAsFixed(0)),
                  _buildTotalCell('1'), // порций(шт) в итого всегда 1
                  const SizedBox.shrink(), // Стоимость (пусто)
                  widget.isCook
                      ? const SizedBox.shrink() // Скрываем стоимость для поваров
                      : _buildTotalCell('${NumberFormatUtils.formatInt(costPerKgFinishedProduct)} $_currencySymbol'), // Стоимость за кг готового продукта
                  const SizedBox.shrink(), // Удаление
                ],
              ),
                ],
              ),
                  // Объединённая ячейка «Тип ТТК» — позиция и размеры по границам столбца 0
                  Positioned(
                    left: 0,
                    top: mergedOverlayTop,
                    width: 50,
                    height: (displayRows.clamp(0, indexedRows.length) * 44 + 2)
                        .toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.isSemiFinished ? widget.loc.t('tt_type_pf') : widget.loc.t('tt_type_dish'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  // Объединённая ячейка «Название» — позиция и размеры по границам столбца 1
                  Positioned(
                    left: 50,  // граница между колонками 0 и 1
                    top: mergedOverlayTop,
                    width: 120,
                    height: (displayRows.clamp(0, indexedRows.length) * 44 + 2)
                        .toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      alignment: Alignment.topLeft,
                      child: widget.dishNameController != null
                          ? ValueListenableBuilder<TextEditingValue>(
                              valueListenable: widget.dishNameController!,
                              builder: (_, value, __) => Text(
                                value.text,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 10,
                              ),
                            )
                          : Text(
                              widget.dishName,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 10,
                            ),
                    ),
                  ),
                ],
              ),

              // Поле технологии под таблицей на всю ширину (если не скрыто)
              if (widget.ingredients.isNotEmpty && !widget.hideTechnologyBlock)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 1),
                    color: Colors.white,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок технологии
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          border: const Border(bottom: BorderSide(color: Colors.black, width: 1)),
                        ),
                        child: Text(
                          'Технология',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Поле для ввода технологии
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 120),
                        padding: const EdgeInsets.all(12),
                        child: widget.canEdit && widget.technologyController != null
                            ? TextField(
                                controller: widget.technologyController,
                                maxLines: null,
                                minLines: 5,
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.left,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  hintText: widget.loc.t('ttk_technology_placeholder'),
                                ),
                              )
                            : Text(
                                widget.technologyController?.text ?? '',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.left,
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    if (widget.shrinkWrap) {
      return tableCore;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: tableCore,
      ),
    );
    } catch (e, stackTrace) {
      // В случае ошибки показываем fallback
      return Container(
        color: Colors.red.shade100,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Error in TTK table', style: TextStyle(color: Colors.red)),
            Text('Error: $e', style: const TextStyle(color: Colors.red, fontSize: 10)),
          ],
        ),
      );
    }
  }

  // Вспомогательные методы для создания ячеек

  Widget _buildHeaderCell(String text) {
    return Container(
      height: 44,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMergedCell(String text, int rowSpan) {
    return Container(
      height: rowSpan * 44.0, // Высота всех объединенных строк
      alignment: Alignment.topCenter, // Выравнивание текста по верху
      padding: const EdgeInsets.only(top: 12), // Отступ от верха
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMergedTechnologyCell(int rowSpan) {
    return Container(
      height: rowSpan * 44.0, // Высота всех объединенных строк
      alignment: Alignment.topLeft, // Выравнивание текста по левому верхнему углу
      padding: const EdgeInsets.only(top: 12, left: 4), // Отступы
      child: widget.canEdit && widget.technologyController != null
          ? TextField(
              controller: widget.technologyController,
              maxLines: null, // Позволяет неограниченное количество строк
              minLines: 1,    // Минимум 1 строка
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
              ),
            )
          : Text(
              widget.technologyController?.text ?? '',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.left,
              softWrap: true,
            ),
    );
  }

  Widget _buildTechnologyCell(int rowIndex) {
    // Эта функция больше не используется, оставлена для совместимости
    return const SizedBox.shrink();
  }

  /// Returns localized display name for an ingredient (product or PF tech card).
  String _getIngredientDisplayName(TTIngredient ingredient, String lang) {
    if (ingredient.sourceTechCardId != null && ingredient.sourceTechCardId!.isNotEmpty) {
      final pf = widget.semiFinishedProducts
          ?.where((tc) => tc.id == ingredient.sourceTechCardId)
          .firstOrNull;
      if (pf != null) return pf.getDisplayNameInLists(lang);
      return TechCard.pfLinkedIngredientDisplayName(ingredient, lang);
    }
    final product = widget.productStore.findProductForIngredient(ingredient.productId, ingredient.productName);
    if (product != null) return product.getLocalizedName(lang);
    return ingredient.productName;
  }

  Widget _buildProductCell(TTIngredient ingredient, int rowIndex) {
    try {
      final lang = widget.loc.currentLanguageCode;
      if (!widget.canEdit) {
        final name = _getIngredientDisplayName(ingredient, lang);
        return Container(
          height: 44,
          child: Center(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        );
      }

      if (ingredient.productId != null || ingredient.productName.isNotEmpty ||
          (ingredient.sourceTechCardId != null && ingredient.sourceTechCardId!.isNotEmpty)) {
        final name = _getIngredientDisplayName(ingredient, lang);
        final isPf = ingredient.sourceTechCardId != null && ingredient.sourceTechCardId!.isNotEmpty;
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 1),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (isPf && widget.onTapPfIngredient != null) {
                      widget.onTapPfIngredient!(ingredient.sourceTechCardId!);
                    } else {
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        productId: null,
                        productName: '',
                      ));
                    }
                  },
                  child: Tooltip(
                    message: name,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          color: isPf ? Theme.of(context).colorScheme.primary : null,
                          decoration: isPf ? TextDecoration.underline : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
              if (isPf && widget.onTapPfIngredient != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  tooltip: widget.loc.t('ttk_view') ?? 'Просмотр ТТК',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => widget.onTapPfIngredient!(ingredient.sourceTechCardId!),
                ),
              const Icon(Icons.edit, size: 16, color: Colors.grey),
            ],
          ),
        );
      }

    // Показываем searchable dropdown для выбора продукта (по размеру ячейки)
    return _buildSearchableProductDropdown(ingredient, rowIndex);
    } catch (e, stackTrace) {
      // В случае ошибки показываем fallback
      return Container(
        height: 44,
        color: Colors.red.shade100,
        child: const Center(
          child: Text('Error in product cell', style: TextStyle(color: Colors.red, fontSize: 10)),
        ),
      );
    }
  }

  Widget _buildSearchableProductDropdown(TTIngredient ingredient, int rowIndex) {
    try {
      final allItems = _getProductItemsForDropdown();
      return _ProductSearchDropdown(
        items: allItems,
        loc: widget.loc,
        onProductSelected: (selectedItem) {
          try {
            TTIngredient? updated;
            final idx = rowIndex;
            if (selectedItem.type == 'product') {
              final product = selectedItem.item as Product;
              // Отказ: был другой продукт — не предлагать его снова
              final origKey = normalizeProductAliasKey(ingredient.productName);
              if (origKey.isNotEmpty && ingredient.productId != null && ingredient.productId != product.id) {
                widget.productStore.saveProductAliasRejection(origKey, ingredient.productId!, establishmentId: widget.establishmentId);
              }
              // Обучение: сохраняем алиас «яйцо куричное» → «яйцо»
              final prodKey = normalizeProductAliasKey(product.name);
              if (origKey.isNotEmpty && origKey != prodKey) {
                widget.productStore.saveProductAlias(origKey, product.id, establishmentId: widget.establishmentId);
              }
              final establishmentPrice = widget.productStore.getEstablishmentPrice(product.id, widget.establishmentId);
              final pricePerKg = establishmentPrice?.$1 ?? 0.0;
              var gross = ingredient.grossWeight;
              var wastePct = ingredient.primaryWastePct;
              final newGpp = product.gramsPerPiece;
              final productIsPcs = (product.unit == 'шт' || product.unit == 'pcs') && (newGpp ?? 0) > 0;
              if (productIsPcs && _usesPieces(ingredient)) {
                final oldGpp = ingredient.gramsPerPiece ?? 50;
                if (oldGpp > 0 && (newGpp == null || (newGpp - oldGpp).abs() > 0.01)) {
                  final gpp = newGpp ?? 50;
                  final pieces = ingredient.grossWeight / oldGpp;
                  gross = pieces * gpp;
                  final net = ingredient.netWeight;
                  wastePct = gross > 0 ? ((1.0 - net / gross) * 100).clamp(0.0, 99.9) : 0.0;
                }
              }
              final qty = productIsPcs
                  ? (gross / (newGpp ?? 50))
                  : (gross / 1000);
              final cost = pricePerKg * qty;
              var ing = ingredient.copyWith(
                productId: product.id,
                productName: product.name,
                unit: product.unit ?? 'g',
                gramsPerPiece: product.gramsPerPiece,
                grossWeight: gross,
                primaryWastePct: wastePct,
                pricePerKg: pricePerKg,
                cost: cost,
              );
              final outputWeight = ing.netWeight * (1 - (ing.cookingLossPctOverride ?? 0) / 100);
              updated = ing.copyWith(outputWeight: outputWeight);
            } else if (selectedItem.type == 'add_by_name') {
              final name = (selectedItem.item as String).trim();
              if (name.isEmpty) return;
              final p = widget.productStore.findProductForIngredient(null, name);
              if (p != null) {
                final origKey = normalizeProductAliasKey(ingredient.productName);
                if (origKey.isNotEmpty && ingredient.productId != null && ingredient.productId != p.id) {
                  widget.productStore.saveProductAliasRejection(origKey, ingredient.productId!, establishmentId: widget.establishmentId);
                }
                final prodKey = normalizeProductAliasKey(p.name);
                if (origKey.isNotEmpty && origKey != prodKey) {
                  widget.productStore.saveProductAlias(origKey, p.id, establishmentId: widget.establishmentId);
                }
                final establishmentPrice = widget.productStore.getEstablishmentPrice(p.id, widget.establishmentId);
                final pricePerKg = establishmentPrice?.$1 ?? 0.0;
                var gross = ingredient.grossWeight;
                var wastePct = ingredient.primaryWastePct;
                final newGpp = p.gramsPerPiece;
                final productIsPcs = (p.unit == 'шт' || p.unit == 'pcs') && (newGpp ?? 0) > 0;
                if (productIsPcs && _usesPieces(ingredient)) {
                  final oldGpp = ingredient.gramsPerPiece ?? 50;
                  if (oldGpp > 0 && (newGpp == null || (newGpp - oldGpp).abs() > 0.01)) {
                    final gpp = newGpp ?? 50;
                    final pieces = ingredient.grossWeight / oldGpp;
                    gross = pieces * gpp;
                    final net = ingredient.netWeight;
                    wastePct = gross > 0 ? ((1.0 - net / gross) * 100).clamp(0.0, 99.9) : 0.0;
                  }
                }
                final qty = productIsPcs ? (gross / (newGpp ?? 50)) : (gross / 1000);
                final cost = pricePerKg * qty;
                var ing = ingredient.copyWith(
                  productId: p.id,
                  productName: p.name,
                  unit: p.unit ?? 'g',
                  gramsPerPiece: p.gramsPerPiece,
                  grossWeight: gross,
                  primaryWastePct: wastePct,
                  pricePerKg: pricePerKg,
                  cost: cost,
                );
                final outputWeight = ing.netWeight * (1 - (ing.cookingLossPctOverride ?? 0) / 100);
                updated = ing.copyWith(outputWeight: outputWeight);
              } else {
                updated = ingredient.copyWith(productName: name);
              }
            } else if (selectedItem.type == 'pf') {
              final pf = selectedItem.item as TechCard;
              double? pfPricePerKg;
              if (pf.ingredients.isNotEmpty) {
                final r = _resolvePfRecipeCostOutput(pf.id, <String>{});
                if (r != null && r.output > 0 && r.cost > 0) {
                  pfPricePerKg = (r.cost / r.output) * 1000;
                }
              }
              final gross = ingredient.grossWeight;
              updated = ingredient.copyWith(
                sourceTechCardId: pf.id,
                sourceTechCardName: pf.dishName,
                productName: pf.getDisplayNameInLists(widget.loc.currentLanguageCode),
                unit: 'г',
                pricePerKg: pfPricePerKg,
                cost: (pfPricePerKg ?? 0) * (gross / 1000),
              );
            }
            if (updated != null) {
              _updateIngredient(idx, updated);
            }
          } catch (e, st) {
            devLog('TTK onProductSelected error: $e\n$st');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(widget.loc.t('error_generic',
                      args: {'error': e.toString()})),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      );
    } catch (e, stackTrace) {
      // В случае ошибки показываем fallback
      return Container(
        height: 44,
        color: Colors.red.shade100,
        child: const Center(
          child: Text('Error in dropdown', style: TextStyle(color: Colors.red, fontSize: 10)),
        ),
      );
    }
  }

  Widget _buildNumericCell(String value, Function(String) onChanged, String key) {
    // Обновляем контроллер если значение изменилось
    final controller = _getController(key, value);
    final focusNode = _getFocusNode(key);
    // Важно: не затираем ввод пользователя во время редактирования — иначе iOS часто
    // «дожидается подтверждения», и соседние ячейки визуально не обновляются.
    if (!focusNode.hasFocus && controller.text != value) {
      controller.text = value;
    }

    return Container(
      height: 44,
      child: widget.canEdit
          ? TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
              ],
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) {
                _debounceTimers[key]?.cancel();
                _debounceTimers[key] = Timer(const Duration(milliseconds: 150), () {
                  if (!mounted) return;
                  onChanged(v);
                });
              },
            )
          : Container(
              alignment: Alignment.center,
              child: Text(value, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ),
    );
  }

  Widget _buildReadOnlyCell(String value) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      child: Text(value, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
    );
  }

  Widget _buildCookingMethodCell(TTIngredient ingredient, int rowIndex) {
    return Container(
      child: widget.canEdit
          ? DropdownButton<String>(
              isExpanded: true,
              hint: Text(widget.loc.t('ttk_cooking_method'),
                  style: const TextStyle(fontSize: 12)),
              value: ingredient.cookingProcessId ?? (ingredient.cookingProcessName == 'Свой вариант' ? 'custom' : null),
              items: [
                DropdownMenuItem<String>(
                  value: 'custom',
                  child: Text(widget.loc.t('cooking_method_custom'),
                      style: const TextStyle(fontSize: 12)),
                ),
                ...CookingProcess.defaultProcesses.map((process) {
                  return DropdownMenuItem<String>(
                    value: process.id,
                    child: Text(process.getLocalizedName(widget.loc.currentLanguageCode), style: const TextStyle(fontSize: 12)),
                  );
                }),
              ],
              onChanged: (processId) {
                if (processId == 'custom') {
                  // Для "своего варианта" очищаем cookingProcessId и cookingProcessName
                  _updateIngredient(rowIndex, ingredient.copyWith(
                    cookingProcessId: null,
                    cookingProcessName: 'Свой вариант',
                  ));
                } else {
                  final process = CookingProcess.defaultProcesses.firstWhere((p) => p.id == processId);
                  _updateIngredient(rowIndex, ingredient.copyWith(
                    cookingProcessId: processId,
                    cookingProcessName: process.name,
                  ));
                }
              },
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              style: const TextStyle(fontSize: 12, color: Colors.black),
            )
          : Center(
              child: Text(
                ingredient.cookingProcessId != null
                    ? CookingProcess.findById(ingredient.cookingProcessId!)?.getLocalizedName(widget.loc.currentLanguageCode) ?? ingredient.cookingProcessName ?? ''
                    : ingredient.cookingProcessName ?? '',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
    );
  }

  /// Граммы выхода строки для расчёта вложенных ПФ (как в списке ТТК).
  double _rowOutputGramsForNested(TTIngredient ing) {
    if (ing.outputWeight > 0) return ing.outputWeight;
    if (ing.netWeight > 0) return ing.netWeight;
    return ing.grossWeight;
  }

  /// Количество для расчёта стоимости листового ингредиента (кг или шт).
  double _quantityForCostNested(TTIngredient ing) {
    final qty = ing.grossWeight > 0
        ? ing.grossWeight
        : (ing.netWeight > 0 ? ing.netWeight : ing.outputWeight);
    if (qty <= 0) return 0;
    final u = ing.unit.toLowerCase().trim();
    if (u == 'шт' || u == 'pcs') {
      final gpp = ing.gramsPerPiece ?? 50.0;
      return gpp > 0 ? qty / gpp : qty / 1000;
    }
    return qty / 1000;
  }

  /// Стоимость листового (продуктового) ингредиента: из сохранённых данных или из номенклатуры.
  double _resolveLeafIngredientCost(TTIngredient ing) {
    var c = ing.effectiveCost;
    if (c > 0) return c;
    if (ing.pricePerKg != null && ing.pricePerKg! > 0) {
      final q = _quantityForCostNested(ing);
      if (q > 0) return ing.pricePerKg! * q;
    }
    final estId = widget.establishmentId;
    if (estId == null || estId.isEmpty) return 0;
    final product = widget.productStore
        .findProductForIngredient(ing.productId, ing.productName);
    if (product == null) return 0;
    final ep = widget.productStore.getEstablishmentPrice(product.id, estId);
    double pricePerKg = ep?.$1 ?? 0.0;
    if (pricePerKg <= 0 && product.basePrice != null && product.basePrice! > 0) {
      pricePerKg = product.basePrice!;
    }
    if (pricePerKg <= 0) return 0;
    final q = _quantityForCostNested(ing);
    return q > 0 ? pricePerKg * q : 0;
  }

  /// Рекурсивно: себестоимость и суммарный «выход» по рецепту ПФ (для цены/кг и строки в родителе).
  ({double cost, double output})? _resolvePfRecipeCostOutput(
      String pfId, Set<String> stack, {String? fallbackName}) {
    if (!stack.add(pfId)) return null;
    TechCard? pf;
    try {
      final list = widget.semiFinishedProducts;
      if (list == null || list.isEmpty) return null;
      for (final t in list) {
        if (t.id == pfId) {
          pf = t;
          break;
        }
      }
      // Fallback: поиск по имени (sourceTechCardName / productName) при расхождении ID.
      if (pf == null && fallbackName != null && fallbackName.trim().isNotEmpty) {
        final norm = normalizeForPfMatching(fallbackName);
        if (norm.isNotEmpty) {
          for (final t in list) {
            final dn = normalizeForPfMatching(t.dishName);
            if (dn == norm) {
              if (!stack.add(t.id)) return null;
              pf = t;
              break;
            }
            final display = t.getDisplayNameInLists(widget.loc.currentLanguageCode);
            if (normalizeForPfMatching(display) == norm) {
              if (!stack.add(t.id)) return null;
              pf = t;
              break;
            }
          }
        }
      }
      if (pf == null || pf.ingredients.isEmpty) return null;

      double totalCost = 0;
      double totalOutput = 0;
      for (final ing in pf.ingredients) {
        final io = _rowOutputGramsForNested(ing);
        if (io <= 0) continue;
        totalOutput += io;
        if (ing.sourceTechCardId != null && ing.sourceTechCardId!.isNotEmpty) {
          final nested = _resolvePfRecipeCostOutput(
            ing.sourceTechCardId!,
            stack,
            fallbackName: ing.sourceTechCardName ?? ing.productName,
          );
          if (nested != null && nested.output > 0 && nested.cost > 0) {
            totalCost += nested.cost * io / nested.output;
          } else if (ing.effectiveCost > 0) {
            totalCost += ing.effectiveCost;
          }
        } else {
          // Листовой ингредиент (продукт): цена из номенклатуры, если cost=0 в БД
          final leafCost = _resolveLeafIngredientCost(ing);
          if (leafCost > 0) totalCost += leafCost;
        }
      }
      if (totalOutput <= 0) return null;
      return (cost: totalCost, output: totalOutput);
    } finally {
      stack.remove(pfId);
      final resolvedId = pf?.id;
      if (resolvedId != null && resolvedId != pfId) stack.remove(resolvedId);
    }
  }

  /// Стоимость строки для строки «Итого» (учитывает вложенные ПФ по рецепту).
  double _lineCostForTotals(TTIngredient ing) {
    final ppk = _resolvePricePerKg(ing);
    if (ppk > 0) {
      final line = ppk * _quantityForCost(ing);
      if (line > 0) return line;
    }
    return ing.effectiveCost < 0 ? 0 : ing.effectiveCost;
  }

  double _resolvePricePerKg(TTIngredient ingredient) {
    var pricePerKg = ingredient.pricePerKg ?? 0;
    if (pricePerKg > 0) return pricePerKg;

    final sid = ingredient.sourceTechCardId;
    if (sid != null &&
        sid.isNotEmpty &&
        (widget.semiFinishedProducts?.isNotEmpty ?? false)) {
      final r = _resolvePfRecipeCostOutput(
        sid,
        <String>{},
        fallbackName: ingredient.sourceTechCardName ?? ingredient.productName,
      );
      if (r != null && r.output > 0 && r.cost > 0) {
        return (r.cost / r.output) * 1000;
      }
    }

    if (ingredient.productId != null || ingredient.productName.isNotEmpty) {
      final product = widget.productStore
          .findProductForIngredient(ingredient.productId, ingredient.productName);
      if (product != null) {
        final ep = widget.productStore
            .getEstablishmentPrice(product.id, widget.establishmentId);
        pricePerKg = ep?.$1 ?? 0.0;
        if (pricePerKg <= 0 && product.basePrice != null && product.basePrice! > 0) {
          pricePerKg = product.basePrice!;
        }
      }
    }
    return pricePerKg;
  }

  String get _currencySymbol {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    return est?.currencySymbol ?? Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
  }

  Widget _buildCostCell(TTIngredient ingredient) {
    final pricePerKg = _resolvePricePerKg(ingredient);
    final sym = _currencySymbol;
    final fmt = NumberFormatUtils.formatInt(pricePerKg);
    return Container(
      height: 44,
      child: Center(
        child: Text(
          sym.isNotEmpty ? '$fmt $sym' : fmt,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  /// Количество для расчёта стоимости: кг (г/1000) или шт (г/gramsPerPiece).
  double _quantityForCost(TTIngredient ing) {
    if (_usesPieces(ing)) {
      final gpp = ing.gramsPerPiece ?? 50;
      return gpp > 0 ? ing.grossWeight / gpp : ing.grossWeight / 1000;
    }
    return ing.grossWeight / 1000;
  }

  Widget _buildPricePerKgCell(TTIngredient ingredient) {
    final pricePerKg = _resolvePricePerKg(ingredient);
    final grossCost = pricePerKg * _quantityForCost(ingredient);
    final sym = _currencySymbol;
    final fmt = NumberFormatUtils.formatInt(grossCost);

    return Container(
      height: 44,
      child: Center(
        child: Text(
          sym.isNotEmpty ? '$fmt $sym' : fmt,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildTotalCell(String text) {
    return Container(
      height: 44,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Количество продукта на 1 порцию (г) = outputWeight * (weightPerPortion / totalOutput).
  String _portionsPerOne(double totalOutput, TTIngredient ingredient) {
    if (ingredient.productName.isEmpty || totalOutput <= 0) return '';
    final val = ingredient.outputWeight * (widget.weightPerPortion / totalOutput);
    return val == val.truncateToDouble() ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  void _updateIngredient(int index, TTIngredient updated) {
    widget.onUpdate(index, updated);
    // Локальный rebuild, чтобы пересчёты видны сразу при вводе на web/iOS.
    if (mounted) setState(() {});
  }

  Widget _buildDeleteButton(int rowIndex) {
    return Container(
      height: 44, // Фиксированная высота для центровки
      child: Center(
        child: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
          onPressed: () => _removeIngredient(rowIndex),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }

  void _removeIngredient(int index) {
    widget.onRemove(index);
  }

}

class SelectableItem {
  final String type; // 'product' или 'pf'
  final dynamic item; // Product или TechCard
  final String displayName;
  final String searchName;

  SelectableItem({
    required this.type,
    required this.item,
    required this.displayName,
    required this.searchName,
  });
}

class _ProductSearchDropdown extends StatefulWidget {
  final List<SelectableItem> items;
  final Function(SelectableItem) onProductSelected;
  final LocalizationService loc;

  const _ProductSearchDropdown({
    required this.items,
    required this.onProductSelected,
    required this.loc,
  });

  @override
  State<_ProductSearchDropdown> createState() => _ProductSearchDropdownState();
}

class _ProductSearchDropdownState extends State<_ProductSearchDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<SelectableItem> _filterItems(String query) {
    if (query.isEmpty) {
      return widget.items.toList();
    }
    final q = query.trim().toLowerCase();
    final qStripped = stripIikoPrefix(query).trim().toLowerCase();
    return widget.items
        .where((item) {
          final dn = item.displayName.toLowerCase();
          final sn = item.searchName;
          final dnStripped = stripIikoPrefix(item.displayName).toLowerCase();
          return dn.contains(q) || sn.contains(q) ||
              (qStripped.isNotEmpty && (dn.contains(qStripped) || dnStripped.contains(qStripped) || sn.contains(qStripped)));
        })
        .toList();
  }

  Future<void> _openPicker() async {
    final searchCtrl = TextEditingController(text: _searchController.text);
    List<SelectableItem> filtered = _filterItems(_searchController.text);

    final selected = await showDialog<SelectableItem>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: Material(
              color: Colors.white,
              child: SizedBox(
                width: 360,
                height: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: widget.loc.t('search'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (_) {
                          setState(() => filtered = _filterItems(searchCtrl.text));
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (searchCtrl.text.trim().isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.add_circle_outline, size: 20),
                              title: Text(
                                '${widget.loc.t('add')} "${searchCtrl.text.trim()}"',
                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                              ),
                              onTap: () => Navigator.of(ctx).pop(SelectableItem(
                                type: 'add_by_name',
                                item: searchCtrl.text.trim(),
                                displayName: searchCtrl.text.trim(),
                                searchName: searchCtrl.text.trim().toLowerCase(),
                              )),
                            ),
                          ...List.generate(filtered.length, (i) {
                            final item = filtered[i];
                            return ListTile(
                              title: Text(item.displayName, style: const TextStyle(fontSize: 14)),
                              onTap: () => Navigator.of(ctx).pop(item),
                            );
                          }),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(widget.loc.t('cancel')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    searchCtrl.dispose();
    if (selected != null && mounted) {
      widget.onProductSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.white,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openPicker,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _searchController.text.isEmpty ? widget.loc.t('ttk_choose_product') : _searchController.text,
              style: TextStyle(
                fontSize: 12,
                color: _searchController.text.isEmpty ? Colors.grey : Colors.black,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

