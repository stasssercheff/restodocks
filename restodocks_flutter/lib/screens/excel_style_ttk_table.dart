import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/localization_service.dart';
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
  final ProductStore productStore;
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

  @override
  Widget build(BuildContext context) {
    return _buildExcelStyleTable(context);
  }

  Widget _buildExcelStyleTable(BuildContext context) {
    final theme = Theme.of(context);
    final ingredients = widget.ingredients.where((ing) => !ing.isPlaceholder).toList();
    final totalNet = ingredients.fold<double>(0, (s, ing) => s + ing.netWeight);
    final totalCost = ingredients.fold<double>(0, (s, ing) => s + ing.cost);
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final sym = currency == 'RUB' ? '₽' : currency == 'VND' ? '₫' : currency == 'USD' ? '\$' : currency;

    // Новая структура: слева объединенные ячейки названия и технологии, справа таблица продуктов
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Левая часть: Название блюда и Технология (объединенные ячейки)
        Container(
          width: 280,
          child: Column(
            children: [
              // Название блюда
              Container(
                height: 60,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black87),
                  color: Colors.grey.shade100,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Название блюда/ПФ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: widget.canEdit && widget.dishNameController != null
                        ? GestureDetector(
                            onTap: () => _showEditDialog(context, 'Название блюда', widget.dishNameController!.text, (value) {
                              widget.dishNameController!.text = value;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.dishNameController!.text.isEmpty ? 'Нажмите для редактирования' : widget.dishNameController!.text,
                                style: TextStyle(
                                  color: widget.dishNameController!.text.isEmpty ? Colors.grey : Colors.black,
                                  decoration: widget.dishNameController!.text.isEmpty ? TextDecoration.underline : null,
                                ),
                              ),
                            ),
                          )
                        : Text(widget.dishName, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
              // Технология приготовления
              Container(
                height: ingredients.isEmpty ? 200 : (ingredients.length * 44.0) + 44, // Высота под таблицу продуктов
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black87),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Технология приготовления', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: widget.canEdit && widget.technologyController != null
                        ? GestureDetector(
                            onTap: () => _showEditDialog(context, 'Технология приготовления', widget.technologyController!.text, (value) {
                              widget.technologyController!.text = value;
                            }, maxLines: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.technologyController!.text.isEmpty ? 'Нажмите для редактирования' : widget.technologyController!.text,
                                style: TextStyle(
                                  color: widget.technologyController!.text.isEmpty ? Colors.grey : Colors.black,
                                  decoration: widget.technologyController!.text.isEmpty ? TextDecoration.underline : null,
                                ),
                                maxLines: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        : Text(widget.technologyController?.text ?? '', style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Правая часть: Таблица продуктов
        Expanded(
          child: _buildProductsTable(context, theme, ingredients, totalNet, totalCost, sym),
        ),
      ],
    );
  }

  Widget _buildProductsTable(BuildContext context, ThemeData theme, List<TTIngredient> ingredients,
      double totalNet, double totalCost, String sym) {

    final borderColor = Colors.black87;
    final cellBg = theme.colorScheme.surface;
    final headerBg = Colors.grey.shade800;
    final headerTextColor = Colors.white;

    // Колонки для продуктов
    const colProduct = 140.0;
    const colGross = 80.0;
    const colWaste = 70.0;
    const colNet = 80.0;
    const colMethod = 120.0;
    const colShrink = 70.0;
    const colOutput = 80.0;
    const colCost = 90.0;
    const colPriceKg = 90.0;
    const colDel = 50.0;

    final hasDeleteCol = widget.canEdit;
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(colProduct),
      1: const FixedColumnWidth(colGross),
      2: const FixedColumnWidth(colWaste),
      3: const FixedColumnWidth(colNet),
      4: const FixedColumnWidth(colMethod),
      5: const FixedColumnWidth(colShrink),
      6: const FixedColumnWidth(colOutput),
      7: const FixedColumnWidth(colCost),
      8: const FixedColumnWidth(colPriceKg),
      if (hasDeleteCol) 9: const FixedColumnWidth(colDel),
    };

    TableCell headerCell(String text) => TableCell(
      child: Container(
        padding: _cellPad,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: headerBg,
          border: Border.all(width: 1, color: borderColor),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerTextColor),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    Widget dataCell(String text, {bool editable = false, VoidCallback? onTap, Color? bgColor}) => TableCell(
      child: GestureDetector(
        onTap: editable ? onTap : null,
        child: Container(
          padding: _cellPad,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor ?? cellBg,
            border: Border.all(width: 1, color: borderColor),
          ),
          constraints: const BoxConstraints(minHeight: 44),
          child: Text(
            text.isEmpty ? '' : text,
            style: TextStyle(
              fontSize: 12,
              color: editable ? Colors.blue : Colors.black,
              decoration: editable ? TextDecoration.underline : null,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    return Column(
      children: [
        // Заголовок таблицы продуктов
        Table(
          border: TableBorder.all(width: 1, color: Colors.black87),
          columnWidths: columnWidths,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                headerCell('Продукт'),
                headerCell('Брутто\nг'),
                headerCell('Отход\n%'),
                headerCell('Нетто\nг'),
                headerCell('Способ\nприготовления'),
                headerCell('Ужарка\n%'),
                headerCell('Выход\nг'),
                headerCell('Стоимость'),
                headerCell('Цена\nза кг'),
                if (hasDeleteCol) headerCell(''),
              ],
            ),
          ],
        ),
        // Строки с продуктами
        if (ingredients.isEmpty)
          // Пустая строка для добавления первого продукта
          Table(
            border: TableBorder.all(width: 1, color: Colors.black87),
            columnWidths: columnWidths,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  dataCell('Нажмите для добавления продукта', editable: true, onTap: widget.onAdd),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  dataCell(''),
                  if (hasDeleteCol) dataCell(''),
                ],
              ),
            ],
          )
        else
          Table(
            border: TableBorder.all(width: 1, color: Colors.black87),
            columnWidths: columnWidths,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              // Строки с продуктами
              ...ingredients.asMap().entries.map((entry) {
                final i = entry.key;
                final ing = entry.value;
                final product = ing.productId != null ? widget.productStore.allProducts.where((p) => p.id == ing.productId).firstOrNull : null;

                return TableRow(
                  children: [
                    // Продукт
                    dataCell(
                      ing.productName.isEmpty ? 'Выберите продукт' : ing.productName,
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showProductSelection(context, i) : null,
                    ),
                    // Брутто
                    dataCell(
                      ing.grossWeight == 0 ? '' : ing.grossWeight.toStringAsFixed(0),
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Брутто (г)', ing.grossWeight, (value) {
                        if (value != null && value >= 0) {
                          widget.onUpdate(i, ing.copyWith(grossWeight: value));
                          // Автоматически рассчитать нетто на основе отхода
                          if (ing.primaryWastePct > 0) {
                            final netWeight = value * (1 - ing.primaryWastePct / 100);
                            widget.onUpdate(i, ing.copyWith(manualEffectiveGross: netWeight));
                          }
                        }
                      }) : null,
                    ),
                    // Отход %
                    dataCell(
                      ing.primaryWastePct == 0 ? '' : ing.primaryWastePct.toStringAsFixed(1),
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Отход (%)', ing.primaryWastePct, (value) {
                        if (value != null && value >= 0 && value <= 99.9) {
                          widget.onUpdate(i, ing.copyWith(primaryWastePct: value));
                          // Автоматически рассчитать нетто
                          if (ing.grossWeight > 0) {
                            final netWeight = ing.grossWeight * (1 - value / 100);
                            widget.onUpdate(i, ing.copyWith(manualEffectiveGross: netWeight));
                          }
                        }
                      }) : null,
                    ),
                    // Нетто
                    dataCell(
                      ing.effectiveGrossWeight == 0 ? '' : ing.effectiveGrossWeight.toStringAsFixed(0),
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Нетто (г)', ing.effectiveGrossWeight, (value) {
                        if (value != null && value >= 0) {
                          widget.onUpdate(i, ing.copyWith(manualEffectiveGross: value));
                        }
                      }) : null,
                    ),
                    // Способ приготовления
                    dataCell(
                      ing.cookingProcessName ?? 'Выберите способ',
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showCookingMethodDialog(context, i, ing, product) : null,
                    ),
                    // Ужарка %
                    dataCell(
                      ing.cookingLossPctOverride == null || ing.cookingLossPctOverride == 0
                        ? (product != null ? ing.weightLossPercentage.toStringAsFixed(1) : '')
                        : ing.cookingLossPctOverride!.toStringAsFixed(1),
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Ужарка (%)', ing.cookingLossPctOverride ?? ing.weightLossPercentage, (value) {
                        if (value != null && value >= 0 && value <= 99.9) {
                          widget.onUpdate(i, ing.copyWith(cookingLossPctOverride: value));
                          // Автоматически рассчитать выход
                          if (ing.effectiveGrossWeight > 0) {
                            final outputWeight = ing.effectiveGrossWeight * (1 - value / 100);
                            widget.onUpdate(i, ing.copyWith(netWeight: outputWeight));
                          }
                        }
                      }) : null,
                    ),
                    // Выход
                    dataCell(
                      ing.netWeight == 0 ? '' : ing.netWeight.toStringAsFixed(1),
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Выход (г)', ing.netWeight, (value) {
                        if (value != null && value >= 0) {
                          widget.onUpdate(i, ing.copyWith(netWeight: value));
                        }
                      }) : null,
                    ),
                    // Стоимость
                    dataCell(
                      ing.cost == 0 ? '' : '$sym${ing.cost.toStringAsFixed(2)}',
                      editable: widget.canEdit,
                      onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Стоимость', ing.cost, (value) {
                        if (value != null && value >= 0) {
                          widget.onUpdate(i, ing.copyWith(cost: value));
                        }
                      }) : null,
                    ),
                    // Цена за кг
                    dataCell(
                      ing.netWeight > 0 ? '$sym${(ing.cost * 1000 / ing.netWeight).toStringAsFixed(2)}' : '',
                    ),
                    // Кнопка удаления
                    if (hasDeleteCol) TableCell(
                      child: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => widget.onRemove(i),
                        iconSize: 20,
                      ),
                    ),
                  ],
                );
              }),
              // Строка итогов
              TableRow(
                children: [
                  dataCell('Итого', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell(totalNet.toStringAsFixed(1), bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell('$sym${totalCost.toStringAsFixed(2)}', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  dataCell(totalNet > 0 ? '$sym${(totalCost * 1000 / totalNet).toStringAsFixed(2)}' : '', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                  if (hasDeleteCol) dataCell('', bgColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)),
                ],
              ),
            ],
          ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, String title, String initialValue, Function(String) onSave, {int maxLines = 1}) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showNumberEditDialog(BuildContext context, String title, double initialValue, Function(double?) onSave) {
    final controller = TextEditingController(text: initialValue == 0 ? '' : initialValue.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text.replaceAll(',', '.'));
              onSave(value);
              Navigator.of(context).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showProductSelection(BuildContext context, int index) {
    // Используем существующий механизм добавления продукта
    widget.onAdd(index);
  }

  void _showCookingMethodDialog(BuildContext context, int index, TTIngredient ing, Product? product) {
    final processes = product != null
      ? CookingProcess.forCategory(product.category)
      : CookingProcess.defaultProcesses;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Способ приготовления'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...processes.map((process) => ListTile(
              title: Text(process.getLocalizedName('ru')),
              onTap: () {
                widget.onUpdate(index, ing.copyWith(
                  cookingProcessId: process.id,
                  cookingProcessName: process.getLocalizedName('ru'),
                ));
                // Автоматически предложить процент ужарки
                widget.onSuggestCookingLoss?.call(index);
                Navigator.of(context).pop();
              },
            )),
            ListTile(
              title: const Text('Другое'),
              onTap: () {
                widget.onUpdate(index, ing.copyWith(
                  cookingProcessId: 'custom',
                  cookingProcessName: 'Другое',
                ));
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}