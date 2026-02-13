import 'package:flutter/material.dart';
import '../models/models.dart';
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
  final void Function([int?]) onAdd;
  final void Function(int, TTIngredient) onUpdate;
  final void Function(int) onRemove;
  final void Function(int)? onSuggestWaste;
  final void Function(int)? onSuggestCookingLoss;

  const ExcelStyleTtkTable({
    super.key,
    required this.loc,
    required this.dishName,
    required this.isSemiFinished,
    required this.ingredients,
    required this.canEdit,
    this.dishNameController,
    this.technologyController,
    required this.productStore,
    required this.onAdd,
    required this.onUpdate,
    required this.onRemove,
    this.onSuggestWaste,
    this.onSuggestCookingLoss,
  });

  @override
  State<ExcelStyleTtkTable> createState() => _ExcelStyleTtkTableState();
}

class _ExcelStyleTtkTableState extends State<ExcelStyleTtkTable> {
  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  // Отслеживаем последнее изменение для правильных расчетов
  final Map<int, String> _lastChangedField = {};

  @override
  Widget build(BuildContext context) {
    return _buildTtkTable(context);
  }

  Widget _buildTtkTable(BuildContext context) {
    // Подготавливаем данные
    final ingredients = widget.ingredients.where((ing) => !ing.isPlaceholder).toList();
    final allRows = [...ingredients];

    // Добавляем пустую строку, если последняя не пустая или если строк меньше 2
    if (allRows.isEmpty || (allRows.last.productName.isNotEmpty)) {
      allRows.add(TTIngredient.emptyPlaceholder());
    }

    // Добавляем строку "Итого"
    final totalOutput = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) {
      final output = ing.netWeight * (1 - (ing.cookingLossPctOverride ?? 0) / 100);
      return s + (output > 0 ? output : ing.netWeight);
    });
    final totalCost = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) => s + ing.cost);
    final costPerKg = totalOutput > 0 ? totalCost / totalOutput * 1000 : 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child:         ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1400), // Минимальная ширина для всех столбцов
          child: Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            columnWidths: const {
              0: FixedColumnWidth(70),   // Тип ТТК
              1: FixedColumnWidth(100),  // Название
              2: FixedColumnWidth(130),  // Продукт
              3: FixedColumnWidth(70),   // Брутто
              4: FixedColumnWidth(70),   // % отхода
              5: FixedColumnWidth(70),   // Нетто
              6: FixedColumnWidth(100),  // Способ
              7: FixedColumnWidth(70),   // % ужарки
              8: FixedColumnWidth(70),   // Выход
              9: FixedColumnWidth(80),   // Стоимость
              10: FixedColumnWidth(80),  // Цена за кг
              11: FixedColumnWidth(120), // Технология
              12: FixedColumnWidth(50),  // Удаление
            },
            children: [
              // Шапка
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade200),
                children: [
                  _buildHeaderCell('Тип ТТК'),
                  _buildHeaderCell('Название'),
                  _buildHeaderCell('Продукт'),
                  _buildHeaderCell('Брутто'),
                  _buildHeaderCell('% отхода'),
                  _buildHeaderCell('Нетто'),
                  _buildHeaderCell('Способ'),
                  _buildHeaderCell('% ужарки'),
                  _buildHeaderCell('Выход'),
                  _buildHeaderCell('Стоимость'),
                  _buildHeaderCell('Цена за кг'),
                  _buildHeaderCell('Технология'),
                  _buildHeaderCell(''), // Столбец для удаления
                ],
              ),
              // Строки с данными
              ...allRows.asMap().entries.map((entry) {
                final rowIndex = entry.key;
                final ingredient = entry.value;
                return TableRow(
                  children: [
                    // Тип ТТК (объединенная ячейка)
                    rowIndex == 0 ? _buildMergedCell(widget.isSemiFinished ? 'ПФ' : 'Блюдо', allRows.length) :
                    const SizedBox(height: 44), // Пустая ячейка нормальной высоты

                    // Название (объединенная ячейка)
                    rowIndex == 0 ? _buildMergedCell(widget.dishName, allRows.length) :
                    const SizedBox(height: 44), // Пустая ячейка нормальной высоты

                    // Продукт
                    _buildProductCell(ingredient, rowIndex),

                    // Брутто
                    _buildNumericCell(ingredient.grossWeight.toStringAsFixed(0), (value) {
                      final gross = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(grossWeight: gross));
                      _lastChangedField[rowIndex] = 'gross';
                      _recalculate(rowIndex, ingredient.copyWith(grossWeight: gross));
                    }),

                    // % отхода
                    _buildNumericCell(ingredient.primaryWastePct.toStringAsFixed(1), (value) {
                      final waste = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(primaryWastePct: waste.clamp(0, 99.9)));
                      _lastChangedField[rowIndex] = 'waste';
                      _recalculate(rowIndex, ingredient.copyWith(primaryWastePct: waste.clamp(0, 99.9)));
                    }),

                    // Нетто
                    _buildNumericCell(ingredient.netWeight.toStringAsFixed(0), (value) {
                      final net = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(netWeight: net));
                      _lastChangedField[rowIndex] = 'net';
                      _recalculate(rowIndex, ingredient.copyWith(netWeight: net));
                    }),

                    // Способ приготовления
                    _buildCookingMethodCell(ingredient, rowIndex),

                    // % ужарки
                    _buildNumericCell((ingredient.cookingLossPctOverride ?? 0).toStringAsFixed(1), (value) {
                      final loss = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(cookingLossPctOverride: loss.clamp(0, 99.9)));
                      _lastChangedField[rowIndex] = 'cooking_loss';
                      _recalculate(rowIndex, ingredient.copyWith(cookingLossPctOverride: loss.clamp(0, 99.9)));
                    }),

                    // Выход
                    _buildNumericCell(ingredient.netWeight.toStringAsFixed(0), (value) {
                      final output = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(netWeight: output));
                      _lastChangedField[rowIndex] = 'output';
                      _recalculate(rowIndex, ingredient);
                    }),

                    // Стоимость
                    _buildCostCell(ingredient),

                    // Цена за кг
                    _buildPricePerKgCell(ingredient),

                    // Технология (объединенная ячейка)
                    rowIndex == 0 ? _buildTechnologyCell(allRows.length) :
                    const SizedBox(height: 44), // Пустая ячейка

                    // Кнопка удаления (только для строк с данными, не для пустой строки)
                    ingredient.productName.isNotEmpty ? _buildDeleteButton(rowIndex) :
                    const SizedBox(height: 44), // Пустая ячейка для пустой строки
                  ],
                );
              }),
              // Строка "Итого"
              TableRow(
                decoration: BoxDecoration(color: Colors.red.shade50),
                children: [
                  _buildTotalCell('Итого'),
                  const SizedBox(height: 44), // Пустые ячейки
                  const SizedBox(height: 44),
                  const SizedBox(height: 44),
                  const SizedBox(height: 44),
                  const SizedBox(height: 44),
                  const SizedBox(height: 44),
                  const SizedBox(height: 44),
                  _buildTotalCell('${totalOutput.toStringAsFixed(0)}г'),
                  _buildTotalCell('${totalCost.toStringAsFixed(0)}₽'),
                  _buildTotalCell('${costPerKg.toStringAsFixed(0)}₽/кг'),
                  const SizedBox(height: 44), // Пустая ячейка для кнопки удаления в итого
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Вспомогательные методы для создания ячеек

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: _cellPad,
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
      padding: _cellPad,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildTechnologyCell(int rowSpan) {
    return Container(
      padding: _cellPad,
      child: widget.canEdit && widget.technologyController != null
          ? TextField(
              controller: widget.technologyController,
              maxLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            )
          : Text(
              widget.technologyController?.text ?? '',
              style: const TextStyle(fontSize: 12),
            ),
    );
  }

  Widget _buildProductCell(TTIngredient ingredient, int rowIndex) {
    if (!widget.canEdit) {
      return Container(
        padding: _cellPad,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            ingredient.sourceTechCardName ?? ingredient.productName,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    if (ingredient.productId != null) {
      final product = widget.productStore.allProducts.where((p) => p.id == ingredient.productId).firstOrNull;
      return Container(
        padding: _cellPad,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            product?.name ?? ingredient.productName,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    // Показываем dropdown для выбора продукта
    return Container(
      padding: _cellPad,
      child: DropdownButton<String>(
        isExpanded: true,
        hint: const Text('Выберите продукт', style: TextStyle(fontSize: 12)),
        value: null,
        items: widget.productStore.allProducts.map((product) {
          return DropdownMenuItem<String>(
            value: product.id,
            child: Text(product.name, style: const TextStyle(fontSize: 12)),
          );
        }).toList(),
        onChanged: (productId) {
          if (productId != null) {
            final product = widget.productStore.allProducts.firstWhere((p) => p.id == productId);
            _updateIngredient(rowIndex, ingredient.copyWith(
              productId: productId,
              productName: product.name,
              unit: product.unit,
            ));
          }
        },
      ),
    );
  }

  Widget _buildNumericCell(String value, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: widget.canEdit
          ? TextField(
              controller: TextEditingController(text: value),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: onChanged,
            )
          : Text(value, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
    );
  }

  Widget _buildCookingMethodCell(TTIngredient ingredient, int rowIndex) {
    return Container(
      padding: _cellPad,
      child: widget.canEdit
          ? DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Способ', style: TextStyle(fontSize: 12)),
              value: ingredient.cookingProcessId,
              items: CookingProcess.defaultProcesses.map((process) {
                return DropdownMenuItem<String>(
                  value: process.id,
                  child: Text(process.name, style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (processId) {
                _updateIngredient(rowIndex, ingredient.copyWith(cookingProcessId: processId));
              },
            )
          : Text(
              ingredient.cookingProcessId != null
                  ? CookingProcess.findById(ingredient.cookingProcessId!)?.name ?? ''
                  : '',
              style: const TextStyle(fontSize: 12),
            ),
    );
  }

  Widget _buildCostCell(TTIngredient ingredient) {
    final product = ingredient.productId != null
        ? widget.productStore.allProducts.where((p) => p.id == ingredient.productId).firstOrNull
        : null;
    final cost = product != null && product.basePrice != null ? product.basePrice! * ingredient.grossWeight / 1000 : 0.0;

    return Container(
      padding: _cellPad,
      child: Center(
        child: Text(
          '${cost.toStringAsFixed(0)}₽',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPricePerKgCell(TTIngredient ingredient) {
    final product = ingredient.productId != null
        ? widget.productStore.allProducts.where((p) => p.id == ingredient.productId).firstOrNull
        : null;
    if (product == null || product.basePrice == null) return Container(padding: _cellPad);

    final cookingLoss = ingredient.cookingLossPctOverride ?? 0;
    final outputWeight = ingredient.netWeight * (1 - cookingLoss / 100);
    final effectiveGross = ingredient.grossWeight > 0 ? ingredient.grossWeight : 1;
    final pricePerKg = outputWeight > 0 ? (product.basePrice! * 1000 / effectiveGross) * (effectiveGross / outputWeight) : 0.0;

    return Container(
      padding: _cellPad,
      child: Center(
        child: Text(
          '${pricePerKg.toStringAsFixed(0)}₽/кг',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildTotalCell(String text) {
    return Container(
      padding: _cellPad,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _updateIngredient(int index, TTIngredient updated) {
    widget.onUpdate(index, updated);
  }

  void _recalculate(int index, TTIngredient ingredient) {
    final lastField = _lastChangedField[index];

    if (lastField == 'gross') {
      // Изменен брутто - пересчитываем нетто на основе % отхода
      final wastePct = ingredient.primaryWastePct;
      final net = ingredient.grossWeight * (1 - wastePct / 100);
      _updateIngredient(index, ingredient.copyWith(netWeight: net));
    } else if (lastField == 'waste') {
      // Изменен % отхода - пересчитываем нетто на основе брутто
      final net = ingredient.grossWeight * (1 - ingredient.primaryWastePct / 100);
      _updateIngredient(index, ingredient.copyWith(netWeight: net));
    } else if (lastField == 'net') {
      // Изменено нетто - пересчитываем % отхода на основе брутто
      if (ingredient.grossWeight > 0) {
        final wastePct = (1 - ingredient.netWeight / ingredient.grossWeight) * 100;
        _updateIngredient(index, ingredient.copyWith(primaryWastePct: wastePct.clamp(0, 99.9)));
      }
    } else if (lastField == 'cooking_loss') {
      // Изменена % ужарки - ничего не пересчитываем, так как выход = нетто
      // Выход всегда рассчитывается как нетто * (1 - ужарка/100)
    } else if (lastField == 'output') {
      // Изменен выход - пересчитываем % ужарки на основе нетто
      if (ingredient.netWeight > 0) {
        final lossPct = (1 - ingredient.netWeight / ingredient.netWeight) * 100;
        _updateIngredient(index, ingredient.copyWith(cookingLossPctOverride: lossPct.clamp(0, 99.9)));
      }
    }
  }

  Widget _buildDeleteButton(int rowIndex) {
    return Container(
      padding: const EdgeInsets.all(2),
      child: IconButton(
        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
        onPressed: () => _removeIngredient(rowIndex),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  void _removeIngredient(int index) {
    widget.onRemove(index);
  }
}
