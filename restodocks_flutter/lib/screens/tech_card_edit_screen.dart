import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';
import '../services/ai_service_supabase.dart';
import '../services/app_toast_service.dart';
import '../services/services.dart';
import '../services/tech_card_cost_hydrator.dart';
import '../services/tech_card_nutrition_hydrator.dart';
import '../utils/layout_breakpoints.dart';
import '../utils/number_format_utils.dart';
import '../utils/unit_converter.dart';
import '../widgets/app_bar_home_button.dart';
import 'excel_style_ttk_table.dart';

/// Совпадает с фиксированной шириной тела [ExcelStyleTtkTable].
const double _kExcelTtkCompositionBodyWidth = 1295;

/// Ширина блока «Технология»: как у таблицы состава, но не шире области контента при узком экране.
double _ttkTechnologyStripWidth(BuildContext context, bool tableOnlyView) {
  final intrinsic = tableOnlyView
      ? _TtkCookTable.intrinsicTableWidth(context)
      : _kExcelTtkCompositionBodyWidth.toDouble();
  final vw = MediaQuery.sizeOf(context).width;
  final maxOuter = vw > 24 ? vw - 24 : vw;
  return intrinsic > maxOuter ? maxOuter : intrinsic;
}

enum _DuplicateNameAction { createDuplicate, edit, delete }

/// Создание или редактирование ТТК. Ингредиенты — из номенклатуры или из других ТТК (ПФ).
///
/// Составление/редактирование карточек остаётся как реализовано (таблица, ингредиенты, технология).
/// Отображение для сотрудников (режим просмотра, !effectiveCanEdit) должно соответствовать референсу:
/// https://github.com/stasssercheff/shbb326 — kitchen/kitchen/ttk/Preps (ТТК ПФ), dish (карточки блюд), sv (су-вид).

Color _ttkEditableFill(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7);

/// Розовый фон числового поля на всю ячейку таблицы, цифры по центру.
/// Фокус подсвечивает всю ячейку (рамка темы), не отдельное поле ввода.
Widget _ttkNumericEditableField({
  required BuildContext context,
  required TextEditingController controller,
  required TextInputType keyboardType,
  required VoidCallback onInputChanged,
  required VoidCallback onSubmit,
  FocusNode? focusNode,
  bool requestFocusOnOuterTap = true,

  /// Если false — одна строка по центру (для высоких ячеек, напр. «Итого»).
  bool expandToCell = true,
}) {
  final fillColor = _ttkEditableFill(context);
  final cs = Theme.of(context).colorScheme;

  Widget coreLayout() {
    if (!expandToCell) {
      return SizedBox(
        width: double.infinity,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: TextField(
            focusNode: focusNode,
            controller: controller,
            keyboardType: keyboardType,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            expands: false,
            maxLines: 1,
            cursorColor: cs.onSurface,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              filled: false,
            ),
            style: const TextStyle(fontSize: 12, height: 1),
            strutStyle: const StrutStyle(
              forceStrutHeight: true,
              height: 1,
            ),
            onChanged: (_) => onInputChanged(),
            onSubmitted: (_) => onSubmit(),
            onTapOutside: (_) => onSubmit(),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final stretch = maxH.isFinite && maxH > 0;
        final h = stretch ? maxH : 44.0;
        return SizedBox(
          width: double.infinity,
          height: h,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: Center(
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                keyboardType: keyboardType,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                expands: false,
                maxLines: 1,
                cursorColor: cs.onSurface,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                style: const TextStyle(fontSize: 12, height: 1),
                strutStyle: const StrutStyle(
                  forceStrutHeight: true,
                  height: 1,
                ),
                onChanged: (_) => onInputChanged(),
                onSubmitted: (_) => onSubmit(),
                onTapOutside: (_) => onSubmit(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget shell() {
    final fn = focusNode;
    if (fn != null) {
      return ListenableBuilder(
        listenable: fn,
        builder: (context, _) {
          final focused = fn.hasFocus;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(
                width: 2,
                color: focused ? cs.primary : Colors.transparent,
              ),
            ),
            child: coreLayout(),
          );
        },
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: fillColor),
      child: coreLayout(),
    );
  }

  final field = shell();
  final fn = focusNode;
  if (fn != null && requestFocusOnOuterTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => fn.requestFocus(),
      child: field,
    );
  }
  return field;
}

/// Поле выбора категории: выпадающий список с «Свой вариант» сверху. Удаление своих — через «Управление».
class _CategoryPickerField extends StatelessWidget {
  const _CategoryPickerField({
    required this.selectedCategory,
    required this.categoryOptions,
    required this.customCategories,
    required this.categoryLabel,
    required this.canEdit,
    required this.onCategorySelected,
    required this.onAddCustom,
    required this.onRefreshCustom,
    required this.onManageCustom,
    required this.loc,
  });
  final String selectedCategory;
  final List<String> categoryOptions;
  final List<({String id, String name})> customCategories;
  final String Function(String) categoryLabel;
  final bool canEdit;
  final void Function(String) onCategorySelected;
  final Future<void> Function() onAddCustom;
  final Future<void> Function() onRefreshCustom;
  final Future<void> Function() onManageCustom;
  final LocalizationService loc;

  static const String _addValue = '__add_custom__';
  static const String _manageValue = '__manage_custom__';

  @override
  Widget build(BuildContext context) {
    if (!canEdit) {
      return InputDecorator(
        decoration: InputDecoration(
            labelText: loc.t('category'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        child: Text(categoryLabel(selectedCategory),
            overflow: TextOverflow.ellipsis),
      );
    }
    final validValues = [
      ...categoryOptions,
      ...customCategories.map((c) => 'custom:${c.id}')
    ];
    final displayValue = _addValue != selectedCategory &&
            _manageValue != selectedCategory &&
            validValues.contains(selectedCategory)
        ? selectedCategory
        : (categoryOptions.isNotEmpty ? categoryOptions.first : 'misc');
    return DropdownButtonFormField<String>(
      value: displayValue,
      isExpanded: true,
      decoration: InputDecoration(
          labelText: loc.t('category'),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      items: [
        DropdownMenuItem(
          value: _addValue,
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(loc.t('ttk_add_custom_category'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        ...categoryOptions.map(
            (c) => DropdownMenuItem(value: c, child: Text(categoryLabel(c)))),
        ...customCategories.map((c) =>
            DropdownMenuItem(value: 'custom:${c.id}', child: Text(c.name))),
        if (customCategories.isNotEmpty)
          DropdownMenuItem(
            value: _manageValue,
            child: Row(
              children: [
                Icon(Icons.settings,
                    size: 18,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text(loc.t('ttk_manage_custom_categories'),
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
              ],
            ),
          ),
      ],
      onChanged: (v) async {
        if (v == _addValue) {
          await onAddCustom();
          return;
        }
        if (v == _manageValue) {
          await onManageCustom();
          return;
        }
        if (v != null) onCategorySelected(v);
      },
    );
  }
}

class _EditableShrinkageCell extends StatefulWidget {
  const _EditableShrinkageCell({required this.value, required this.onChanged});

  final double value;
  final void Function(double? pct) onChanged;

  @override
  State<_EditableShrinkageCell> createState() => _EditableShrinkageCellState();
}

class _EditableShrinkageCellState extends State<_EditableShrinkageCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _EditableShrinkageCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _ctrl.text != widget.value.toStringAsFixed(1)) {
      _ctrl.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: _scheduleSubmit,
      onSubmit: _submit,
    );
  }
}

/// Редактируемая ячейка процента отхода
class _EditableWasteCell extends StatefulWidget {
  const _EditableWasteCell({required this.value, required this.onChanged});

  final double value;
  final void Function(double? pct) onChanged;

  @override
  State<_EditableWasteCell> createState() => _EditableWasteCellState();
}

class _EditableWasteCellState extends State<_EditableWasteCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _EditableWasteCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _ctrl.text != widget.value.toStringAsFixed(1)) {
      _ctrl.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: _scheduleSubmit,
      onSubmit: _submit,
    );
  }
}

/// Редактируемая ячейка названия продукта: ввод вручную и/или выбор из списка.
class _EditableProductNameCell extends StatefulWidget {
  const _EditableProductNameCell(
      {required this.value, required this.onChanged, this.hintText});

  final String value;
  final void Function(String) onChanged;
  final String? hintText;

  @override
  State<_EditableProductNameCell> createState() =>
      _EditableProductNameCellState();
}

class _EditableProductNameCellState extends State<_EditableProductNameCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _EditableProductNameCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    widget.onChanged(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLow
              .withValues(alpha: 0.7),
        ),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
    );
  }
}

/// Редактируемая ячейка брутто (граммы). Тап по ячейке даёт фокус полю ввода.
class _EditableGrossCell extends StatefulWidget {
  const _EditableGrossCell({
    required this.grams,
    required this.onChanged,
    this.canonicalToDisplay,
    this.displayToCanonical,
    this.decimalPlaces = 0,
  });

  final double grams;
  final void Function(double? g) onChanged;
  final double Function(double canonical)? canonicalToDisplay;
  final double Function(double display)? displayToCanonical;
  final int decimalPlaces;

  String _format(double canonical) {
    final shown = canonicalToDisplay?.call(canonical) ?? canonical;
    if (decimalPlaces <= 0) return shown.toStringAsFixed(0);
    if (shown == shown.truncateToDouble()) return shown.toInt().toString();
    return shown.toStringAsFixed(decimalPlaces);
  }

  @override
  State<_EditableGrossCell> createState() => _EditableGrossCellState();
}

class _EditableGrossCellState extends State<_EditableGrossCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget._format(widget.grams));
  }

  @override
  void didUpdateWidget(covariant _EditableGrossCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.grams != widget.grams &&
        _ctrl.text != widget._format(widget.grams)) {
      _ctrl.text = widget._format(widget.grams);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    if (v == null || v < 0) {
      widget.onChanged(null);
      return;
    }
    final canonical = widget.displayToCanonical?.call(v) ?? v;
    widget.onChanged(canonical >= 0 ? canonical : null);
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: _scheduleSubmit,
      onSubmit: _submit,
    );
  }
}

/// Редактируемая ячейка «Цена за 1000 гр» (стоимость = цена × брутто/1000)
class _EditablePricePerKgCell extends StatefulWidget {
  const _EditablePricePerKgCell({
    required this.pricePerKg,
    required this.grossWeight,
    required this.symbol,
    required this.onChanged,
  });

  final double pricePerKg;
  final double grossWeight;
  final String symbol;
  final void Function(double? cost) onChanged;

  @override
  State<_EditablePricePerKgCell> createState() =>
      _EditablePricePerKgCellState();
}

class _EditablePricePerKgCellState extends State<_EditablePricePerKgCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.pricePerKg.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _EditablePricePerKgCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pricePerKg != widget.pricePerKg &&
        _ctrl.text != widget.pricePerKg.toStringAsFixed(2)) {
      _ctrl.text = widget.pricePerKg.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    if (v != null && v >= 0 && widget.grossWeight > 0) {
      widget.onChanged(v * widget.grossWeight / 1000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: () {},
      onSubmit: _submit,
    );
  }
}

/// Редактируемая ячейка стоимости
class _EditableCostCell extends StatefulWidget {
  const _EditableCostCell(
      {required this.cost, required this.symbol, required this.onChanged});

  final double cost;
  final String symbol;
  final void Function(double? v) onChanged;

  @override
  State<_EditableCostCell> createState() => _EditableCostCellState();
}

class _EditableCostCellState extends State<_EditableCostCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.cost.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _EditableCostCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.cost != widget.cost &&
        _ctrl.text != widget.cost.toStringAsFixed(2)) {
      _ctrl.text = widget.cost.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: _scheduleSubmit,
      onSubmit: _submit,
    );
  }
}

/// Категории бара (для определения права на продажную цену).
const _barCategoriesForEdit = {
  'beverages',
  'alcoholic_cocktails',
  'non_alcoholic_drinks',
  'hot_drinks',
  'drinks_pure',
  'snacks',
  'zakuska'
};

bool _isBarDishTechCard(TechCard tc) =>
    _barCategoriesForEdit.contains(tc.category) || tc.sections.contains('bar');

bool _canSeeFullTtkViewTechCard(Employee? emp, TechCard tc) {
  if (emp == null) return false;
  if (emp.hasRole('owner')) return true;
  if ((emp.hasRole('executive_chef') || emp.hasRole('sous_chef')) &&
      !_isBarDishTechCard(tc)) return true;
  if (emp.hasRole('bar_manager') && _isBarDishTechCard(tc)) return true;
  return false;
}

bool _canEditSellingPrice(Employee? emp, TechCard? tc,
    {bool isSemiFinished = false,
    String? category,
    List<String>? sections,
    String? department}) {
  if (emp == null || isSemiFinished) return false;
  if (tc != null) return _canSeeFullTtkViewTechCard(emp, tc);
  final isBar = department == 'bar' ||
      (category != null && _barCategoriesForEdit.contains(category)) ||
      (sections?.contains('bar') ?? false);
  if (emp.hasRole('owner')) return true;
  if ((emp.hasRole('executive_chef') || emp.hasRole('sous_chef')) && !isBar)
    return true;
  if (emp.hasRole('bar_manager') && isBar) return true;
  return false;
}

TechCard _applyEdits(
  TechCard t, {
  String? dishName,
  String? category,
  List<String>? sections,
  bool? isSemiFinished,
  double? portionWeight,
  double? yieldGrams,
  Map<String, String>? technologyLocalized,
  String? descriptionForHall,
  String? compositionForHall,
  double? sellingPrice,
  List<String>? photoUrls,
  List<TTIngredient>? ingredients,
}) {
  return t.copyWith(
    dishName: dishName,
    category: category,
    sections: sections,
    isSemiFinished: isSemiFinished,
    portionWeight: portionWeight,
    yield: yieldGrams,
    technologyLocalized: technologyLocalized,
    descriptionForHall: descriptionForHall,
    compositionForHall: compositionForHall,
    sellingPrice: sellingPrice,
    photoUrls: photoUrls,
    ingredients: ingredients,
  );
}

class TechCardEditScreen extends StatefulWidget {
  const TechCardEditScreen({
    super.key,
    required this.techCardId,
    this.initialFromAi,
    this.initialTechCard,
    this.forceViewMode = false,
    this.department,
    this.forceHallView = false,
    this.initialCategory,
    this.initialSections,
    this.initialIsSemiFinished,
    this.initialTypeRevision,
    this.initialHeaderSignature,
    this.initialSourceRows,
    this.initialViewTargetOutputGrams,
    this.fromAiGeneration = false,
  });

  /// Пусто для «новой», иначе id существующей ТТК.
  final String techCardId;

  /// Предзагруженная карточка (от _DeferredTechCardEdit). Пропускает getTechCardById.
  final TechCard? initialTechCard;

  /// Предзаполнение из ИИ (фото/Excel). Используется только при techCardId == 'new'.
  final TechCardRecognitionResult? initialFromAi;

  /// ТТК создана запросом «Создать с ИИ» (текстовый промпт), не импорт из файла.
  final bool fromAiGeneration;

  /// Подпись заголовка при импорте — для сохранения правок в tt_parse_corrections.
  final String? initialHeaderSignature;

  /// Строки при импорте — для обучения (ищем corrected в них, сохраняем позицию).
  final List<List<String>>? initialSourceRows;

  /// Режим только просмотра (для управляющих кухней — кнопка «Просмотр ТТК»).
  final bool forceViewMode;

  /// Отдел при создании: 'bar' — категории бара, иначе кухни.
  final String? department;

  /// Показать описание и состав для зала вместо полной ТТК (меню зала).
  final bool forceHallView;

  /// Целевой выход (г) для режима просмотра из чеклиста.
  /// Может передаваться роутером; в ручном редактировании не используется.
  final double? initialViewTargetOutputGrams;

  /// Категория и цеха при открытии из импорта.
  final String? initialCategory;
  final List<String>? initialSections;
  final bool? initialIsSemiFinished;

  /// Версия массового выбора типа на экране проверки импорта. При изменении должна перебивать ручной выбор в черновике.
  final int? initialTypeRevision;

  @override
  State<TechCardEditScreen> createState() => _TechCardEditScreenState();
}

