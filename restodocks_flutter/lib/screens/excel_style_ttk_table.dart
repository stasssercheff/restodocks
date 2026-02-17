import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
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

  ExcelStyleTtkTable({
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
    if (widget.dishNameController != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.dishNameController!,
        builder: (context, value, child) {
          return _buildTtkTable(context);
        },
      );
    } else {
      return _buildTtkTable(context);
    }
  }

  Widget _buildTtkTable(BuildContext context) {
    // Подготавливаем данные
    final ingredients = widget.ingredients.where((ing) => !ing.isPlaceholder).toList();
    final allRows = [...ingredients];

    // Инициализируем outputWeight для существующих ингредиентов
    for (var i = 0; i < allRows.length; i++) {
      if (allRows[i].productName.isNotEmpty && allRows[i].outputWeight == 0) {
        final output = allRows[i].netWeight * (1 - (allRows[i].cookingLossPctOverride ?? 0) / 100);
        allRows[i] = allRows[i].copyWith(outputWeight: output);
      }
    }

    // Всегда добавляем пустую строку для нового ингредиента
    allRows.add(TTIngredient.emptyPlaceholder());

    // Добавляем строку "Итого"
    final totalOutput = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) => s + ing.outputWeight);
    final totalCost = allRows.where((ing) => ing.productName.isNotEmpty).fold<double>(0, (s, ing) => s + ing.cost);

    // Стоимость за кг готового продукта: (сумма стоимостей брутто / общий нетто вес) * 1000, округлить вверх
    final costPerKgFinishedProduct = totalOutput > 0 ? ((totalCost / totalOutput) * 1000).ceil() : 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000), // Минимальная ширина для всех столбцов - уменьшена
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая часть: таблица без столбца технологии
              Expanded(
                child: Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            columnWidths: const {
              0: FixedColumnWidth(50),   // Тип ТТК
              1: FixedColumnWidth(120),  // Название
              2: FixedColumnWidth(100),  // Продукт
              3: FixedColumnWidth(80),   // Брутто
              4: FixedColumnWidth(80),   // % отхода
              5: FixedColumnWidth(80),   // Нетто
              6: FixedColumnWidth(80),   // Способ
              7: FixedColumnWidth(80),   // % ужарки
              8: FixedColumnWidth(60),   // Выход
              9: FixedColumnWidth(70),   // Стоимость
              10: FixedColumnWidth(70),  // Цена за кг
              11: FixedColumnWidth(40),  // Удаление
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
                  _buildHeaderCell('Цена'),
                  _buildHeaderCell('Стоимость (за кг)'),
                  _buildHeaderCell(''), // Столбец удаления
                ],
              ),
              // Строки с данными
              ...allRows.asMap().entries.map((entry) {
                final rowIndex = entry.key;
                final ingredient = entry.value;
                return TableRow(
                  children: [
                    // Тип ТТК (в каждой строке)
                    Container(
                      height: 44,
                      alignment: Alignment.center,
                      child: Text(
                        widget.isSemiFinished ? 'ПФ' : 'Блюдо',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Название (в каждой строке)
                    Container(
                      height: 44,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        widget.dishNameController?.text ?? widget.dishName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Продукт
                    _buildProductCell(ingredient, rowIndex),

                    // Брутто
                    _buildNumericCell(ingredient.grossWeight == 0 ? '' : ingredient.grossWeight.toStringAsFixed(0), (value) {
                      final gross = double.tryParse(value) ?? 0;
                      // При изменении брутто пересчитываем нетто, выход и стоимость
                      final net = gross * (1 - ingredient.primaryWastePct / 100);
                      final output = net * (1 - (ingredient.cookingLossPctOverride ?? 0) / 100);

                      // Пересчитываем стоимость: цена за кг * вес брутто в кг
                      final newCost = (ingredient.pricePerKg ?? 0) * (gross / 1000.0);

                      _updateIngredient(rowIndex, ingredient.copyWith(
                        grossWeight: gross,
                        netWeight: net,
                        outputWeight: output,
                        cost: newCost,
                      ));
                    }, 'gross_$rowIndex'),

                    // % отхода
                    _buildNumericCell(ingredient.primaryWastePct == 0 ? '' : ingredient.primaryWastePct.toString(), (value) {
                      final waste = double.tryParse(value) ?? 0;
                      final clampedWaste = waste.clamp(0, 100);
                      // При изменении % отхода автоматически пересчитываем нетто, выход и стоимость
                      final net = ingredient.grossWeight > 0 ? ingredient.grossWeight * (1 - clampedWaste / 100) : ingredient.netWeight;
                      final output = net * (1 - (ingredient.cookingLossPctOverride ?? 0) / 100);
                      // Стоимость не меняется при изменении отхода - она зависит только от брутто веса
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        primaryWastePct: clampedWaste,
                        netWeight: net,
                        outputWeight: output,
                      ));
                    }, 'waste_$rowIndex'),

                    // Нетто
                    _buildNumericCell(ingredient.netWeight == 0 ? '' : ingredient.netWeight.toStringAsFixed(0), (value) {
                      final net = double.tryParse(value) ?? 0;
                      // При изменении нетто автоматически пересчитываем % отхода (если брутто > 0)
                      final wastePct = ingredient.grossWeight > 0
                        ? ((1 - net / ingredient.grossWeight) * 100).clamp(0, 100)
                        : ingredient.primaryWastePct;
                      // Пересчитываем выход в соответствии с % ужарки
                      final output = net * (1 - (ingredient.cookingLossPctOverride ?? 0) / 100);
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        netWeight: net,
                        primaryWastePct: wastePct,
                        outputWeight: output, // Выход с учетом ужарки
                      ));
                    }, 'net_$rowIndex'),

                    // Способ приготовления
                    _buildCookingMethodCell(ingredient, rowIndex),

                    // % ужарки
                    _buildNumericCell(
                      ((ingredient.cookingLossPctOverride ?? 0) == 0 ? '' : (ingredient.cookingLossPctOverride ?? 0).toString()),
                      (value) {
                      final loss = double.tryParse(value) ?? 0;
                      final clampedLoss = loss.clamp(0, 100);
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        cookingLossPctOverride: clampedLoss,
                      ));
                    }, 'cooking_loss_$rowIndex'),

                    // Выход (всегда равен нетто)
                    _buildNumericCell(ingredient.outputWeight == 0 ? '' : ingredient.outputWeight.toStringAsFixed(0), (value) {
                      final output = double.tryParse(value) ?? 0;
                      _updateIngredient(rowIndex, ingredient.copyWith(
                        outputWeight: output,
                        isNetWeightManual: true, // Помечаем что выход изменен вручную
                      ));
                    }, 'output_$rowIndex'),

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
                  _buildTotalCell('Итого'),
                  _buildTotalCell(widget.isSemiFinished ? 'ПФ' : 'Блюдо'), // Тип ТТК
                  const SizedBox.shrink(), // Название (пусто)
                  const SizedBox.shrink(), // Продукт (пусто)
                  const SizedBox.shrink(), // Брутто
                  const SizedBox.shrink(), // % отхода
                  const SizedBox.shrink(), // Нетто
                  const SizedBox.shrink(), // Способ
                  _buildTotalCell('${totalOutput.toStringAsFixed(0)}г'), // Выход
                  const SizedBox.shrink(), // Стоимость (пусто)
                  _buildTotalCell('${costPerKgFinishedProduct.toStringAsFixed(0)}'), // Стоимость за кг готового продукта
                  const SizedBox.shrink(), // Удаление
                ],
              ),
            ],
          ),
              ),
              // Правая часть: объединенная ячейка технологии
              if (ingredients.isNotEmpty)
                Container(
                  width: 100,
                  child: Column(
                    children: [
                      // Шапка технологии
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                          color: Colors.grey.shade200,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Технология',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Объединенная ячейка технологии
                      Container(
                        height: ingredients.length * 44.0,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                          color: Colors.white,
                        ),
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
                        child: widget.canEdit && widget.technologyController != null
                            ? TextField(
                                controller: widget.technologyController,
                                maxLines: null,
                                minLines: 1,
                                style: const TextStyle(fontSize: 11),
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
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.left,
                              ),
                      ),
                      // Пустое место для строки итого
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                          color: Colors.red.shade50,
                        ),
                      ),
                    ],
                  ),
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
      return InkWell(
        onTap: () {
          // При клике на выбранный продукт открываем dropdown для изменения
          // Очищаем productId, чтобы показать поле поиска
          _updateIngredient(rowIndex, ingredient.copyWith(
            productId: null,
            productName: '',
          ));
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 1),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  product?.name ?? ingredient.productName,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const Icon(
                Icons.edit,
                size: 16,
                color: Colors.grey,
              ),
            ],
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
    // Создаем объединенный список: продукты + ПФ
    final allItems = <SelectableItem>[];

    // Добавляем продукты
    for (final product in widget.productStore.allProducts) {
      allItems.add(SelectableItem(
        type: 'product',
        item: product,
        displayName: product.getLocalizedName('ru'),
        searchName: product.name.toLowerCase(),
      ));
    }

    // Добавляем ПФ
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

    // Удаляем дубликаты по displayName (сохраняем первый найденный)
    final seenDisplayNames = <String>{};
    allItems.retainWhere((item) {
      if (seenDisplayNames.contains(item.displayName)) {
        return false;
      }
      seenDisplayNames.add(item.displayName);
      return true;
    });

    // Сортируем по displayName
    allItems.sort((a, b) => a.displayName.compareTo(b.displayName));

    return _ProductSearchDropdown(
      items: allItems,
      loc: widget.loc,
      onProductSelected: (selectedItem) {
        if (selectedItem.type == 'product') {
          final product = selectedItem.item as Product;
          // Получаем цену за кг
          final establishmentPrice = widget.productStore?.getEstablishmentPrice(product.id, widget.establishmentId);
          final productPrice = establishmentPrice?.$1 ?? product.basePrice;

          // Сначала обновляем продукт, потом пересчитаем выход
          var updatedIngredient = ingredient.copyWith(
            productId: product.id,
            productName: product.name,
            unit: product.unit,
            pricePerKg: productPrice, // Сохраняем цену за кг
            cost: 0.0, // Пока cost = 0, будет пересчитан при вводе grossWeight
          );

          // Выход = нетто с учетом % ужарки
          final outputWeight = updatedIngredient.netWeight * (1 - (updatedIngredient.cookingLossPctOverride ?? 0) / 100);

          updatedIngredient = updatedIngredient.copyWith(outputWeight: outputWeight);

          _updateIngredient(rowIndex, updatedIngredient);
        } else if (selectedItem.type == 'pf') {
          final pf = selectedItem.item as TechCard;
          // Для ПФ создаем ингредиент с ссылкой на ТТК

          // Рассчитываем стоимость за кг для ПФ
          double? pfPricePerKg;
          if (pf.ingredients.isNotEmpty) {
            final totalCost = pf.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
            final totalOutput = pf.ingredients.fold<double>(0, (sum, ing) => sum + ing.outputWeight);
            if (totalOutput > 0) {
              pfPricePerKg = (totalCost / totalOutput) * 1000;
            }
          }

          var updatedIngredient = ingredient.copyWith(
            sourceTechCardId: pf.id,
            sourceTechCardName: pf.dishName,
            productName: pf.getDisplayNameInLists(widget.loc.currentLanguageCode),
            unit: 'г',
            pricePerKg: pfPricePerKg, // Стоимость за кг ПФ
            cost: 0.0, // Пока cost = 0, будет пересчитан при вводе grossWeight
          );

          _updateIngredient(rowIndex, updatedIngredient);
        }

        // Добавляем новую пустую строку только если это была последняя строка
        if (rowIndex == widget.ingredients.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onAdd();
          });
        }
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
      height: 44,
      child: widget.canEdit
          ? GestureDetector(
              onTap: () {
                // Force focus on TextField when tapped
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final focusNode = FocusNode();
                  focusNode.requestFocus();
                  // Dispose focus node after use
                  Future.delayed(const Duration(milliseconds: 100), () {
                    focusNode.dispose();
                  });
                });
              },
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: onChanged,
                onSubmitted: onChanged,
              ),
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

  Widget _buildCostCell(TTIngredient ingredient) {
    // Цена за кг из номенклатуры (фиксированная)
    double pricePerKg = ingredient.pricePerKg ?? 0;

    // Если цена не сохранена, но есть productId - получаем из ProductStore
    if (pricePerKg == 0 && ingredient.productId != null) {
      final establishmentPrice = widget.productStore?.getEstablishmentPrice(ingredient.productId!, widget.establishmentId);
      pricePerKg = establishmentPrice?.$1 ?? 0;
      // Для продуктов без establishment цены используем basePrice из кеша номенклатуры
      if (pricePerKg == 0) {
        // Здесь можно добавить логику для получения basePrice из номенклатуры
        // Пока оставим 0
      }
    }

    return Container(
      height: 44,
      child: Center(
        child: Text(
          pricePerKg.toStringAsFixed(0),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPricePerKgCell(TTIngredient ingredient) {
    // Стоимость продукта по брутто (цена за кг * вес брутто в кг)
    final pricePerKg = ingredient.pricePerKg ?? 0;
    final grossCost = pricePerKg * (ingredient.grossWeight / 1000);

    return Container(
      height: 44,
      child: Center(
        child: Text(
          grossCost.toStringAsFixed(0),
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
    // Принудительно обновляем UI после изменения данных
    setState(() {});
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
  _ProductSearchDropdownState createState() => _ProductSearchDropdownState();
}

class _ProductSearchDropdownState extends State<_ProductSearchDropdown> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;
  List<SelectableItem> _filteredItems = [];
  bool _isSelectingProduct = false; // Флаг для предотвращения конфликта при выборе продукта

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items.take(50).toList();
    _searchController.addListener(_filterProducts);
    _searchController.addListener(_showDropdownOnInput);
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.trim();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items.take(50).toList();
      } else {
        _filteredItems = widget.items
            .where((item) => item.displayName.toLowerCase().contains(query.toLowerCase()) ||
                            item.searchName.contains(query.toLowerCase()))
            .take(20)
            .toList();
      }
    });

    // Пересоздаем overlay для обновления списка
    if (_isDropdownOpen && _overlayEntry != null) {
      _hideOverlay();
      _showOverlay();
    }
  }

  void _showDropdownOnInput() {
    if (!_isDropdownOpen) {
      setState(() {
        _isDropdownOpen = true;
      });
      _showOverlay();
    }
  }

  void _onFocusChange() {
    if (!_searchFocusNode.hasFocus && _isDropdownOpen && !_isSelectingProduct) {
      // Не закрываем overlay сразу, даем время на обработку клика
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_searchFocusNode.hasFocus && _isDropdownOpen && !_isSelectingProduct) {
          _hideOverlay();
        }
      });
    }
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
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return InkWell(
                    onTap: () {
                      _isSelectingProduct = true;
                      widget.onProductSelected(item);
                      _searchController.text = item.displayName;
                      _hideOverlay();
                      // Сбрасываем флаг через короткое время
                      Future.delayed(const Duration(milliseconds: 50), () {
                        _isSelectingProduct = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: index < _filteredItems.length - 1
                          ? const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2)),
                            )
                          : null,
                      child: Text(
                        item.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                },
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
    if (mounted) {
      setState(() {
        _isDropdownOpen = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400, width: 1),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Выберите продукт',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
                onChanged: (value) {
                  if (!_isDropdownOpen && value.isNotEmpty) {
                    setState(() {
                      _isDropdownOpen = true;
                    });
                    _showOverlay();
                  }
                  _filterProducts();
                },
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isDropdownOpen = !_isDropdownOpen;
                });
                if (_isDropdownOpen) {
                  _showOverlay();
                } else {
                  _hideOverlay();
                }
              },
              child: Icon(
                _isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
