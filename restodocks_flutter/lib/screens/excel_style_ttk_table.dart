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

  @override
  Widget build(BuildContext context) {
    return _buildExcelStyleTable(context);
  }

  Widget _buildExcelStyleTable(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800; // Адаптивный breakpoint

    final theme = Theme.of(context);
    final ingredients = widget.ingredients.where((ing) => !ing.isPlaceholder).toList();
    final totalNet = ingredients.fold<double>(0, (s, ing) => s + ing.netWeight);
    final totalCost = ingredients.fold<double>(0, (s, ing) => s + ing.cost);
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final sym = currency == 'RUB' ? '₽' : currency == 'VND' ? '₫' : currency == 'USD' ? '\$' : currency;

    // Адаптивная структура: на мобильных - вертикальная, на десктопе - горизонтальная
    if (isMobile) {
      return Column(
        children: [
          // Название блюда (компактное для мобильных)
          Container(
            width: double.infinity,
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
                widget.canEdit && widget.dishNameController != null
                  ? GestureDetector(
                      onTap: () => _showEditDialog(context, 'Название блюда', widget.dishNameController!.text, (value) {
                        widget.dishNameController!.text = value;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                  : Text(widget.dishName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Технология приготовления (компактное для мобильных)
          Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87),
              color: Colors.grey.shade50,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Технология приготовления', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  widget.canEdit && widget.technologyController != null
                    ? GestureDetector(
                        onTap: () => _showEditDialog(context, 'Технология приготовления', widget.technologyController!.text, (value) {
                          widget.technologyController!.text = value;
                        }, maxLines: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : Text(widget.technologyController?.text ?? '', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Таблица продуктов (адаптивная для мобильных)
          Expanded(
            child: _buildMobileProductsTable(context, theme, ingredients, totalNet, totalCost, sym),
          ),
        ],
      );
    } else {
      // Десктопная версия
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
  }

  Widget _buildProductsTable(BuildContext context, ThemeData theme, List<TTIngredient> ingredients,
      double totalNet, double totalCost, String sym) {

    final borderColor = Colors.black87;
    final cellBg = theme.colorScheme.surface;
    final headerBg = Colors.grey.shade800;
    final headerTextColor = Colors.white;

    final hasDeleteCol = widget.canEdit;

    // Адаптивные колонки для продуктов (учитываем ширину экрана)
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - (screenWidth >= 800 ? 280 : 0) - 32; // Вычитаем ширину левой панели и отступы

    // Фиксированные ширины колонок (упрощенная версия)
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(120.0), // Продукт
      1: const FixedColumnWidth(70.0),  // Брутто
      2: const FixedColumnWidth(60.0),  // Отход %
      3: const FixedColumnWidth(70.0),  // Нетто
      4: const FixedColumnWidth(100.0), // Способ
      5: const FixedColumnWidth(60.0),  // Ужарка %
      6: const FixedColumnWidth(70.0),  // Выход
      7: const FixedColumnWidth(80.0),  // Стоимость
      8: const FixedColumnWidth(80.0),  // Цена за кг
      if (hasDeleteCol) 9: const FixedColumnWidth(40.0), // Удаление
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

  Widget _buildMobileProductsTable(BuildContext context, ThemeData theme, List<TTIngredient> ingredients,
      double totalNet, double totalCost, String sym) {

    return Column(
      children: [
        // Заголовок
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            border: Border.all(color: Colors.black87),
          ),
          child: const Text(
            'Продукты',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // Список продуктов
        Expanded(
          child: ingredients.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: widget.onAdd,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.blue.shade50,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 32, color: Colors.blue),
                        SizedBox(height: 8),
                        Text(
                          'Нажмите для добавления\nпервого продукта',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: ingredients.length + 1, // +1 для итоговой строки
                itemBuilder: (context, index) {
                  if (index == ingredients.length) {
                    // Итоговая строка
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                        border: Border.all(color: Colors.black87),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Итого:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Выход:', style: TextStyle(fontWeight: FontWeight.w500)),
                              Text('${totalNet.toStringAsFixed(1)} г'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Стоимость:', style: TextStyle(fontWeight: FontWeight.w500)),
                              Text('$sym${totalCost.toStringAsFixed(2)}'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Цена за кг:', style: TextStyle(fontWeight: FontWeight.w500)),
                              Text(totalNet > 0 ? '$sym${(totalCost * 1000 / totalNet).toStringAsFixed(2)}' : '—'),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  final ing = ingredients[index];
                  final product = ing.productId != null ? widget.productStore.allProducts.where((p) => p.id == ing.productId).firstOrNull : null;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black87),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Название продукта
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: widget.canEdit ? () => _showProductSelection(context, index) : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: widget.canEdit ? Colors.blue : Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    ing.productName.isEmpty ? 'Выберите продукт' : ing.productName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: ing.productName.isEmpty ? Colors.grey : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.canEdit)
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => widget.onRemove(index),
                                iconSize: 20,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Параметры в две колонки
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildMobileParameterField(
                                    context,
                                    'Брутто',
                                    '${ing.grossWeight == 0 ? '' : ing.grossWeight.toStringAsFixed(0)} г',
                                    widget.canEdit ? () => _showNumberEditDialog(context, 'Брутто (г)', ing.grossWeight, (value) {
                                      if (value != null && value >= 0) {
                                        widget.onUpdate(index, ing.copyWith(grossWeight: value));
                                        // Автоматически рассчитать нетто на основе отхода
                                        if (ing.primaryWastePct > 0) {
                                          final netWeight = value * (1 - ing.primaryWastePct / 100);
                                          widget.onUpdate(index, ing.copyWith(manualEffectiveGross: netWeight));
                                        }
                                      }
                                    }) : null,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMobileParameterField(
                                    context,
                                    'Отход',
                                    '${ing.primaryWastePct == 0 ? '' : ing.primaryWastePct.toStringAsFixed(1)}%',
                                    widget.canEdit ? () => _showNumberEditDialog(context, 'Отход (%)', ing.primaryWastePct, (value) {
                                      if (value != null && value >= 0 && value <= 99.9) {
                                        widget.onUpdate(index, ing.copyWith(primaryWastePct: value));
                                        // Автоматически рассчитать нетто
                                        if (ing.grossWeight > 0) {
                                          final netWeight = ing.grossWeight * (1 - value / 100);
                                          widget.onUpdate(index, ing.copyWith(manualEffectiveGross: netWeight));
                                        }
                                      }
                                    }) : null,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMobileParameterField(
                                    context,
                                    'Нетто',
                                    '${ing.effectiveGrossWeight == 0 ? '' : ing.effectiveGrossWeight.toStringAsFixed(0)} г',
                                    widget.canEdit ? () => _showNumberEditDialog(context, 'Нетто (г)', ing.effectiveGrossWeight, (value) {
                                      if (value != null && value >= 0) {
                                        widget.onUpdate(index, ing.copyWith(manualEffectiveGross: value));
                                      }
                                    }) : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildMobileParameterField(
                                    context,
                                    'Способ',
                                    ing.cookingProcessName ?? 'Выберите способ',
                                    widget.canEdit ? () => _showCookingMethodDialog(context, index, ing, product) : null,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMobileParameterField(
                                    context,
                                    'Ужарка',
                                    ing.cookingLossPctOverride == null || ing.cookingLossPctOverride == 0
                                      ? (product != null ? '${ing.weightLossPercentage.toStringAsFixed(1)}%' : '')
                                      : '${ing.cookingLossPctOverride!.toStringAsFixed(1)}%',
                                    widget.canEdit ? () => _showNumberEditDialog(context, 'Ужарка (%)', ing.cookingLossPctOverride ?? ing.weightLossPercentage, (value) {
                                      if (value != null && value >= 0 && value <= 99.9) {
                                        widget.onUpdate(index, ing.copyWith(cookingLossPctOverride: value));
                                        // Автоматически рассчитать выход
                                        if (ing.effectiveGrossWeight > 0) {
                                          final outputWeight = ing.effectiveGrossWeight * (1 - value / 100);
                                          widget.onUpdate(index, ing.copyWith(netWeight: outputWeight));
                                        }
                                      }
                                    }) : null,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMobileParameterField(
                                    context,
                                    'Выход',
                                    '${ing.netWeight == 0 ? '' : ing.netWeight.toStringAsFixed(1)} г',
                                    widget.canEdit ? () => _showNumberEditDialog(context, 'Выход (г)', ing.netWeight, (value) {
                                      if (value != null && value >= 0) {
                                        widget.onUpdate(index, ing.copyWith(netWeight: value));
                                      }
                                    }) : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Стоимость и цена за кг
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Стоимость:', style: TextStyle(fontWeight: FontWeight.w500)),
                                  GestureDetector(
                                    onTap: widget.canEdit ? () => _showNumberEditDialog(context, 'Стоимость', ing.cost, (value) {
                                      if (value != null && value >= 0) {
                                        widget.onUpdate(index, ing.copyWith(cost: value));
                                      }
                                    }) : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: widget.canEdit ? Colors.blue : Colors.transparent),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        ing.cost == 0 ? '0.00' : '$sym${ing.cost.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: widget.canEdit ? Colors.blue : Colors.black,
                                          decoration: widget.canEdit ? TextDecoration.underline : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Цена за кг:', style: TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    ing.netWeight > 0 ? '$sym${(ing.cost * 1000 / ing.netWeight).toStringAsFixed(2)}' : '—',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ],
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
    );
  }

  Widget _buildMobileParameterField(BuildContext context, String label, String value, VoidCallback? onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: onTap != null ? Colors.blue : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
            ),
            child: Text(
              value.isEmpty ? 'Нажмите для ввода' : value,
              style: TextStyle(
                fontSize: 14,
                color: value.isEmpty ? Colors.grey : Colors.black,
                decoration: onTap != null ? TextDecoration.underline : null,
              ),
            ),
          ),
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