class _TechCardEditScreenState extends State<TechCardEditScreen>
    with
        AutoSaveMixin<TechCardEditScreen>,
        InputChangeListenerMixin<TechCardEditScreen> {
  TechCard? _techCard;
  bool _loading = true;
  bool _technologyTranslating = false;
  String? _error;

  /// 0=подготовка, 1=полная форма. Растягиваем билд по кадрам — без замирания.
  int _contentPhase = 1;

  /// В режиме просмотра для повара `_TtkCookTable` пересчитывает значения локально.
  /// Синхронизацию обратно в родителя и автосохранение делаем с debounce и без `setState`,
  /// чтобы не блокировать UI при каждом пересчёте.
  Timer? _cookTableSyncDebounce;

  late final VoidCallback _localizationListener;

  /// 'photo' | 'excel' — какая кнопка сейчас загружает (чтобы показывать правильный текст).
  final _nameController = TextEditingController();

  /// Кухня: без напитков. Рыба, мясо, птица, заготовка и т.д.
  static const _kitchenCategoryOptions = [
    'sauce',
    'vegetables',
    'zagotovka',
    'salad',
    'zakuska',
    'meat',
    'seafood',
    'poultry',
    'side',
    'subside',
    'bakery',
    'dessert',
    'decor',
    'soup',
    'misc',
    'banquet',
    'catering'
  ];

  /// Бар: только напитки и снеки.
  static const _barCategoryOptions = [
    'alcoholic_cocktails',
    'non_alcoholic_drinks',
    'hot_drinks',
    'drinks_pure',
    'snacks',
    'zakuska',
    'beverages'
  ];

  /// Отдел для категорий: bar или kitchen.
  String get _categoryDepartment {
    if (widget.department == 'bar') return 'bar';
    if (_techCard != null && _barCategoryOptions.contains(_techCard!.category))
      return 'bar';
    return 'kitchen';
  }

  /// Клик вне активного поля ввода — снять фокус с ячейки ТТК (веб/ПК).
  void _unfocusTtkPointerIfOutsideFocusedField(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    final ctx = focus.context;
    if (ctx == null) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
      focus.unfocus();
      return;
    }
    final rect = ro.localToGlobal(Offset.zero) & ro.size;
    if (!rect.contains(event.position)) {
      focus.unfocus();
    }
  }

  /// Базовые + пользовательские категории.
  List<String> get _categoryOptions {
    final base = _categoryDepartment == 'bar'
        ? _barCategoryOptions
        : _kitchenCategoryOptions;
    final custom = _customCategories.map((c) => 'custom:${c.id}').toList();
    return [...base, ...custom];
  }

  /// Пользовательские категории (свой вариант) по отделам.
  List<({String id, String name})> _customCategoriesKitchen = [];
  List<({String id, String name})> _customCategoriesBar = [];

  List<({String id, String name})> get _customCategories =>
      _categoryDepartment == 'bar'
          ? _customCategoriesBar
          : _customCategoriesKitchen;
  // Ключи секций: id → (localization_key, requiresPro)
  // Цеха кухни: код → (ключ локализации, requiresPro)
  static const _sectionKeys = <String, (String, bool)>{
    'hot_kitchen': ('section_hot_kitchen', false),
    'cold_kitchen': ('section_cold_kitchen', false),
    'preparation': ('section_prep', false),
    'confectionery': ('section_pastry', false),
    'grill': ('section_grill', false),
    'pizza': ('section_pizza', false),
    'sushi': ('section_sushi', false),
    'bakery': ('section_bakery', false),
    'banquet_catering': ('section_banquet_catering', false),
  };

  // Русские названия цехов (fallback если нет локализации)
  static const _sectionLabelsRu = <String, String>{
    'hot_kitchen': 'Горячий цех',
    'cold_kitchen': 'Холодный цех',
    'preparation': 'Заготовки',
    'confectionery': 'Кондитерский',
    'grill': 'Гриль',
    'pizza': 'Пицца',
    'sushi': 'Суши',
    'bakery': 'Пекарня',
    'banquet_catering': 'Банкет / Кейтринг',
  };

  Map<String, String> _getAvailableSections(
      bool hasPro, LocalizationService loc) {
    return Map.fromEntries(
      _sectionKeys.entries.map((e) => MapEntry(e.key, loc.t(e.value.$1))),
    );
  }

  String _sectionLabel(String code, LocalizationService loc) {
    final sections = _getAvailableSections(true, loc);
    return sections[code] ?? _sectionLabelsRu[code] ?? code;
  }

  String _selectedCategory = 'misc';
  List<String> _selectedSections = []; // [] = Скрыто, ['all'] = Все цеха
  bool _isSemiFinished =
      true; // ПФ или блюдо (порция — в карточках блюд, отдельно)
  // Если пользователь вручную переключил тип ПФ/Блюдо в редакторе, его выбор должен иметь приоритет над экраном импорта.
  bool _typeManuallyChanged = false;
  final _technologyController = TextEditingController();
  final _descriptionForHallController = TextEditingController();
  final _compositionForHallController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final List<TTIngredient> _ingredients = [];

  /// Кэш блока КБЖУ блюда (пересчёт только при изменении строк или данных продуктов в Store).
  String? _dishKbjuDerivedKey;
  List<String> _dishKbjuMissingNames = const [];
  double _dishKbjuTotalCal = 0;
  double _dishKbjuTotalProt = 0;
  double _dishKbjuTotalFat = 0;
  double _dishKbjuTotalCarb = 0;
  String? _dishKbjuAllergenStr;
  List<TechCard> _pickerTechCards = [];
  List<TechCard> _semiFinishedProducts = [];
  double _portionWeight =
      100; // вес порции (г), вносится в столбец «вес прц» в итого
  /// URL фото с сервера (для существующей ТТК)
  List<String> _photoUrls = [];

  /// Фото, выбранные для новой ТТК до первого сохранения (загружаем после create)
  List<Uint8List> _pendingPhotoBytes = [];
  bool _saving = false;
  bool _duplicating = false;
  Map<String, String> _ingredientNameTranslationsById = const {};
  String _ingredientNameTranslationsLang = '';
  String _ingredientNameTranslationsCardId = '';
  final Set<String> _ingredientTranslationBackfillInFlight = <String>{};

  Timer? _ingredientUpdateDebounce;
  Timer? _reconcileOpenCardTimer;
  TechCardsReconcileNotifier? _reconcileNotifier;
  int _lastReconcileNotifierVersion = 0;
  bool _reconciling = false;
  DateTime _lastReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _portionWeightUpdateDebounce;

  /// Только для горизонтального скролла таблицы состава — иначе [Scrollbar] цепляется к вложенному вертикальному [SingleChildScrollView] и рисуется «по центру».
  final ScrollController _compositionTableHScrollController =
      ScrollController();

  /// Время последнего пользовательского взаимодействия (ввод/тап в таблице).
  /// Используется, чтобы не запускать тяжёлый reconcile в момент, когда пользователь
  /// прямо что-то меняет — иначе UI начинает "подвисать".
  DateTime _lastUserInteractionAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Дебаунс на запуск reconcile после пользовательских правок.
  Timer? _reconcileDebounceTimer;

  /// Для web автосохранение черновика (localStorage + jsonEncode) может быть тяжёлым,
  /// поэтому откладываем сохранение до "паузы" после ввода, чтобы не фризить UI.
  Timer? _draftSaveIdleDebounceTimer;

  bool get _isNew => widget.techCardId.isEmpty || widget.techCardId == 'new';

  /// Защита от повторного запуска тяжёлой гидратации ПФ, если пользователь быстро
  /// переключает режимы/окна (view/edit) или карточка догружается асинхронно.
  bool _semiFinishedCostHydrationRunning = false;

  Future<void> _ensureSemiFinishedProductsForCost(TechCard currentTc) async {
    if (_semiFinishedCostHydrationRunning) return;
    // Если список ПФ уже заполнен и в нём уже есть цены/стоимости —
    // повторно не гидратим.
    if (_semiFinishedProducts.isNotEmpty) {
      final hasIngredients =
          _semiFinishedProducts.any((pf) => pf.ingredients.isNotEmpty);
      final hasAnyPrices = _semiFinishedProducts.any((pf) => pf.ingredients.any(
          (ing) =>
              (ing.pricePerKg != null && ing.pricePerKg! > 0) ||
              ing.cost > 0 ||
              ing.effectiveCost > 0));
      if (hasIngredients && hasAnyPrices) return;
    }

    _semiFinishedCostHydrationRunning = true;
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      if (est == null) return;

      final tcSvc = context.read<TechCardServiceSupabase>();
      final productStore = context.read<ProductStoreSupabase>();

      final estPriceId =
          est.isBranch ? est.id : (est.dataEstablishmentId ?? '');
      if (estPriceId.isEmpty) return;

      // Цены листовых ингредиентов берём из номенклатуры заведения.
      await productStore.loadProducts().catchError((_) {});
      if (est.isBranch) {
        await productStore
            .loadNomenclatureForBranch(
                est.id, est.dataEstablishmentId ?? estPriceId)
            .catchError((_) {});
      } else {
        final mainId = est.dataEstablishmentId ?? estPriceId;
        if (mainId.isNotEmpty) {
          await productStore.loadNomenclature(mainId).catchError((_) {});
        }
      }

      final neededPfIds = <String>{};
      for (final ing in currentTc.ingredients) {
        if (ing.sourceTechCardId != null &&
            ing.sourceTechCardId!.trim().isNotEmpty) {
          neededPfIds.add(ing.sourceTechCardId!.trim());
        }
      }
      if (neededPfIds.isEmpty) return;

      // Точечная загрузка только связанных ПФ — без полного списка ТТК заведения.
      final fetched = await Future.wait(
        neededPfIds.map((id) => tcSvc.getTechCardById(id)),
      );
      final pfCards =
          fetched.whereType<TechCard>().where((t) => t.isSemiFinished).toList();
      if (pfCards.isEmpty) return;

      // Догружаем ингредиенты ПФ и гидратим их стоимость/pricePerKg.
      final pfFilled = await tcSvc.fillIngredientsForCardsBulk(pfCards);
      final attachedPfs = pfFilled
          .map((pf) => _attachMissingPfSourceTechCardId(pf, pfFilled))
          .toList();

      final hydratedPfs = TechCardCostHydrator.hydrate(
        attachedPfs,
        productStore,
        estPriceId,
      );

      // Важно: прикрепить sourceTechCardId текущей ТТК к нужным ПФ, иначе
      // ExcelStyleTtkTable не сможет рекурсивно достать цены ПФ.
      final updatedCurrent =
          _attachMissingPfSourceTechCardId(currentTc, hydratedPfs);

      final hydratedList = TechCardCostHydrator.hydrate(
        [updatedCurrent, ...hydratedPfs],
        productStore,
        estPriceId,
      );
      final hydratedCurrent = hydratedList.firstWhere(
        (item) => item.id == updatedCurrent.id,
        orElse: () => updatedCurrent,
      );
      final hydratedNutrition =
          TechCardNutritionHydrator.hydrate(hydratedList, productStore);
      final hydratedCurrent2 = hydratedNutrition.firstWhere(
        (item) => item.id == hydratedCurrent.id,
        orElse: () => hydratedCurrent,
      );

      if (!mounted) return;
      setState(() {
        _semiFinishedProducts = hydratedNutrition
            .where((t) => t.isSemiFinished)
            .toList(growable: false);
        _techCard = hydratedCurrent2;
        _ingredients
          ..clear()
          ..addAll(hydratedCurrent2.ingredients);
        _ensurePlaceholderRowAtEnd();
      });
    } finally {
      _semiFinishedCostHydrationRunning = false;
    }
  }

  @override
  String get draftKey {
    if (widget.techCardId.isNotEmpty && widget.techCardId != 'new') {
      return 'tech_card_edit_${widget.techCardId}';
    }
    // При открытии из импорта — детерминированный ключ по содержимому карточки (не identityHashCode),
    // чтобы корректно работало у всех: разные платформы, сессии, браузеры.
    if (widget.initialFromAi != null) {
      return 'tech_card_edit_import_${_importDraftKeyHash(widget.initialFromAi!)}';
    }
    final dept =
        (widget.department ?? '').trim().toLowerCase() == 'bar' ? 'bar' : 'kitchen';
    return 'tech_card_edit_new_$dept';
  }

  /// Детерминированный хеш для уникального ключа черновика при открытии из импорта.
  /// На основе названия и ингредиентов — один и тот же состав даёт один и тот же ключ.
  static String _importDraftKeyHash(TechCardRecognitionResult r) {
    final name = r.dishName ?? '';
    final ingPart = r.ingredients
        .map((i) => '${i.productName}|${i.grossGrams ?? 0}|${i.netGrams ?? 0}')
        .join(';');
    final h = Object.hash(name, ingPart);
    return (h & 0x7FFFFFFF).toRadixString(36);
  }

  @override
  bool get restoreDraftAfterLoad => true;

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'draftSavedAt': DateTime.now().toUtc().toIso8601String(),
      'techCardId': widget.techCardId,
      'name': _nameController.text,
      'technology': _technologyController.text,
      'category': _selectedCategory,
      'sections': _selectedSections,
      'isSemiFinished': _isSemiFinished,
      'typeManuallyChanged': _typeManuallyChanged,
      'typeRevision': widget.initialTypeRevision ?? 0,
      'portionWeight': _portionWeight,
      'descriptionForHall': _descriptionForHallController.text,
      'compositionForHall': _compositionForHallController.text,
      'sellingPrice': _sellingPriceController.text,
      'ingredients': _ingredients.map((i) => i.toJson()).toList(),
      'photoUrls': _photoUrls,
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (data['techCardId'] != widget.techCardId) return;
    // При открытии из импорта иногда остаётся пустой черновик (например, после сбоя/непереданного extra).
    // Чтобы не затирать распознанные данные, игнорируем «пустой» черновик для импорт‑карточек.
    if (widget.initialFromAi != null) {
      final name = (data['name'] as String? ?? '').trim();
      final tech = (data['technology'] as String? ?? '').trim();
      final rawIng = data['ingredients'];
      final hasAnyIngredientName = rawIng is List
          ? rawIng.any((e) {
              if (e is! Map) return false;
              final m = Map<String, dynamic>.from(e);
              return (m['productName'] as String? ?? '').trim().isNotEmpty;
            })
          : false;
      final looksEmpty = name.isEmpty && tech.isEmpty && !hasAnyIngredientName;
      if (looksEmpty) return;
    }
    // Web: после загрузки с сервера вызывается restoreDraftNow(). Если в localStorage
    // лежит старый черновик только с пустыми строками таблицы, он перетирает реальный состав.
    // Для обычных ТТК (не импорт) не подменяем серверные ингредиенты «пустым» черновиком.
    final skipIngredientsFromDraft = widget.techCardId.isNotEmpty &&
        widget.techCardId != 'new' &&
        widget.initialFromAi == null &&
        _namedIngredientCountLoaded() > 0 &&
        _namedIngredientCountInDraft(data['ingredients'] as List<dynamic>?) ==
            0;
    if (!mounted) return;
    setState(() {
      _nameController.text = data['name'] as String? ?? '';
      _technologyController.text = data['technology'] as String? ?? '';
      _selectedCategory = data['category'] as String? ?? 'misc';
      _selectedSections =
          List<String>.from(data['sections'] as List<dynamic>? ?? []);
      // При открытии из импорта тип ПФ/Блюдо управляется экраном проверки импорта (extra initialIsSemiFinished).
      // Но если пользователь вручную переключал тип внутри редактора — берём тип из черновика.
      final desiredFromImport = widget.initialIsSemiFinished ??
          widget.initialFromAi?.isSemiFinished ??
          true;
      final draftRev = (data['typeRevision'] is num)
          ? (data['typeRevision'] as num).toInt()
          : 0;
      final currentRev = widget.initialTypeRevision ?? 0;
      final revisionChanged =
          widget.initialFromAi != null && currentRev != draftRev;
      final manual = !revisionChanged && data['typeManuallyChanged'] == true;
      _typeManuallyChanged = manual;
      _isSemiFinished = widget.initialFromAi != null
          ? (manual
              ? (data['isSemiFinished'] as bool? ?? desiredFromImport)
              : desiredFromImport)
          : (data['isSemiFinished'] as bool? ?? true);
      final fromDraft = (data['portionWeight'] as num?)?.toDouble();
      // Сумма выходов из восстанавливаемых ингредиентов (для расчёта веса порции при импорте)
      var sumFromData = 0.0;
      for (final item in data['ingredients'] as List<dynamic>? ?? []) {
        final m = item is Map ? item as Map : null;
        if (m != null)
          sumFromData += ((m['outputWeight'] as num?)?.toDouble()) ?? 0;
      }
      final sum = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
      final sumOrData = sum > 0 ? sum : sumFromData;
      if (widget.initialFromAi != null) {
        // Открыто из импорта: вес порции только по правилу (ПФ=100, Блюдо=выход из файла или сумма), черновик не используем
        _portionWeight = _isSemiFinished
            ? 100
            : (widget.initialFromAi!.yieldGrams != null &&
                    widget.initialFromAi!.yieldGrams! > 0
                ? widget.initialFromAi!.yieldGrams!.toDouble()
                : (sumOrData > 0 ? sumOrData : 100));
      } else if (_isSemiFinished) {
        // ТТК ПФ: по умолчанию 100; из черновика (защита от ошибочно больших значений)
        _portionWeight =
            (fromDraft != null && fromDraft > 0 && fromDraft <= 10000
                    ? fromDraft
                    : null) ??
                100;
      } else {
        // ТТК блюдо: по умолчанию = вес выхода итого; черновик не берём если явно ошибочный
        double? draft = fromDraft != null && fromDraft > 0 ? fromDraft : null;
        if (draft != null &&
            sumOrData > 0 &&
            (draft > 5 * sumOrData || draft < 0.2 * sumOrData)) draft = null;
        _portionWeight = draft ?? (sumOrData > 0 ? sumOrData : 100);
      }
      _descriptionForHallController.text =
          data['descriptionForHall'] as String? ?? '';
      _compositionForHallController.text =
          data['compositionForHall'] as String? ?? '';
      _sellingPriceController.text = data['sellingPrice'] as String? ?? '';
      _photoUrls = List<String>.from(data['photoUrls'] as List<dynamic>? ?? []);
      if (!skipIngredientsFromDraft) {
        _ingredients.clear();
        for (final item in data['ingredients'] as List<dynamic>? ?? []) {
          try {
            _ingredients.add(
                TTIngredient.fromJson(Map<String, dynamic>.from(item as Map)));
          } catch (_) {}
        }
      }
      _ensurePlaceholderRowAtEnd();
    });
  }

  /// Сколько строк черновика реально похожи на ингредиенты (не placeholder и с названием).
  int _namedIngredientCountInDraft(List<dynamic>? raw) {
    if (raw == null) return 0;
    var n = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final ing = TTIngredient.fromJson(Map<String, dynamic>.from(item));
        if (ing.isPlaceholder) continue;
        if (ing.productName.trim().isEmpty) continue;
        n++;
      } catch (_) {}
    }
    return n;
  }

  int _namedIngredientCountLoaded() {
    return _ingredients
        .where((i) => !i.isPlaceholder && i.productName.trim().isNotEmpty)
        .length;
  }

  /// Всегда держать хотя бы одну пустую строку для ввода в конце таблицы ингредиентов.
  void _ensurePlaceholderRowAtEnd() {
    if (!mounted) return;
    final canEdit = context
            .read<AccountManagerSupabase>()
            .currentEmployee
            ?.canEditChecklistsAndTechCards ??
        false;
    if (!canEdit || widget.forceViewMode) return;
    if (_ingredients.isEmpty) {
      _ingredients.add(TTIngredient.emptyPlaceholder());
      _ingredients.add(TTIngredient.emptyPlaceholder());
    } else if (!_ingredients.last.isPlaceholder) {
      _ingredients.add(TTIngredient.emptyPlaceholder());
    }
  }

  /// Макс. фото: ПФ — 10, блюдо — 1
  int get _maxPhotos => _isSemiFinished ? 10 : 1;

  double? _parseSellingPrice() {
    final s = _sellingPriceController.text.trim();
    if (s.isEmpty) return null;
    final v = double.tryParse(s.replaceAll(',', '.'));
    return (v != null && v >= 0) ? v : null;
  }

  String _categoryLabel(String c, String lang) {
    if (TechCardServiceSupabase.isCustomCategory(c)) {
      final id = TechCardServiceSupabase.customCategoryId(c);
      for (final x in _customCategories) {
        if (x.id == id) return x.name;
      }
      return c;
    }
    final Map<String, Map<String, String>> categoryTranslations = {
      'sauce': {'ru': 'Соус', 'en': 'Sauce'},
      'vegetables': {'ru': 'Овощи', 'en': 'Vegetables'},
      'zagotovka': {'ru': 'Заготовка', 'en': 'Preparation'},
      'salad': {'ru': 'Салат', 'en': 'Salad'},
      'meat': {'ru': 'Мясо', 'en': 'Meat'},
      'seafood': {'ru': 'Рыба', 'en': 'Seafood'},
      'poultry': {'ru': 'Птица', 'en': 'Poultry'},
      'side': {'ru': 'Гарнир', 'en': 'Side dish'},
      'subside': {'ru': 'Подгарнир', 'en': 'Sub-side dish'},
      'bakery': {'ru': 'Выпечка', 'en': 'Bakery'},
      'dessert': {'ru': 'Десерт', 'en': 'Dessert'},
      'decor': {'ru': 'Декор', 'en': 'Decor'},
      'soup': {'ru': 'Суп', 'en': 'Soup'},
      'misc': {'ru': 'Разное', 'en': 'Misc'},
      'beverages': {'ru': 'Напитки', 'en': 'Beverages'},
      'alcoholic_cocktails': {
        'ru': 'Алкогольные коктейли',
        'en': 'Alcoholic cocktails'
      },
      'non_alcoholic_drinks': {
        'ru': 'Безалкогольные напитки',
        'en': 'Non-alcoholic drinks'
      },
      'hot_drinks': {'ru': 'Горячие напитки', 'en': 'Hot drinks'},
      'drinks_pure': {'ru': 'Напитки в чистом виде', 'en': 'Drinks (neat)'},
      'snacks': {'ru': 'Снеки', 'en': 'Snacks'},
      'zakuska': {'ru': 'Закуска', 'en': 'Appetizer'},
      'banquet': {'ru': 'Банкет', 'en': 'Banquet'},
      'catering': {'ru': 'Кейтеринг', 'en': 'Catering'},
    };

    return categoryTranslations[c]?[lang] ?? c;
  }

  /// Подтягивает цену за кг и стоимость из номенклатуры заведения по названию продукта (для импортированных ТТК).
  void _autoFillPriceFromNomenclature() {
    final store = context.read<ProductStoreSupabase>();
    final est = context.read<AccountManagerSupabase>().establishment;
    final establishmentId =
        est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
    if (establishmentId == null) return;
    final list = <TTIngredient>[];
    for (final ing in _ingredients) {
      if (ing.isPlaceholder ||
          ing.productName.trim().isEmpty ||
          ing.sourceTechCardId != null) {
        list.add(ing);
        continue;
      }
      final product =
          store.findProductForIngredient(ing.productId, ing.productName);
      if (product == null) {
        list.add(ing);
        continue;
      }
      final priceInfo =
          store.getEstablishmentPrice(product.id, establishmentId);
      final pricePerKg = priceInfo?.$1 ?? 0.0;
      if (pricePerKg <= 0) {
        list.add(ing);
        continue;
      }
      final cost = (pricePerKg * ing.grossWeight / 1000);
      list.add(ing.copyWith(
          productId: product.id, pricePerKg: pricePerKg, cost: cost));
    }
    _ingredients
      ..clear()
      ..addAll(list);
  }

  /// Подставляет брутто в граммах по номенклатуре, когда продукт в шт и задан вес 1 шт (например яйцо 1 шт → 60 г).
  void _autoFillBruttoFromNomenclature() {
    final store = context.read<ProductStoreSupabase>();
    final list = <TTIngredient>[];
    for (final ing in _ingredients) {
      if (ing.isPlaceholder || ing.productName.trim().isEmpty) {
        list.add(ing);
        continue;
      }
      final product =
          store.findProductForIngredient(ing.productId, ing.productName);
      final unit = (product?.unit ?? ing.unit).toLowerCase();
      final gpp = product?.gramsPerPiece;
      if ((unit == 'шт' || unit == 'pcs') && gpp != null && gpp > 0) {
        final g = ing.grossWeight;
        final n = ing.netWeight;
        final oldGpp = ing.gramsPerPiece ?? 50;
        // Вес 1 шт изменился в номенклатуре — сохраняем нетто, пересчитываем брутто и % отхода
        if (oldGpp > 0 && (gpp - oldGpp).abs() > 0.01 && g > 0) {
          final pieces = g / oldGpp;
          final newGross = pieces * gpp;
          final newWaste = newGross > 0
              ? ((1.0 - n / newGross) * 100).clamp(0.0, 99.9)
              : 0.0;
          list.add(ing.copyWith(
            grossWeight: newGross,
            gramsPerPiece: gpp,
            primaryWastePct: newWaste,
            isNetWeightManual: ing.isNetWeightManual,
          ));
          continue;
        }
        // Брутто в документе часто в штуках (1–25); переводим в граммы по номенклатуре
        if (g > 0 && g <= 25 && g == g.roundToDouble()) {
          final grossGrams = g * gpp;
          list.add(ing.copyWith(grossWeight: grossGrams, gramsPerPiece: gpp));
          continue;
        }
        // Брутто 0, нетто в штуках (1–20) — подставляем брутто в граммах
        if (g <= 0 && n > 0 && n <= 20 && n == n.roundToDouble()) {
          final grossGrams = n * gpp;
          list.add(ing.copyWith(grossWeight: grossGrams, gramsPerPiece: gpp));
          continue;
        }
        if (ing.gramsPerPiece == null)
          list.add(ing.copyWith(gramsPerPiece: gpp));
        else
          list.add(ing);
        continue;
      }
      // Продукт в граммах: брутто 0 при заполненном нетто — подставляем брутто = нетто (без отхода)
      if (ing.grossWeight <= 0 && ing.netWeight > 0) {
        final u = (product?.unit ?? ing.unit).toLowerCase();
        if (u == 'g' || u == 'г' || u == 'kg' || u == 'кг' || u.isEmpty) {
          list.add(ing.copyWith(grossWeight: ing.netWeight));
          continue;
        }
      }
      list.add(ing);
    }
    _ingredients
      ..clear()
      ..addAll(list);
  }

  /// После привязки продуктов из номенклатуры — пересчитать нетто/КБЖУ с учётом способа и % ужарки.
  void _syncIngredientsCookingNutrition() {
    final store = context.read<ProductStoreSupabase>();
    final lang = context.read<LocalizationService>().currentLanguageCode;
    final list = <TTIngredient>[];
    for (final ing in _ingredients) {
      if (ing.isPlaceholder) {
        list.add(ing);
        continue;
      }
      final product =
          store.findProductForIngredient(ing.productId, ing.productName);
      final procId = ing.cookingProcessId?.trim();
      if (product == null ||
          procId == null ||
          procId.isEmpty ||
          procId == 'custom') {
        list.add(ing);
        continue;
      }
      final proc = CookingProcess.findById(procId);
      if (proc == null) {
        list.add(ing);
        continue;
      }
      list.add(
        ing.updateCookingLossPct(
          ing.cookingLossPctOverride,
          product,
          proc,
          languageCode: lang,
        ),
      );
    }
    _ingredients
      ..clear()
      ..addAll(list);
  }

  /// После выбора продукта в таблице — глобальные подсказки % отхода и % ужарки (системная БД).
  void _refreshGlobalProcessingHintsForRow(int index) {
    unawaited(_refreshGlobalProcessingHintsForRowAsync(index));
  }

  Future<void> _refreshGlobalProcessingHintsForRowAsync(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _ingredients.length) return;
    var ing = _ingredients[index];
    final pid = ing.productId?.trim();
    if (pid == null || pid.isEmpty || ing.isPlaceholder) return;
    if (ing.sourceTechCardId != null &&
        ing.sourceTechCardId!.trim().isNotEmpty) {
      return;
    }
    final store = context.read<ProductStoreSupabase>();
    final product = store.findProductForIngredient(pid, ing.productName);
    final lang = context.read<LocalizationService>().currentLanguageCode;

    final suggestedWaste =
        await ProductCookingLossLearning.getSuggestedWastePct(productId: pid);
    final catalogWaste = product?.primaryWastePct;
    final wasteToApply = suggestedWaste ?? catalogWaste;

    final procId = ing.cookingProcessId?.trim();
    double? suggestedLoss;
    if (procId != null && procId.isNotEmpty && procId != 'custom') {
      suggestedLoss = await ProductCookingLossLearning.getSuggestedLossPct(
        productId: pid,
        cookingProcessId: procId,
      );
    }

    if (!mounted) return;
    if (index < 0 || index >= _ingredients.length) return;
    ing = _ingredients[index];
    if (ing.productId?.trim() != pid) return;

    var next = ing;
    if (wasteToApply != null) {
      final w = wasteToApply.clamp(0.0, 99.9);
      final proc = procId != null && procId.isNotEmpty && procId != 'custom'
          ? CookingProcess.findById(procId)
          : null;
      next = next.updatePrimaryWastePct(w, product, proc);
    }
    if (suggestedLoss != null &&
        procId != null &&
        procId.isNotEmpty &&
        procId != 'custom' &&
        product != null) {
      final proc = CookingProcess.findById(procId);
      if (proc != null) {
        next = next.updateCookingLossPct(
          suggestedLoss,
          product,
          proc,
          languageCode: lang,
        );
      }
    }

    setState(() {
      if (index < _ingredients.length &&
          _ingredients[index].productId?.trim() == pid) {
        _ingredients[index] = next;
      }
    });
    _scheduleDraftSave();
  }

  Future<void> _suggestCookingLossForRow(int index) async {
    if (index < 0 || index >= _ingredients.length) return;
    final ing = _ingredients[index];
    if (ing.isPlaceholder) return;
    final pid = ing.productId?.trim();
    final procId = ing.cookingProcessId?.trim();
    if (pid == null ||
        pid.isEmpty ||
        procId == null ||
        procId.isEmpty ||
        procId == 'custom') {
      return;
    }
    final suggested = await ProductCookingLossLearning.getSuggestedLossPct(
      productId: pid,
      cookingProcessId: procId,
    );
    if (!mounted || suggested == null) return;
    final store = context.read<ProductStoreSupabase>();
    final lang = context.read<LocalizationService>().currentLanguageCode;
    final product =
        store.findProductForIngredient(ing.productId, ing.productName);
    final proc = CookingProcess.findById(procId);
    if (product == null || proc == null) return;
    setState(() {
      _ingredients[index] = _ingredients[index].updateCookingLossPct(
        suggested,
        product,
        proc,
        languageCode: lang,
      );
    });
    _scheduleDraftSave();
  }

  /// Простой вывод категории из названия блюда (для предзаполнения из ИИ).
  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (widget.department == 'bar') {
      if (lower.contains('коктейл') ||
          lower.contains('cocktail') ||
          lower.contains('мохито') ||
          lower.contains('маргарит')) return 'alcoholic_cocktails';
      if (lower.contains('лимонад') ||
          lower.contains('сок') ||
          lower.contains('кола') ||
          lower.contains('тоник') ||
          lower.contains('soda') ||
          lower.contains('juice')) return 'non_alcoholic_drinks';
      if (lower.contains('кофе') ||
          lower.contains('капучино') ||
          lower.contains('латте') ||
          lower.contains('эспрессо') ||
          lower.contains('раф') ||
          lower.contains('чай') ||
          lower.contains('какао') ||
          lower.contains('coffee') ||
          lower.contains('cappuccino') ||
          lower.contains('latte') ||
          lower.contains('espresso') ||
          lower.contains('flat white') ||
          lower.contains('tea') ||
          lower.contains('cocoa')) return 'hot_drinks';
      if (lower.contains('виски') ||
          lower.contains('ром') ||
          lower.contains('водка') ||
          lower.contains('вино') ||
          lower.contains('пиво') ||
          lower.contains('whiskey') ||
          lower.contains('rum') ||
          lower.contains('vodka') ||
          lower.contains('wine') ||
          lower.contains('beer')) return 'drinks_pure';
      if (lower.contains('орех') ||
          lower.contains('чипс') ||
          lower.contains('снек') ||
          lower.contains('nuts') ||
          lower.contains('chips') ||
          lower.contains('snack')) return 'snacks';
      if (lower.contains('закуск') ||
          lower.contains('appetizer') ||
          lower.contains('antipasti')) return 'zakuska';
    }
    if (lower.contains('соус') || lower.contains('sauce')) return 'sauce';
    if (lower.contains('овощ') || lower.contains('vegetable'))
      return 'vegetables';
    if (lower.contains('заготовк') ||
        lower.contains('preparation') ||
        lower.contains('подготовк')) return 'zagotovka';
    if (lower.contains('салат') || lower.contains('salad')) return 'salad';
    if (lower.contains('закуск') ||
        lower.contains('appetizer') ||
        lower.contains('antipasti')) return 'zakuska';
    if (lower.contains('мяс') ||
        lower.contains('meat') ||
        lower.contains('говядин') ||
        lower.contains('свинин') ||
        lower.contains('баран')) return 'meat';
    if (lower.contains('рыб') ||
        lower.contains('fish') ||
        lower.contains('море') ||
        lower.contains('seafood')) return 'seafood';
    if (lower.contains('птиц') ||
        lower.contains('poultry') ||
        lower.contains('куриц') ||
        lower.contains('индейк') ||
        lower.contains('утк') ||
        lower.contains('цыплят')) return 'poultry';
    if (lower.contains('гарнир') || lower.contains('side')) return 'side';
    if (lower.contains('подгарнир') || lower.contains('subside'))
      return 'subside';
    if (lower.contains('выпеч') ||
        lower.contains('bakery') ||
        lower.contains('хлеб') ||
        lower.contains('тест')) return 'bakery';
    if (lower.contains('десерт') || lower.contains('dessert')) return 'dessert';
    if (lower.contains('декор') || lower.contains('decor')) return 'decor';
    if (lower.contains('суп') || lower.contains('soup')) return 'soup';
    if (lower.contains('напит') ||
        lower.contains('beverage') ||
        lower.contains('сок') ||
        lower.contains('компот')) return 'beverages';
    return 'misc';
  }

  bool get _hasImportVerificationContext {
    if (widget.initialFromAi != null) return true;
    final sig = widget.initialHeaderSignature?.trim();
    if (sig != null && sig.isNotEmpty) return true;
    final rows = widget.initialSourceRows;
    return rows != null && rows.isNotEmpty;
  }

  Future<void> _maybeShowImportVerificationNotice() async {
    if (!_hasImportVerificationContext) return;
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final titleKey = widget.fromAiGeneration
        ? 'ttk_ai_verify_title'
        : 'ttk_import_verify_title';
    final messageKey = widget.fromAiGeneration
        ? 'ttk_ai_verify_message'
        : 'ttk_import_verify_message';
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t(titleKey)),
        content: SingleChildScrollView(
          child: Text(loc.t(messageKey)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('dialog_ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final est = context.read<AccountManagerSupabase>().establishment;
      var loadedTechCards = <TechCard>[];
      if (est != null) {
        final productStore = context.read<ProductStoreSupabase>();
        final canEditNow = context
                .read<AccountManagerSupabase>()
                .currentEmployee
                ?.canEditChecklistsAndTechCards ??
            false;
        final shouldLoadPickerData = canEditNow && !widget.forceViewMode;
        // Продукты и номенклатура — в фоне, не блокируем показ формы
        Future.microtask(() async {
          try {
            await productStore.loadProducts().catchError((_) {});
            if (!mounted) return;
            setState(() {}); // обновить UI после загрузки продуктов
          } catch (_) {}
        });
        Future.microtask(() async {
          try {
            if (est.isBranch) {
              await productStore.loadNomenclatureForBranch(
                  est.id, est.dataEstablishmentId!);
            } else {
              await productStore.loadNomenclature(est.dataEstablishmentId);
            }
            if (!mounted) return;
            setState(() {}); // обновить цены в таблице
          } catch (_) {}
        });
        // Не блокируем первый рендер загрузкой всех ТТК.
        // Справочник ТТК подтягиваем фоном и досчитываем вложенные ПФ после открытия экрана.
        final deferTcLoad = true;
        if (!deferTcLoad) {
          final tcSvc = context.read<TechCardServiceSupabase>();
          List<TechCard> tcs;
          if (est.isBranch) {
            final mainTcs = await tcSvc
                .getTechCardsForEstablishment(est.dataEstablishmentId!);
            final branchTcs = await tcSvc.getTechCardsForEstablishment(est.id);
            tcs = [...mainTcs, ...branchTcs];
          } else {
            tcs = await tcSvc
                .getTechCardsForEstablishment(est.dataEstablishmentId);
          }
          tcs = tcs.map(stripInvalidNestedPfSelfLinks).toList();
          tcs = await tcSvc.fillIngredientsForCardsBulk(tcs);
          final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
          if (estPriceId != null && estPriceId.isNotEmpty) {
            tcs = TechCardCostHydrator.hydrate(tcs, productStore, estPriceId);
          }
          tcs = TechCardNutritionHydrator.hydrate(tcs, productStore);
          loadedTechCards = tcs;
          final customKitchen = await tcSvc.getCustomCategories(
              est.isBranch ? est.id : est.dataEstablishmentId!, 'kitchen');
          final customBar = await tcSvc.getCustomCategories(
              est.isBranch ? est.id : est.dataEstablishmentId!, 'bar');
          if (mounted) {
            _pickerTechCards = _isNew
                ? tcs
                : tcs.where((t) => t.id != widget.techCardId).toList();
            _semiFinishedProducts = tcs.where((t) => t.isSemiFinished).toList();
            _customCategoriesKitchen = customKitchen;
            _customCategoriesBar = customBar;
            _ensureTechCardTranslations(tcs);
          }
        } else {
          // Фоновая догрузка, чтобы дальше работали подбор ПФ/категорий без задержки при открытии.
          if (!shouldLoadPickerData) {
            // В режиме просмотра без редактирования не грузим все ТТК для справочников.
            // Текущую карточку (и технологию) загрузим ниже как обычно.
          } else {
            () async {
              try {
                final tcSvc = context.read<TechCardServiceSupabase>();

                final customCategoriesFuture = Future.wait([
                  tcSvc.getCustomCategories(
                      est.isBranch ? est.id : est.dataEstablishmentId!,
                      'kitchen'),
                  tcSvc.getCustomCategories(
                      est.isBranch ? est.id : est.dataEstablishmentId!, 'bar'),
                ]);
                final customResults = await customCategoriesFuture;
                final customKitchen =
                    customResults[0] as List<({String id, String name})>;
                final customBar =
                    customResults[1] as List<({String id, String name})>;

                void applyPickerSlice(List<TechCard> merged) {
                  if (!mounted) return;
                  final slice =
                      merged.map(stripInvalidNestedPfSelfLinks).toList();
                  setState(() {
                    _pickerTechCards = _isNew
                        ? slice
                        : slice
                            .where((t) => t.id != widget.techCardId)
                            .toList();
                    _semiFinishedProducts =
                        slice.where((t) => t.isSemiFinished).toList();
                    _customCategoriesKitchen = customKitchen;
                    _customCategoriesBar = customBar;
                  });
                }

                late List<TechCard> tcs;
                final scopeIds = est.isBranch
                    ? <String>[est.dataEstablishmentId!, est.id]
                    : <String>[est.dataEstablishmentId];
                var settledFromLocal = false;

                // Натив: сначала локальный снимок; иначе — те же страницы, что на веб (без одного гигантского ответа).
                if (!kIsWeb) {
                  try {
                    if (est.isBranch) {
                      final main = await tcSvc.getTechCardsForEstablishment(
                        est.dataEstablishmentId!,
                        includeIngredients: false,
                      );
                      final br = await tcSvc.getTechCardsForEstablishment(
                        est.id,
                        includeIngredients: false,
                      );
                      final byId = <String, TechCard>{};
                      for (final t in main) {
                        byId[t.id] = t;
                      }
                      for (final t in br) {
                        byId[t.id] = t;
                      }
                      final merged = byId.values.toList()
                        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      if (merged.isNotEmpty) {
                        tcs =
                            merged.map(stripInvalidNestedPfSelfLinks).toList();
                        settledFromLocal = true;
                        applyPickerSlice(merged);
                      }
                    } else {
                      final c = await tcSvc.getTechCardsForEstablishment(
                        est.dataEstablishmentId,
                        includeIngredients: false,
                      );
                      if (c.isNotEmpty) {
                        tcs = c.map(stripInvalidNestedPfSelfLinks).toList();
                        settledFromLocal = true;
                        applyPickerSlice(c);
                      }
                    }
                  } catch (_) {}
                }

                if (!settledFromLocal) {
                  tcs = await tcSvc.loadAllTechCardsShallowFromNetworkPaged(
                    scopeIds,
                    pageSize: 90,
                    onProgress: applyPickerSlice,
                  );
                  tcs = tcs.map(stripInvalidNestedPfSelfLinks).toList();
                }

                // Для расчёта цены ПФ в ExcelStyleTtkTable нужны ingredients + cost внутри самих ПФ.
                // В режиме deferTcLoad мы грузим карточки без ingredients, поэтому догружаем только ПФ.
                unawaited(() async {
                  try {
                    if (!mounted) return;
                    await productStore.loadProducts().catchError((_) {});
                    if (est.isBranch) {
                      await productStore
                          .loadNomenclatureForBranch(
                              est.id, est.dataEstablishmentId!)
                          .catchError((_) {});
                    } else {
                      await productStore
                          .loadNomenclature(est.dataEstablishmentId)
                          .catchError((_) {});
                    }

                    final pfs = tcs.where((t) => t.isSemiFinished).toList();
                    var hydratedPfs =
                        await tcSvc.fillIngredientsForCardsBulk(pfs);

                    final estPriceId =
                        est.isBranch ? est.id : (est.dataEstablishmentId ?? '');
                    if (estPriceId.isNotEmpty) {
                      hydratedPfs = TechCardCostHydrator.hydrate(
                          hydratedPfs, productStore, estPriceId);
                    }

                    if (!mounted) return;
                    setState(() => _semiFinishedProducts = hydratedPfs);
                  } catch (_) {}
                }());
                _ensureTechCardTranslations(tcs);
              } catch (_) {}
            }();
          }
        }
      }
      if (_isNew) {
        if (mounted) {
          final ai = widget.initialFromAi;
          if (ai != null) {
            _nameController.text = ai.dishName?.trim() ?? '';
            _technologyController.text = ai.technologyText?.trim() ?? '';
            if (widget.initialIsSemiFinished != null) {
              _isSemiFinished = widget.initialIsSemiFinished!;
            } else if (ai.isSemiFinished != null) {
              _isSemiFinished = ai.isSemiFinished!;
            }
            if (widget.initialCategory != null &&
                _categoryOptions.contains(widget.initialCategory) &&
                widget.department != 'bar') {
              _selectedCategory = widget.initialCategory!;
            }
            if (ai.dishName != null && ai.dishName!.isNotEmpty) {
              final cat = _inferCategory(ai.dishName!);
              if (_categoryOptions.contains(cat)) _selectedCategory = cat;
            } else if (widget.initialCategory != null &&
                _categoryOptions.contains(widget.initialCategory)) {
              _selectedCategory = widget.initialCategory!;
            }
            if (widget.initialSections != null &&
                widget.initialSections!.isNotEmpty) {
              _selectedSections = List<String>.from(widget.initialSections!);
            } else if (widget.initialSections != null &&
                widget.initialSections!.isEmpty) {
              _selectedSections = [];
            }
            _ingredients.clear();
            final langForAi =
                context.read<LocalizationService>().currentLanguageCode;
            for (final line in ai.ingredients) {
              if (line.productName.trim().isEmpty) continue;
              final proc = CookingProcess.resolveFromAiToken(
                  line.cookingMethod, langForAi);
              final resolvedProc = proc ?? CookingProcess.findById('mixing');
              var gross = line.grossGrams ?? 0.0;
              var net = line.netGrams ?? line.grossGrams ?? gross;
              final unit =
                  line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
              final wastePct = (line.primaryWastePct ?? 0).clamp(0.0, 99.9);
              final outG = line.outputGrams != null && line.outputGrams! > 0
                  ? line.outputGrams!
                  : 0.0;
              final isPcs = unit == 'шт' || unit == 'pcs';
              final gpp = isPcs ? 50.0 : null;
              // Для шт/pcs парсер отдаёт количество штук (1, 2…). Конвертируем только когда значение похоже на штуки (малое целое 1–50), иначе это граммы с ошибочной единицей.
              if (isPcs && gross > 0 && gross <= 50 && gross == gross.round()) {
                gross = gross * (gpp ?? 50);
                if (net == (line.grossGrams ?? 0)) net = gross;
              }
              final outW = (outG > 0
                      ? outG
                      : (net > 0 ? net : (gross > 0 ? gross : 100.0)))
                  .toDouble();
              _ingredients.add(TTIngredient(
                id: DateTime.now().millisecondsSinceEpoch.toString() +
                    _ingredients.length.toString(),
                productId: null,
                productName: line.productName.trim(),
                cookingProcessId: resolvedProc?.id,
                cookingProcessName: resolvedProc != null
                    ? resolvedProc.getLocalizedName(langForAi)
                    : null,
                grossWeight: gross > 0 ? gross : 100,
                netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
                outputWeight: outW.toDouble(),
                unit: unit,
                gramsPerPiece: gpp,
                primaryWastePct: wastePct,
                cookingLossPctOverride: line.cookingLossPct != null
                    ? line.cookingLossPct!.clamp(0.0, 99.9)
                    : null,
                isNetWeightManual: line.netGrams != null,
                finalCalories: 0,
                finalProtein: 0,
                finalFat: 0,
                finalCarbs: 0,
                cost: 0,
              ));
            }
            _autoFillBruttoFromNomenclature();
            _syncIngredientsCookingNutrition();
            _autoFillPriceFromNomenclature();
            // Вес порции при импорте: ПФ = 100, Блюдо = выход из файла (yieldGrams) или сумма выходов
            final sumOutput =
                _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
            _portionWeight = _isSemiFinished
                ? 100
                : (ai.yieldGrams != null && ai.yieldGrams! > 0
                    ? ai.yieldGrams!.toDouble()
                    : (sumOutput > 0 ? sumOutput : 100));
            _ensurePlaceholderRowAtEnd();
          } else {
            _ensurePlaceholderRowAtEnd();
          }
          setState(() {
            _loading = false;
          });
          if (mounted) {
            if (kIsWeb) {
              // На web jsonDecode/localStorage может блокировать UI на несколько секунд.
              // Не ждём восстановление, чтобы форма/инпуты успевали отрисоваться.
              unawaited(() async {
                await restoreDraftNow();
                if (mounted) await _maybeShowImportVerificationNotice();
              }());
            } else {
              await restoreDraftNow();
              if (mounted) await _maybeShowImportVerificationNotice();
            }
          }
        }
        return;
      }
      final svc = context.read<TechCardServiceSupabase>();
      TechCard? tc;
      // Список ТТК передаёт карточку без состава (includeIngredients: false) — не использовать как полный снимок.
      if (widget.initialTechCard != null &&
          widget.initialTechCard!.ingredients.isNotEmpty) {
        tc = widget.initialTechCard;
      } else {
        tc = await svc.getTechCardById(widget.techCardId, preferCache: true);
      }
      if (mounted) {
        // Показываем экран сразу, тяжёлую догрузку выполняем уже внутри страницы.
        setState(() {
          _techCard = tc;
          _loading = false;
          _contentPhase = 1;
        });
        // Не прогреваем переводы состава здесь: из кэша списка карточка часто без ingredients,
        // а `_warmIngredientNameTranslations` запоминает card+lang и тогда пропускает повторный
        // запрос после догрузки состава. Переводы запускаются после заполнения `_ingredients` ниже.
      }
      // Кэш из списка часто без строк состава — один запрос, без «первого открытия в сессии».
      if (tc != null && tc.ingredients.isEmpty) {
        try {
          var full = await svc.getTechCardById(
            widget.techCardId,
            preferCache: false,
          );
          if (full != null && full.ingredients.isEmpty) {
            final filled = await svc.fillIngredientsForCardsBulk([full]);
            if (filled.isNotEmpty) full = filled.first;
          }
          if (full != null) tc = full;
        } catch (_) {}
      }
      List<TechCard> semiFinishedForCost = <TechCard>[];
      if (tc != null) {
        var working = stripInvalidNestedPfSelfLinks(tc);
        // Нужные ПФ для расчёта цен/стоимости в таблице:
        // в режиме просмотра раньше могли не подгружаться "справочники" (loadedTechCards пустой),
        // из-за чего sourceTechCardId не прикреплялся и стоимость вложенных ПФ становилась 0.
        // Никогда не автосохраняем при открытии экрана:
        // если карточка прилетела с пустым составом из кэша, такое сохранение
        // удалит строки ingredients в БД (saveTechCard делает delete+insert).
        if (loadedTechCards.isNotEmpty) {
          final pfCards =
              loadedTechCards.where((t) => t.isSemiFinished).toList();
          working = _attachMissingPfSourceTechCardId(working, pfCards);
          final currentTechCardId = working.id;
          final productStore = context.read<ProductStoreSupabase>();
          final est = context.read<AccountManagerSupabase>().establishment;
          final estPriceId =
              est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
          var hydratedList = [working, ...loadedTechCards];
          if (estPriceId != null && estPriceId.isNotEmpty) {
            hydratedList = TechCardCostHydrator.hydrate(
                hydratedList, productStore, estPriceId);
          }
          final hydrated =
              TechCardNutritionHydrator.hydrate(hydratedList, productStore);
          working = hydrated.firstWhere((item) => item.id == currentTechCardId,
              orElse: () => working);
          semiFinishedForCost =
              hydrated.where((t) => t.isSemiFinished).toList();
        } else {
          // loadedTechCards пустой (часто в forceViewMode / без прав редактирования).
          // Подгружаем полуфабрикаты только по sourceTechCardId текущей карточки.
          final est = context.read<AccountManagerSupabase>().establishment;
          if (est != null) {
            final productStore = context.read<ProductStoreSupabase>();
            final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
            final neededPfIds = <String>{};
            for (final ing in working.ingredients) {
              final id = ing.sourceTechCardId?.trim();
              if (id != null && id.isNotEmpty) neededPfIds.add(id);
            }
            if (neededPfIds.isNotEmpty) {
              final fetched = await Future.wait(
                neededPfIds.map((id) => svc.getTechCardById(id)),
              );
              final neededPfCards = fetched
                  .whereType<TechCard>()
                  .where((t) => t.isSemiFinished)
                  .toList();
              if (neededPfCards.isNotEmpty) {
                final pfCardsFilled =
                    await svc.fillIngredientsForCardsBulk(neededPfCards);

                // В ПФ мог быть не заполнен sourceTechCardId для вложенных ПФ — прикрепим по имени.
                final attachedPfs = pfCardsFilled
                    .map((pf) =>
                        _attachMissingPfSourceTechCardId(pf, pfCardsFilled))
                    .toList();

                // Прикрепим sourceTechCardId и к самой текущей карте.
                working =
                    _attachMissingPfSourceTechCardId(working, attachedPfs);

                var hydratedList = [working, ...attachedPfs];
                if (estPriceId.isNotEmpty) {
                  hydratedList = TechCardCostHydrator.hydrate(
                    hydratedList,
                    productStore,
                    estPriceId,
                  );
                }
                hydratedList = TechCardNutritionHydrator.hydrate(
                    hydratedList, productStore);
                working = hydratedList.firstWhere(
                    (item) => item.id == working.id,
                    orElse: () => working);

                semiFinishedForCost = attachedPfs;
              }
            }
          }
        }
        tc = working;
      }
      if (!mounted) return;
      // Применяем данные сразу: не ждём новый frame, иначе UI может обновиться
      // только после первого пользовательского действия (скролл/тап).
      setState(() {
        _techCard = tc;
        _loading = false;
        if (tc != null) {
          if (tc.isSemiFinished) {
            // для ПФ самой по себе достаточно своих ингредиентов, но пусть не пусто для рекурсии
            _semiFinishedProducts =
                semiFinishedForCost.isNotEmpty ? semiFinishedForCost : [tc];
          } else {
            if (semiFinishedForCost.isNotEmpty) {
              _semiFinishedProducts = semiFinishedForCost;
            }
          }
          final sumOutput =
              tc.ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
          if (tc.isSemiFinished) {
            // ТТК ПФ: по умолчанию 100; из БД только если задан
            _portionWeight = tc.portionWeight > 0 ? tc.portionWeight : 100;
          } else {
            // ТТК блюдо: по умолчанию = вес выхода итого (сумма); из БД если реалистично, иначе сброс на сумму (защита от ошибочных 35000 и т.п.)
            if (tc.portionWeight <= 0 && sumOutput > 0) {
              _portionWeight = sumOutput;
            } else if (sumOutput > 0 && tc.portionWeight > 5 * sumOutput) {
              _portionWeight = sumOutput;
            } else {
              _portionWeight = tc.portionWeight;
            }
          }
          _nameController.text = tc.getLocalizedDishName(
              context.read<LocalizationService>().currentLanguageCode);
          _selectedCategory = _categoryOptions.contains(tc.category)
              ? tc.category
              : 'misc'; // fallback if custom category was deleted
          _selectedSections = List<String>.from(tc.sections);
          _isSemiFinished = tc.isSemiFinished;
          _photoUrls = tc.photoUrls ?? [];
          _pendingPhotoBytes = [];
          _technologyController.text = tc.getLocalizedTechnology(
              context.read<LocalizationService>().currentLanguageCode);
          _descriptionForHallController.text = tc.descriptionForHall ?? '';
          _compositionForHallController.text = tc.compositionForHall ?? '';
          _sellingPriceController.text =
              tc.sellingPrice != null && tc.sellingPrice! > 0
                  ? tc.sellingPrice!.toStringAsFixed(2)
                  : '';
          _ingredients
            ..clear()
            ..addAll(_ensureOutputWeights(tc.ingredients));
          final targetFromChecklist = widget.initialViewTargetOutputGrams;
          if (widget.forceViewMode &&
              targetFromChecklist != null &&
              targetFromChecklist > 0) {
            final currentTotal = _ingredients
                .where((i) => i.productName.trim().isNotEmpty)
                .fold<double>(0, (s, i) => s + i.outputWeight);
            if (currentTotal > 0) {
              final factor = targetFromChecklist / currentTotal;
              if ((factor - 1.0).abs() > 0.0001) {
                final scaled =
                    _ingredients.map((i) => i.scaleBy(factor)).toList();
                _ingredients
                  ..clear()
                  ..addAll(scaled);
              }
            }
            // Для переходов из чеклиста целевой выход — источник истины UI.
            _portionWeight = targetFromChecklist;
          }
          _ensurePlaceholderRowAtEnd();
        }
        _contentPhase =
            1; // показываем полную форму сразу после загрузки данных
      });
      // Защитный fallback: если по какой-то причине semiFinishedProducts не
      // успели заполниться (например, view-режим без loadedTechCards),
      // подгружаем/гидратим их, чтобы ExcelStyleTtkTable успел посчитать цены.
      if (tc != null &&
          _semiFinishedProducts.isEmpty &&
          tc.ingredients.any((ing) =>
              (ing.sourceTechCardId?.trim().isNotEmpty ?? false) ||
              (ing.productId == null && ing.productName.trim().isNotEmpty))) {
        unawaited(_ensureSemiFinishedProductsForCost(tc));
      }
      // Если перевод технологии ещё не сохранён — запросить через DeepL
      if (tc != null) _translateTechnologyIfNeeded(tc);
      if (tc != null) {
        unawaited(_refreshDishNameTranslationForCurrentLanguage(tc));
      }
      if (tc != null) {
        unawaited(
          _refreshIngredientNameTranslationsForCard(
            tc,
            context.read<LocalizationService>().currentLanguageCode,
          ),
        );
      }
      // Дополнить цены из номенклатуры (если productId есть, cost=0)
      if (tc != null && est != null) {
        _enrichPricesFromNomenclature(
            est.isBranch ? est.id : est.dataEstablishmentId!);
      }
      if (mounted) {
        // Для существующих ТТК не восстанавливаем черновик автоматически:
        // старый draft может перетирать серверные поля (название/категория/цех/тип/технология).
        final shouldRestoreDraft = _isNew || widget.initialFromAi != null;
        if (shouldRestoreDraft) {
          if (kIsWeb) {
            unawaited(restoreDraftNow());
          } else {
            await restoreDraftNow();
          }
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  void _ensureDishKbjuDerived(
      LocalizationService loc, ProductStoreSupabase store) {
    final buf = StringBuffer();
    for (final ing in _ingredients) {
      buf.write(ing.productId);
      buf.write('|');
      buf.write(ing.finalCalories);
      buf.write('|');
      buf.write(ing.finalProtein);
      buf.write('|');
      buf.write(ing.finalFat);
      buf.write('|');
      buf.write(ing.finalCarbs);
      buf.write('|');
      buf.write(ing.hasData);
      buf.write('|');
      buf.write(ing.productName);
      final p = store.findProductForIngredient(ing.productId, ing.productName);
      buf.write(p?.containsGluten);
      buf.write(p?.containsLactose);
      buf.write(p?.kbjuManuallyConfirmed);
    }
    final key = buf.toString();
    if (_dishKbjuDerivedKey == key) return;
    _dishKbjuDerivedKey = key;

    const eps = 1e-9;
    var totalCal = 0.0;
    var totalProt = 0.0;
    var totalFat = 0.0;
    var totalCarb = 0.0;
    final missing = <String>[];
    final seen = <String>{};
    for (final ing in _ingredients) {
      totalCal += ing.finalCalories;
      totalProt += ing.finalProtein;
      totalFat += ing.finalFat;
      totalCarb += ing.finalCarbs;
      if (!ing.hasData) continue;
      final missingRow = ing.finalCalories.abs() < eps &&
          ing.finalProtein.abs() < eps &&
          ing.finalFat.abs() < eps &&
          ing.finalCarbs.abs() < eps;
      if (!missingRow) continue;
      final name = ing.productName.trim();
      if (name.isEmpty) continue;
      final prod =
          store.findProductForIngredient(ing.productId, ing.productName);
      if (prod != null && prod.kbjuManuallyConfirmed) continue;
      if (seen.add(name)) missing.add(name);
    }
    final allergens = <String>[];
    for (final ing in _ingredients.where((i) => i.productId != null)) {
      final p = store.findProductForIngredient(ing.productId, ing.productName);
      if (p?.containsGluten == true && !allergens.contains('глютен')) {
        allergens.add('глютен');
      }
      if (p?.containsLactose == true && !allergens.contains('лактоза')) {
        allergens.add('лактоза');
      }
    }
    final allergenStr = allergens.isEmpty
        ? (loc.currentLanguageCode == 'ru' ? 'нет' : 'none')
        : allergens.join(', ');

    _dishKbjuMissingNames = missing;
    _dishKbjuTotalCal = totalCal;
    _dishKbjuTotalProt = totalProt;
    _dishKbjuTotalFat = totalFat;
    _dishKbjuTotalCarb = totalCarb;
    _dishKbjuAllergenStr = allergenStr;
  }

  /// Дополняет цены ингредиентов из номенклатуры (по productId или по названию).
  /// Нормализация: убираем пунктуацию, множественные пробелы — для сопоставления у всех пользователей.
  void _enrichPricesFromNomenclature(String establishmentId) {
    final store = context.read<ProductStoreSupabase>();
    final products = store.getNomenclatureProducts(establishmentId);
    final invalidChars = RegExp(r'[^a-zA-Zа-яёЁ0-9\s]');
    final multiSpaces = RegExp(r'\s+');
    final norm = (String s) => s
        .replaceAll(invalidChars, '')
        .toLowerCase()
        .replaceAll(multiSpaces, ' ')
        .trim();
    // Lookup: нормализованное имя -> (productId, pricePerKg)
    final priceByNormName = <String, ({String productId, double pricePerKg})>{};
    for (final p in products) {
      final pricePerKg = store.getEstablishmentPrice(p.id, establishmentId)?.$1;
      if (pricePerKg == null || pricePerKg <= 0) continue;

      void addKey(String? raw) {
        if (raw == null) return;
        final k = norm(raw);
        if (k.isEmpty) return;
        priceByNormName.putIfAbsent(
          k,
          () => (productId: p.id, pricePerKg: pricePerKg),
        );
      }

      addKey(p.name);
      for (final alias in p.names?.values ?? const Iterable<String>.empty()) {
        addKey(alias);
      }
    }

    var changed = false;
    final updated = <int, TTIngredient>{};
    for (var i = 0; i < _ingredients.length; i++) {
      final ing = _ingredients[i];
      if (ing.cost > 0) continue;

      final productName = ing.productName.trim();
      if (productName.isEmpty) continue;

      String? pid = ing.productId;
      double? pricePerKg;
      if (pid != null) {
        pricePerKg = store.getEstablishmentPrice(pid, establishmentId)?.$1;
      }

      if (pricePerKg == null || pricePerKg <= 0) {
        final hit = priceByNormName[norm(productName)];
        pid = hit?.productId;
        pricePerKg = hit?.pricePerKg;
      }

      if (pricePerKg == null || pricePerKg <= 0) continue;
      final newCost = (pricePerKg / 1000) * ing.grossWeight;
      updated[i] = ing.copyWith(
        productId: pid ?? ing.productId,
        cost: newCost,
        pricePerKg: pricePerKg,
      );
      changed = true;
    }
    if (changed && mounted) {
      setState(() {
        for (final e in updated.entries) {
          if (e.key < _ingredients.length) _ingredients[e.key] = e.value;
        }
      });
      _scheduleDraftSave();
    }
  }

  void _scheduleDraftSave() {
    _lastUserInteractionAt = DateTime.now();
    // Автосохранение черновика с полным состоянием (включая ингредиенты) может
    // заметно блокировать UI, особенно сразу после импорта больших ТТК.
    // Сохраняем только после короткой паузы на всех платформах.
    _draftSaveIdleDebounceTimer?.cancel();
    _draftSaveIdleDebounceTimer = Timer(
      kIsWeb ? const Duration(seconds: 2) : const Duration(milliseconds: 700),
      () {
        if (!mounted) return;
        scheduleSave();
      },
    );
  }

  String _normalizeForTechCardName(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9\s]+'), ' ')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return cleaned;
    // Сортируем токены, чтобы порядок слов в названии (масло чесночное/чесночное масло)
    // не ломал совпадение.
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty)
        .toList()
      ..sort();
    return tokens.join(' ');
  }

  String _stripPfPrefix(String s) {
    final r =
        RegExp(r'^(пф|п/ф|п\.ф\.|pf|prep|sf|hf)\s*', caseSensitive: false);
    return s.trim().replaceFirst(r, '').trim();
  }

  TechCard? _pickBestPfCandidate({
    required TechCard owner,
    required List<TechCard> candidates,
  }) {
    final filtered = candidates.where((c) => c.id != owner.id).toList();
    if (filtered.isEmpty) return null;
    if (filtered.length == 1) return filtered.first;

    // Не "угадываем" за пользователя.
    // Автосвязываем только если после фильтра по заведению остаётся ровно один кандидат.
    final sameEst = filtered
        .where((c) => c.establishmentId == owner.establishmentId)
        .toList();
    if (sameEst.length == 1) return sameEst.first;
    return null;
  }

  TechCard _attachMissingPfSourceTechCardId(
      TechCard tc, List<TechCard> pfCards) {
    if (tc.ingredients.isEmpty || pfCards.isEmpty) return tc;

    final lang = context.read<LocalizationService>().currentLanguageCode;

    var changed = false;
    final updatedIngredients = tc.ingredients.map((ing) {
      final sid = ing.sourceTechCardId;
      if (sid != null && sid.isNotEmpty && sid == tc.id) {
        changed = true;
        return ing.copyWith(sourceTechCardId: null, sourceTechCardName: null);
      }
      final hasSourceId = sid != null && sid.isNotEmpty;
      if (hasSourceId) return ing;
      if (ing.productName.trim().isEmpty) return ing;
      final candidates = _findPfCandidatesForIngredientName(
        ing.productName,
        pfCards,
        lang,
        excludeTechCardId: tc.id,
      );
      final picked = _pickBestPfCandidate(owner: tc, candidates: candidates);
      if (picked == null) return ing;

      changed = true;
      final display = picked.getDisplayNameInLists(lang);
      return ing.copyWith(
        sourceTechCardId: picked.id,
        sourceTechCardName: display,
        productName: display,
      );
    }).toList();

    return changed ? tc.copyWith(ingredients: updatedIngredients) : tc;
  }

  List<TechCard> _findPfCandidatesForIngredientName(
    String ingredientName,
    List<TechCard> pfCards,
    String lang, {
    String? excludeTechCardId,
  }) {
    final target = _normalizeForTechCardName(_stripPfPrefix(ingredientName));
    if (target.isEmpty) return const [];

    final byId = <String, TechCard>{};
    for (final pf in pfCards) {
      if (excludeTechCardId != null && pf.id == excludeTechCardId) continue;
      final names = <String>[
        pf.getDisplayNameInLists(lang),
        pf.getLocalizedDishName(lang),
        pf.dishName,
      ];
      for (final n in names) {
        final k = _normalizeForTechCardName(_stripPfPrefix(n));
        if (k.isNotEmpty && k == target) {
          byId[pf.id] = pf;
          break;
        }
      }
    }
    return byId.values.toList();
  }

  Future<TechCard?> _pickPfCandidateDialog({
    required String ingredientName,
    required List<TechCard> candidates,
  }) async {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (candidates.isEmpty) return null;

    String? selectedId = candidates.first.id;
    final res = await showDialog<TechCard>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setInnerState) {
            return AlertDialog(
              title: Text(loc
                  .t('ttk_clarify_pf_for')
                  .replaceFirst('%s', ingredientName)),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...candidates.map((c) {
                        final name = c.getDisplayNameInLists(lang);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Theme.of(ctx2)
                                      .colorScheme
                                      .outlineVariant),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: c.id,
                                      groupValue: selectedId,
                                      onChanged: (v) {
                                        setInnerState(() => selectedId = v);
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          _showTechCardCompositionDialog(
                                              ctx2, c, lang),
                                      child:
                                          Text(loc.t('ttk_composition_short')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(loc.t('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final picked =
                        candidates.where((c) => c.id == selectedId).firstOrNull;
                    Navigator.of(ctx).pop(picked);
                  },
                  child: Text(loc.t('apply')),
                ),
              ],
            );
          },
        );
      },
    );

    return res;
  }

  void _showTechCardCompositionDialog(
      BuildContext ctx, TechCard tc, String lang) {
    showDialog<void>(
      context: ctx,
      builder: (dCtx) {
        final loc = dCtx.read<LocalizationService>();
        final items = tc.ingredients
            .where((i) => i.productName.trim().isNotEmpty)
            .toList();
        return AlertDialog(
          title: Text(tc.getDisplayNameInLists(lang)),
          content: SizedBox(
            width: 620,
            height: 420,
            child: items.isEmpty
                ? Center(child: Text(loc.t('ttk_composition_empty')))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, idx) {
                      final ing = items[idx];
                      final name = ing.sourceTechCardId != null &&
                              ing.sourceTechCardId!.isNotEmpty
                          ? TechCard.pfLinkedIngredientDisplayName(ing, lang)
                          : (_ingredientNameTranslationsById[ing.id] ??
                              ing.productName);
                      final w = ing.outputWeight > 0
                          ? ing.outputWeight
                          : ing.netWeight;
                      return ListTile(
                        dense: true,
                        title: Text(name),
                        subtitle: Text(loc
                            .t('ttk_output_weight_grams')
                            .replaceFirst('%s', w.toStringAsFixed(0))),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: Text(loc.t('dialog_ok'))),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    setOnInputChanged(_scheduleDraftSave);
    _nameController.addListener(() {
      _scheduleDraftSave();
    });
    _technologyController.addListener(() {
      _scheduleDraftSave();
    });
    _descriptionForHallController.addListener(_scheduleDraftSave);
    _compositionForHallController.addListener(_scheduleDraftSave);
    _sellingPriceController.addListener(_scheduleDraftSave);
    // Сразу 2 строки для внесения продуктов; при заполнении последней добавится следующая
    _ingredients.add(TTIngredient.emptyPlaceholder());
    _ingredients.add(TTIngredient.emptyPlaceholder());
    final locSvc = LocalizationService();
    _localizationListener = () {
      if (!mounted) return;
      final tc = _techCard;
      if (tc == null) return;
      final code = locSvc.currentLanguageCode;
      final next = tc.getLocalizedDishName(code);
      if (_nameController.text != next) {
        _nameController.text = next;
      }
      unawaited(
        _refreshIngredientNameTranslationsForCard(
          tc,
          code,
        ),
      );
    };
    locSvc.addListener(_localizationListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Даем завершиться свайп-анимации перехода, и только потом стартуем загрузку.
      // Так переход на экран ТТК не фризит посередине.
      unawaited(_startLoadAfterRouteTransition());

      // Периодическая автодосвязка вложенных ПФ (например, чтобы "йогурт"
      // появился в "соус салатный" без повторного открытия редактирования).
      _reconcileNotifier = context.read<TechCardsReconcileNotifier>();
      _lastReconcileNotifierVersion = _reconcileNotifier!.version;
      _reconcileNotifier!.addListener(_handleTechCardsReconcileSignal);
      _reconcileOpenCardTimer?.cancel();
      _reconcileOpenCardTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _tryReconcileOpenCard(force: false);
      });
    });
  }

  Future<void> _startLoadAfterRouteTransition() async {
    if (!_isNew) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
    if (!mounted) {
      return;
    }
    await _load();
  }

  Map<String, String> _ingredientFieldsForTranslation(
    List<TTIngredient> ingredients,
  ) {
    final out = <String, String>{};
    for (final ing in ingredients) {
      final id = ing.id.trim();
      final name = ing.productName.trim();
      final sourceTc = ing.sourceTechCardId?.trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      if (sourceTc.isNotEmpty) continue;
      out['ingredient_name_$id'] = name;
    }
    return out;
  }

  String _inferSourceLanguageFromTexts(Iterable<String> texts) {
    var cyrillicChars = 0;
    var latinChars = 0;
    for (final text in texts) {
      for (final rune in text.runes) {
        if ((rune >= 0x0400 && rune <= 0x04FF) ||
            (rune >= 0x0500 && rune <= 0x052F)) {
          cyrillicChars++;
        } else if ((rune >= 0x0041 && rune <= 0x005A) ||
            (rune >= 0x0061 && rune <= 0x007A)) {
          latinChars++;
        }
      }
    }
    if (cyrillicChars > latinChars) return 'ru';
    return 'en';
  }

  Future<void> _warmIngredientNameTranslations({
    required String techCardId,
    required String languageCode,
    bool force = false,
  }) async {
    final cardId = techCardId.trim();
    final lang = languageCode.trim().toLowerCase();
    if (cardId.isEmpty || lang.isEmpty) return;
    if (!force &&
        _ingredientNameTranslationsLang == lang &&
        _ingredientNameTranslationsCardId == cardId) {
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('translations')
          .select('field_name, translated_text')
          .eq('entity_type', TranslationEntityType.techCard.name)
          .eq('entity_id', cardId)
          .eq('target_language', lang);
      final next = <String, String>{};
      if (rows is List) {
        for (final raw in rows) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final field = (m['field_name'] as String? ?? '').trim();
          if (!field.startsWith('ingredient_name_')) continue;
          final ingId = field.substring('ingredient_name_'.length).trim();
          final translated = (m['translated_text'] as String? ?? '').trim();
          if (ingId.isEmpty || translated.isEmpty) continue;
          next[ingId] = translated;
        }
      }
      if (!mounted) return;
      setState(() {
        _ingredientNameTranslationsById = next;
        _ingredientNameTranslationsLang = lang;
        _ingredientNameTranslationsCardId = cardId;
      });
    } catch (_) {}
  }

  Future<void> _refreshIngredientNameTranslationsForCard(
    TechCard tc,
    String languageCode,
  ) async {
    await _warmIngredientNameTranslations(
      techCardId: tc.id,
      languageCode: languageCode,
      force: true,
    );
    await _backfillMissingIngredientTranslations(
      techCardId: tc.id,
      languageCode: languageCode,
    );
  }

  Future<void> _backfillMissingIngredientTranslations({
    required String techCardId,
    required String languageCode,
  }) async {
    final cardId = techCardId.trim();
    final lang = languageCode.trim().toLowerCase();
    if (cardId.isEmpty || lang.isEmpty) return;
    final key = '$cardId:ingredient_i18n_all';
    if (_ingredientTranslationBackfillInFlight.contains(key)) return;

    final sourceFields = _ingredientFieldsForTranslation(_ingredients);
    if (sourceFields.isEmpty) return;

    final missing = <String, String>{};
    sourceFields.forEach((field, text) {
      final ingId = field.substring('ingredient_name_'.length).trim();
      if ((_ingredientNameTranslationsById[ingId] ?? '').trim().isEmpty) {
        missing[field] = text;
      }
    });
    if (missing.isEmpty) return;

    _ingredientTranslationBackfillInFlight.add(key);
    try {
      final tm = context.read<TranslationManager>();
      final userId = context.read<AccountManagerSupabase>().currentEmployee?.id;
      final entries = missing.entries.toList(growable: false);
      const batchSize = 6;
      for (var i = 0; i < entries.length; i += batchSize) {
        final end =
            (i + batchSize < entries.length) ? i + batchSize : entries.length;
        final chunk = entries.sublist(i, end);
        await Future.wait(
          chunk.map((entry) {
            final inferredSourceLanguage =
                _inferSourceLanguageFromTexts(<String>[entry.value]);
            return tm.handleEntitySave(
              entityType: TranslationEntityType.techCard,
              entityId: cardId,
              textFields: <String, String>{entry.key: entry.value},
              sourceLanguage: inferredSourceLanguage,
              userId: userId,
              // null → все [LocalizationService.productLanguageCodes], кроме sourceLanguage
            );
          }),
        );
      }
      await _warmIngredientNameTranslations(
        techCardId: cardId,
        languageCode: lang,
        force: true,
      );
    } catch (_) {
      // Keep UI responsive if translation provider is temporarily unavailable.
    } finally {
      _ingredientTranslationBackfillInFlight.remove(key);
    }
  }

  @override
  void dispose() {
    LocalizationService().removeListener(_localizationListener);
    _reconcileOpenCardTimer?.cancel();
    _portionWeightUpdateDebounce?.cancel();
    if (_reconcileNotifier != null) {
      _reconcileNotifier!.removeListener(_handleTechCardsReconcileSignal);
    }
    _ingredientUpdateDebounce?.cancel();
    _cookTableSyncDebounce?.cancel();
    _reconcileDebounceTimer?.cancel();
    _draftSaveIdleDebounceTimer?.cancel();
    _nameController.dispose();
    _technologyController.dispose();
    _descriptionForHallController.dispose();
    _compositionForHallController.dispose();
    _sellingPriceController.dispose();
    _compositionTableHScrollController.dispose();
    super.dispose();
  }

  void _handleTechCardsReconcileSignal() {
    if (!mounted) return;
    final notifier =
        _reconcileNotifier ?? context.read<TechCardsReconcileNotifier>();
    if (notifier.version == _lastReconcileNotifierVersion) return;
    _lastReconcileNotifierVersion = notifier.version;

    // Пользователь мог только что обновить ингредиенты/веса.
    // В этот момент reconcile запускается "мимо ожиданий" и CPU-часть может блокировать UI.
    // Делаем небольшой idle-debounce: если правки были <2с назад — запускаем позже.
    final sinceUser = DateTime.now().difference(_lastUserInteractionAt);
    if (sinceUser < const Duration(seconds: 2)) {
      _reconcileDebounceTimer?.cancel();
      _reconcileDebounceTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _tryReconcileOpenCard(force: true);
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryReconcileOpenCard(force: true);
    });
  }

  Future<void> _tryReconcileOpenCard({bool force = false}) async {
    if (!mounted) return;
    if (_reconciling) return;
    if (_techCard == null) return;

    final now = DateTime.now();
    if (!force &&
        now.difference(_lastReconcileAt) < const Duration(seconds: 30)) return;

    _reconciling = true;
    _lastReconcileAt = now;
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      if (est == null) return;

      final tcSvc = context.read<TechCardServiceSupabase>();
      List<TechCard> all;
      if (est.isBranch) {
        final mainTcs =
            await tcSvc.getTechCardsForEstablishment(est.dataEstablishmentId!);
        final branchTcs = await tcSvc.getTechCardsForEstablishment(est.id);
        all = [...mainTcs, ...branchTcs];
      } else {
        all = await tcSvc.getTechCardsForEstablishment(est.dataEstablishmentId);
      }

      all = all.map(stripInvalidNestedPfSelfLinks).toList();
      final pfCards = all.where((t) => t.isSemiFinished).toList();

      final currentTc = _techCard!;
      // Снимаем самоссылки и назначаем однозначные совпадения (1 кандидат).
      var fixed = stripInvalidNestedPfSelfLinks(currentTc);
      if (!identical(fixed, currentTc)) {
        try {
          await tcSvc.saveTechCard(fixed, skipHistory: true);
        } catch (_) {}
      }
      fixed = _attachMissingPfSourceTechCardId(fixed, pfCards);

      final productStore = context.read<ProductStoreSupabase>();
      final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
      var hydratedList = [fixed, ...all];
      if (estPriceId != null && estPriceId.isNotEmpty) {
        hydratedList = TechCardCostHydrator.hydrate(
            hydratedList, productStore, estPriceId);
      }
      final hydrated =
          TechCardNutritionHydrator.hydrate(hydratedList, productStore);
      final hydratedTc = hydrated.firstWhere((item) => item.id == fixed.id,
          orElse: () => fixed);
      final hydratedPfs = hydrated.where((t) => t.isSemiFinished).toList();

      if (!mounted) return;
      setState(() {
        _semiFinishedProducts = hydratedPfs;
        _techCard = hydratedTc;
        _ingredients
          ..clear()
          ..addAll(hydratedTc.ingredients);
        _ensurePlaceholderRowAtEnd();
      });
    } catch (_) {
      // Фоновая автодосвязка — не критична для UX; если не получилось — просто пропускаем тик.
    } finally {
      _reconciling = false;
    }
  }

  /// Если для текущего языка перевод технологии отсутствует — запрашивает DeepL и
  /// обновляет _technologyController + сохраняет в technologyLocalized в БД.
  Future<void> _translateTechnologyIfNeeded(TechCard tc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;

    bool looksRussianText(String text) =>
        RegExp(r'[\u0400-\u04FF]').hasMatch(text);

    String inferSourceLang(String text) {
      final t = text.trim();
      if (t.isEmpty) return 'en';
      if (RegExp(r'[\u0400-\u04FF]').hasMatch(t)) return 'ru';
      return 'en';
    }

    // Найти исходный язык технологии (первый непустой ключ в technologyLocalized),
    // а если карта пустая/неполная — взять текущий текст из контроллера.
    final techMap = tc.technologyLocalized ?? {};
    final sourceLang = techMap.entries
        .where((e) => e.value.trim().isNotEmpty && e.key != targetLang)
        .map((e) => e.key)
        .firstOrNull;
    var sourceText = sourceLang != null ? techMap[sourceLang]!.trim() : '';
    var effectiveSourceLang = sourceLang;
    if (sourceText.isEmpty) {
      final fallbackText = _technologyController.text.trim();
      if (fallbackText.isNotEmpty) {
        sourceText = fallbackText;
        effectiveSourceLang = inferSourceLang(fallbackText);
      }
    }

    // Уже есть перевод на целевой язык — ничего не делать.
    // Исключение: для не-ru языка в карте может лежать русский текст
    // (например карточка создана ИИ при UI=en) — такой «перевод» нужно исправить.
    final existing = techMap[targetLang]?.trim() ?? '';
    final existingLooksMismatched =
        targetLang != 'ru' && existing.isNotEmpty && looksRussianText(existing);
    if (existing.isNotEmpty && !existingLooksMismatched) return;

    // Нет исходного текста — нечего переводить
    if (sourceText.isEmpty || effectiveSourceLang == null) return;
    if (effectiveSourceLang == targetLang) return;

    if (!mounted) return;
    setState(() => _technologyTranslating = true);
    try {
      final translationManager = context.read<TranslationManager>();
      final svc = context.read<TechCardServiceSupabase>();

      final translated = await translationManager.getLocalizedText(
        entityType: TranslationEntityType.techCard,
        entityId: tc.id,
        fieldName: 'technology',
        sourceText: sourceText,
        sourceLanguage: effectiveSourceLang,
        targetLanguage: targetLang,
      );

      if (!mounted) return;
      if (translated.trim().isNotEmpty && translated != sourceText) {
        // Обновляем контроллер чтобы текст появился сразу
        setState(() {
          _technologyController.text = translated;
        });
        // Сохраняем перевод в technologyLocalized в БД
        final newTechMap = Map<String, String>.from(techMap);
        newTechMap[targetLang] = translated;
        try {
          final updated = tc.copyWith(technologyLocalized: newTechMap);
          await svc.saveTechCard(updated, skipHistory: true);
          if (mounted) setState(() => _techCard = updated);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _technologyTranslating = false);
  }

  String _inferLanguageFromText(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'en';
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(t)) return 'ru';
    return 'en';
  }

  /// Канонический текст названия для запроса перевода — без приоритета «только ru».
  String _canonicalDishNameSource(TechCard tc) {
    final dn = tc.dishName.trim();
    if (dn.isNotEmpty) return dn;
    final loc = tc.dishNameLocalized;
    if (loc != null) {
      for (final code in TechCard.kDishNameFallbackLanguageOrder) {
        final v = loc[code]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      for (final code in LocalizationService.productLanguageCodes) {
        final v = loc[code]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      for (final v in loc.values) {
        final t = v.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }

  Future<void> _refreshDishNameTranslationForCurrentLanguage(
      TechCard tc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode.trim().toLowerCase();

    final localized =
        Map<String, String>.from(tc.dishNameLocalized ?? const {});
    final sourceText = _canonicalDishNameSource(tc);
    if (sourceText.isEmpty) return;
    final sourceLang = _inferLanguageFromText(sourceText);
    if (sourceLang == targetLang) return;

    final existing = localized[targetLang]?.trim() ?? '';
    try {
      final translationManager = context.read<TranslationManager>();
      final svc = context.read<TechCardServiceSupabase>();
      final translated = await translationManager.getLocalizedText(
        entityType: TranslationEntityType.techCard,
        entityId: tc.id,
        fieldName: 'dish_name',
        sourceText: sourceText,
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );
      final next = translated.trim();
      if (next.isEmpty || next == sourceText || next == existing) return;
      if (!mounted) return;

      localized[targetLang] = next;
      // Поддерживаем консистентность списка/деталей в этой сессии:
      // overlay используется в списке ТТК даже до перезагрузки карточки из БД.
      TechCard.setTranslationOverlay(
        {tc.id: next},
        languageCode: targetLang,
        merge: true,
      );
      final updated = tc.copyWith(dishNameLocalized: localized);
      try {
        await svc.saveTechCard(updated, skipHistory: true);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _techCard = updated;
        _nameController.text = next;
      });
    } catch (_) {}
  }

  Future<void> _showAddCustomCategoryDialog() async {
    final loc = context.read<LocalizationService>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('ttk_add_custom_category')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: loc.t('ttk_custom_category_hint'),
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc.t('back'))),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(loc.t('save')),
            ),
          ],
        );
      },
    );
    final name = result?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    final category = await context
        .read<TechCardServiceSupabase>()
        .addCustomCategory(est.dataEstablishmentId, _categoryDepartment, name);
    if (!mounted) return;
    if (category == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('ttk_custom_category_save_error')),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    final custom = await context
        .read<TechCardServiceSupabase>()
        .getCustomCategories(est.dataEstablishmentId, _categoryDepartment);
    setState(() {
      if (_categoryDepartment == 'bar') {
        _customCategoriesBar = custom;
      } else {
        _customCategoriesKitchen = custom;
      }
      _selectedCategory = category;
    });
    _scheduleDraftSave();
  }

  Future<void> _showManageCustomCategoriesDialog() async {
    final loc = context.read<LocalizationService>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    final list = [..._customCategories];
    if (list.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('ttk_no_custom_categories'))));
      return;
    }
    final tcSvc = context.read<TechCardServiceSupabase>();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('ttk_manage_custom_categories'),
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...list.map((c) => ListTile(
                  title: Text(c.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () async {
                      final count =
                          await tcSvc.countTechCardsUsingCustomCategory(
                              est.dataEstablishmentId, c.id);
                      if (!ctx.mounted) return;
                      if (count > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(loc
                                  .t('ttk_custom_category_in_use')
                                  .replaceAll('%s', '$count'))),
                        );
                        return;
                      }
                      final ok = await tcSvc.deleteCustomCategory(
                          est.dataEstablishmentId, c.id);
                      if (!ctx.mounted) return;
                      if (ok) {
                        await _refreshCustomCategories();
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCustomCategories() async {
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    final customKitchen = await context
        .read<TechCardServiceSupabase>()
        .getCustomCategories(est.dataEstablishmentId, 'kitchen');
    final customBar = await context
        .read<TechCardServiceSupabase>()
        .getCustomCategories(est.dataEstablishmentId, 'bar');
    if (mounted)
      setState(() {
        _customCategoriesKitchen = customKitchen;
        _customCategoriesBar = customBar;
      });
  }

  /// Собрать результат распознавания из текущей формы (для возврата «Назад» при импорте без сохранения в систему).
  TechCardRecognitionResult _buildRecognitionResultFromForm() {
    final toSaveIngredients =
        _ingredients.where((i) => !i.isPlaceholder).toList();
    final yieldVal = !_isSemiFinished
        ? _portionWeight
        : (toSaveIngredients.isEmpty
            ? 0.0
            : toSaveIngredients.fold(0.0, (s, i) => s + i.netWeight));
    final ingredientsForResult = toSaveIngredients
        .map((i) => TechCardIngredientLine(
              productName: i.productName,
              grossGrams: i.grossWeight,
              netGrams: i.netWeight,
              outputGrams: i.outputWeight,
              unit: i.unit,
              primaryWastePct: i.primaryWastePct,
              cookingLossPct: i.cookingLossPctOverride,
              ingredientType:
                  i.sourceTechCardId != null ? 'semi_finished' : 'product',
            ))
        .toList();
    return TechCardRecognitionResult(
      dishName: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      technologyText: _technologyController.text.trim().isEmpty
          ? null
          : _technologyController.text.trim(),
      ingredients: ingredientsForResult,
      isSemiFinished: _isSemiFinished,
      yieldGrams: yieldVal > 0 ? yieldVal : null,
    );
  }

  String _normalizeDishName(String input) =>
      input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<String?> _buildDuplicateNameIfNeeded({
    required String establishmentId,
    required String originalName,
  }) async {
    final normalized = _normalizeDishName(originalName);
    final rows = await Supabase.instance.client
        .from('tech_cards')
        .select('dish_name')
        .eq('establishment_id', establishmentId);
    final existingNames = <String>{};
    for (final row in (rows as List)) {
      final name = (row as Map)['dish_name']?.toString() ?? '';
      if (name.trim().isEmpty) continue;
      existingNames.add(_normalizeDishName(name));
    }
    if (!existingNames.contains(normalized)) return null;
    var i = 1;
    while (true) {
      final candidate = '$originalName-$i';
      if (!existingNames.contains(_normalizeDishName(candidate))) {
        return candidate;
      }
      i++;
    }
  }

  Future<_DuplicateNameAction?> _showDuplicateNameDialog({
    required String originalName,
    required String duplicateName,
  }) {
    return showDialog<_DuplicateNameAction>(
      context: context,
      builder: (ctx) {
        final loc = context.read<LocalizationService>();
        return AlertDialog(
          title: Text(loc.t('ttk_duplicate_exists_in_system')),
          content: Text(loc.t('ttk_duplicate_name_dialog_body', args: {
            'original': originalName,
            'duplicate': duplicateName,
          })),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_DuplicateNameAction.edit),
              child: Text(loc.t('ttk_edit_existing')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_DuplicateNameAction.delete),
              child: Text(loc.t('delete')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_DuplicateNameAction.createDuplicate),
              child: Text(loc.t('ttk_create_duplicate')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('dish_name_required_ttk'))));
      return;
    }
    if (_saving) return;
    if (mounted) {
      setState(() => _saving = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.t('ttk_saving')),
            duration: const Duration(seconds: 2)),
      );
    }
    final toSaveIngredients =
        _ingredients.where((i) => !i.isPlaceholder).toList();
    // ТТК блюдо: вес выхода = вес порции (1 порция)
    final yieldVal = !_isSemiFinished
        ? _portionWeight
        : (toSaveIngredients.isEmpty
            ? 0.0
            : toSaveIngredients.fold(0.0, (s, i) => s + i.netWeight));
    final category = _selectedCategory;
    final curLang = context.read<LocalizationService>().currentLanguageCode;
    final tc = _techCard;
    final techMap = Map<String, String>.from(tc?.technologyLocalized ?? {});
    techMap[curLang] = _technologyController.text.trim();
    for (final c in LocalizationService.productLanguageCodes) {
      techMap.putIfAbsent(c, () => '');
    }
    final svc = context.read<TechCardServiceSupabase>();

    final translationManager = context.read<TranslationManager>();
    try {
      if (_isNew || tc == null) {
        final targetEstablishmentId =
            est.isBranch ? est.id : est.dataEstablishmentId;
        final duplicateName = await _buildDuplicateNameIfNeeded(
          establishmentId: targetEstablishmentId,
          originalName: name,
        );
        if (duplicateName != null) {
          final action = await _showDuplicateNameDialog(
            originalName: name,
            duplicateName: duplicateName,
          );
          if (!mounted) return;
          if (action != _DuplicateNameAction.createDuplicate &&
              action != _DuplicateNameAction.edit &&
              action != _DuplicateNameAction.delete) {
            setState(() => _saving = false);
            return;
          }
          if (action == _DuplicateNameAction.edit) {
            setState(() => _saving = false);
            return;
          }
          if (action == _DuplicateNameAction.delete) {
            setState(() => _saving = false);
            await clearDraft();
            context.pop(false);
            return;
          }
        }
        final saveName = duplicateName ?? name;
        // Филиал создаёт ТТК в своём заведении (доп от филиала); головное — в своём.
        final created = await svc.createTechCard(
          dishName: saveName,
          category: category,
          sections: _selectedSections,
          department: widget.department == 'bar' ||
                  widget.department == 'banquet-catering-bar'
              ? 'bar'
              : 'kitchen',
          isSemiFinished: _isSemiFinished,
          establishmentId: targetEstablishmentId,
          createdBy: emp.id,
        );
        final sellingPrice = _parseSellingPrice();
        var updated = _applyEdits(created,
            portionWeight: _portionWeight,
            yieldGrams: yieldVal,
            technologyLocalized: techMap,
            descriptionForHall:
                _descriptionForHallController.text.trim().isEmpty
                    ? null
                    : _descriptionForHallController.text.trim(),
            compositionForHall:
                _compositionForHallController.text.trim().isEmpty
                    ? null
                    : _compositionForHallController.text.trim(),
            sellingPrice: sellingPrice,
            ingredients: toSaveIngredients);
        if (_pendingPhotoBytes.isNotEmpty) {
          final urls = <String>[];
          for (var i = 0; i < _pendingPhotoBytes.length; i++) {
            final url = await svc.uploadTechCardPhoto(
              establishmentId: est.dataEstablishmentId,
              techCardId: created.id,
              index: i,
              bytes: _pendingPhotoBytes[i],
            );
            if (url != null) urls.add(url);
          }
          if (urls.isNotEmpty) updated = updated.copyWith(photoUrls: urls);
        }
        await svc.saveTechCard(updated,
            changedByEmployeeId: emp.id, changedByName: emp.fullName);
        unawaited(
          ProductCookingLossLearning.recordSamplesFromIngredients(
            establishmentId: targetEstablishmentId,
            ingredients: toSaveIngredients,
            source: widget.fromAiGeneration ? 'ai' : 'user',
          ),
        );
        // Обучение: только при карточке из импорта. Иначе сбрасываем, чтобы не показывать старый тост.
        if (widget.initialFromAi == null ||
            widget.initialHeaderSignature == null) {
          AiServiceSupabase.lastLearningSuccess = null;
        }
        final sig = widget.initialHeaderSignature;
        final orig = widget.initialFromAi?.dishName?.trim();
        final sourceRows = widget.initialSourceRows;
        final shouldLearn = sig != null &&
            sig.isNotEmpty &&
            sourceRows != null &&
            sourceRows.isNotEmpty &&
            (orig != null &&
                orig.isNotEmpty &&
                (orig != name ||
                    toSaveIngredients.any((i) =>
                        !i.isPlaceholder &&
                        i.productName.trim().isNotEmpty &&
                        i.grossWeight > 0)));
        if (shouldLearn) {
          final ingredientsForLearning = toSaveIngredients
              .where((i) =>
                  !i.isPlaceholder &&
                  i.productName.trim().isNotEmpty &&
                  i.grossWeight > 0)
              .map((i) => (
                    productName: i.productName.trim(),
                    grossWeight: i.grossWeight,
                    netWeight: i.netWeight
                  ))
              .toList();
          await AiServiceSupabase.learnDishNamePosition(
            Supabase.instance.client,
            sourceRows,
            sig,
            name,
            correctedIngredients: ingredientsForLearning.isNotEmpty
                ? ingredientsForLearning
                : null,
            originalDishName: orig,
            technologyText: _technologyController.text.trim(),
          ).timeout(const Duration(seconds: 10), onTimeout: () {});
        }
        // Правка для подстановки (original → corrected) — если обучение не сработает
        if (sig != null &&
            sig.isNotEmpty &&
            orig != null &&
            orig.isNotEmpty &&
            orig != name) {
          await AiServiceSupabase.saveLearningCorrection(
            headerSignature: sig,
            field: 'dish_name',
            originalValue: orig,
            correctedValue: name,
            establishmentId: est.dataEstablishmentId,
          ).timeout(const Duration(seconds: 6), onTimeout: () {});
        }
        // Переводим название и технологию фоново. Используем updated (с фото и ингредиентами),
        // иначе перезапись через created удалит photoUrls и ingredients.
        final savedForTranslation = updated;
        final techText = _technologyController.text.trim();
        final fieldsToTranslate = <String, String>{'dish_name': saveName};
        fieldsToTranslate
            .addAll(_ingredientFieldsForTranslation(toSaveIngredients));
        if (techText.isNotEmpty) fieldsToTranslate['technology'] = techText;
        final fastTargets = LocalizationService.productLanguageCodes
            .where((code) => code != curLang)
            .toSet();
        translationManager
            .handleEntitySave(
          entityType: TranslationEntityType.techCard,
          entityId: created.id,
          textFields: fieldsToTranslate,
          sourceLanguage: curLang,
          userId: emp.id,
          targetLanguages: fastTargets.toList(growable: false),
        )
            .then((_) async {
          final nameMap = Map<String, String>.from(
              savedForTranslation.dishNameLocalized ?? {});
          nameMap[curLang] = saveName;
          final newTechMap = Map<String, String>.from(techMap);
          for (final targetLang in fastTargets) {
            final translatedName = await translationManager.getLocalizedText(
              entityType: TranslationEntityType.techCard,
              entityId: created.id,
              fieldName: 'dish_name',
              sourceText: saveName,
              sourceLanguage: curLang,
              targetLanguage: targetLang,
            );
            if (translatedName.trim().isNotEmpty &&
                translatedName != saveName) {
              nameMap[targetLang] = translatedName;
            }
            if (techText.isNotEmpty) {
              final translatedTech = await translationManager.getLocalizedText(
                entityType: TranslationEntityType.techCard,
                entityId: created.id,
                fieldName: 'technology',
                sourceText: techText,
                sourceLanguage: curLang,
                targetLanguage: targetLang,
              );
              if (translatedTech.trim().isNotEmpty &&
                  translatedTech != techText) {
                newTechMap[targetLang] = translatedTech;
              }
            }
          }
          try {
            await svc.saveTechCard(
                savedForTranslation.copyWith(
                  dishNameLocalized: nameMap,
                  technologyLocalized: newTechMap,
                ),
                skipHistory: true);
          } catch (_) {}
        });
        if (mounted) {
          setState(() => _saving = false);
          await clearDraft();
          final createdMsg = loc.t('tech_card_created');
          final fromImport = widget.initialFromAi != null &&
              widget.initialHeaderSignature != null;
          if (fromImport && AiServiceSupabase.lastLearningSuccess != null) {
            AppToastService.show(
                '$createdMsg ${AiServiceSupabase.lastLearningSuccess!}');
          } else {
            AppToastService.show(createdMsg);
          }
          if (widget.initialFromAi != null &&
              widget.initialHeaderSignature != null) {
            final ingredientsForResult = toSaveIngredients
                .map((i) => TechCardIngredientLine(
                      productName: i.productName,
                      grossGrams: i.grossWeight,
                      netGrams: i.netWeight,
                      outputGrams: i.outputWeight,
                      unit: i.unit,
                      primaryWastePct: i.primaryWastePct,
                      cookingLossPct: i.cookingLossPctOverride,
                      ingredientType: i.sourceTechCardId != null
                          ? 'semi_finished'
                          : 'product',
                    ))
                .toList();
            final result = TechCardRecognitionResult(
              dishName: saveName,
              technologyText: _technologyController.text.trim().isEmpty
                  ? null
                  : _technologyController.text.trim(),
              ingredients: ingredientsForResult,
              isSemiFinished: _isSemiFinished,
              yieldGrams: yieldVal > 0 ? yieldVal : null,
            );
            if (mounted)
              context.pop(
                  <String, dynamic>{'result': result, 'savedToSystem': true});
          } else {
            context
                .pop(true); // Новая карточка сохранена — список обновит в фоне
          }
        }
      } else {
        // Редактирование существующей ТТК. Филиал не может сохранять карточки головного заведения (должен открываться с view=1).
        var photoUrls = List<String>.from(_photoUrls);
        if (_pendingPhotoBytes.isNotEmpty) {
          for (var i = 0; i < _pendingPhotoBytes.length; i++) {
            final url = await svc.uploadTechCardPhoto(
              establishmentId: est.dataEstablishmentId,
              techCardId: tc.id,
              index: photoUrls.length + i,
              bytes: _pendingPhotoBytes[i],
            );
            if (url != null) photoUrls.add(url);
          }
        }
        final sellingPrice = _parseSellingPrice();
        final updated = _applyEdits(tc,
            dishName: name,
            category: category,
            sections: _selectedSections,
            isSemiFinished: _isSemiFinished,
            portionWeight: _portionWeight,
            yieldGrams: yieldVal,
            technologyLocalized: techMap,
            descriptionForHall:
                _descriptionForHallController.text.trim().isEmpty
                    ? null
                    : _descriptionForHallController.text.trim(),
            compositionForHall:
                _compositionForHallController.text.trim().isEmpty
                    ? null
                    : _compositionForHallController.text.trim(),
            sellingPrice: sellingPrice,
            photoUrls: photoUrls,
            ingredients: toSaveIngredients);
        final canPublishDirect =
            emp.hasRole('owner') || emp.hasRole('general_manager');
        if (!canPublishDirect) {
          await TechCardChangeRequestService.instance.submitProposal(
            techCard: updated,
            authorEmployeeId: emp.id,
          );
          if (mounted) {
            setState(() => _saving = false);
            await clearDraft();
            AppToastService.show(loc.t('tech_card_change_submitted'));
            context.pop(true);
          }
          return;
        }
        await svc.saveTechCard(updated,
            changedByEmployeeId: emp.id, changedByName: emp.fullName);
        final learnEstId =
            est.isBranch ? est.id : (est.dataEstablishmentId ?? '');
        if (learnEstId.isNotEmpty) {
          unawaited(
            ProductCookingLossLearning.recordSamplesFromIngredients(
              establishmentId: learnEstId,
              ingredients: toSaveIngredients,
              source: 'user',
            ),
          );
        }
        // Переводим название и технологию фоново
        final techText = _technologyController.text.trim();
        final fieldsToTranslate = <String, String>{'dish_name': name};
        fieldsToTranslate
            .addAll(_ingredientFieldsForTranslation(toSaveIngredients));
        if (techText.isNotEmpty) fieldsToTranslate['technology'] = techText;
        final fastTargets = LocalizationService.productLanguageCodes
            .where((code) => code != curLang)
            .toSet();
        translationManager
            .handleEntitySave(
          entityType: TranslationEntityType.techCard,
          entityId: tc.id,
          textFields: fieldsToTranslate,
          sourceLanguage: curLang,
          userId: emp.id,
          targetLanguages: fastTargets.toList(growable: false),
        )
            .then((_) async {
          final nameMap =
              Map<String, String>.from(updated.dishNameLocalized ?? {});
          nameMap[curLang] = name;
          // Обновляем technologyLocalized
          final newTechMap =
              Map<String, String>.from(updated.technologyLocalized ?? techMap);
          for (final targetLang in fastTargets) {
            final translatedName = await translationManager.getLocalizedText(
              entityType: TranslationEntityType.techCard,
              entityId: tc.id,
              fieldName: 'dish_name',
              sourceText: name,
              sourceLanguage: curLang,
              targetLanguage: targetLang,
            );
            if (translatedName.trim().isNotEmpty && translatedName != name) {
              nameMap[targetLang] = translatedName;
            }
            if (techText.isNotEmpty) {
              final translatedTech = await translationManager.getLocalizedText(
                entityType: TranslationEntityType.techCard,
                entityId: tc.id,
                fieldName: 'technology',
                sourceText: techText,
                sourceLanguage: curLang,
                targetLanguage: targetLang,
              );
              if (translatedTech.trim().isNotEmpty &&
                  translatedTech != techText) {
                newTechMap[targetLang] = translatedTech;
              }
            }
          }
          try {
            await svc.saveTechCard(
                updated.copyWith(
                  dishNameLocalized: nameMap,
                  technologyLocalized: newTechMap,
                ),
                skipHistory: true);
          } catch (_) {}
        });
        if (mounted) {
          setState(() => _saving = false);
          await clearDraft();
          AppToastService.show(context.read<LocalizationService>().t('saved'));
          context.pop(
              true); // Список обновит данные в фоне, без полного перезагруза
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  Future<void> _confirmClearForm(
      BuildContext context, LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('clear_ttk_form')),
        content: Text(loc.t('clear_ttk_form_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(loc.t('clear_ttk_form'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _nameController.clear();
      _technologyController.clear();
      _descriptionForHallController.clear();
      _compositionForHallController.clear();
      _sellingPriceController.clear();
      _selectedCategory = 'misc';
      _selectedSections = [];
      _isSemiFinished = true;
      _portionWeight = 100;
      _photoUrls = [];
      _pendingPhotoBytes = [];
      _ingredients.clear();
      _ensurePlaceholderRowAtEnd();
    });
    await clearDraft();
  }

  Future<void> _showTechCardHistory(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final historyService = context.read<TechCardHistoryService>();
    final techCardId = widget.techCardId;
    if (techCardId.isEmpty || techCardId == 'new') return;
    final entries = await historyService.getHistory(techCardId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('ttk_history')),
        content: SizedBox(
          width: 400,
          child: entries.isEmpty
              ? Text(loc.t('ttk_history_empty'),
                  style: Theme.of(ctx).textTheme.bodyMedium)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final dateStr =
                        '${e.changedAt.day.toString().padLeft(2, '0')}.${e.changedAt.month.toString().padLeft(2, '0')}.${e.changedAt.year} ${e.changedAt.hour.toString().padLeft(2, '0')}:${e.changedAt.minute.toString().padLeft(2, '0')}';
                    final who = e.changedByName ?? loc.t('ttk_history_unknown');
                    final changeLines = e.changes
                        .map<String>((c) => _formatHistoryChange(c, loc))
                        .where((s) => s.isNotEmpty)
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateStr,
                            style: Theme.of(ctx)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: Theme.of(ctx).colorScheme.primary)),
                        const SizedBox(height: 2),
                        Text(who,
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        if (changeLines.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ...changeLines.map((line) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text('• $line',
                                    style: Theme.of(ctx).textTheme.bodySmall),
                              )),
                        ],
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('back'))),
        ],
      ),
    );
  }

  String _formatHistoryChange(Map<String, dynamic> c, LocalizationService loc) {
    final type = c['type'] as String?;
    final label = c['label'] as String? ?? '';
    if (type == 'created') return label;
    if (type == 'portion_weight')
      return '$label: ${_numStr(c['old'])} → ${_numStr(c['new'])} г';
    if (type == 'yield')
      return '$label: ${_numStr(c['old'])} → ${_numStr(c['new'])} г';
    if (type == 'dish_name') return '$label: "${c['old']}" → "${c['new']}"';
    if (type == 'technology') return '$label';
    if (type == 'ingredient_added')
      return '$label "${c['product']}" (${_numStr(c['gross'])} г)';
    if (type == 'ingredient_removed') return '$label "${c['product']}"';
    if (type == 'ingredient_modified') {
      final product = c['product'] as String? ?? '';
      final details = c['details'] as List<dynamic>? ?? [];
      final parts = details.map((d) {
        final m = Map<String, dynamic>.from(d as Map);
        return '${m['field']}: ${_numStr(m['old'])} → ${_numStr(m['new'])}';
      }).join(', ');
      return '$label "$product" ($parts)';
    }
    return label;
  }

  String _numStr(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v.toStringAsFixed(v is int ? 0 : 1);
    return v.toString();
  }

  Future<void> _confirmDelete(
      BuildContext context, LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_tech_card')),
        content: Text(loc.t('delete_tech_card_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(loc.t('delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<TechCardServiceSupabase>()
          .deleteTechCard(widget.techCardId);
      if (mounted) {
        AppToastService.show(loc.t('tech_card_deleted'));
        context.pop(true); // Список обновит в фоне
      }
    } catch (e) {
      if (!mounted) return;
      if (e is PostgrestException && e.code == '23503') {
        final isRu = loc.currentLanguageCode.toLowerCase().startsWith('ru');
        final msg = isRu
            ? 'Нельзя удалить ТТК: она уже используется в заказах. Сначала удалите или переназначьте связанные позиции.'
            : 'Cannot delete this tech card: it is already used in orders. Remove or reassign linked order items first.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              loc.t('error_with_message').replaceAll('%s', e.toString()))));
    }
  }

  Future<void> _duplicateTechCard(LocalizationService loc) async {
    if (_isNew) return;
    final tc = _techCard;
    if (tc == null) return;
    if (_duplicating) return;

    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null) return;

    setState(() => _duplicating = true);
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final created = await svc.cloneTechCard(tc, emp.id);
      if (!mounted) return;
      AppToastService.show(loc.t('ttk_created_duplicate'));
      context.pushReplacement('/tech-cards/${created.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(loc.t('error_with_message').replaceAll('%s', e.toString())),
        ));
      }
    } finally {
      if (mounted) setState(() => _duplicating = false);
    }
  }

  Future<void> _showExportOptionsDialog(LocalizationService loc) async {
    final tc = _techCard;
    if (tc == null) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;

    var kind = TechCardExportKind.withPrice;
    var format = TechCardExportFormat.xlsx;
    var lang = loc.currentLanguageCode;
    var organolepticMode = OrganolepticMode.template;
    OrganolepticProperties tpl =
        ExcelExportService().defaultOrganolepticTemplate(lang);
    final appearanceCtrl = TextEditingController(text: tpl.appearance);
    final consistencyCtrl = TextEditingController(text: tpl.consistency);
    final colorCtrl = TextEditingController(text: tpl.color);
    final tasteCtrl = TextEditingController(text: tpl.tasteAndSmell);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(loc.t('ttk_export_document_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.t('ttk_export_what_to_save')),
                RadioListTile<TechCardExportKind>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(loc.t('ttk_export_with_price')),
                  value: TechCardExportKind.withPrice,
                  groupValue: kind,
                  onChanged: (v) {
                    if (v != null) setLocalState(() => kind = v);
                  },
                ),
                RadioListTile<TechCardExportKind>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(loc.t('ttk_export_without_price')),
                  value: TechCardExportKind.withoutPrice,
                  groupValue: kind,
                  onChanged: (v) {
                    if (v != null) setLocalState(() => kind = v);
                  },
                ),
                RadioListTile<TechCardExportKind>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(loc.t('ttk_export_as_act')),
                  value: TechCardExportKind.actDevelopment,
                  groupValue: kind,
                  onChanged: (v) {
                    if (v != null) setLocalState(() => kind = v);
                  },
                ),
                const SizedBox(height: 8),
                Text(loc.t('ttk_export_file_format')),
                const SizedBox(height: 6),
                DropdownButtonFormField<TechCardExportFormat>(
                  value: format,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: TechCardExportFormat.pdf,
                      child: Text('PDF'),
                    ),
                    DropdownMenuItem(
                      value: TechCardExportFormat.xlsx,
                      child: Text('XLSX'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocalState(() => format = v);
                  },
                ),
                const SizedBox(height: 10),
                Text(loc.t('ttk_export_document_language')),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: lang,
                  isExpanded: true,
                  items: loc.availableLanguages
                      .map((e) => DropdownMenuItem<String>(
                            value: e['code']!,
                            child: Text('${e['flag']} ${e['name']}'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setLocalState(() {
                        lang = v;
                        if (organolepticMode == OrganolepticMode.template) {
                          tpl =
                              ExcelExportService().defaultOrganolepticTemplate(
                            lang,
                          );
                          appearanceCtrl.text = tpl.appearance;
                          consistencyCtrl.text = tpl.consistency;
                          colorCtrl.text = tpl.color;
                          tasteCtrl.text = tpl.tasteAndSmell;
                        }
                      });
                    }
                  },
                ),
                if (kind == TechCardExportKind.actDevelopment) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(loc.t('ttk_organoleptic_properties')),
                  RadioListTile<OrganolepticMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(loc.t('ttk_organoleptic_by_template')),
                    value: OrganolepticMode.template,
                    groupValue: organolepticMode,
                    onChanged: (v) {
                      if (v != null) {
                        setLocalState(() {
                          organolepticMode = v;
                          tpl =
                              ExcelExportService().defaultOrganolepticTemplate(
                            lang,
                          );
                          appearanceCtrl.text = tpl.appearance;
                          consistencyCtrl.text = tpl.consistency;
                          colorCtrl.text = tpl.color;
                          tasteCtrl.text = tpl.tasteAndSmell;
                        });
                      }
                    },
                  ),
                  RadioListTile<OrganolepticMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(loc.t('ttk_organoleptic_edit_template')),
                    value: OrganolepticMode.custom,
                    groupValue: organolepticMode,
                    onChanged: (v) {
                      if (v != null) {
                        setLocalState(() => organolepticMode = v);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: appearanceCtrl,
                    enabled: organolepticMode == OrganolepticMode.custom,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: loc.t('ttk_organoleptic_appearance'),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: consistencyCtrl,
                    enabled: organolepticMode == OrganolepticMode.custom,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: loc.t('ttk_organoleptic_consistency'),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: colorCtrl,
                    enabled: organolepticMode == OrganolepticMode.custom,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: loc.t('ttk_organoleptic_color'),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: tasteCtrl,
                    enabled: organolepticMode == OrganolepticMode.custom,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: loc.t('ttk_organoleptic_taste_smell'),
                    ),
                    maxLines: 3,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await ExcelExportService().exportSingleTechCardAdvanced(
                    tc,
                    TechCardExportOptions(
                      format: format,
                      kind: kind,
                      languageCode: lang,
                      establishmentName: est?.name ?? '',
                      chefName: emp?.fullName ?? '',
                      chefPosition:
                          emp?.positionRole ?? est?.directorPosition ?? '',
                      documentDate: tc.createdAt,
                      organolepticMode: organolepticMode,
                      organoleptic: OrganolepticProperties(
                        appearance: appearanceCtrl.text.trim(),
                        consistency: consistencyCtrl.text.trim(),
                        color: colorCtrl.text.trim(),
                        tasteAndSmell: tasteCtrl.text.trim(),
                      ),
                    ),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (loc.t('ttk_exported')).replaceFirst('%s', tc.dishName),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        loc.t('ttk_export_error').replaceFirst('%s', '$e'),
                      ),
                    ),
                  );
                }
              },
              child: Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
    appearanceCtrl.dispose();
    consistencyCtrl.dispose();
    colorCtrl.dispose();
    tasteCtrl.dispose();
  }

  /// Применить результат распознавания ИИ к форме (название, технология, ингредиенты).
  void _applyAiResult(TechCardRecognitionResult ai) {
    if (ai.dishName != null && ai.dishName!.trim().isNotEmpty) {
      _nameController.text = ai.dishName!.trim();
      final cat = _inferCategory(ai.dishName!);
      if (_categoryOptions.contains(cat)) _selectedCategory = cat;
    }
    if (ai.technologyText != null && ai.technologyText!.trim().isNotEmpty) {
      _technologyController.text = ai.technologyText!.trim();
    }
    if (ai.isSemiFinished != null) _isSemiFinished = ai.isSemiFinished!;
    final hadPlaceholder =
        _ingredients.isNotEmpty && _ingredients.last.isPlaceholder;
    if (ai.ingredients.isNotEmpty) {
      _ingredients.removeWhere((e) => e.isPlaceholder);
      for (final line in ai.ingredients) {
        if (line.productName.trim().isEmpty) continue;
        var gross = line.grossGrams ?? 0.0;
        var net = line.netGrams ?? line.grossGrams ?? gross;
        final outG = line.outputGrams != null && line.outputGrams! > 0
            ? line.outputGrams!
            : 0.0;
        final unit = line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
        final wastePct = (line.primaryWastePct ?? 0).clamp(0.0, 99.9);
        final isPcs = unit == 'шт' || unit == 'pcs';
        final gpp = isPcs ? 50.0 : null;
        if (isPcs && gross > 0 && gross <= 50 && gross == gross.round()) {
          gross = gross * (gpp ?? 50);
          if (net == (line.grossGrams ?? 0)) net = gross;
        }
        final outW =
            (outG > 0 ? outG : (net > 0 ? net : (gross > 0 ? gross : 100.0)))
                .toDouble();
        _ingredients.add(TTIngredient(
          id: DateTime.now().millisecondsSinceEpoch.toString() +
              _ingredients.length.toString(),
          productId: null,
          productName: line.productName.trim(),
          grossWeight: gross > 0 ? gross : 100,
          netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
          outputWeight: outW.toDouble(),
          unit: unit,
          gramsPerPiece: gpp,
          primaryWastePct: wastePct,
          cookingLossPctOverride: line.cookingLossPct != null
              ? line.cookingLossPct!.clamp(0.0, 99.9)
              : null,
          isNetWeightManual: line.netGrams != null,
          finalCalories: 0,
          finalProtein: 0,
          finalFat: 0,
          finalCarbs: 0,
          cost: 0,
        ));
      }
      _ensurePlaceholderRowAtEnd();
      final sumOutput =
          _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
      _portionWeight = _isSemiFinished
          ? 100
          : (ai.yieldGrams != null && ai.yieldGrams! > 0
              ? ai.yieldGrams!.toDouble()
              : (sumOutput > 0 ? sumOutput : 100));
    } else if (hadPlaceholder && _ingredients.isNotEmpty) {
      // сохраняем плейсхолдер
    } else {
      _ensurePlaceholderRowAtEnd();
    }
    _autoFillBruttoFromNomenclature();
  }

  /// При загрузке/просмотре: пересчёт outputWeight если 0 (нетто × (1 − ужарка/100)).
  List<TTIngredient> _ensureOutputWeights(List<TTIngredient> list) {
    return list.map((i) {
      if (i.productName.isNotEmpty && i.outputWeight == 0 && i.netWeight > 0) {
        final loss = (i.cookingLossPctOverride ?? 0).clamp(0.0, 99.9) / 100.0;
        return i.copyWith(outputWeight: i.netWeight * (1.0 - loss));
      }
      return i;
    }).toList();
  }

  /// Масштабировать все ингредиенты под целевой выход — в реальном времени без подтверждения.
  void _scaleIngredientsToTotalOutput(double newOutput) {
    if (newOutput <= 0) return;
    final currentTotal = _ingredients
        .where((i) => i.productName.trim().isNotEmpty)
        .fold<double>(0, (s, i) => s + i.outputWeight);
    if (currentTotal <= 0) return;
    final factor = newOutput / currentTotal;
    if ((factor - 1.0).abs() < 0.0001) return;
    setState(() {
      final scaled = _ingredients.map((i) => i.scaleBy(factor)).toList();
      _ingredients
        ..clear()
        ..addAll(scaled);
      _ensurePlaceholderRowAtEnd();
      if (!_isSemiFinished) _portionWeight = newOutput;
    });
    _scheduleDraftSave();
  }

  /// Подстроить % отхода у всех ингредиентов так, чтобы сумма выходов = [targetOutput] г.
  /// Один общий процент отхода: (1 - w/100) * sum(gross_i * (1 - loss_i/100)) = target => w = 100*(1 - target/denom).
  void _adjustWasteToMatchOutput(double targetOutput) {
    if (targetOutput <= 0) return;
    final productStore = context.read<ProductStoreSupabase>();
    final valid =
        _ingredients.where((i) => i.productName.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;

    double denominator = 0;
    for (final ing in valid) {
      final grossG = CulinaryUnits.toGrams(ing.grossWeight, ing.unit,
          gramsPerPiece: ing.gramsPerPiece ?? 50);
      final lossPct = ing.cookingLossPctOverride ??
          CookingProcess.findById(ing.cookingProcessId ?? '')
              ?.weightLossPercentage ??
          0;
      denominator += grossG * (1.0 - lossPct.clamp(0.0, 99.9) / 100.0);
    }
    if (denominator <= 0) return;
    double w = 100.0 * (1.0 - targetOutput / denominator);
    w = w.clamp(0.0, 99.9);

    final newList = <TTIngredient>[];
    for (var i = 0; i < _ingredients.length; i++) {
      final ing = _ingredients[i];
      if (ing.productName.trim().isEmpty) {
        newList.add(ing);
        continue;
      }
      final product =
          productStore.findProductForIngredient(ing.productId, ing.productName);
      final process = ing.cookingProcessId != null
          ? CookingProcess.findById(ing.cookingProcessId!)
          : null;
      var updated = ing.updatePrimaryWastePct(w, product, process);
      updated = updated.copyWith(outputWeight: updated.netWeight);
      newList.add(updated);
    }
    setState(() {
      _ingredients.clear();
      _ingredients.addAll(newList);
      _ensurePlaceholderRowAtEnd();
    });
    _scheduleDraftSave();
  }

  /// Загрузить номенклатуру и вернуть список продуктов (для выпадающего списка в ячейке).
  Future<List<Product>> _getProductsForDropdown() async {
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return [];
    final productStore = context.read<ProductStoreSupabase>();
    await productStore.loadProducts();
    if (est.isBranch) {
      await productStore.loadNomenclatureForBranch(
          est.id, est.dataEstablishmentId!);
    } else {
      await productStore.loadNomenclature(est.dataEstablishmentId);
    }
    if (!mounted) return [];
    final effectiveId = est.isBranch ? est.id : est.dataEstablishmentId!;
    return productStore.getNomenclatureProducts(effectiveId);
  }

  /// [replaceIndex] — если задан, заменяем строку вместо добавления (тап по ячейке «Продукт»).
  Future<void> _showAddIngredient([int? replaceIndex]) async {
    final loc = context.read<LocalizationService>();
    final productStore = context.read<ProductStoreSupabase>();
    final tcSvc = context.read<TechCardServiceSupabase>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    final effectiveId = est.isBranch ? est.id : est.dataEstablishmentId!;
    if (est.isBranch) {
      await productStore.loadNomenclatureForBranch(
          est.id, est.dataEstablishmentId!);
    } else {
      await productStore.loadNomenclature(est.dataEstablishmentId);
    }

    if (!mounted) return;
    final nomenclatureProducts =
        productStore.getNomenclatureProducts(effectiveId);
    final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId!;
    Future<TechCard> ensureHydratedTechCard(TechCard tc) async {
      var working = tc;
      if (working.ingredients.isEmpty) {
        final filled = await tcSvc.fillIngredientsForCardsBulk([working]);
        if (filled.isNotEmpty) working = filled.first;
      }
      var hydratedList = [working];
      if (estPriceId.isNotEmpty) {
        hydratedList = TechCardCostHydrator.hydrate(
          hydratedList,
          productStore,
          estPriceId,
        );
      }
      hydratedList = TechCardNutritionHydrator.hydrate(
        hydratedList,
        productStore,
      );
      return hydratedList.isNotEmpty ? hydratedList.first : working;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(replaceIndex != null
                  ? loc.t('change_ingredient')
                  : loc.t('add_ingredient')),
              bottom: TabBar(
                tabs: [
                  Tab(text: loc.t('nomenclature')),
                  Tab(text: loc.t('semi_finished')),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                nomenclatureProducts.isEmpty
                    ? _EmptyNomenclatureState(loc: loc)
                    : _ProductPicker(
                        products: nomenclatureProducts,
                        onPick: (p, w, proc, waste, unit, gpp,
                                {cookingLossPctOverride}) =>
                            _addProductIngredient(p, w, proc, waste, unit, gpp,
                                replaceIndex: replaceIndex,
                                cookingLossPctOverride: cookingLossPctOverride),
                      ),
                _TechCardPicker(
                  techCards: _pickerTechCards,
                  onPick: (t, w, unit, gpp) => _addTechCardIngredient(
                    t,
                    w,
                    unit,
                    gpp,
                    replaceIndex: replaceIndex,
                  ),
                  ensureHydrated: ensureHydratedTechCard,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Показать диалог количества/единицы/способ для выбранного продукта (при выборе из выпадающего списка в ячейке).
  Future<void> _showWeightDialogForProduct(Product p, int? replaceIndex) async {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final pu = (p.unit ?? 'g').toString().toLowerCase().trim();
    final usePieces = pu == 'pcs' || pu == 'шт';
    final defaultUnit = usePieces ? pu : 'g';
    final defaultQty = usePieces ? '1' : '100';
    final defaultGpp = (p.gramsPerPiece ?? 50).toStringAsFixed(0);
    final c = TextEditingController(text: defaultQty);
    final gppController = TextEditingController(text: defaultGpp);
    final shrinkageController = TextEditingController();
    final processes = CookingProcess.forCategory(p.category);
    CookingProcess? selectedProcess;
    String selectedUnit = defaultUnit;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDlg) {
          return AlertDialog(
            title: Text(p.getLocalizedName(lang)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: c,
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                              labelText: loc.t('quantity_label')),
                          autofocus: true,
                          onSubmitted: (_) {
                            final v = double.tryParse(
                                    c.text.replaceFirst(',', '.')) ??
                                0;
                            final waste =
                                (p.primaryWastePct ?? 0).clamp(0.0, 99.9);
                            double? gpp =
                                CulinaryUnits.isCountable(selectedUnit)
                                    ? (double.tryParse(gppController.text) ??
                                        50)
                                    : null;
                            if (gpp != null && gpp <= 0) gpp = 50;
                            double? cookLossOverride;
                            if (selectedProcess != null) {
                              final entered = double.tryParse(
                                  shrinkageController.text
                                      .replaceFirst(',', '.'));
                              if (entered != null &&
                                  (entered -
                                              selectedProcess!
                                                  .weightLossPercentage)
                                          .abs() >
                                      0.01) {
                                cookLossOverride = entered.clamp(0.0, 99.9);
                              }
                            }
                            Navigator.of(ctx).pop();
                            if (v > 0)
                              _addProductIngredient(p, v, selectedProcess,
                                  waste, selectedUnit, gpp,
                                  replaceIndex: replaceIndex,
                                  cookingLossPctOverride: cookLossOverride,
                                  popNavigator: false);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: InputDecoration(
                              isDense: true, labelText: loc.t('unit_short')),
                          items: CulinaryUnits.all
                              .map((u) => DropdownMenuItem(
                                  value: u.id,
                                  child: Text(loc.unitLabel(u.id))))
                              .toList(),
                          onChanged: (v) =>
                              setStateDlg(() => selectedUnit = v ?? 'g'),
                        ),
                      ),
                    ],
                  ),
                  if (CulinaryUnits.isCountable(selectedUnit)) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: gppController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: loc.t('g_pc'), hintText: loc.t('hint_50')),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(loc.t('cooking_process'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<CookingProcess?>(
                    value: selectedProcess,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      DropdownMenuItem(
                          value: null, child: Text(loc.t('no_process'))),
                      ...processes.map((proc) => DropdownMenuItem(
                            value: proc,
                            child: Text(
                                '${loc.cookingProcessLabel(proc)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
                          )),
                    ],
                    onChanged: (v) => setStateDlg(() {
                      selectedProcess = v;
                      if (v != null)
                        shrinkageController.text =
                            v.weightLossPercentage.toStringAsFixed(1);
                      else
                        shrinkageController.text = '';
                    }),
                  ),
                  if (selectedProcess != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: shrinkageController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('ttk_cook_loss'),
                        hintText: selectedProcess?.weightLossPercentage
                            .toStringAsFixed(1),
                        helperText: loc.t('ttk_cook_loss_override_hint'),
                      ),
                      onChanged: (_) => setStateDlg(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(loc.t('back'))),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(c.text.replaceFirst(',', '.')) ?? 0;
                  final waste = (p.primaryWastePct ?? 0).clamp(0.0, 99.9);
                  double? gpp = CulinaryUnits.isCountable(selectedUnit)
                      ? (double.tryParse(gppController.text) ?? 50)
                      : null;
                  if (gpp != null && gpp <= 0) gpp = 50;
                  double? cookLossOverride;
                  if (selectedProcess != null) {
                    final entered = double.tryParse(
                        shrinkageController.text.replaceFirst(',', '.'));
                    if (entered != null &&
                        (entered - selectedProcess!.weightLossPercentage)
                                .abs() >
                            0.01) {
                      cookLossOverride = entered.clamp(0.0, 99.9);
                    }
                  }
                  Navigator.of(ctx).pop();
                  if (v > 0)
                    _addProductIngredient(
                        p, v, selectedProcess, waste, selectedUnit, gpp,
                        replaceIndex: replaceIndex,
                        cookingLossPctOverride: cookLossOverride,
                        popNavigator: false);
                },
                child: Text(loc.t('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _ensureTechCardTranslations(List<TechCard> cards) async {
    if (!mounted) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;
    final svc = context.read<TechCardServiceSupabase>();
    final missing = cards
        .where(
          (tc) => !(tc.dishNameLocalized?.containsKey(lang) == true &&
              (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false)),
        )
        .toList();
    for (final tc in missing) {
      if (!mounted) break;
      try {
        final translated = await svc
            .translateTechCardName(tc.id, tc.dishName, lang)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (translated != null && mounted) {
          setState(() {
            final idx = _semiFinishedProducts.indexWhere((c) => c.id == tc.id);
            if (idx >= 0) {
              _semiFinishedProducts[idx] = _semiFinishedProducts[idx].copyWith(
                dishNameLocalized: {
                  ...(_semiFinishedProducts[idx].dishNameLocalized ?? {}),
                  lang: translated
                },
              );
            }
            final idx2 = _pickerTechCards.indexWhere((c) => c.id == tc.id);
            if (idx2 >= 0) {
              _pickerTechCards[idx2] = _pickerTechCards[idx2].copyWith(
                dishNameLocalized: {
                  ...(_pickerTechCards[idx2].dishNameLocalized ?? {}),
                  lang: translated
                },
              );
            }
          });
        }
      } catch (_) {}
    }
  }

  void _addProductIngredient(
      Product p,
      double value,
      CookingProcess? cookingProcess,
      double primaryWastePct,
      String unit,
      double? gramsPerPiece,
      {int? replaceIndex,
      double? cookingLossPctOverride,
      bool popNavigator = true}) {
    if (popNavigator) Navigator.of(context).pop();
    final loc = context.read<LocalizationService>();
    final accountManager = context.read<AccountManagerSupabase>();
    final est = accountManager.establishment;
    final establishmentId = est != null && est.isBranch
        ? est.id
        : accountManager.dataEstablishmentId;
    final currency = accountManager.currentEmployee?.currency ??
        est?.defaultCurrency ??
        'RUB';
    final productStore = context.read<ProductStoreSupabase>();
    if (establishmentId != null && establishmentId.isNotEmpty) {
      final ep = productStore.getEstablishmentPrice(p.id, establishmentId);
      productStore.addToNomenclature(establishmentId, p.id,
          price: ep?.$1, currency: ep?.$2 ?? currency);
    }
    final ing = TTIngredient.fromProduct(
      product: p,
      cookingProcess: cookingProcess,
      grossWeight: value,
      netWeight: null,
      primaryWastePct: primaryWastePct,
      languageCode: loc.currentLanguageCode,
      unit: unit,
      gramsPerPiece: gramsPerPiece,
      cookingLossPctOverride: cookingLossPctOverride,
      productStore: productStore,
      establishmentId: establishmentId,
      defaultCurrency: currency,
    );
    setState(() {
      if (replaceIndex != null &&
          replaceIndex >= 0 &&
          replaceIndex < _ingredients.length) {
        _ingredients[replaceIndex] = ing;
      } else {
        _ingredients.add(ing);
      }
      _ensurePlaceholderRowAtEnd();
    });
    _scheduleDraftSave();
  }

  /// Подстановка продукта из поиска по номенклатуре в строку [replaceIndex] (или добавление новой).
  /// Отложенный кадр, чтобы закрытие попапа DropdownSearch не приводило к Navigator.pop экрана редактирования.
  void _addProductIngredientAt(int replaceIndex, Product p,
      {double? grossGrams}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      final accountManager = context.read<AccountManagerSupabase>();
      final est = accountManager.establishment;
      final establishmentId = est != null && est.isBranch
          ? est.id
          : accountManager.dataEstablishmentId;
      final currency = accountManager.currentEmployee?.currency ??
          est?.defaultCurrency ??
          'RUB';
      final productStore = context.read<ProductStoreSupabase>();
      if (establishmentId != null && establishmentId.isNotEmpty) {
        try {
          await productStore.addToNomenclature(
            establishmentId,
            p.id,
            price:
                productStore.getEstablishmentPrice(p.id, establishmentId)?.$1,
            currency: p.currency ?? currency,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      final ing = TTIngredient.fromProduct(
        product: p,
        cookingProcess: null,
        grossWeight: grossGrams ?? 100,
        netWeight: null,
        primaryWastePct: p.primaryWastePct ?? 0,
        languageCode: loc.currentLanguageCode,
        unit: p.unit ?? 'g',
        productStore: productStore,
        establishmentId: establishmentId,
        defaultCurrency: currency,
      );
      setState(() {
        if (replaceIndex >= 0 && replaceIndex < _ingredients.length) {
          _ingredients[replaceIndex] = ing;
          _ensurePlaceholderRowAtEnd();
        } else {
          _ingredients.add(ing);
          _ensurePlaceholderRowAtEnd();
        }
      });
      _scheduleDraftSave();
    });
  }

  void _addTechCardIngredient(
      TechCard t, double weightG, String unit, double? gramsPerPiece,
      {int? replaceIndex}) {
    Navigator.of(context).pop();
    final totalNet = t.totalNetWeight;
    if (totalNet <= 0) return;
    final loc = context.read<LocalizationService>();
    final weightConv =
        CulinaryUnits.toGrams(weightG, unit, gramsPerPiece: gramsPerPiece);
    final ing = TTIngredient.fromTechCardData(
      techCardId: t.id,
      techCardName: t.getDisplayNameInLists(loc.currentLanguageCode),
      totalNetWeight: totalNet,
      totalCalories: t.totalCalories,
      totalProtein: t.totalProtein,
      totalFat: t.totalFat,
      totalCarbs: t.totalCarbs,
      totalCost: t.totalCost,
      grossWeight: weightConv,
      unit: unit,
      gramsPerPiece: gramsPerPiece,
    );
    setState(() {
      if (replaceIndex != null &&
          replaceIndex >= 0 &&
          replaceIndex < _ingredients.length) {
        _ingredients[replaceIndex] = ing;
      } else {
        _ingredients.add(ing);
      }
      _ensurePlaceholderRowAtEnd();
    });
    _scheduleDraftSave();
  }

  /// Добавить первый ингредиент по введённому названию (пустая строка при ingredients.isEmpty) и новую пустую строку.
  void _addIngredientFromName(String productName) {
    final name = productName.trim();
    if (name.isEmpty) return;
    final ing = TTIngredient.emptyPlaceholder()
        .copyWith(productName: name)
        .withRealId();
    setState(() {
      _ingredients.add(ing);
      _ensurePlaceholderRowAtEnd();
    });
    _scheduleDraftSave();
  }

  void _removeIngredient(int i) {
    setState(() {
      _ingredients.removeAt(i);
      _ensurePlaceholderRowAtEnd();
    });
    _scheduleDraftSave();
  }

  /// Подсказка: глобальное среднее по продукту, иначе КБЖУ-карточка продукта, иначе ИИ по названию.
  Future<void> _suggestWasteForRow(int i) async {
    if (i < 0 || i >= _ingredients.length) return;
    final ing = _ingredients[i];
    final name = ing.productName.trim();
    if (name.isEmpty) return;
    final store = context.read<ProductStoreSupabase>();
    final product =
        store.findProductForIngredient(ing.productId, ing.productName);
    double? waste;
    final pid = ing.productId?.trim();
    if (pid != null && pid.isNotEmpty) {
      waste =
          await ProductCookingLossLearning.getSuggestedWastePct(productId: pid);
    }
    waste ??= product?.primaryWastePct;
    if (waste == null) {
      final ai = context.read<AiService>();
      final result = await ai.recognizeProduct(name);
      if (!mounted || result?.suggestedWastePct == null) return;
      waste = result!.suggestedWastePct;
    }
    if (!mounted || waste == null) return;
    final wFinal = waste.clamp(0.0, 99.9);
    final procId = ing.cookingProcessId?.trim();
    final proc = procId != null && procId.isNotEmpty && procId != 'custom'
        ? CookingProcess.findById(procId)
        : null;
    setState(() =>
        _ingredients[i] = ing.updatePrimaryWastePct(wFinal, product, proc));
    _scheduleDraftSave();
  }

  /// Блок фото: ПФ — сетка до 10, блюдо — 1 фото. Под технологией.
  /// Ширина как у блока "Технология" (под ширину таблицы).
  /// На мобиле — 2 фото в ряд, на десктопе — горизонтальный wrap.
  /// Тап по фото — полноэкранный просмотр.
  Widget _buildPhotoSection(LocalizationService loc, bool effectiveCanEdit) {
    final maxPhotos = _maxPhotos;
    final existing = _photoUrls.length + _pendingPhotoBytes.length;
    if (existing == 0 && !effectiveCanEdit) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Все фото в одном списке для единой нумерации индексов при тапе
    final allPhotos =
        <({String? url, Uint8List? bytes, bool isUrl, int index})>[
      ..._photoUrls.asMap().entries.map((e) =>
          (url: e.value, bytes: null as Uint8List?, isUrl: true, index: e.key)),
      ..._pendingPhotoBytes.asMap().entries.map((e) =>
          (url: null as String?, bytes: e.value, isUrl: false, index: e.key)),
    ];

    Widget photoGrid() {
      if (isMobile) {
        // 2 фото в ряд, квадратные
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: allPhotos.length,
          itemBuilder: (_, i) {
            final p = allPhotos[i];
            return _photoThumb(
              url: p.url,
              bytes: p.bytes,
              onRemove: effectiveCanEdit
                  ? () => _removePhotoByIndex(p.index, isUrl: p.isUrl)
                  : null,
              onTap: p.url != null || p.bytes != null
                  ? () => _showPhotoFullscreen(
                      allPhotos
                          .map((x) => (url: x.url, bytes: x.bytes))
                          .toList(),
                      i)
                  : null,
            );
          },
        );
      } else {
        // Десктоп — wrap с фиксированным размером миниатюр
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allPhotos.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            return _photoThumb(
              url: p.url,
              bytes: p.bytes,
              onRemove: effectiveCanEdit
                  ? () => _removePhotoByIndex(p.index, isUrl: p.isUrl)
                  : null,
              onTap: p.url != null || p.bytes != null
                  ? () => _showPhotoFullscreen(
                      allPhotos
                          .map((x) => (url: x.url, bytes: x.bytes))
                          .toList(),
                      i)
                  : null,
            );
          }).toList(),
        );
      }
    }

    final centerDesktopWebBlock = kIsWeb && !isMobile;
    return Align(
      alignment:
          centerDesktopWebBlock ? Alignment.topCenter : Alignment.centerLeft,
      child: SizedBox(
        width: _ttkTechnologyStripWidth(context, !effectiveCanEdit),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: const Border(
                      bottom: BorderSide(color: Colors.grey, width: 1)),
                ),
                child: Row(
                  children: [
                    Text(loc.t('photo'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    if (effectiveCanEdit) ...[
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add_photo_alternate, size: 20),
                        label: Text(loc.t('add')),
                        onPressed: existing >= maxPhotos
                            ? null
                            : () => _pickPhotoForTechCard(loc),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: photoGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Блок «Описание для зала» и «Состав для зала» — под фото, только для блюд.
  Widget _buildHallFieldsSection(
      LocalizationService loc, bool effectiveCanEdit) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxW = screenWidth > 1000 ? 1000.0 : screenWidth;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: maxW,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: const Border(
                      bottom: BorderSide(color: Colors.grey, width: 1)),
                ),
                child: Text(loc.t('hall_menu_info'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.t('description_for_hall'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    effectiveCanEdit
                        ? TextField(
                            controller: _descriptionForHallController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: loc.t('description_for_hall_hint'),
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          )
                        : Text(
                            _descriptionForHallController.text.isEmpty
                                ? '—'
                                : _descriptionForHallController.text,
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                    const SizedBox(height: 12),
                    Text(loc.t('composition_for_hall'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    effectiveCanEdit
                        ? TextField(
                            controller: _compositionForHallController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: loc.t('composition_for_hall_hint'),
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          )
                        : Text(
                            _compositionForHallController.text.isEmpty
                                ? '—'
                                : _compositionForHallController.text,
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                    if (_canEditSellingPrice(
                        context.read<AccountManagerSupabase>().currentEmployee,
                        _techCard,
                        isSemiFinished: _isSemiFinished,
                        category: _selectedCategory,
                        sections: _selectedSections,
                        department: widget.department)) ...[
                      const SizedBox(height: 12),
                      Text(loc.t('selling_price'),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _sellingPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          suffixText: context
                                  .read<AccountManagerSupabase>()
                                  .establishment
                                  ?.currencySymbol ??
                              '',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ] else if (_techCard != null &&
                        !_isSemiFinished &&
                        _techCard!.sellingPrice != null &&
                        _techCard!.sellingPrice! > 0) ...[
                      const SizedBox(height: 12),
                      Text(loc.t('selling_price'),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(
                          '${_techCard!.sellingPrice!.toStringAsFixed(2)} ${context.read<AccountManagerSupabase>().establishment?.currencySymbol ?? ''}',
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Миниатюра фото — квадратная, с кнопкой удаления и тапом для просмотра.
  Widget _photoThumb({
    String? url,
    Uint8List? bytes,
    VoidCallback? onRemove,
    VoidCallback? onTap,
  }) {
    final isMobile = isHandheldNarrowLayout(context);
    final size = isMobile ? double.infinity : 100.0;

    Widget image() {
      if (url != null) {
        return kIsWeb
            ? Image.network(url,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.image_not_supported),
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)))
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.image_not_supported));
      }
      if (bytes != null)
        return Image.memory(bytes,
            fit: BoxFit.cover, width: double.infinity, height: double.infinity);
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: isMobile ? double.infinity : size,
              height: isMobile ? double.infinity : size,
              child: image(),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          if (onTap != null)
            Positioned(
              bottom: 4,
              right: onRemove != null ? 32 : 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  /// Полноэкранный просмотр фото с возможностью листать между фото и зумить.
  void _showPhotoFullscreen(
      List<({String? url, Uint8List? bytes})> photos, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) =>
          _PhotoViewerDialog(photos: photos, initialIndex: initialIndex),
    );
  }

  Future<void> _pickPhotoForTechCard(LocalizationService loc) async {
    Uint8List? bytes;

    try {
      if (kIsWeb) {
        // На вебе FilePicker надёжнее
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        bytes = result.files.single.bytes;
      } else {
        final source = await showModalBottomSheet<bool>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(loc.t('photo_from_gallery')),
                  onTap: () => Navigator.pop(ctx, true),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text(loc.t('photo_from_camera')),
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
        if (source == null || !mounted) return;
        final picker = ImagePicker();
        final file = await picker.pickImage(
          source: source ? ImageSource.gallery : ImageSource.camera,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
        if (file == null || !mounted) return;
        bytes = await file.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty || !mounted) return;
      setState(() {
        if (_pendingPhotoBytes.length + _photoUrls.length < _maxPhotos) {
          _pendingPhotoBytes.add(bytes!);
        }
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.t('photo_upload_error')}: $e')));
    }
  }

  void _removePhotoByIndex(int index, {required bool isUrl}) {
    setState(() {
      if (isUrl) {
        _photoUrls.removeAt(index);
      } else {
        _pendingPhotoBytes.removeAt(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context
            .watch<AccountManagerSupabase>()
            .currentEmployee
            ?.canEditChecklistsAndTechCards ??
        false;
    final est = context.watch<AccountManagerSupabase>().establishment;
    // Филиал не может редактировать карточки головного заведения (только просмотр).
    final forceViewBecauseBranch = est != null &&
        est.isBranch &&
        _techCard != null &&
        _techCard!.establishmentId != est.id;
    final effectiveCanEdit = canEdit &&
        !widget.forceViewMode &&
        !forceViewBecauseBranch; // forceViewMode = режим «Просмотр ТТК»
    /// В просмотре без редактирования — только таблица состава (без шапки полей, КБЖУ, цен, фото и т.д.).
    final tableOnlyView = !effectiveCanEdit;
    final employee = context.watch<AccountManagerSupabase>().currentEmployee;
    final isCook = employee?.department == 'kitchen' &&
        !effectiveCanEdit; // Повар - кухня без прав редактирования

    // Определяем, является ли устройство мобильным
    final isMobile = isHandheldNarrowLayout(context);
    final compositionHScrollThumbVisible = !kIsWeb || isMobile;
    final centerDesktopWebBlock = kIsWeb && !isMobile;

    if (_isNew && !effectiveCanEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement('/tech-cards');
      });
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('appbar_title_ttk_short')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('appbar_title_ttk_short')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('appbar_title_ttk_short')),
        ),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () => context.pop(),
                          child: Text(loc.t('back')))
                    ]))),
      );
    }

    // Фаза 0: лёгкий placeholder, полная форма — в след. кадре (без замирания)
    if (!_isNew && _contentPhase == 0) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('appbar_title_ttk_short')),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text(
                loc.t('loading'),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Режим «для зала»: описание, состав, продажная цена. Только при явном forceHallView (меню зала).
    // Повары и сотрудники кухни/бара — полная ТТК в просмотре без цен (через _TtkCookTable).
    final showLimitedView =
        _techCard != null && !_techCard!.isSemiFinished && widget.forceHallView;
    if (showLimitedView) {
      final desc = _techCard!.descriptionForHall?.trim() ?? '';
      final comp = _techCard!.compositionForHall?.trim() ?? '';
      final photoUrls = _techCard!.photoUrls ?? [];
      final photoUrl = photoUrls.isNotEmpty ? photoUrls.first : null;
      final sellingPrice = _techCard!.sellingPrice;
      final currencySym = context
              .read<AccountManagerSupabase>()
              .establishment
              ?.currencySymbol ??
          '';
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('appbar_title_ttk_short')),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photoUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.restaurant, size: 64)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (desc.isNotEmpty) ...[
                Text(loc.t('description_for_hall'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (comp.isNotEmpty) ...[
                Text(loc.t('composition_for_hall'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(comp, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (sellingPrice != null && sellingPrice > 0) ...[
                Text(loc.t('selling_price'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${sellingPrice.toStringAsFixed(2)} $currencySym',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 16),
              ],
              if (desc.isEmpty &&
                  comp.isEmpty &&
                  (sellingPrice == null || sellingPrice <= 0))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    loc.t('hall_info_empty'),
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.initialFromAi != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  context.pop(<String, dynamic>{
                    'result': _buildRecognitionResultFromForm(),
                    'savedToSystem': false,
                  });
                },
                tooltip: loc.t('back'),
              )
            : appBarBackButton(context),
        title: Text(
          _isNew ? loc.t('create_tech_card') : loc.t('appbar_title_ttk_short'),
        ),
        actions: [
          if (effectiveCanEdit)
            IconButton(
                icon: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                onPressed: _saving ? null : _save,
                tooltip: loc.t('save'),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
          if (effectiveCanEdit && !_isNew)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, loc),
                tooltip: loc.t('delete_tech_card'),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
          // В режиме просмотра (view=1): разрешаем быстро создать дубликат, если есть право редактирования.
          if (canEdit && !effectiveCanEdit && !_isNew && _techCard != null)
            IconButton(
              icon: _duplicating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.copy),
              onPressed: _duplicating ? null : () => _duplicateTechCard(loc),
              tooltip: loc.t('ttk_create_duplicate'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          // Кнопка экспорта текущей ТТК
          if (!_isNew && _techCard != null)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _showExportOptionsDialog(loc),
              tooltip: loc.t('ttk_export_pdf_xlsx_tooltip'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _unfocusTtkPointerIfOutsideFocusedField,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            final topHeaderWidth =
                _ttkTechnologyStripWidth(context, tableOnlyView);
            return Column(
              children: [
                Expanded(
                  child: ClipRect(
                    child: CustomScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Шапка: название, категория, тип — на узком экране колонкой, на широком строкой
                                if (!tableOnlyView)
                                  if (narrow) ...[
                                    TextField(
                                      controller: _nameController,
                                      readOnly: !effectiveCanEdit,
                                      style: TextStyle(
                                          fontSize: isMobile ? 12 : 14),
                                      decoration: InputDecoration(
                                        labelText: loc.t('ttk_name'),
                                        isDense: true,
                                        filled: false,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _CategoryPickerField(
                                      selectedCategory: _categoryOptions
                                              .contains(_selectedCategory)
                                          ? _selectedCategory
                                          : 'misc',
                                      categoryOptions:
                                          _categoryDepartment == 'bar'
                                              ? _barCategoryOptions
                                              : _kitchenCategoryOptions,
                                      customCategories: _customCategories,
                                      categoryLabel: (c) => _categoryLabel(
                                          c, loc.currentLanguageCode),
                                      canEdit: effectiveCanEdit,
                                      onCategorySelected: (v) {
                                        setState(() => _selectedCategory = v);
                                        _scheduleDraftSave();
                                      },
                                      onAddCustom: _showAddCustomCategoryDialog,
                                      onRefreshCustom: _refreshCustomCategories,
                                      onManageCustom:
                                          _showManageCustomCategoriesDialog,
                                      loc: loc,
                                    ),
                                    const SizedBox(height: 12),
                                    _SectionPicker(
                                      selected: _selectedSections,
                                      availableSections: _getAvailableSections(
                                          context
                                              .read<AccountManagerSupabase>()
                                              .hasProSubscription,
                                          loc),
                                      canEdit: effectiveCanEdit,
                                      onChanged: (v) {
                                        setState(() => _selectedSections = v);
                                        _scheduleDraftSave();
                                      },
                                      loc: loc,
                                    ),
                                    const SizedBox(height: 12),
                                    effectiveCanEdit
                                        ? DropdownButtonFormField<bool>(
                                            value: _isSemiFinished,
                                            decoration: InputDecoration(
                                                labelText:
                                                    loc.t('tt_type_hint'),
                                                isDense: true,
                                                border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8))),
                                            items: [
                                              DropdownMenuItem(
                                                  value: true,
                                                  child: Row(children: [
                                                    const Icon(
                                                        Icons.inventory_2,
                                                        size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.t('tt_type_pf'))
                                                  ])),
                                              DropdownMenuItem(
                                                  value: false,
                                                  child: Row(children: [
                                                    const Icon(Icons.restaurant,
                                                        size: 20),
                                                    const SizedBox(width: 8),
                                                    Text(loc.t('tt_type_dish'))
                                                  ])),
                                            ],
                                            onChanged: (v) {
                                              setState(() {
                                                final toPf = v ?? true;
                                                _isSemiFinished = toPf;
                                                if (toPf) {
                                                  _portionWeight =
                                                      100; // ТТК ПФ: вес порции по умолчанию 100
                                                } else {
                                                  final sum =
                                                      _ingredients.fold<double>(
                                                          0,
                                                          (s, i) =>
                                                              s +
                                                              i.outputWeight);
                                                  _portionWeight = sum > 0
                                                      ? sum
                                                      : 100; // ТТК блюдо: вес порции = вес выхода итого
                                                }
                                              });
                                              _scheduleDraftSave();
                                            },
                                          )
                                        : InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: loc.t('tt_type_hint'),
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                    _isSemiFinished
                                                        ? Icons.inventory_2
                                                        : Icons.restaurant,
                                                    size: 20,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface),
                                                const SizedBox(width: 8),
                                                Text(
                                                    _isSemiFinished
                                                        ? loc.t('tt_type_pf')
                                                        : loc.t('tt_type_dish'),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1),
                                              ],
                                            ),
                                          ),
                                  ] else
                                    Align(
                                      alignment: centerDesktopWebBlock
                                          ? Alignment.topCenter
                                          : Alignment.topLeft,
                                      child: SizedBox(
                                        width: centerDesktopWebBlock
                                            ? topHeaderWidth
                                            : constraints.maxWidth,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 320,
                                                height: 56,
                                                child: Transform.translate(
                                                  offset: const Offset(0, 6),
                                                  child: TextField(
                                                    controller: _nameController,
                                                    readOnly: !effectiveCanEdit,
                                                    style:
                                                        TextStyle(fontSize: 14),
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          loc.t('ttk_name'),
                                                      isDense: true,
                                                      filled: false,
                                                      border:
                                                          OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8)),
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 12,
                                                              vertical: 14),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 280,
                                                child: _CategoryPickerField(
                                                  selectedCategory:
                                                      _categoryOptions.contains(
                                                              _selectedCategory)
                                                          ? _selectedCategory
                                                          : 'misc',
                                                  categoryOptions:
                                                      _categoryDepartment ==
                                                              'bar'
                                                          ? _barCategoryOptions
                                                          : _kitchenCategoryOptions,
                                                  customCategories:
                                                      _customCategories,
                                                  categoryLabel: (c) =>
                                                      _categoryLabel(c,
                                                          loc.currentLanguageCode),
                                                  canEdit: effectiveCanEdit,
                                                  onCategorySelected: (v) {
                                                    setState(() =>
                                                        _selectedCategory = v);
                                                    _scheduleDraftSave();
                                                  },
                                                  onAddCustom:
                                                      _showAddCustomCategoryDialog,
                                                  onRefreshCustom:
                                                      _refreshCustomCategories,
                                                  onManageCustom:
                                                      _showManageCustomCategoriesDialog,
                                                  loc: loc,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 180,
                                                child: _SectionPicker(
                                                  selected: _selectedSections,
                                                  availableSections:
                                                      _getAvailableSections(
                                                          context
                                                              .read<
                                                                  AccountManagerSupabase>()
                                                              .hasProSubscription,
                                                          loc),
                                                  canEdit: effectiveCanEdit,
                                                  onChanged: (v) {
                                                    setState(() =>
                                                        _selectedSections = v);
                                                    _scheduleDraftSave();
                                                  },
                                                  loc: loc,
                                                  compact: true,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 160,
                                                        maxWidth: 220),
                                                child: SizedBox(
                                                  height: 56,
                                                  child: Transform.translate(
                                                    offset: const Offset(0, -2),
                                                    child: Align(
                                                      alignment:
                                                          Alignment.center,
                                                      child: effectiveCanEdit
                                                          ? Tooltip(
                                                              message: loc.t(
                                                                  'tt_type_hint'),
                                                              child:
                                                                  SegmentedButton<
                                                                      bool>(
                                                                style: SegmentedButton
                                                                    .styleFrom(
                                                                  foregroundColor: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                                  selectedForegroundColor: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary,
                                                                  visualDensity:
                                                                      VisualDensity
                                                                          .compact,
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          6),
                                                                  tapTargetSize:
                                                                      MaterialTapTargetSize
                                                                          .shrinkWrap,
                                                                  minimumSize:
                                                                      const Size(
                                                                          80,
                                                                          44),
                                                                ).copyWith(
                                                                  shape: WidgetStateProperty
                                                                      .all(
                                                                          const StadiumBorder()),
                                                                ),
                                                                expandedInsets:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8),
                                                                segments: [
                                                                  ButtonSegment(
                                                                    value: true,
                                                                    label: Text(
                                                                        loc.t(
                                                                            'tt_type_pf'),
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis),
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .inventory_2,
                                                                        size:
                                                                            16),
                                                                  ),
                                                                  ButtonSegment(
                                                                    value:
                                                                        false,
                                                                    label: Text(
                                                                        loc.t(
                                                                            'tt_type_dish'),
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis),
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .restaurant,
                                                                        size:
                                                                            16),
                                                                  ),
                                                                ],
                                                                selected: {
                                                                  _isSemiFinished
                                                                },
                                                                onSelectionChanged:
                                                                    (v) {
                                                                  setState(() {
                                                                    final toPf =
                                                                        v.first;
                                                                    _isSemiFinished =
                                                                        toPf;
                                                                    _typeManuallyChanged =
                                                                        true;
                                                                    if (toPf) {
                                                                      _portionWeight =
                                                                          100; // ТТК ПФ: вес порции по умолчанию 100
                                                                    } else {
                                                                      final sum = _ingredients.fold<
                                                                              double>(
                                                                          0,
                                                                          (s, i) =>
                                                                              s +
                                                                              i.outputWeight);
                                                                      _portionWeight = sum >
                                                                              0
                                                                          ? sum
                                                                          : 100; // ТТК блюдо: вес порции = вес выхода итого
                                                                    }
                                                                  });
                                                                  _scheduleDraftSave();
                                                                },
                                                                showSelectedIcon:
                                                                    false,
                                                              ),
                                                            )
                                                          : InputDecorator(
                                                              decoration:
                                                                  InputDecoration(
                                                                labelText: loc.t(
                                                                    'tt_type_hint'),
                                                                isDense: true,
                                                                border: OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            8)),
                                                                contentPadding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            14),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Icon(
                                                                      _isSemiFinished
                                                                          ? Icons
                                                                              .inventory_2
                                                                          : Icons
                                                                              .restaurant,
                                                                      size: 20,
                                                                      color: Theme.of(
                                                                              context)
                                                                          .colorScheme
                                                                          .onSurface),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Text(
                                                                      _isSemiFinished
                                                                          ? loc.t(
                                                                              'tt_type_pf')
                                                                          : loc.t(
                                                                              'tt_type_dish'),
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      maxLines:
                                                                          1),
                                                                ],
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                const SizedBox(height: 16),
                                if (!tableOnlyView) ...[
                                  Align(
                                    alignment: centerDesktopWebBlock
                                        ? Alignment.topCenter
                                        : Alignment.topLeft,
                                    child: SizedBox(
                                      width: centerDesktopWebBlock
                                          ? _ttkTechnologyStripWidth(
                                              context, tableOnlyView)
                                          : double.infinity,
                                      child: Text(
                                        loc.t('ttk_composition'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (false && effectiveCanEdit && !isCook && isMobile)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _TtkCompositionPinnedHeaderDelegate(
                              loc: loc,
                              hScroll: _compositionTableHScrollController,
                              surfaceColor:
                                  Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: centerDesktopWebBlock
                                  ? Alignment.topCenter
                                  : Alignment.topLeft,
                              child: RawScrollbar(
                                controller: _compositionTableHScrollController,
                                scrollbarOrientation:
                                    ScrollbarOrientation.bottom,
                                thumbVisibility: compositionHScrollThumbVisible,
                                child: SingleChildScrollView(
                                  controller:
                                      _compositionTableHScrollController,
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  child: Builder(builder: (ctx) {
                                    // On iOS handhelds InteractiveViewer may render
                                    // the table off-screen after recent layout changes.
                                    // Keep stable table rendering across platforms.
                                    const enableZoomViewer = false;
                                    final table = effectiveCanEdit
                                        ? RepaintBoundary(
                                            child: ExcelStyleTtkTable(
                                              loc: loc,
                                              dishName: _nameController.text,
                                              isSemiFinished: _isSemiFinished,
                                              ingredients: _ingredients,
                                              canEdit: effectiveCanEdit,
                                              dishNameController:
                                                  _nameController,
                                              technologyController:
                                                  _technologyController,
                                              productStore: context
                                                  .read<ProductStoreSupabase>(),
                                              ingredientNameTranslationsById:
                                                  _ingredientNameTranslationsById,
                                              establishmentId: (() {
                                                final est = context
                                                    .read<
                                                        AccountManagerSupabase>()
                                                    .establishment;
                                                return est != null &&
                                                        est.isBranch
                                                    ? est.id
                                                    : (est?.dataEstablishmentId ??
                                                        '');
                                              })(),
                                              semiFinishedProducts:
                                                  _semiFinishedProducts,
                                              isCook: isCook,
                                              weightPerPortion: _portionWeight,
                                              onWeightPerPortionChanged: (v) {
                                                _portionWeightUpdateDebounce
                                                    ?.cancel();
                                                _portionWeight = v;
                                                _portionWeightUpdateDebounce =
                                                    Timer(
                                                  const Duration(
                                                      milliseconds: 200),
                                                  () {
                                                    if (!mounted) return;
                                                    setState(() {});
                                                    _scheduleDraftSave();
                                                  },
                                                );
                                              },
                                              onTotalOutputChanged:
                                                  (newOutput) {
                                                _scaleIngredientsToTotalOutput(
                                                    newOutput);
                                              },
                                              onAdd: _showAddIngredient,
                                              onUpdate: (i, ing) {
                                                _lastUserInteractionAt =
                                                    DateTime.now();
                                                if (_ingredients.isEmpty &&
                                                    i == 0) {
                                                  _ingredients.add(ing);
                                                  if (ing.hasData) {
                                                    _ingredients[0] =
                                                        ing.isPlaceholder
                                                            ? ing.withRealId()
                                                            : ing;
                                                  }
                                                  _ensurePlaceholderRowAtEnd();
                                                } else if (i <
                                                    _ingredients.length) {
                                                  _ingredients[i] =
                                                      ing.isPlaceholder &&
                                                              ing.hasData
                                                          ? ing.withRealId()
                                                          : ing;
                                                  _ensurePlaceholderRowAtEnd();
                                                }
                                                _ingredientUpdateDebounce
                                                    ?.cancel();
                                                _ingredientUpdateDebounce =
                                                    Timer(
                                                  const Duration(
                                                      milliseconds: 250),
                                                  () {
                                                    if (!mounted) return;
                                                    setState(() {});
                                                    _scheduleDraftSave();
                                                  },
                                                );
                                              },
                                              onRemove: _removeIngredient,
                                              onSuggestWaste:
                                                  _suggestWasteForRow,
                                              onSuggestCookingLoss:
                                                  _suggestCookingLossForRow,
                                              onAfterProductLinked:
                                                  _refreshGlobalProcessingHintsForRow,
                                              hideTechnologyBlock: true,
                                              omitTableHeader: false,
                                              shrinkWrap: true,
                                              isBarDepartment:
                                                  _categoryDepartment == 'bar',
                                              onTapPfIngredient: (id) => context
                                                  .push('/tech-cards/$id'),
                                            ),
                                          )
                                        : ListenableBuilder(
                                            listenable: context
                                                .read<ProductStoreSupabase>()
                                                .catalogRevision,
                                            builder: (context, _) {
                                              return SizedBox(
                                                width: _TtkCookTable
                                                    .intrinsicTableWidth(
                                                        context),
                                                child: _TtkCookTable(
                                                  loc: loc,
                                                  dishName:
                                                      _nameController.text,
                                                  ingredients: _ingredients
                                                      .where((i) =>
                                                          !i.isPlaceholder ||
                                                          i.hasData)
                                                      .toList(),
                                                  technology:
                                                      _technologyController
                                                          .text,
                                                  weightPerPortion:
                                                      _portionWeight,
                                                  hideTechnologyInTable: true,
                                                  productStore: context.read<
                                                      ProductStoreSupabase>(),
                                                  ingredientNameTranslationsById:
                                                      _ingredientNameTranslationsById,
                                                  onTapPfIngredient: (id) =>
                                                      context.push(
                                                          '/tech-cards/$id?view=1'),
                                                  onIngredientsChanged: (list) {
                                                    _cookTableSyncDebounce
                                                        ?.cancel();
                                                    final snapshot =
                                                        List<TTIngredient>.from(
                                                            list);
                                                    _cookTableSyncDebounce =
                                                        Timer(
                                                      const Duration(
                                                          milliseconds: 150),
                                                      () {
                                                        if (!mounted) return;
                                                        setState(() {
                                                          _ingredients
                                                            ..clear()
                                                            ..addAll(snapshot);
                                                          _ensurePlaceholderRowAtEnd();
                                                        });
                                                        _scheduleDraftSave();
                                                      },
                                                    );
                                                  },
                                                ),
                                              );
                                            },
                                          );
                                    if (!enableZoomViewer) {
                                      return table;
                                    }
                                    return InteractiveViewer(
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      constrained: false,
                                      alignment: Alignment.topLeft,
                                      minScale: 0.5,
                                      maxScale: 2.2,
                                      boundaryMargin: const EdgeInsets.all(64),
                                      child: table,
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          sliver: SliverToBoxAdapter(
                            child: Align(
                              alignment: centerDesktopWebBlock
                                  ? Alignment.topCenter
                                  : Alignment.topLeft,
                              child: SizedBox(
                                width: _ttkTechnologyStripWidth(
                                    context, tableOnlyView),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Кнопка «Подстроить % отхода под целевой выход» — отдельно под таблицей, не на панели, компактная
                                    if (!tableOnlyView)
                                      Builder(
                                        builder: (context) {
                                          final totalOutput = _ingredients
                                              .where((i) => i.productName
                                                  .trim()
                                                  .isNotEmpty)
                                              .fold<double>(0,
                                                  (s, i) => s + i.outputWeight);
                                          final showAdjust = effectiveCanEdit &&
                                              _portionWeight > 0 &&
                                              totalOutput > 0 &&
                                              (totalOutput - _portionWeight)
                                                      .abs() >
                                                  1;
                                          if (!showAdjust)
                                            return const SizedBox.shrink();
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 32),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () async {
                                                  final ok =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                      title: Text(loc.t(
                                                          'ttk_adjust_waste_title')),
                                                      content: Text(
                                                        loc
                                                            .t(
                                                                'ttk_adjust_waste_confirm')
                                                            .replaceFirst(
                                                                '%s',
                                                                _portionWeight
                                                                    .toStringAsFixed(
                                                                        0))
                                                            .replaceFirst(
                                                                '%s',
                                                                totalOutput
                                                                    .toStringAsFixed(
                                                                        0)),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        ctx)
                                                                    .pop(false),
                                                            child: Text(
                                                                MaterialLocalizations
                                                                        .of(ctx)
                                                                    .cancelButtonLabel)),
                                                        FilledButton(
                                                          onPressed: () =>
                                                              Navigator.of(ctx)
                                                                  .pop(true),
                                                          child: Text(loc
                                                              .t('answer_yes')),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (ok == true && mounted)
                                                    _adjustWasteToMatchOutput(
                                                        _portionWeight);
                                                },
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.tune,
                                                        size: 16,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                        loc.t(
                                                            'ttk_adjust_waste_to_output'),
                                                        style: const TextStyle(
                                                            fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    // Блок технологии сразу под таблицей, на странице (без ограничения по высоте «окном»)
                                    Align(
                                      alignment: centerDesktopWebBlock
                                          ? Alignment.topCenter
                                          : Alignment.centerLeft,
                                      child: SizedBox(
                                        width: _ttkTechnologyStripWidth(
                                            context, tableOnlyView),
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(top: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerLowest,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                        horizontal: 12),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  border: const Border(
                                                      bottom: BorderSide(
                                                          color: Colors.grey,
                                                          width: 1)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                        loc.t('ttk_technology'),
                                                        style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                    if (_technologyTranslating) ...[
                                                      const SizedBox(width: 8),
                                                      const SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child:
                                                              CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2)),
                                                      const SizedBox(width: 6),
                                                      Text(loc.t('loading'),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              SingleChildScrollView(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: effectiveCanEdit
                                                    ? TextField(
                                                        controller:
                                                            _technologyController,
                                                        maxLines: null,
                                                        minLines: 2,
                                                        style: const TextStyle(
                                                            fontSize: 13),
                                                        decoration:
                                                            InputDecoration(
                                                          border:
                                                              InputBorder.none,
                                                          isDense: true,
                                                          filled: false,
                                                          hintText: loc.t(
                                                              'ttk_technology'),
                                                        ),
                                                      )
                                                    : Text(
                                                        _technologyController
                                                                .text.isEmpty
                                                            ? '—'
                                                            : _technologyController
                                                                .text,
                                                        style: const TextStyle(
                                                            fontSize: 13,
                                                            height: 1.4),
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // КБЖУ и аллергены (только для блюда)
                                    if (!_isSemiFinished && !tableOnlyView)
                                      RepaintBoundary(
                                        child: Builder(
                                          builder: (ctx) {
                                            final store = context
                                                .read<ProductStoreSupabase>();
                                            _ensureDishKbjuDerived(loc, store);

                                            final totalCal = _dishKbjuTotalCal;
                                            final totalProt =
                                                _dishKbjuTotalProt;
                                            final totalFatVal =
                                                _dishKbjuTotalFat;
                                            final totalCarbVal =
                                                _dishKbjuTotalCarb;
                                            final missingNutritionIngredients =
                                                _dishKbjuMissingNames;
                                            final allergenStr =
                                                _dishKbjuAllergenStr ??
                                                    (loc.currentLanguageCode ==
                                                            'ru'
                                                        ? 'нет'
                                                        : 'none');

                                            final showKbjuBlock =
                                                !(totalCal == 0 &&
                                                    totalProt == 0 &&
                                                    totalFatVal == 0 &&
                                                    totalCarbVal == 0);

                                            final kbjuMarginTop =
                                                missingNutritionIngredients
                                                        .isNotEmpty
                                                    ? 8.0
                                                    : 12.0;

                                            String? warningText;
                                            if (missingNutritionIngredients
                                                .isNotEmpty) {
                                              const maxShown = 5;
                                              final shown =
                                                  missingNutritionIngredients
                                                      .take(maxShown)
                                                      .join(', ');
                                              final remaining =
                                                  missingNutritionIngredients
                                                          .length -
                                                      missingNutritionIngredients
                                                          .take(maxShown)
                                                          .length;
                                              final listText = remaining > 0
                                                  ? '$shown (+$remaining)'
                                                  : shown;
                                              warningText = loc
                                                  .t('kbju_incomplete_dish_nutrition_warning')
                                                  .replaceFirst('%s', listText);
                                            }

                                            void showMissingNutritionDialog() {
                                              if (missingNutritionIngredients
                                                  .isEmpty) {
                                                return;
                                              }
                                              showDialog<void>(
                                                context: ctx,
                                                builder: (dCtx) {
                                                  return AlertDialog(
                                                    title: Text(
                                                      loc.t(
                                                          'kbju_incomplete_dish_nutrition_title'),
                                                    ),
                                                    content: SizedBox(
                                                      width: 520,
                                                      height: 320,
                                                      child: ListView.builder(
                                                        itemCount:
                                                            missingNutritionIngredients
                                                                .length,
                                                        itemBuilder: (c, idx) {
                                                          final name =
                                                              missingNutritionIngredients[
                                                                  idx];
                                                          return ListTile(
                                                            dense: true,
                                                            title: Text(
                                                              name,
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(dCtx)
                                                                .pop(),
                                                        child: Text(
                                                            loc.t('dialog_ok')),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            }

                                            if (!showKbjuBlock) {
                                              if (warningText == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            top: 12),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12,
                                                        vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .errorContainer
                                                          .withOpacity(0.18),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                            .withOpacity(0.35),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      warningText,
                                                      style: const TextStyle(
                                                          fontSize: 13),
                                                    ),
                                                  ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton(
                                                      onPressed:
                                                          showMissingNutritionDialog,
                                                      child: Text(
                                                        loc.t(
                                                            'kbju_incomplete_dish_nutrition_show_list'),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                if (warningText != null)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            top: 12, bottom: 8),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12,
                                                        vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .errorContainer
                                                          .withOpacity(0.18),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                            .withOpacity(0.35),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          warningText,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 13),
                                                        ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: TextButton(
                                                            onPressed:
                                                                showMissingNutritionDialog,
                                                            child: Text(
                                                              loc.t(
                                                                  'kbju_incomplete_dish_nutrition_show_list'),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                Container(
                                                  margin: EdgeInsets.only(
                                                      top: kbjuMarginTop),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer
                                                        .withOpacity(0.3),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: Border.all(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withOpacity(0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    loc
                                                        .t(
                                                            'kbju_allergens_in_dish')
                                                        .replaceFirst(
                                                            '%s',
                                                            totalCal
                                                                .round()
                                                                .toString())
                                                        .replaceFirst(
                                                            '%s',
                                                            totalProt
                                                                .toStringAsFixed(
                                                                    1))
                                                        .replaceFirst(
                                                            '%s',
                                                            totalFatVal
                                                                .toStringAsFixed(
                                                                    1))
                                                        .replaceFirst(
                                                            '%s',
                                                            totalCarbVal
                                                                .toStringAsFixed(
                                                                    1))
                                                        .replaceFirst(
                                                            '%s', allergenStr),
                                                    style: const TextStyle(
                                                        fontSize: 13),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    // Блок фото: ПФ — сетка до 10, блюдо — 1 фото
                                    if (!tableOnlyView)
                                      _buildPhotoSection(loc, effectiveCanEdit),
                                    // Описание и состав для зала (только для блюд)
                                    if (!_isSemiFinished && !tableOnlyView)
                                      _buildHallFieldsSection(
                                          loc, effectiveCanEdit),
                                    if (effectiveCanEdit)
                                      SafeArea(
                                        top: false,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              12, 12, 12, 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  FilledButton(
                                                    onPressed:
                                                        _saving ? null : _save,
                                                    child: _saving
                                                        ? SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onPrimary))
                                                        : Text(loc.t('save')),
                                                    style:
                                                        FilledButton.styleFrom(
                                                            minimumSize:
                                                                const Size(120,
                                                                    48),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        24,
                                                                    vertical:
                                                                        14)),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  TextButton.icon(
                                                    icon: Icon(Icons.clear_all,
                                                        size: 20,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface),
                                                    label: Text(loc
                                                        .t('clear_ttk_form')),
                                                    onPressed: () =>
                                                        _confirmClearForm(
                                                            context, loc),
                                                    style: TextButton.styleFrom(
                                                        minimumSize:
                                                            const Size(100, 48),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal:
                                                                    16)),
                                                  ),
                                                  if (!_isNew) ...[
                                                    const SizedBox(width: 16),
                                                    TextButton.icon(
                                                      icon: Icon(
                                                          Icons.delete_outline,
                                                          size: 20,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .error),
                                                      label: Text(
                                                          loc.t(
                                                              'delete_tech_card'),
                                                          style: TextStyle(
                                                              color: Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .error)),
                                                      onPressed: () =>
                                                          _confirmDelete(
                                                              context, loc),
                                                      style: TextButton.styleFrom(
                                                          minimumSize:
                                                              const Size(
                                                                  120, 48),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      16)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (!_isNew) ...[
                                                const SizedBox(height: 8),
                                                TextButton.icon(
                                                  icon: Icon(Icons.history,
                                                      size: 16,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant),
                                                  label: Text(
                                                      loc.t('ttk_history'),
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant)),
                                                  onPressed: () =>
                                                      _showTechCardHistory(
                                                          context),
                                                  style: TextButton.styleFrom(
                                                      minimumSize:
                                                          const Size(0, 36),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 0)),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Закреп шапки таблицы состава при вертикальном скролле страницы.
/// Горизонталь — не второй ScrollView (один [ScrollController] может быть только у одного скролла),
/// а сдвиг содержимого по [hScroll.offset] тела таблицы — как закреплённая строка в Excel.
class _TtkCompositionPinnedHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  _TtkCompositionPinnedHeaderDelegate({
    required this.loc,
    required this.hScroll,
    required this.surfaceColor,
  });

  final LocalizationService loc;
  final ScrollController hScroll;
  final Color surfaceColor;

  static const double _extent = 45;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: surfaceColor,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: hScroll,
            builder: (context, child) {
              final dx = hScroll.hasClients ? hScroll.offset : 0.0;
              return Transform.translate(
                offset: Offset(-dx, 0),
                child: child,
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                if (!hScroll.hasClients) return;
                final p = hScroll.position;
                final next = (p.pixels - details.delta.dx)
                    .clamp(p.minScrollExtent, p.maxScrollExtent);
                hScroll.jumpTo(next);
              },
              child: ExcelStyleTtkTable.compositionPinnedHeader(loc),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(
      covariant _TtkCompositionPinnedHeaderDelegate oldDelegate) {
    return oldDelegate.loc != loc ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.hScroll != hScroll;
  }
}

class _TtkTable extends StatefulWidget {
  const _TtkTable({
    required this.loc,
    required this.dishName,
    required this.isSemiFinished,
    required this.ingredients,
    required this.effectiveCanEdit,
    required this.onRemove,
    required this.onUpdate,
    required this.onAdd,
    this.onAddFromText,
    required this.productStore,
    this.onPickProductFromSearch,
    this.getProductsForDropdown,
    this.onProductSelectedFromDropdown,
    this.dishNameController,
    this.technologyController,
    this.onSuggestWaste,
  });

  final LocalizationService loc;
  final String dishName;
  final bool isSemiFinished;
  final List<TTIngredient> ingredients;
  final bool effectiveCanEdit;
  final void Function(int i) onRemove;
  final void Function(int i, TTIngredient ing) onUpdate;
  final VoidCallback onAdd;

  /// Когда в пустой строке (при ingredients.isEmpty) вводят название продукта — добавить ингредиент и новую пустую строку.
  final void Function(String productName)? onAddFromText;
  final ProductStoreSupabase productStore;
  final void Function(int index, Product product, {double? grossGrams})?
      onPickProductFromSearch;

  /// Загрузка списка продуктов для выпадающего списка из ячейки.
  final Future<List<Product>> Function()? getProductsForDropdown;

  /// Выбран продукт из выпадающего списка в ячейке — показать диалог количества и добавить.
  final void Function(int index, Product product)?
      onProductSelectedFromDropdown;

  /// Контроллер названия блюда — первая ячейка первой строки редактируется по нему.
  final TextEditingController? dishNameController;

  /// Контроллер поля «Технология» — колонка справа в таблице.
  final TextEditingController? technologyController;

  /// Для ручной строки (без продукта): подсказка ИИ по проценту отхода.
  final void Function(int i)? onSuggestWaste;

  @override
  State<_TtkTable> createState() => _TtkTableState();
}

class _TtkTableState extends State<_TtkTable> {
  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  /// Возвращает отображаемое имя ингредиента: локализованное из store.
  /// Все ингредиенты в ТТК добавляются из номенклатуры и имеют productId,
  /// поэтому getLocalizedName всегда вернёт корректный перевод.
  String _getIngredientDisplayName(TTIngredient ing, String lang) {
    final sid = ing.sourceTechCardId?.trim();
    if (sid != null && sid.isNotEmpty) {
      return TechCard.pfLinkedIngredientDisplayName(ing, lang);
    }
    final product = widget.productStore
        .findProductForIngredient(ing.productId, ing.productName);
    if (product != null) return product.getLocalizedName(lang);
    return ing.productName;
  }

  /// Ячейка по шаблону: граница, фон, мин. высота и мин. ширина (чтобы ячейки данных и «Итого» не схлопывались).
  Widget wrapCell(Widget child, {Color? fillColor, bool dataCell = true}) {
    final theme = Theme.of(context);
    final cellBg = theme.colorScheme.surface;
    final borderColor = Colors.black87;
    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
      decoration: BoxDecoration(
        color: fillColor ?? cellBg,
        border: Border.all(width: 1, color: borderColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: double.infinity,
        child: dataCell
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44), child: child)
            : child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = widget.loc;
    final lang = loc.currentLanguageCode;
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final ozLb = {'oz': loc.t('unit_abbr_oz'), 'lb': loc.t('unit_abbr_lb')};
    final grossHeader = unitPrefs.isImperial
        ? loc.t('ttk_gross_imperial', args: ozLb)
        : loc.t('ttk_gross_gr');
    final netHeader = unitPrefs.isImperial
        ? loc.t('ttk_net_imperial', args: ozLb)
        : loc.t('ttk_net_gr');
    final outputHeader = unitPrefs.isImperial
        ? loc.t('ttk_output_imperial', args: ozLb)
        : loc.t('ttk_output_gr');
    final ingredients = widget.ingredients;
    final totalNet = ingredients.fold<double>(0, (s, ing) => s + ing.netWeight);
    // Выход г. итого — сумма выходов по ингредиентам (не нетто)
    final totalOutput = ingredients
        .where((ing) => ing.productName.trim().isNotEmpty)
        .fold<double>(0, (s, ing) {
      final out = ing.outputWeight > 0
          ? ing.outputWeight
          : ing.effectiveGrossWeight *
              (1.0 -
                  (ing.cookingLossPctOverride ?? ing.weightLossPercentage) /
                      100.0);
      return s + out;
    });
    final accountManagerForEst = context.read<AccountManagerSupabase>();
    final estId = accountManagerForEst.establishment?.id;
    // Итого по стоимости: effectiveCost или, если нет — цена заведения × нетто (чтобы не показывать 0₫ при привязанной номенклатуре)
    double resolvedCost(TTIngredient ing) {
      if (ing.effectiveCost > 0) return ing.effectiveCost;
      final product = widget.productStore
          .findProductForIngredient(ing.productId, ing.productName);
      if (product != null && estId != null && ing.netWeight > 0) {
        final price =
            widget.productStore.getEstablishmentPrice(product.id, estId)?.$1;
        if (price != null && price > 0) return price * ing.netWeight / 1000;
      }
      return 0;
    }

    final totalCost =
        ingredients.fold<double>(0, (s, ing) => s + resolvedCost(ing));
    final totalCalories =
        ingredients.fold<double>(0, (s, ing) => s + ing.finalCalories);
    final totalProtein =
        ingredients.fold<double>(0, (s, ing) => s + ing.finalProtein);
    final totalFat = ingredients.fold<double>(0, (s, ing) => s + ing.finalFat);
    final totalCarbs =
        ingredients.fold<double>(0, (s, ing) => s + ing.finalCarbs);
    final est = accountManagerForEst.establishment;
    final sym = est?.currencySymbol ??
        Establishment.currencySymbolFor(est?.defaultCurrency ??
            accountManagerForEst.currentEmployee?.currency ??
            'VND');
    UnitViewValue _displayWeight(double grams, TTIngredient ing) =>
        UnitConverter.toDisplay(
          canonicalValue: grams,
          canonicalUnit: ing.unit,
          system: unitPrefs.unitSystem,
          gramsPerPiece: ing.gramsPerPiece,
        );

    final hasDeleteCol = widget.effectiveCanEdit;
    // Порядок колонок как в образце.
    // На мобильном просмотре делаем таблицу заметно компактнее:
    // - продукт ~ на 40% уже;
    // - числовые столбцы под ширину заголовков/значений.
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideDesktop = screenWidth >= 1200;
    final isMobile = screenWidth < 600;
    final colType = isMobile ? 56.0 : 64.0; // Тип ТТК
    final colName = isMobile ? 84.0 : 100.0; // Наименование
    final colProduct = isWideDesktop ? 240.0 : (isMobile ? 126.0 : 160.0);
    final colGross = isMobile ? 56.0 : 70.0; // Брутто
    final colWaste = isMobile ? 56.0 : 64.0; // Отход %
    final colNet = isMobile ? 56.0 : 70.0; // Нетто
    final colMethod = isMobile ? 72.0 : 100.0; // Способ
    final colShrink = isMobile ? 56.0 : 64.0; // Ужарка %
    final colOutput = isMobile ? 56.0 : 70.0; // Выход
    final colCost = isMobile ? 72.0 : 82.0; // Стоимость
    final colPriceKg = isMobile ? 76.0 : 88.0; // Цена за 1 кг/шт
    final colTech = isMobile ? 140.0 : 180.0; // Технология
    const colDel = 44.0;
    final columnWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(colType),
      1: FixedColumnWidth(colName),
      2: FixedColumnWidth(colProduct),
      3: FixedColumnWidth(colGross),
      4: FixedColumnWidth(colWaste),
      5: FixedColumnWidth(colNet),
      6: FixedColumnWidth(colMethod),
      7: FixedColumnWidth(colShrink),
      8: FixedColumnWidth(colOutput),
      9: FixedColumnWidth(colCost),
      10: FixedColumnWidth(colPriceKg),
      11: FixedColumnWidth(colTech),
      if (hasDeleteCol) 12: const FixedColumnWidth(colDel),
    };
    final tableWidth = colType +
        colName +
        colProduct +
        colGross +
        colWaste +
        colNet +
        colMethod +
        colShrink +
        colOutput +
        colCost +
        colPriceKg +
        colTech +
        (hasDeleteCol ? colDel : 0.0);

    // ——— ШАБЛОН ТАБЛИЦЫ ТТК (отрисовка строго по нему) ———
    // 1) Одна строка шапки: тёмно-серая (headerBg), белый текст, границы.
    // 2) Строки данных: у каждой строки 13 колонок в порядке: Тип | Наименование | Продукт | Брутто | Отход % | Нетто | Способ | Ужарка % | Выход | Стоимость | Цена за 1 кг/шт | Технология | [Удаление].
    //    Первые три ячейки (Тип, Наименование, Продукт) — светло-серые (firstColsBg). Остальные — белые/фон поверхности, у всех границы и мин. высота 44.
    // 3) Последняя строка: «Итого» — жёлтая (amber.shade100), в колонке «Продукт» текст «Итого», в остальных — суммы или пусто.
    final borderColor = Colors.black87;
    final cellBg = theme.colorScheme.surface;
    final headerBg = Colors.grey.shade800;
    final headerTextColor = Colors.white;
    final firstColsBg = Colors.grey.shade200;

    /// Пустая ячейка в зоне заполнения — явная высота и границы (не схлопывается при пустом содержимом)
    Widget emptyDataCell({double minHeight = 56}) => wrapCell(
          Container(
            constraints: BoxConstraints(minHeight: minHeight, minWidth: 1),
            padding: _cellPad,
            alignment: Alignment.centerLeft,
            child: const SizedBox(width: 1, height: 1),
          ),
          dataCell: true,
        );

    // Одна строка шапки, без переноса и без объединения ячеек
    TableCell headerCell(String text) => TableCell(
          child: wrapCell(
            Padding(
              padding: _cellPad,
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: headerTextColor),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            fillColor: headerBg,
            dataCell: false,
          ),
        );

    // Высота объединённой ячейки «Название»: первая строка с колонкой «Технология» выше (120), остальные по 44.
    const dataRowHeight = 44.0;
    const firstRowTechHeight = 120.0;
    double mergedNameHeight(int rowCount) {
      if (rowCount <= 0) return dataRowHeight;
      return firstRowTechHeight + (rowCount - 1) * dataRowHeight;
    }

    // Отрисовка по шаблону: шапка → N строк данных (у каждой полный набор ячеек) → строка «Итого». Колонка «Название» — одна объединённая ячейка поверх (Stack).
    final table = SizedBox(
      width: tableWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Table(
            border: TableBorder.all(width: 1, color: Colors.black87),
            columnWidths: columnWidths,
            defaultColumnWidth: const FixedColumnWidth(80),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              // 1. Шапка (одна строка)
              TableRow(
                decoration: BoxDecoration(color: headerBg),
                children: [
                  headerCell(loc.t('ttk_type')),
                  headerCell(loc.t('ttk_name')),
                  headerCell(loc.t('ttk_product')),
                  headerCell(grossHeader),
                  headerCell(loc.t('ttk_waste_pct')),
                  headerCell(netHeader),
                  headerCell(loc.t('ttk_cooking_method')),
                  headerCell(loc.t('ttk_shrink_pct')),
                  headerCell(outputHeader),
                  headerCell(loc.t('ttk_cost')),
                  headerCell(loc.t('ttk_price_per_1kg_dish')),
                  headerCell(loc.t('ttk_technology')),
                  if (hasDeleteCol)
                    TableCell(
                        child: wrapCell(
                            Padding(
                                padding: _cellPad,
                                child: const SizedBox.shrink()),
                            fillColor: headerBg,
                            dataCell: false)),
                ],
              ),
              // 2. Строки данных (каждая строка = те же 13 колонок по шаблону; пустая строка — те же ячейки, без данных)
              ...ingredients.asMap().entries.map((e) {
                final i = e.key;
                final ing = e.value;
                final product = widget.productStore
                    .findProductForIngredient(ing.productId, ing.productName);
                final proc = ing.cookingProcessId != null
                    ? CookingProcess.findById(ing.cookingProcessId!)
                    : null;
                final estId =
                    context.read<AccountManagerSupabase>().establishment?.id;
                final estPrice = product != null && estId != null
                    ? widget.productStore
                        .getEstablishmentPrice(product.id, estId)
                        ?.$1
                    : null;
                final pricePerUnit = estPrice ??
                    (ing.netWeight > 0
                        ? ing.effectiveCost * 1000 / ing.netWeight
                        : 0.0);
                final isFirstRow = i == 0;
                return TableRow(
                  decoration: BoxDecoration(color: cellBg),
                  children: [
                    // Тип ТТК — пустая ячейка (объединённая ячейка рисуется в Stack ниже)
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: Container(
                        color: firstColsBg,
                        constraints: const BoxConstraints(minHeight: 44),
                      ),
                    ),
                    // Название — одна объединённая ячейка поверх всех строк (рисуется в Stack ниже); здесь — пустая ячейка без границы
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: Container(
                        color: firstColsBg,
                        constraints: const BoxConstraints(minHeight: 44),
                      ),
                    ),
                    // Продукт: выпадающий список из ячейки (не снизу экрана). Пустая строка = кнопка «Выбрать продукт».
                    widget.effectiveCanEdit &&
                            (ing.productName.isEmpty && !ing.hasData)
                        ? TableCell(
                            child: wrapCell(
                              Container(
                                color: firstColsBg,
                                constraints:
                                    const BoxConstraints(minHeight: 44),
                                padding: _cellPad,
                                alignment: Alignment.centerLeft,
                                child: (widget.getProductsForDropdown != null &&
                                        widget.onProductSelectedFromDropdown !=
                                            null)
                                    ? _ProductDropdownInCell(
                                        index: i,
                                        label: loc.t('ttk_choose_product'),
                                        getProducts:
                                            widget.getProductsForDropdown!,
                                        onSelected: widget
                                            .onProductSelectedFromDropdown!,
                                        lang: lang,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              fillColor: firstColsBg,
                            ),
                          )
                        : widget.effectiveCanEdit && product == null
                            ? TableCell(
                                child: wrapCell(
                                  Container(
                                    color: firstColsBg,
                                    constraints:
                                        const BoxConstraints(minHeight: 44),
                                    padding: _cellPad,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Tooltip(
                                            message: _getIngredientDisplayName(
                                                ing, lang),
                                            child: Text(
                                              _getIngredientDisplayName(
                                                  ing, lang),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        if (widget.getProductsForDropdown !=
                                                null &&
                                            widget.onProductSelectedFromDropdown !=
                                                null) ...[
                                          const SizedBox(width: 6),
                                          _ProductDropdownInCell(
                                            index: i,
                                            label: loc.t('ttk_choose_product'),
                                            getProducts:
                                                widget.getProductsForDropdown!,
                                            onSelected: widget
                                                .onProductSelectedFromDropdown!,
                                            lang: lang,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  fillColor: firstColsBg,
                                  dataCell: true,
                                ),
                              )
                            : TableCell(
                                child: wrapCell(
                                    Container(
                                        color: firstColsBg,
                                        constraints:
                                            const BoxConstraints(minHeight: 44),
                                        padding: _cellPad,
                                        alignment: Alignment.centerLeft,
                                        child: Tooltip(
                                            message: _getIngredientDisplayName(
                                                ing, lang),
                                            child: Text(
                                              _getIngredientDisplayName(
                                                  ing, lang),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              softWrap: true,
                                            ))),
                                    fillColor: firstColsBg,
                                    dataCell: true)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              SizedBox.expand(
                                child: _EditableGrossCell(
                                  grams: ing.grossWeight,
                                  decimalPlaces: unitPrefs.isImperial ? 2 : 0,
                                  canonicalToDisplay: (v) =>
                                      UnitConverter.toDisplay(
                                    canonicalValue: v,
                                    canonicalUnit: ing.unit,
                                    system: unitPrefs.unitSystem,
                                    gramsPerPiece: ing.gramsPerPiece,
                                  ).value,
                                  displayToCanonical: (v) =>
                                      UnitConverter.fromDisplay(
                                    displayValue: v,
                                    canonicalUnit: ing.unit,
                                    system: unitPrefs.unitSystem,
                                    gramsPerPiece: ing.gramsPerPiece,
                                  ),
                                  onChanged: (g) {
                                    if (g != null && g >= 0)
                                      widget.onUpdate(
                                          i, ing.copyWith(grossWeight: g));
                                  },
                                ),
                              ),
                            ),
                          )
                        : _cell(UnitConverter.roundUi(
                                _displayWeight(ing.grossWeight, ing).value,
                                fractionDigits: unitPrefs.isImperial ? 2 : 0)
                            .toStringAsFixed(unitPrefs.isImperial ? 2 : 0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _EditableWasteCell(
                                      value: ing.primaryWastePct,
                                      onChanged: (v) {
                                        if (v != null)
                                          widget.onUpdate(
                                              i,
                                              ing.copyWith(
                                                  primaryWastePct:
                                                      v.clamp(0.0, 99.9)));
                                      },
                                    ),
                                  ),
                                  if (product == null &&
                                      ing.productName.trim().isNotEmpty &&
                                      widget.onSuggestWaste != null)
                                    IconButton(
                                      icon: const Icon(Icons.auto_awesome,
                                          size: 18),
                                      tooltip: loc.t('ttk_suggest_waste'),
                                      onPressed: () =>
                                          widget.onSuggestWaste!(i),
                                      style: IconButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(28, 28)),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : _cell(ing.primaryWastePct.toStringAsFixed(0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              SizedBox.expand(
                                child: _EditableNetCell(
                                  value: ing.effectiveGrossWeight,
                                  decimalPlaces: unitPrefs.isImperial ? 2 : 0,
                                  canonicalToDisplay: (v) =>
                                      UnitConverter.toDisplay(
                                    canonicalValue: v,
                                    canonicalUnit: ing.unit,
                                    system: unitPrefs.unitSystem,
                                    gramsPerPiece: ing.gramsPerPiece,
                                  ).value,
                                  displayToCanonical: (v) =>
                                      UnitConverter.fromDisplay(
                                    displayValue: v,
                                    canonicalUnit: ing.unit,
                                    system: unitPrefs.unitSystem,
                                    gramsPerPiece: ing.gramsPerPiece,
                                  ),
                                  onChanged: (v) {
                                    if (v != null && v >= 0)
                                      widget.onUpdate(
                                          i,
                                          ing.copyWith(
                                              manualEffectiveGross: v));
                                  },
                                ),
                              ),
                            ),
                          )
                        : _cell(
                            UnitConverter.roundUi(
                              _displayWeight(ing.effectiveGrossWeight, ing)
                                  .value,
                              fractionDigits: unitPrefs.isImperial ? 2 : 0,
                            ).toStringAsFixed(unitPrefs.isImperial ? 2 : 0),
                          ),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: ing.cookingProcessId == 'custom'
                                        ? 'mixing'
                                        : ing.cookingProcessId,
                                    isDense: true,
                                    isExpanded: true,
                                    items: product != null
                                        ? [
                                            DropdownMenuItem(
                                                value: null,
                                                child: Text(loc.t('dash'))),
                                            ...CookingProcess.forCategory(
                                                    product!.category)
                                                .map((p) => DropdownMenuItem(
                                                      value: p.id,
                                                      child: Text(
                                                          loc.cookingProcessLabel(
                                                              p),
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    )),
                                          ]
                                        : [
                                            const DropdownMenuItem(
                                                value: null, child: Text('—')),
                                            ...CookingProcess.defaultProcesses
                                                .map((p) => DropdownMenuItem(
                                                      value: p.id,
                                                      child: Text(
                                                          loc.cookingProcessLabel(
                                                              p),
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    )),
                                          ],
                                    onChanged: (id) {
                                      if (id == null) {
                                        widget.onUpdate(
                                            i,
                                            ing.copyWith(
                                                cookingProcessId: null,
                                                cookingProcessName: null));
                                      } else {
                                        final p = CookingProcess.findById(id);
                                        if (p != null) {
                                          widget.onUpdate(
                                              i,
                                              ing.copyWith(
                                                cookingProcessId: p.id,
                                                cookingProcessName:
                                                    loc.cookingProcessLabel(p),
                                              ));
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                            )),
                          )
                        : _cell(
                            (ing.cookingProcessId != null &&
                                    ing.cookingProcessId!.trim().isNotEmpty)
                                ? (CookingProcess.findById(
                                      ing.cookingProcessId!.trim(),
                                    )?.getLocalizedName(lang) ??
                                    ing.cookingProcessName ??
                                    loc.t('dash'))
                                : (ing.cookingProcessName != null &&
                                        ing.cookingProcessName!
                                            .trim()
                                            .isNotEmpty)
                                    ? (CookingProcess.resolveFromAiToken(
                                          ing.cookingProcessName,
                                          lang,
                                        )?.getLocalizedName(lang) ??
                                        ing.cookingProcessName ??
                                        loc.t('dash'))
                                    : loc.t('dash'),
                          ),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              SizedBox.expand(
                                child: _EditableShrinkageCell(
                                  value: product != null
                                      ? ing.weightLossPercentage
                                      : (ing.cookingLossPctOverride ?? 0),
                                  onChanged: (pct) {
                                    if (pct != null) {
                                      final eff = ing.effectiveGrossWeight;
                                      final output = eff > 0
                                          ? eff *
                                              (1.0 -
                                                  pct.clamp(0.0, 99.9) / 100.0)
                                          : 0.0;
                                      widget.onUpdate(
                                          i,
                                          ing.copyWith(
                                              cookingLossPctOverride:
                                                  pct.clamp(0.0, 99.9),
                                              outputWeight: output));
                                    }
                                  },
                                ),
                              ),
                            ),
                          )
                        : _cell(ing.weightLossPercentage.toStringAsFixed(0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              SizedBox.expand(
                                child: _EditableNetCell(
                                  value: ing.outputWeight > 0
                                      ? ing.outputWeight
                                      : (ing.effectiveGrossWeight *
                                          (1.0 -
                                              (ing.cookingLossPctOverride ??
                                                      ing.weightLossPercentage) /
                                                  100.0)),
                                  onChanged: (v) {
                                    if (v != null && v >= 0) {
                                      final eff = ing.effectiveGrossWeight;
                                      if (eff > 0) {
                                        final lossPct = (1.0 - v / eff) * 100.0;
                                        widget.onUpdate(
                                            i,
                                            ing.copyWith(
                                                outputWeight: v,
                                                cookingLossPctOverride:
                                                    lossPct.clamp(0.0, 99.9)));
                                      } else {
                                        widget.onUpdate(
                                            i, ing.copyWith(outputWeight: v));
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          )
                        : _cell(
                            '${(ing.outputWeight > 0 ? ing.outputWeight : ing.effectiveGrossWeight * (1.0 - (ing.cookingLossPctOverride ?? ing.weightLossPercentage) / 100.0)).toStringAsFixed(0)}'),
                    widget.effectiveCanEdit
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              SizedBox.expand(
                                child: _EditableCostCell(
                                  cost: ing.effectiveCost,
                                  symbol: sym,
                                  onChanged: (v) {
                                    if (v != null && v >= 0)
                                      widget.onUpdate(i, ing.copyWith(cost: v));
                                  },
                                ),
                              ),
                            ),
                          )
                        : _cell(
                            NumberFormatUtils.formatDecimal(ing.effectiveCost)),
                    // Цена за 1 кг/шт блюда (по ингредиенту: стоимость за кг при выходе)
                    _cell(_outputForPrice(ing) > 0
                        ? NumberFormatUtils.formatDecimal(
                            ing.effectiveCost * 1000 / _outputForPrice(ing))
                        : ''),
                    // Колонка «Технология» — только в первой строке контент, в остальных пустая ячейка
                    isFirstRow && widget.technologyController != null
                        ? TableCell(
                            verticalAlignment: TableCellVerticalAlignment.fill,
                            child: wrapCell(
                              Container(
                                constraints:
                                    const BoxConstraints(minHeight: 120),
                                padding: _cellPad,
                                alignment: Alignment.topLeft,
                                child: TextField(
                                  controller: widget.technologyController,
                                  readOnly: !widget.effectiveCanEdit,
                                  maxLines: 8,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: loc.t('ttk_technology'),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    filled: true,
                                    fillColor: theme
                                        .colorScheme.surfaceContainerLow
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : TableCell(
                            child: wrapCell(Container(
                              constraints: const BoxConstraints(
                                  minHeight: 48, minWidth: 1),
                              padding: _cellPad,
                              child: const SizedBox(width: 1, height: 1),
                            )),
                          ),
                    if (hasDeleteCol)
                      TableCell(
                        child: wrapCell(Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: _cellPad,
                          alignment: Alignment.center,
                          child: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20),
                            onPressed: () => widget.onRemove(i),
                            tooltip: loc.t('delete'),
                            style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(32, 32)),
                          ),
                        )),
                      ),
                  ],
                );
              }),
              // 3. Строка «Итого»: в первой колонке (Тип ТТК) — «Итого», как на образце
              TableRow(
                children: [
                  _totalCell(loc.t('ttk_total')),
                  _totalCell(''),
                  _totalCell(''),
                  _totalCell(''),
                  _totalCell(''),
                  _totalCell(ingredients
                      .fold<double>(0, (s, ing) => s + ing.effectiveGrossWeight)
                      .toStringAsFixed(0)),
                  _totalCell(''),
                  _totalCell(''),
                  _totalCell(totalOutput
                      .toStringAsFixed(0)), // Выход г. итого — сумма выходов
                  _totalCell(NumberFormatUtils.formatDecimal(totalCost)),
                  _totalCell(totalOutput > 0
                      ? NumberFormatUtils.formatDecimal(
                          totalCost * 1000 / totalOutput)
                      : ''),
                  _totalCell(''),
                  if (hasDeleteCol) _totalCell(''),
                ],
              ),
            ],
          ),
          // Объединённая ячейка «Тип» — отображается один раз для всех строк
          Positioned(
            left: 1,
            top: 44 + 1,
            width: colType,
            height: mergedNameHeight(ingredients.length),
            child: Container(
              decoration: BoxDecoration(
                color: firstColsBg,
                border: Border.all(width: 1, color: borderColor),
              ),
              padding: _cellPad,
              alignment: Alignment.center,
              child: Text(
                widget.isSemiFinished ? loc.t('filter_pf') : loc.t('ttk_dish'),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Объединённая ячейка «Название» поверх всех строк данных (название задаётся при создании и дублируется сюда)
          Positioned(
            left: colType + 1,
            top: 44 + 1,
            width: colName,
            height: mergedNameHeight(ingredients.length),
            child: Container(
              decoration: BoxDecoration(
                color: firstColsBg,
                border: Border.all(width: 1, color: borderColor),
              ),
              padding: _cellPad,
              alignment: Alignment.topLeft,
              child:
                  widget.effectiveCanEdit && widget.dishNameController != null
                      ? TextField(
                          controller: widget.dishNameController,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow
                                .withValues(alpha: 0.7),
                          ),
                          style: const TextStyle(fontSize: 12),
                        )
                      : Text(
                          widget.dishName,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 10,
                        ),
            ),
          ),
        ],
      ),
    );

    // КБЖУ скрыто
    return table;
  }

  Widget _nutritionChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Выход для расчёта цены за кг: сохранённый outputWeight или вычисленный из нетто и % ужарки.
  double _outputForPrice(TTIngredient ing) {
    if (ing.outputWeight > 0) return ing.outputWeight;
    return ing.effectiveGrossWeight *
        (1.0 -
            (ing.cookingLossPctOverride ?? ing.weightLossPercentage) / 100.0);
  }

  /// Ячейка данных: тот же wrapCell (границы, мин. высота). Пустая строка — невидимый символ, чтобы ячейка не схлопывалась.
  Widget _cell(String text, {bool bold = false}) {
    return TableCell(
      child: wrapCell(
        Padding(
          padding: _cellPad,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text.isEmpty ? '\u00A0' : text,
              style: TextStyle(
                  fontSize: 12, fontWeight: bold ? FontWeight.bold : null),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ),
        dataCell: true,
      ),
    );
  }

  /// Строка «Итого»: тот же wrapCell (те же границы, мин. высота), фон жёлтый. Пустая строка — не схлопывается.
  Widget _totalCell(String text) {
    return TableCell(
      child: wrapCell(
        Padding(
          padding: _cellPad,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text.isEmpty ? '\u00A0' : text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ),
        fillColor:
            Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        dataCell: true,
      ),
    );
  }
}

/// Упрощённая таблица для повара (режим просмотра для сотрудников): Блюдо, Продукт, Брутто, Нетто, Способ, Выход, порций (шт).
/// Ширины столбцов как в таблице создания ТТК.
class _TtkCookTable extends StatefulWidget {
  const _TtkCookTable({
    required this.loc,
    required this.dishName,
    required this.ingredients,
    required this.technology,
    required this.onIngredientsChanged,
    this.hideTechnologyInTable = false,
    this.weightPerPortion = 100,
    this.onTapPfIngredient,
    this.productStore,
    this.ingredientNameTranslationsById = const {},
  });

  final LocalizationService loc;
  final String dishName;
  final List<TTIngredient> ingredients;
  final String technology;
  final void Function(List<TTIngredient> list) onIngredientsChanged;
  final bool hideTechnologyInTable;
  final double weightPerPortion;

  /// При нажатии на ингредиент-ПФ открывает карточку ТТК ПФ (просмотр).
  final void Function(String techCardId)? onTapPfIngredient;

  /// Хранилище продуктов для получения локализованных названий.
  final ProductStoreSupabase? productStore;
  final Map<String, String> ingredientNameTranslationsById;

  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);
  // Ширины как в _TtkTable (таблица создания)
  static const _colDish = 100.0;
  static const _colProduct = 190.0;
  static const _colGross = 70.0; // как столбец Цена
  static const _colNet = 70.0;
  static const _colMethod = 100.0;
  static const _colOutput = 70.0;
  static const _colPortions = 56.0;

  /// Совпадает с логикой [ExcelStyleTtkTable]: продукты −20%, «Итого» уменьшено ещё на 15% от предыдущего варианта.
  static const double _kCookBaseRowDp = 44.0;
  static const double _kCookIngredientRowHeight = _kCookBaseRowDp * 0.8;
  static const double _kCookTotalRowHeight = _kCookBaseRowDp * 0.935;
  static const double _kCookHeaderHeight = _kCookBaseRowDp;

  /// Веб на ПК: чуть шире колонки, чтобы в гапке переносы шли по словам, а не посередине.
  static double _webColumnScale(BuildContext context) {
    if (!kIsWeb) return 1.0;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1200) return 1.35;
    if (w >= 900) return 1.22;
    if (w >= 600) return 1.12;
    return 1.0;
  }

  /// Фактическая ширина таблицы просмотра (совпадает с суммой колонок).
  static double intrinsicTableWidth(BuildContext context) {
    final scale = _webColumnScale(context);
    return (_colDish +
            _colProduct +
            _colGross +
            _colNet +
            _colMethod +
            _colOutput +
            _colPortions) *
        scale;
  }

  @override
  State<_TtkCookTable> createState() => _TtkCookTableState();
}

class _TtkCookTableState extends State<_TtkCookTable> {
  late List<TTIngredient> _ingredients;
  late double _totalOutput;
  double _portionsCount =
      1; // количество порций в итого (ввод пользователя), допускаются дробные (0.3)

  /// При просмотре: пересчёт outputWeight если 0 (нетто × (1 − ужарка/100)).
  static List<TTIngredient> _recalcOutputWeights(List<TTIngredient> list) {
    return list.map((i) {
      if (i.productName.isNotEmpty && i.outputWeight == 0 && i.netWeight > 0) {
        final loss = (i.cookingLossPctOverride ?? 0).clamp(0.0, 99.9) / 100.0;
        return i.copyWith(outputWeight: i.netWeight * (1.0 - loss));
      }
      return i;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _ingredients = _recalcOutputWeights(widget.ingredients);
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
  }

  @override
  void didUpdateWidget(covariant _TtkCookTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ingredients != widget.ingredients) {
      _ingredients = _recalcOutputWeights(widget.ingredients);
      _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    }
  }

  void _scaleByOutput(double newOutput) {
    if (newOutput <= 0 || _totalOutput <= 0) return;
    final factor = newOutput / _totalOutput;
    _totalOutput = newOutput;
    _ingredients = _ingredients.map((i) => i.scaleBy(factor)).toList();
    widget.onIngredientsChanged(_ingredients);
  }

  /// При изменении брутто одного продукта — масштабируем ВСЕ продукты, выход и порции.
  void _updateGrossAt(int index, double newGross) {
    if (index < 0 || index >= _ingredients.length) return;
    final ing = _ingredients[index];
    if (ing.grossWeight <= 0) return;
    final factor = newGross / ing.grossWeight;
    if (factor <= 0) return;
    _ingredients = _ingredients.map((i) => i.scaleBy(factor)).toList();
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    setState(() {});
    widget.onIngredientsChanged(_ingredients);
  }

  /// При изменении нетто одного продукта — масштабируем ВСЕ продукты, выход и порции.
  void _updateNetAt(int index, double newNet) {
    if (index < 0 || index >= _ingredients.length) return;
    final ing = _ingredients[index];
    if (ing.netWeight <= 0) return;
    final factor = newNet / ing.netWeight;
    if (factor <= 0) return;
    _ingredients = _ingredients.map((i) => i.scaleBy(factor)).toList();
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    setState(() {});
    widget.onIngredientsChanged(_ingredients);
  }

  /// Количество продукта на N порций: outputWeight * (N * weightPerPortion / totalOutput). Допускаются дробные порции (0.3).
  String _portionsAmount(TTIngredient ing) {
    if (ing.productName.isEmpty || _totalOutput <= 0) return '';
    final val = ing.outputWeight *
        (_portionsCount * widget.weightPerPortion / _totalOutput);
    return val == val.truncateToDouble()
        ? val.toInt().toString()
        : val.toStringAsFixed(1);
  }

  Widget _cell(
    String text, {
    bool bold = false,
    TextAlign align = TextAlign.start,
    int maxLines = 4,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: _TtkCookTable._cellPad,
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : null,
          ),
          softWrap: true,
          maxLines: maxLines,
        ),
      ),
    );
  }

  /// Заголовки таблицы просмотра: по центру по горизонтали и вертикали.
  TableCell _cookHeaderCell(String text) {
    const titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      height: 1.15,
    );
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: SizedBox(
        height: _TtkCookTable._kCookHeaderHeight,
        child: Center(
          child: Padding(
            padding: _TtkCookTable._cellPad,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: titleStyle,
              softWrap: true,
              maxLines: 4,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ),
    );
  }

  TableCell _totalRowEmptyCell() {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: SizedBox(
        height: _TtkCookTable._kCookTotalRowHeight,
        width: double.infinity,
      ),
    );
  }

  TableCell _totalRowLabelCell(String label) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: SizedBox(
        height: _TtkCookTable._kCookTotalRowHeight,
        width: double.infinity,
        child: Padding(
          padding: _TtkCookTable._cellPad,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final ozLb = {
      'oz': widget.loc.t('unit_abbr_oz'),
      'lb': widget.loc.t('unit_abbr_lb'),
    };
    final grossHeader = unitPrefs.isImperial
        ? widget.loc.t('ttk_gross_imperial', args: ozLb)
        : widget.loc.t('ttk_gross_gr');
    final netHeader = unitPrefs.isImperial
        ? widget.loc.t('ttk_net_imperial', args: ozLb)
        : widget.loc.t('ttk_net_gr');
    final outputHeader = unitPrefs.isImperial
        ? widget.loc.t('ttk_output_imperial', args: ozLb)
        : widget.loc.t('ttk_output_gr');
    UnitViewValue displayWeight(TTIngredient ing, double grams) =>
        UnitConverter.toDisplay(
          canonicalValue: grams,
          canonicalUnit: ing.unit,
          system: unitPrefs.unitSystem,
          gramsPerPiece: ing.gramsPerPiece,
        );
    final totalOutputDisplay = UnitConverter.toDisplay(
      canonicalValue: _totalOutput,
      canonicalUnit: 'g',
      system: unitPrefs.unitSystem,
    );
    String weightText(TTIngredient ing, double grams) {
      final dv = displayWeight(ing, grams);
      final digits = unitPrefs.isImperial ? 2 : 0;
      return UnitConverter.roundUi(dv.value, fractionDigits: digits)
          .toStringAsFixed(digits);
    }

    final borderColor = Colors.grey;
    final colScale = _TtkCookTable._webColumnScale(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Table(
          border: TableBorder.all(width: 0.5, color: borderColor),
          columnWidths: {
            0: FixedColumnWidth(_TtkCookTable._colDish * colScale),
            1: FixedColumnWidth(_TtkCookTable._colProduct * colScale),
            2: FixedColumnWidth(_TtkCookTable._colGross * colScale),
            3: FixedColumnWidth(_TtkCookTable._colNet * colScale),
            4: FixedColumnWidth(_TtkCookTable._colMethod * colScale),
            5: FixedColumnWidth(_TtkCookTable._colOutput * colScale),
            6: FixedColumnWidth(_TtkCookTable._colPortions * colScale),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)),
              children: [
                _cookHeaderCell(widget.loc.t('ttk_name')),
                _cookHeaderCell(widget.loc.t('ttk_product')),
                _cookHeaderCell(grossHeader),
                _cookHeaderCell(netHeader),
                _cookHeaderCell(widget.loc.t('ttk_cooking_method')),
                _cookHeaderCell(outputHeader),
                _cookHeaderCell(widget.loc.t('ttk_portions_pcs')),
              ],
            ),
            if (_ingredients.isEmpty)
              TableRow(
                children: List.filled(
                  7,
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: _TtkCookTable._cellPad,
                      child: Text(
                        widget.loc.t('dash'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              )
            else
              ..._ingredients.asMap().entries.map((e) {
                final i = e.key;
                final ing = e.value;
                final cookProduct = widget.productStore
                    ?.findProductForIngredient(ing.productId, ing.productName);
                final cookLang = widget.loc.currentLanguageCode;
                final cookDisplayName = ing.sourceTechCardId != null &&
                        ing.sourceTechCardId!.trim().isNotEmpty
                    ? TechCard.pfLinkedIngredientDisplayName(ing, cookLang)
                    : (widget.ingredientNameTranslationsById[ing.id] ??
                        cookProduct?.getLocalizedName(cookLang) ??
                        ing.productName);
                // Название — placeholder (объединённая ячейка рисуется поверх в Stack)
                return TableRow(
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: _TtkCookTable._kCookIngredientRowHeight,
                        ),
                        color: Colors.white,
                      ),
                    ),
                    ing.sourceTechCardId != null &&
                            ing.sourceTechCardId!.isNotEmpty &&
                            widget.onTapPfIngredient != null
                        ? TableCell(
                            verticalAlignment:
                                TableCellVerticalAlignment.middle,
                            child: InkWell(
                              onTap: () => widget
                                  .onTapPfIngredient!(ing.sourceTechCardId!),
                              child: Padding(
                                padding: _TtkCookTable._cellPad,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text.rich(
                                    TextSpan(
                                      style: const TextStyle(fontSize: 12),
                                      children: [
                                        TextSpan(
                                          text: cookDisplayName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' (${weightText(ing, ing.outputWeight)} ${widget.loc.unitLabel(displayWeight(ing, ing.outputWeight).unitId)})',
                                        ),
                                      ],
                                    ),
                                    textAlign: TextAlign.start,
                                    softWrap: true,
                                    maxLines: null,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : TableCell(
                            verticalAlignment:
                                TableCellVerticalAlignment.middle,
                            child: Padding(
                              padding: _TtkCookTable._cellPad,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  cookDisplayName,
                                  textAlign: TextAlign.start,
                                  style: const TextStyle(fontSize: 12),
                                  softWrap: true,
                                  maxLines: null,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                          ),
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: SizedBox.expand(
                        child: _EditableNetCell(
                          value: ing.grossWeight,
                          decimalPlaces: unitPrefs.isImperial ? 2 : 0,
                          canonicalToDisplay: (v) =>
                              displayWeight(ing, v).value,
                          displayToCanonical: (v) => UnitConverter.fromDisplay(
                            displayValue: v,
                            canonicalUnit: ing.unit,
                            system: unitPrefs.unitSystem,
                            gramsPerPiece: ing.gramsPerPiece,
                          ),
                          onChanged: (v) =>
                              _updateGrossAt(i, v ?? ing.grossWeight),
                        ),
                      ),
                    ),
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: SizedBox.expand(
                        child: _EditableNetCell(
                          value: ing.netWeight,
                          decimalPlaces: unitPrefs.isImperial ? 2 : 0,
                          canonicalToDisplay: (v) =>
                              displayWeight(ing, v).value,
                          displayToCanonical: (v) => UnitConverter.fromDisplay(
                            displayValue: v,
                            canonicalUnit: ing.unit,
                            system: unitPrefs.unitSystem,
                            gramsPerPiece: ing.gramsPerPiece,
                          ),
                          onChanged: (v) => _updateNetAt(i, v ?? ing.netWeight),
                        ),
                      ),
                    ),
                    _cell(
                      (ing.cookingProcessId != null &&
                              ing.cookingProcessId!.trim().isNotEmpty)
                          ? (CookingProcess.findById(
                                ing.cookingProcessId!.trim(),
                              )?.getLocalizedName(cookLang) ??
                              ing.cookingProcessName ??
                              widget.loc.t('dash'))
                          : (ing.cookingProcessName != null &&
                                  ing.cookingProcessName!.trim().isNotEmpty)
                              ? (CookingProcess.resolveFromAiToken(
                                    ing.cookingProcessName,
                                    cookLang,
                                  )?.getLocalizedName(cookLang) ??
                                  ing.cookingProcessName ??
                                  widget.loc.t('dash'))
                              : widget.loc.t('dash'),
                    ),
                    _cell(weightText(ing, ing.outputWeight),
                        align: TextAlign.center),
                    _cell(_portionsAmount(ing), align: TextAlign.center),
                  ],
                );
              }),
            TableRow(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest),
              children: [
                _totalRowLabelCell(widget.loc.t('ttk_total')),
                _totalRowEmptyCell(),
                _totalRowEmptyCell(),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: SizedBox(
                    height: _TtkCookTable._kCookTotalRowHeight,
                    width: double.infinity,
                    child: Center(
                      child: Text(
                        UnitConverter.roundUi(
                          totalOutputDisplay.value,
                          fractionDigits: unitPrefs.isImperial ? 2 : 0,
                        ).toStringAsFixed(unitPrefs.isImperial ? 2 : 0),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                _totalRowEmptyCell(),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: SizedBox(
                    height: _TtkCookTable._kCookTotalRowHeight,
                    width: double.infinity,
                    child: _EditableNetCell(
                      value: _totalOutput,
                      decimalPlaces: unitPrefs.isImperial ? 2 : 0,
                      canonicalToDisplay: (v) => UnitConverter.toDisplay(
                        canonicalValue: v,
                        canonicalUnit: 'g',
                        system: unitPrefs.unitSystem,
                      ).value,
                      displayToCanonical: (v) => UnitConverter.fromDisplay(
                        displayValue: v,
                        canonicalUnit: 'g',
                        system: unitPrefs.unitSystem,
                      ),
                      onChanged: (v) {
                        if (v != null && v > 0) _scaleByOutput(v);
                      },
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: SizedBox(
                    height: _TtkCookTable._kCookTotalRowHeight,
                    width: double.infinity,
                    child: _EditableNetCell(
                      value: _portionsCount,
                      decimalPlaces: 1,
                      onChanged: (v) {
                        if (v == null || v <= 0) return;
                        setState(() {
                          _portionsCount = v.clamp(0.1, 9999.0);
                          // Пересчёт всей таблицы под N порций: брутто, нетто, выход по всем продуктам и в Итого
                          final targetOutput =
                              _portionsCount * widget.weightPerPortion;
                          _scaleByOutput(targetOutput);
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.hideTechnologyInTable &&
                widget.technology.trim().isNotEmpty) ...[
              TableRow(
                children: [
                  TableCell(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.loc.t('ttk_technology'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.technology,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                  const TableCell(child: SizedBox()),
                ],
              ),
            ],
          ],
        ),
        // Объединённая ячейка «Название» — по границам колонки 0
        if (_ingredients.isNotEmpty)
          Positioned(
            left: 0,
            top: _TtkCookTable._kCookHeaderHeight,
            width: _TtkCookTable._colDish * colScale,
            height:
                _ingredients.length * _TtkCookTable._kCookIngredientRowHeight +
                    1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey, width: 0.5),
              ),
              padding: _TtkCookTable._cellPad,
              alignment: Alignment.topLeft,
              child: Text(
                widget.dishName,
                style: const TextStyle(fontSize: 12),
                softWrap: true,
              ),
            ),
          ),
      ],
    );
  }
}

class _EditableNetCell extends StatefulWidget {
  const _EditableNetCell({
    required this.value,
    required this.onChanged,
    this.decimalPlaces = 0,
    this.canonicalToDisplay,
    this.displayToCanonical,
    this.expandToCell = true,
  });

  final double value;
  final void Function(double? v) onChanged;

  /// true — как раньше, растягивается на высоту ячейки; false — одна строка по центру.
  final bool expandToCell;

  /// Количество знаков после запятой (0 = целые, 1 = 0.3 и т.д.)
  final int decimalPlaces;
  final double Function(double canonical)? canonicalToDisplay;
  final double Function(double display)? displayToCanonical;

  /// Целые без .0 (1, 2), дробные с одним знаком (0.5, 0.3).
  String _format(double v) {
    final shown = canonicalToDisplay?.call(v) ?? v;
    if (decimalPlaces == 0) return shown.toStringAsFixed(0);
    return shown == shown.truncateToDouble()
        ? shown.toInt().toString()
        : shown.toStringAsFixed(decimalPlaces);
  }

  @override
  State<_EditableNetCell> createState() => _EditableNetCellState();
}

class _EditableNetCellState extends State<_EditableNetCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget._format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _EditableNetCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fmt = widget._format(widget.value);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _ctrl.text != fmt) {
      _ctrl.text = fmt;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleSubmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    if (v == null || v < 0) {
      widget.onChanged(null);
      return;
    }
    final canonical = widget.displayToCanonical?.call(v) ?? v;
    widget.onChanged(canonical >= 0 ? canonical : null);
  }

  @override
  Widget build(BuildContext context) {
    return _ttkNumericEditableField(
      context: context,
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onInputChanged: _scheduleSubmit,
      onSubmit: _submit,
      expandToCell: widget.expandToCell,
    );
  }
}

/// Диалог выбора продукта: поле ручного поиска по названию + скроллируемый список.
class _ProductSelectDialog extends StatefulWidget {
  const _ProductSelectDialog({required this.products, required this.lang});

  final List<Product> products;
  final String lang;

  @override
  State<_ProductSelectDialog> createState() => _ProductSelectDialogState();
}

class _ProductSelectDialogState extends State<_ProductSelectDialog> {
  String _query = '';
  bool _translating = false;
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTranslations());
  }

  Future<void> _ensureTranslations() async {
    if (!mounted) return;
    final lang = widget.lang;
    if (lang == 'ru') {
      _searchFocus.requestFocus();
      return;
    }
    final store = context.read<ProductStoreSupabase>();
    final missing = widget.products
        .where(
          (p) => !(p.names?.containsKey(lang) == true &&
              (p.names![lang]?.trim().isNotEmpty ?? false)),
        )
        .toList();

    if (missing.isNotEmpty) {
      setState(() => _translating = true);
      // Переводим по одному с таймаутом 5 сек — если зависнет, не блокируем UI
      for (final p in missing) {
        if (!mounted) break;
        try {
          await store
              .translateProductAwait(p.id)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
        } catch (_) {}
        if (mounted) setState(() {});
      }
      if (!mounted) return;
      setState(() => _translating = false);
    }

    _searchFocus.requestFocus();
  }

  String _getDisplayName(Product p) => p.getLocalizedName(widget.lang);

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();

    if (_translating) {
      return AlertDialog(
        title: Text(loc.t('ttk_choose_product')),
        content: const SizedBox(
          width: 420,
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.products
        : widget.products
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                _getDisplayName(p).toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: Text(loc.t('ttk_choose_product')),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Строка для ручного ввода — поиск по названию, чтобы не скроллить список
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  labelText: loc.t('search'),
                  hintText: loc.t('search'),
                  prefixIcon: const Icon(Icons.search, size: 22),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  filled: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  return ListTile(
                    title: Text(
                      _getDisplayName(p),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    onTap: () => Navigator.of(context).pop(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка в ячейке таблицы: по нажатию открывается диалог выбора продукта (поиск вручную + скролл списка).
class _ProductDropdownInCell extends StatelessWidget {
  const _ProductDropdownInCell({
    required this.index,
    required this.label,
    required this.getProducts,
    required this.onSelected,
    required this.lang,
  });

  final int index;
  final String label;
  final Future<List<Product>> Function() getProducts;
  final void Function(int index, Product product) onSelected;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        // Не ждём загрузку продуктов "до" открытия диалога: на слабых сетях/данных
        // это блокирует UI на несколько секунд. Сначала показываем диалог-лоадер,
        // а список подгружается внутри FutureBuilder.
        final productsFuture = getProducts();
        final selected = await showDialog<Product>(
          context: context,
          builder: (ctx) => FutureBuilder<List<Product>>(
            future: productsFuture,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const AlertDialog(
                  content: SizedBox(
                    width: 420,
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              final products = snap.data!;
              if (products.isEmpty) {
                final loc = ctx.read<LocalizationService>();
                return AlertDialog(
                  title: Text(loc.t('products_list_empty_title')),
                  content: Text(loc.t('products_list_empty_body')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(loc.t('dialog_ok')),
                    ),
                  ],
                );
              }
              return _ProductSelectDialog(products: products, lang: lang);
            },
          ),
        );
        if (selected != null && context.mounted) onSelected(index, selected);
      },
      icon: const Icon(Icons.arrow_drop_down, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 36)),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.onPick});

  final List<Product> products;
  final void Function(Product p, double value, CookingProcess? proc,
      double waste, String unit, double? gramsPerPiece,
      {double? cookingLossPctOverride}) onPick;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _EmptyNomenclatureState extends StatelessWidget {
  const _EmptyNomenclatureState({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              loc.t('products_list_empty_title'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('products_list_empty_body'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPickerState extends State<_ProductPicker> {
  String _query = '';
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTranslations());
  }

  /// Для продуктов без names[lang] — ждём перевода через auto-translate-product,
  /// обновляем store. Показываем лоадер пока не готово.
  Future<void> _ensureTranslations() async {
    if (!mounted) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (lang == 'ru') return;

    final store = context.read<ProductStoreSupabase>();
    final missing = widget.products
        .where(
          (p) => !(p.names?.containsKey(lang) == true &&
              (p.names![lang]?.trim().isNotEmpty ?? false)),
        )
        .toList();

    if (missing.isEmpty) return;

    setState(() => _translating = true);
    await Future.wait(missing.map((p) => store.translateProductAwait(p.id)));
    if (mounted) setState(() => _translating = false);
  }

  String _getDisplayName(Product p, String lang) => p.getLocalizedName(lang);

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;

    if (_translating) {
      return const Center(child: CircularProgressIndicator());
    }

    var list = widget.products;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              _getDisplayName(p, lang).toLowerCase().contains(q))
          .toList();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: InputDecoration(
                labelText: loc.t('search'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _askWeight(p, loc),
                child: ListTile(
                  title: Text(_getDisplayName(p, lang)),
                  subtitle:
                      Text(loc.unitLabel((p.unit ?? 'g').trim().toLowerCase())),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _askWeight(Product p, LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final pu = (p.unit ?? 'g').toString().toLowerCase().trim();
    final usePieces = pu == 'pcs' || pu == 'шт';
    final defaultUnit = usePieces ? pu : 'g';
    final defaultQty = usePieces ? '1' : '100';
    final defaultGpp = (p.gramsPerPiece ?? 50).toStringAsFixed(0);
    final c = TextEditingController(text: defaultQty);
    final gppController = TextEditingController(text: defaultGpp);
    final shrinkageController = TextEditingController();
    final processes = CookingProcess.forCategory(p.category);
    CookingProcess? selectedProcess;
    String selectedUnit = defaultUnit;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDlg) {
          return AlertDialog(
            title: Text(_getDisplayName(p, lang)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: c,
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                              labelText: loc.t('quantity_label')),
                          autofocus: true,
                          onSubmitted: (_) => _submit(
                              p,
                              c.text,
                              gppController.text,
                              selectedProcess,
                              selectedUnit,
                              ctx,
                              shrinkageController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: InputDecoration(
                              isDense: true, labelText: loc.t('unit_short')),
                          items: CulinaryUnits.all
                              .map((u) => DropdownMenuItem(
                                    value: u.id,
                                    child: Text(loc.unitLabel(u.id)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setStateDlg(() => selectedUnit = v ?? 'g'),
                        ),
                      ),
                    ],
                  ),
                  if (CulinaryUnits.isCountable(selectedUnit)) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: gppController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: loc.t('g_pc'),
                        hintText: loc.t('hint_50'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(loc.t('cooking_process'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<CookingProcess?>(
                    value: selectedProcess,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      DropdownMenuItem(
                          value: null, child: Text(loc.t('no_process'))),
                      ...processes.map((proc) => DropdownMenuItem(
                            value: proc,
                            child: Text(
                                '${loc.cookingProcessLabel(proc)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
                          )),
                    ],
                    onChanged: (v) => setStateDlg(() {
                      selectedProcess = v;
                      if (v != null)
                        shrinkageController.text =
                            v.weightLossPercentage.toStringAsFixed(1);
                      else
                        shrinkageController.text = '';
                    }),
                  ),
                  if (selectedProcess != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: shrinkageController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('ttk_cook_loss'),
                        hintText: selectedProcess?.weightLossPercentage
                            .toStringAsFixed(1),
                        helperText: loc.t('ttk_cook_loss_override_hint'),
                      ),
                      onChanged: (_) => setStateDlg(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(loc.t('back'))),
              FilledButton(
                onPressed: () => _submit(p, c.text, gppController.text,
                    selectedProcess, selectedUnit, ctx, shrinkageController),
                child: Text(loc.t('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  String _productUnitToCulinary(String? u) {
    if (u == null || u.isEmpty) return 'g';
    final x = u.toLowerCase();
    if (x.contains('шт') || x.contains('pcs') || x.contains('штук'))
      return 'pcs';
    if (x.contains('кг') || x == 'kg') return 'kg';
    if (x.contains('л') || x == 'l') return 'l';
    if (x.contains('мл') || x == 'ml') return 'ml';
    return 'g';
  }

  void _submit(
      Product p,
      String val,
      String gppStr,
      CookingProcess? proc,
      String unit,
      BuildContext ctx,
      TextEditingController shrinkageController) {
    final v = double.tryParse(val.replaceFirst(',', '.')) ?? 0;
    // Процент отхода не спрашиваем при добавлении — вносится в таблице в колонке «Отход %». Подставляем значение по умолчанию из продукта или 0.
    final waste = (p.primaryWastePct ?? 0).clamp(0.0, 99.9);
    double? gpp;
    if (CulinaryUnits.isCountable(unit)) {
      gpp = double.tryParse(gppStr) ?? 50;
      if (gpp <= 0) gpp = 50;
    }
    double? cookLossOverride;
    if (proc != null) {
      final entered =
          double.tryParse(shrinkageController.text.replaceFirst(',', '.'));
      if (entered != null &&
          (entered - proc.weightLossPercentage).abs() > 0.01) {
        cookLossOverride = entered.clamp(0.0, 99.9);
      }
    }
    Navigator.of(ctx).pop();
    if (v > 0)
      widget.onPick(p, v, proc, waste, unit, gpp,
          cookingLossPctOverride: cookLossOverride);
  }
}

class _TechCardPicker extends StatelessWidget {
  const _TechCardPicker({
    required this.techCards,
    required this.onPick,
    required this.ensureHydrated,
  });

  final List<TechCard> techCards;
  final void Function(
      TechCard t, double value, String unit, double? gramsPerPiece) onPick;
  final Future<TechCard> Function(TechCard t) ensureHydrated;

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (techCards.isEmpty) {
      return Center(
          child: Text(loc.t('ttk_no_other_pf'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: techCards.length,
      itemBuilder: (_, i) {
        final t = techCards[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _askWeight(context, t),
          child: ListTile(
            title: Text(t.getDisplayNameInLists(lang)),
            // В шалоу-загрузке ингредиенты/КБЖУ могут быть пустыми,
            // поэтому не показываем цифры, чтобы не зависеть от гидратации.
            subtitle: t.category.isNotEmpty ? Text(t.category) : null,
          ),
        );
      },
    );
  }

  Future<void> _askWeight(BuildContext context, TechCard t) async {
    // Гидратируем только выбранную ТТК (а не весь справочник), чтобы
    // убрать долгие подвисания при открытии/переходах.
    TechCard hydrated;
    try {
      hydrated = await ensureHydrated(t);
    } catch (_) {
      return;
    }
    final c = TextEditingController(text: '100');
    final gppController = TextEditingController(text: '50');
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    String selectedUnit = 'g';
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDlg) => AlertDialog(
          title: Text(hydrated.getDisplayNameInLists(lang)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: c,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          InputDecoration(labelText: loc.t('quantity_label')),
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: InputDecoration(
                          isDense: true, labelText: loc.t('unit_short')),
                      items: CulinaryUnits.all
                          .map((u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(loc.unitLabel(u.id)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setStateDlg(() => selectedUnit = v ?? 'g'),
                    ),
                  ),
                ],
              ),
              if (CulinaryUnits.isCountable(selectedUnit))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: gppController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: loc.t('g_pc'), hintText: loc.t('hint_50')),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc.t('back'))),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(c.text.replaceFirst(',', '.')) ?? 0;
                Navigator.of(ctx).pop();
                if (v > 0) {
                  double? gpp;
                  if (CulinaryUnits.isCountable(selectedUnit)) {
                    gpp = double.tryParse(gppController.text) ?? 50;
                    if (gpp <= 0) gpp = 50;
                  }
                  onPick(hydrated, v, selectedUnit, gpp);
                }
              },
              child: Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Полноэкранный просмотр фото с листанием и зумом
// ══════════════════════════════════════════════════════════════════════════════
class _PhotoViewerDialog extends StatefulWidget {
  final List<({String? url, Uint8List? bytes})> photos;
  final int initialIndex;

  const _PhotoViewerDialog({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<_PhotoViewerDialog> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;

    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: Stack(
        children: [
          // Листалка фото
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final p = widget.photos[i];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: p.url != null
                      ? (kIsWeb
                          ? Image.network(p.url!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white,
                                  size: 64))
                          : CachedNetworkImage(
                              imageUrl: p.url!,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white,
                                  size: 64)))
                      : p.bytes != null
                          ? Image.memory(p.bytes!, fit: BoxFit.contain)
                          : const SizedBox.shrink(),
                ),
              );
            },
          ),

          // Кнопка закрыть
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),

          // Счётчик фото (если больше 1)
          if (total > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Стрелка влево
                  if (_current > 0)
                    IconButton(
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.white, size: 36),
                      onPressed: () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut),
                    ),
                  // Индикаторы
                  ...List.generate(
                      total,
                      (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _current == i ? 12 : 8,
                            height: _current == i ? 12 : 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  _current == i ? Colors.white : Colors.white38,
                            ),
                          )),
                  // Стрелка вправо
                  if (_current < total - 1)
                    IconButton(
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.white, size: 36),
                      onPressed: () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Выбор цехов для ТТК:
//   [] = Скрыто (только шеф/су-шеф)
//   ['all'] = Все цеха
//   ['hot_kitchen', ...] = конкретные цеха
//
// Логика взаимоисключения:
//   - Выбрать "Все цеха" → снимает все конкретные
//   - Выбрать конкретный → снимает "Все цеха"
//   - Снять все конкретные → возвращается "Скрыто"
//   - "Скрыто" нельзя выбрать вручную — только если ничего не выбрано
// ══════════════════════════════════════════════════════════════════════════════
class _SectionPicker extends StatelessWidget {
  final List<String> selected;
  final Map<String, String> availableSections;
  final bool canEdit;
  final ValueChanged<List<String>> onChanged;
  final LocalizationService loc;
  final bool compact; // компактный режим для горизонтального layout

  const _SectionPicker({
    required this.selected,
    required this.availableSections,
    required this.canEdit,
    required this.onChanged,
    required this.loc,
    this.compact = false,
  });

  String get _displayLabel {
    if (selected.isEmpty) return loc.t('ttk_section_hidden_short');
    if (selected.contains('all')) return loc.t('ttk_section_all');
    if (selected.length == 1) {
      return availableSections[selected.first] ?? selected.first;
    }
    return loc.t('ttk_sections_count').replaceFirst('%s', '${selected.length}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!canEdit) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: loc.t('ttk_col_section'),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            Icon(
              selected.isEmpty ? Icons.visibility_off : Icons.store,
              size: 16,
              color: selected.isEmpty
                  ? theme.colorScheme.error.withValues(alpha: 0.7)
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _displayLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected.isEmpty
                      ? theme.colorScheme.error.withValues(alpha: 0.8)
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: loc.t('ttk_col_section'),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            Icon(
              selected.isEmpty ? Icons.visibility_off : Icons.store,
              size: 16,
              color: selected.isEmpty
                  ? theme.colorScheme.error.withValues(alpha: 0.7)
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _displayLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected.isEmpty
                      ? theme.colorScheme.error.withValues(alpha: 0.8)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<List<String>>(
      context: context,
      builder: (_) => _SectionPickerDialog(
        selected: List<String>.from(selected),
        availableSections: availableSections,
        loc: loc,
      ),
    ).then((result) {
      if (result != null) onChanged(result);
    });
  }
}

class _SectionPickerDialog extends StatefulWidget {
  final List<String> selected;
  final Map<String, String> availableSections;
  final LocalizationService loc;

  const _SectionPickerDialog({
    required this.selected,
    required this.availableSections,
    required this.loc,
  });

  @override
  State<_SectionPickerDialog> createState() => _SectionPickerDialogState();
}

class _SectionPickerDialogState extends State<_SectionPickerDialog> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
  }

  void _toggle(String code) {
    setState(() {
      if (code == 'all') {
        // Выбрать "Все цеха" — снимаем все конкретные
        if (_selected.contains('all')) {
          _selected = []; // снятие "Все" → Скрыто
        } else {
          _selected = ['all'];
        }
      } else {
        // Конкретный цех — снимаем 'all' если был
        _selected.remove('all');
        if (_selected.contains(code)) {
          _selected.remove(code);
          // Сняли последний конкретный → Скрыто (пустой список)
        } else {
          _selected.add(code);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    final isHidden = _selected.isEmpty;
    final isAll = _selected.contains('all');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.store, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Text(loc.t('ttk_section_select'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(
                loc.t('ttk_section_hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),

              // Статус "Скрыто"
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isHidden
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
                      : theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isHidden
                        ? theme.colorScheme.error.withValues(alpha: 0.4)
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.visibility_off,
                      size: 18,
                      color: isHidden
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isHidden
                          ? loc.t('ttk_section_hidden')
                          : loc.t('ttk_section_uncheck_hint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isHidden
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // Список цехов
              ...widget.availableSections.entries.map((e) => _CheckItem(
                    label: e.value,
                    checked: _selected.contains(e.key),
                    onTap: () => _toggle(e.key),
                    theme: theme,
                  )),

              const Divider(height: 20),

              // Все цеха
              _CheckItem(
                label: loc.t('ttk_section_all'),
                checked: isAll,
                onTap: () => _toggle('all'),
                theme: theme,
                icon: Icons.done_all,
                bold: true,
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(loc.t('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(loc.t('save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;
  final ThemeData theme;
  final IconData icon;
  final bool bold;

  const _CheckItem({
    required this.label,
    required this.checked,
    required this.onTap,
    required this.theme,
    this.icon = Icons.kitchen,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(4),
                color: checked ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: 2,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Icon(icon,
                size: 16,
                color: checked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: checked ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
