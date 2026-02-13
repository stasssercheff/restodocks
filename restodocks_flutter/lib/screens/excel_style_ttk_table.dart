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

    // Инициализируем outputWeight для существующих ингредиентов
    for (var i = 0; i < allRows.length; i++) {
      if (allRows[i].productName.isNotEmpty && allRows[i].outputWeight == 0) {
        allRows[i] = allRows[i].copyWith(outputWeight: allRows[i].netWeight);
      }
    }

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000), // Минимальная ширина для всех столбцов - уменьшена
          child: Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            columnWidths: const {
              0: FixedColumnWidth(50),   // Тип ТТК
              1: FixedColumnWidth(70),   // Название
              2: FixedColumnWidth(100),  // Продукт
              3: FixedColumnWidth(60),   // Брутто
              4: FixedColumnWidth(60),   // % отхода
              5: FixedColumnWidth(60),   // Нетто
              6: FixedColumnWidth(80),   // Способ
              7: FixedColumnWidth(60),   // % ужарки
              8: FixedColumnWidth(60),   // Выход
              9: FixedColumnWidth(70),   // Стоимость
              10: FixedColumnWidth(70),  // Цена за кг
              11: FixedColumnWidth(100), // Технология
              12: FixedColumnWidth(40),  // Удаление
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
                  _buildHeaderCell(''), // Столбец удаления
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
                    const SizedBox.shrink(), // Пустая ячейка

                    // Название (объединенная ячейка)
                    rowIndex == 0 ? _buildMergedCell(widget.dishName, allRows.length) :
                    const SizedBox.shrink(), // Пустая ячейка

                    // Продукт
                    _buildProductCell(ingredient, rowIndex),

                    // Брутто
                    _buildNumericCell(ingredient.grossWeight.toStringAsFixed(0), (value) {
                      final gross = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(grossWeight: gross));
                      // При изменении брутто ничего автоматически не пересчитываем
                    }, 'gross_$rowIndex'),

                    // % отхода
                    _buildNumericCell(ingredient.primaryWastePct == 0 ? '' : ingredient.primaryWastePct.toStringAsFixed(1), (value) {
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
                    _buildNumericCell(
                      (ingredient.cookingProcessId == null && ingredient.cookingProcessName != 'Свой вариант')
                        ? '0'
                        : ((ingredient.cookingLossPctOverride ?? 0) == 0 ? '' : (ingredient.cookingLossPctOverride ?? 0).toStringAsFixed(1)),
                      (value) {
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

                    // Технология - обычная ячейка, которая может растягиваться
                    _buildTechnologyCell(rowIndex),

                    // Кнопка удаления
                    _buildDeleteButton(rowIndex),

                  ],
                );
              }),
              // Строка "Итого"
              TableRow(
                decoration: BoxDecoration(color: Colors.red.shade50),
                children: [
                  _buildTotalCell('Итого'),
                  const SizedBox.shrink(), // Название
                  const SizedBox.shrink(), // Продукт
                  const SizedBox.shrink(), // Брутто
                  const SizedBox.shrink(), // % отхода
                  const SizedBox.shrink(), // Нетто
                  const SizedBox.shrink(), // Способ
                  const SizedBox.shrink(), // % ужарки
                  _buildTotalCell('${totalOutput.toStringAsFixed(0)}г'), // Выход
                  _buildTotalCell('${totalCost.toStringAsFixed(0)}₽'), // Стоимость
                  _buildTotalCell('${costPerKg.toStringAsFixed(0)}₽/кг'), // Цена за кг
                  const SizedBox.shrink(), // Технология
                  const SizedBox.shrink(), // Удаление
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
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildTechnologyCell(int rowIndex) {
    // Технология показывается только в первой строке и может растягивать строку
    if (rowIndex > 0) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
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
          : Center(
              child: Text(
                widget.technologyController?.text ?? '',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.left,
                softWrap: true,
              ),
            ),
    );
  }

  Widget _buildProductCell(TTIngredient ingredient, int rowIndex) {
    if (!widget.canEdit) {
      return Container(
        height: 44,
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
        height: 44,
        child: Center(
          child: Text(
            product?.name ?? ingredient.productName,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Показываем searchable dropdown для выбора продукта
    return Container(
      height: 44, // Фиксированная высота для центровки
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: _buildSearchableProductDropdown(ingredient, rowIndex),
    );
  }

  Widget _buildSearchableProductDropdown(TTIngredient ingredient, int rowIndex) {
    return _ProductSearchDropdown(
      products: widget.productStore.allProducts,
      onProductSelected: (product) {
        _updateIngredient(rowIndex, ingredient.copyWith(
          productId: product.id,
          productName: product.name,
          unit: product.unit,
          outputWeight: ingredient.netWeight, // Инициализируем выход весом нетто
        ));
      },
    );
  }

  Widget _buildNumericCell(String value, Function(String) onChanged, String key) {
    // Обновляем контроллер если значение изменилось
    final controller = _getController(key, value);
    if (controller.text != value) {
      controller.text = value;
    }

    return Container(
      child: widget.canEdit
          ? TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
              ),
              onChanged: onChanged,
              onSubmitted: onChanged,
            )
          : Center(
              child: Text(value, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ),
    );
  }

  Widget _buildCookingMethodCell(TTIngredient ingredient, int rowIndex) {
    return Container(
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
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              style: const TextStyle(fontSize: 12, color: Colors.black),
            )
          : Center(
              child: Text(
                ingredient.cookingProcessId != null
                    ? CookingProcess.findById(ingredient.cookingProcessId!)?.name ?? ingredient.cookingProcessName ?? ''
                    : ingredient.cookingProcessName ?? '',
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
      height: 44,
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
    if (product == null || product.basePrice == null || ingredient.outputWeight <= 0) return Container(height: 44);

    // Стоимость за кг готового продукта = (цена за кг брутто * брутто) / выход
    final pricePerKg = (product.basePrice! * ingredient.grossWeight) / ingredient.outputWeight;

    return Container(
      height: 44,
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
      height: 44,
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

class _ProductSearchDropdown extends StatefulWidget {
  final List<Product> products;
  final Function(Product) onProductSelected;

  const _ProductSearchDropdown({
    required this.products,
    required this.onProductSelected,
  });

  @override
  _ProductSearchDropdownState createState() => _ProductSearchDropdownState();
}

class _ProductSearchDropdownState extends State<_ProductSearchDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products.take(10).toList(); // Показываем первые 10 продуктов при инициализации
    _searchController.addListener(_filterProducts);
    _searchController.addListener(_showDropdownOnInput);
  }

  void _showDropdownOnInput() {
    if (!_isDropdownOpen) {
      setState(() {
        _isDropdownOpen = true;
      });
      _showOverlay();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = widget.products.take(10).toList(); // Показываем первые 10 продуктов если поле пустое
      } else {
        _filteredProducts = widget.products
            .where((product) => product.name.toLowerCase().contains(query))
            .take(20) // Ограничиваем до 20 результатов для производительности
            .toList();
      }
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 44),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Поле поиска в первой строке списка
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: const Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Поиск продукта...',
                        hintStyle: TextStyle(fontSize: 12),
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onTap: () {
                        if (!_isDropdownOpen) {
                          setState(() {
                            _isDropdownOpen = true;
                          });
                          _showOverlay();
                        }
                      },
                    ),
                  ),
                  // Список отфильтрованных продуктов
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return InkWell(
                          onTap: () {
                            widget.onProductSelected(product);
                            _searchController.text = product.name;
                            _hideOverlay();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: index < _filteredProducts.length - 1
                                ? const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2)),
                                  )
                                : null,
                            child: Text(
                              product.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() {
      _isDropdownOpen = false;
    });
  }

  void _toggleDropdown() {
    if (_isDropdownOpen) {
      _hideOverlay();
    } else {
      setState(() {
        _isDropdownOpen = true;
      });
      _showOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 1),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _searchController.text.isEmpty ? 'Выберите продукт' : _searchController.text,
                  style: const TextStyle(fontSize: 12, color: Colors.black),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 16,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
