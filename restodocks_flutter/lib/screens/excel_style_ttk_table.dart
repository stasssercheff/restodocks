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


  // Контроллеры для полей ввода
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getController(String key, String initialValue) {
    return _controllers[key] ??= TextEditingController(text: initialValue);
  }

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
    final totalOutput = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) => s + ing.outputWeight);
    final totalCost = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) => s + ing.cost);
    final costPerKg = totalOutput > 0 ? totalCost / totalOutput * 1000 : 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child:         ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1400), // Минимальная ширина для всех столбцов
          child: IntrinsicHeight(
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
                    const SizedBox(height: 44, width: double.infinity), // Пустая ячейка нормальной высоты

                    // Название (объединенная ячейка)
                    rowIndex == 0 ? _buildMergedCell(widget.dishName, allRows.length) :
                    const SizedBox(height: 44, width: double.infinity), // Пустая ячейка нормальной высоты

                    // Продукт
                    _buildProductCell(ingredient, rowIndex),

                    // Брутто
                    _buildNumericCell(ingredient.grossWeight.toStringAsFixed(0), (value) {
                      final gross = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(grossWeight: gross));
                      // При изменении брутто ничего автоматически не пересчитываем
                    }, 'gross_$rowIndex'),

                    // % отхода
                    _buildNumericCell(ingredient.primaryWastePct.toStringAsFixed(1), (value) {
                      final waste = double.tryParse(value) ?? 0;
                      final clampedWaste = waste.clamp(0, 99.9);
                      // При изменении % отхода автоматически пересчитываем нетто
                      final net = ingredient.grossWeight * (1 - clampedWaste / 100);
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        primaryWastePct: clampedWaste,
                        netWeight: net,
                      ));
                    }, 'waste_$rowIndex'),

                    // Нетто
                    _buildNumericCell(ingredient.netWeight.toStringAsFixed(0), (value) {
                      final net = double.tryParse(value) ?? 0;
                      // При изменении нетто автоматически пересчитываем % отхода
                      final wastePct = ingredient.grossWeight > 0
                        ? ((1 - net / ingredient.grossWeight) * 100).clamp(0, 99.9)
                        : 0.0;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        netWeight: net,
                        primaryWastePct: wastePct,
                      ));
                    }, 'net_$rowIndex'),

                    // Способ приготовления
                    _buildCookingMethodCell(ingredient, rowIndex),

                    // % ужарки
                    _buildNumericCell((ingredient.cookingLossPctOverride ?? 0).toStringAsFixed(1), (value) {
                      final loss = double.tryParse(value) ?? 0;
                      final clampedLoss = loss.clamp(0, 99.9);
                      // При изменении % ужарки автоматически пересчитываем выход
                      final output = ingredient.netWeight * (1 - clampedLoss / 100);
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        cookingLossPctOverride: clampedLoss,
                        outputWeight: output,
                      ));
                    }, 'cooking_loss_$rowIndex'),

                    // Выход
                    _buildNumericCell(ingredient.outputWeight.toStringAsFixed(0), (value) {
                      final output = double.tryParse(value) ?? 0;
                      // При изменении выхода автоматически пересчитываем % ужарки
                      final lossPct = ingredient.netWeight > 0
                        ? ((1 - output / ingredient.netWeight) * 100).clamp(0, 99.9)
                        : 0.0;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        outputWeight: output,
                        cookingLossPctOverride: lossPct,
                      ));
                    }, 'output_$rowIndex'),

                    // Стоимость
                    _buildCostCell(ingredient),

                    // Цена за кг
                    _buildPricePerKgCell(ingredient),

                    // Технология (объединенная ячейка)
                    rowIndex == 0 ? _buildTechnologyCell(allRows.length) :
                    const SizedBox(height: 44, width: double.infinity), // Пустая ячейка

                    // Кнопка удаления (только для строк с данными, не для пустой строки)
                    ingredient.productName.isNotEmpty ? _buildDeleteButton(rowIndex) :
                    const SizedBox(height: 44, width: double.infinity), // Пустая ячейка для пустой строки
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
      ),
    );
  }

  // Вспомогательные методы для создания ячеек

  Widget _buildHeaderCell(String text) {
    return Container(
      height: 44, // Фиксированная высота для центровки
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
      height: 44, // Фиксированная высота для центровки
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
      height: 44, // Фиксированная высота для центровки
      padding: _cellPad,
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
              ),
            )
          : Text(
              widget.technologyController?.text ?? '',
              style: const TextStyle(fontSize: 12),
              softWrap: true, // Перенос слов
            ),
    );
  }

  Widget _buildProductCell(TTIngredient ingredient, int rowIndex) {
    if (!widget.canEdit) {
      return Container(
        height: 44, // Фиксированная высота для центровки
        padding: _cellPad,
        child: Center(
          child: Text(
            ingredient.sourceTechCardName ?? ingredient.productName,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (ingredient.productId != null) {
      final product = widget.productStore.allProducts.where((p) => p.id == ingredient.productId).firstOrNull;
      return Container(
        height: 44, // Фиксированная высота для центровки
        padding: _cellPad,
        child: Center(
          child: Text(
            product?.name ?? ingredient.productName,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Показываем dropdown для выбора продукта
    return Container(
      height: 44, // Фиксированная высота для центровки
      padding: _cellPad,
      child: Center(
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
                outputWeight: ingredient.netWeight, // Инициализируем выход весом нетто
              ));
            }
          },
        ),
      ),
    );
  }

  Widget _buildNumericCell(String value, Function(String) onChanged, String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      height: 44, // Фиксированная высота для центровки
      child: Center(
        child: widget.canEdit
            ? TextField(
                controller: _getController(key, value),
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
      ),
    );
  }

  Widget _buildCookingMethodCell(TTIngredient ingredient, int rowIndex) {
    return Container(
      height: 44, // Фиксированная высота для центровки
      padding: _cellPad,
      child: Center(
        child: widget.canEdit
            ? DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Способ', style: TextStyle(fontSize: 12)),
                value: ingredient.cookingProcessId ?? (ingredient.cookingProcessName == 'Свой вариант' ? 'custom' : null),
                items: [
                  const DropdownMenuItem<String>(
                    value: 'custom',
                    child: Text('Свой вариант', style: TextStyle(fontSize: 12)),
                  ),
                  ...CookingProcess.defaultProcesses.map((process) {
                    return DropdownMenuItem<String>(
                      value: process.id,
                      child: Text(process.name, style: const TextStyle(fontSize: 12)),
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
              )
            : Text(
                ingredient.cookingProcessId != null
                    ? CookingProcess.findById(ingredient.cookingProcessId!)?.name ?? ''
                    : '',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }

  Widget _buildCostCell(TTIngredient ingredient) {
    final product = ingredient.productId != null
        ? widget.productStore.allProducts.where((p) => p.id == ingredient.productId).firstOrNull
        : null;
    final cost = product != null && product.basePrice != null ? product.basePrice! * ingredient.grossWeight / 1000 : 0.0;

    return Container(
      height: 44, // Фиксированная высота для центровки
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
    if (product == null || product.basePrice == null || ingredient.outputWeight <= 0) return Container(height: 44, padding: _cellPad);

    // Стоимость за кг готового продукта = (цена за кг брутто * брутто) / выход
    final pricePerKg = (product.basePrice! * ingredient.grossWeight) / ingredient.outputWeight;

    return Container(
      height: 44, // Фиксированная высота для центровки
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
      height: 44, // Фиксированная высота для центровки
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


  Widget _buildDeleteButton(int rowIndex) {
    return Container(
      height: 44, // Фиксированная высота для центровки
      padding: const EdgeInsets.all(2),
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
