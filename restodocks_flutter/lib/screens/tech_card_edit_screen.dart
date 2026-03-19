import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
import '../utils/number_format_utils.dart';
import '../widgets/app_bar_home_button.dart';
import 'excel_style_ttk_table.dart';

/// Создание или редактирование ТТК. Ингредиенты — из номенклатуры или из других ТТК (ПФ).
///
/// Составление/редактирование карточек остаётся как реализовано (таблица, ингредиенты, технология).
/// Отображение для сотрудников (режим просмотра, !effectiveCanEdit) должно соответствовать референсу:
/// https://github.com/stasssercheff/shbb326 — kitchen/kitchen/ttk/Preps (ТТК ПФ), dish (карточки блюд), sv (су-вид).

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
              Text(loc.t('ttk_add_custom_category') ?? 'Свой вариант',
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
                Text(loc.t('ttk_manage_custom_categories') ?? 'Управление',
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
    _debounce = Timer(const Duration(milliseconds: 250), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerLow
        .withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
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
    _debounce = Timer(const Duration(milliseconds: 250), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerLow
        .withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
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
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
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
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// Редактируемая ячейка брутто (граммы). Тап по ячейке даёт фокус полю ввода.
class _EditableGrossCell extends StatefulWidget {
  const _EditableGrossCell({required this.grams, required this.onChanged});

  final double grams;
  final void Function(double? g) onChanged;

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
    _ctrl = TextEditingController(text: widget.grams.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _EditableGrossCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.grams != widget.grams &&
        _ctrl.text != widget.grams.toStringAsFixed(0)) {
      _ctrl.text = widget.grams.toStringAsFixed(0);
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
    _debounce = Timer(const Duration(milliseconds: 250), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerLow
        .withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
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
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerLow
        .withValues(alpha: 0.7);
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: fill,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
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
    _debounce = Timer(const Duration(milliseconds: 250), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLow
              .withValues(alpha: 0.7),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
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
    this.forceViewMode = false,
    this.department,
    this.forceHallView = false,
    this.initialCategory,
    this.initialSections,
    this.initialIsSemiFinished,
    this.initialTypeRevision,
    this.initialHeaderSignature,
    this.initialSourceRows,
  });

  /// Пусто для «новой», иначе id существующей ТТК.
  final String techCardId;

  /// Предзаполнение из ИИ (фото/Excel). Используется только при techCardId == 'new'.
  final TechCardRecognitionResult? initialFromAi;

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
  List<TechCard> _pickerTechCards = [];
  List<TechCard> _semiFinishedProducts = [];
  double _portionWeight =
      100; // вес порции (г), вносится в столбец «вес прц» в итого
  /// URL фото с сервера (для существующей ТТК)
  List<String> _photoUrls = [];

  /// Фото, выбранные для новой ТТК до первого сохранения (загружаем после create)
  List<Uint8List> _pendingPhotoBytes = [];
  bool _saving = false;

  Timer? _reconcileOpenCardTimer;
  TechCardsReconcileNotifier? _reconcileNotifier;
  int _lastReconcileNotifierVersion = 0;
  bool _reconciling = false;
  DateTime _lastReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isNew => widget.techCardId.isEmpty || widget.techCardId == 'new';

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
    return 'tech_card_edit_new';
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
      _ingredients.clear();
      for (final item in data['ingredients'] as List<dynamic>? ?? []) {
        try {
          _ingredients.add(
              TTIngredient.fromJson(Map<String, dynamic>.from(item as Map)));
        } catch (_) {}
      }
      _ensurePlaceholderRowAtEnd();
    });
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
          lower.contains('чай') ||
          lower.contains('какао') ||
          lower.contains('coffee') ||
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
              await productStore.loadNomenclatureForBranch(est.id, est.dataEstablishmentId!);
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
          () async {
            try {
              final tcSvc = context.read<TechCardServiceSupabase>();
              
              // Параллельная загрузка ТТК и кастомных категорий
              final futures = <Future>[];
              
              // ТТК
              late Future<List<TechCard>> allCardsFuture;
              if (est.isBranch) {
                allCardsFuture = Future.wait([
                  tcSvc.getTechCardsForEstablishment(est.dataEstablishmentId!),
                  tcSvc.getTechCardsForEstablishment(est.id),
                ]).then((results) => [...results[0], ...results[1]]);
              } else {
                allCardsFuture = tcSvc.getTechCardsForEstablishment(est.dataEstablishmentId);
              }
              futures.add(allCardsFuture);
              
              // Кастомные категории
              final customCategoriesFuture = Future.wait([
                tcSvc.getCustomCategories(est.isBranch ? est.id : est.dataEstablishmentId!, 'kitchen'),
                tcSvc.getCustomCategories(est.isBranch ? est.id : est.dataEstablishmentId!, 'bar'),
              ]);
              futures.add(customCategoriesFuture);
              
              final results = await Future.wait(futures);
              var tcs = results[0] as List<TechCard>;
              final customResults = results[1] as List;
              final customKitchen = customResults[0] as List<({String id, String name})>;
              final customBar = customResults[1] as List<({String id, String name})>;
              
              tcs = tcs.map(stripInvalidNestedPfSelfLinks).toList();
              // Гидратация цен только если нужно для расчётов вложенных ПФ
              final emp = context.read<AccountManagerSupabase>().currentEmployee;
              final needsCostCalculation = emp?.hasRole('owner') == true || 
                                          emp?.hasRole('executive_chef') == true || 
                                          emp?.hasRole('sous_chef') == true ||
                                          emp?.hasRole('manager') == true ||
                                          emp?.hasRole('general_manager') == true;
              if (needsCostCalculation) {
                tcs = await tcSvc.fillIngredientsForCardsBulk(tcs);
                final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
                if (estPriceId != null && estPriceId.isNotEmpty) {
                  tcs = TechCardCostHydrator.hydrate(tcs, productStore, estPriceId);
                }
              }
              if (!mounted) return;
              setState(() {
                _pickerTechCards = _isNew
                    ? tcs
                    : tcs.where((t) => t.id != widget.techCardId).toList();
                _semiFinishedProducts =
                    tcs.where((t) => t.isSemiFinished).toList();
                _customCategoriesKitchen = customKitchen;
                _customCategoriesBar = customBar;
              });
              // Если мы уже загрузили текущую ТТК — досвязываем вложенные ПФ и пересчитываем цену.
              if (_techCard != null) {
                final pfCards = tcs.where((t) => t.isSemiFinished).toList();
                final fixed =
                    _attachMissingPfSourceTechCardId(_techCard!, pfCards);
                final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
                final hydrated = (estPriceId != null && estPriceId.isNotEmpty)
                    ? TechCardCostHydrator.hydrate([fixed, ...tcs], productStore, estPriceId)
                    : [fixed, ...tcs];
                final hydratedTc = hydrated.firstWhere(
                    (item) => item.id == fixed.id,
                    orElse: () => fixed);
                setState(() {
                  _techCard = hydratedTc;
                  _ingredients
                    ..clear()
                    ..addAll(hydratedTc.ingredients);
                  _ensurePlaceholderRowAtEnd();
                });
              }
              _ensureTechCardTranslations(tcs);
            } catch (_) {}
          }();
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
                _categoryOptions.contains(widget.initialCategory)) {
              _selectedCategory = widget.initialCategory!;
            } else if (ai.dishName != null && ai.dishName!.isNotEmpty) {
              final cat = _inferCategory(ai.dishName!);
              if (_categoryOptions.contains(cat)) _selectedCategory = cat;
            }
            if (widget.initialSections != null &&
                widget.initialSections!.isNotEmpty) {
              _selectedSections = List<String>.from(widget.initialSections!);
            } else if (widget.initialSections != null &&
                widget.initialSections!.isEmpty) {
              _selectedSections = [];
            }
            _ingredients.clear();
            for (final line in ai.ingredients) {
              if (line.productName.trim().isEmpty) continue;
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
          if (mounted) await restoreDraftNow();
        }
        return;
      }
      final svc = context.read<TechCardServiceSupabase>();
      var tc = await svc.getTechCardById(widget.techCardId);
      if (tc != null) {
        // Иногда embed возвращает пустые ингредиенты — догружаем
        if (tc.ingredients.isEmpty) {
          final filled = await svc.fillIngredientsForCardsBulk([tc]);
          if (filled.isNotEmpty) tc = filled.first;
        }
        var working = stripInvalidNestedPfSelfLinks(tc);
        if (!identical(working, tc)) {
          try {
            await svc.saveTechCard(working, skipHistory: true);
          } catch (_) {}
        }
        if (loadedTechCards.isNotEmpty) {
          final pfCards = loadedTechCards.where((t) => t.isSemiFinished).toList();
          working = _attachMissingPfSourceTechCardId(working, pfCards);
          final currentTechCardId = working.id;
          final productStore = context.read<ProductStoreSupabase>();
          final est = context.read<AccountManagerSupabase>().establishment;
          final estPriceId = est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
          final hydrated = (estPriceId != null && estPriceId.isNotEmpty)
              ? TechCardCostHydrator.hydrate([working, ...loadedTechCards], productStore, estPriceId)
              : [working, ...loadedTechCards];
          working = hydrated.firstWhere((item) => item.id == currentTechCardId,
              orElse: () => working);
        }
        tc = working;
      }
      if (!mounted) return;
      // Откладываем тяжёлый setState на следующий кадр, чтобы не блокировать UI при большом числе ингредиентов
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() {
          _techCard = tc;
          _loading = false;
          if (tc != null) {
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
              ..addAll(tc.ingredients);
            _ensurePlaceholderRowAtEnd();
          }
        });
        // Если перевод технологии ещё не сохранён — запросить через DeepL
        if (tc != null) _translateTechnologyIfNeeded(tc);
        // Дополнить цены из номенклатуры (если productId есть, cost=0)
        if (tc != null && est != null)
          _enrichPricesFromNomenclature(
              est.isBranch ? est.id : est.dataEstablishmentId!);
        if (mounted) await restoreDraftNow();
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  /// Дополняет цены ингредиентов из номенклатуры (по productId или по названию).
  /// Нормализация: убираем пунктуацию, множественные пробелы — для сопоставления у всех пользователей.
  void _enrichPricesFromNomenclature(String establishmentId) {
    final store = context.read<ProductStoreSupabase>();
    final products = store.getNomenclatureProducts(establishmentId);
    final norm = (String s) => s
        .replaceAll(RegExp(r'[^a-zA-Zа-яёЁ0-9\s]'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var changed = false;
    final updated = <int, TTIngredient>{};
    for (var i = 0; i < _ingredients.length; i++) {
      final ing = _ingredients[i];
      if (ing.cost > 0) continue;
      String? pid = ing.productId;
      double? price;
      if (pid != null) {
        final ep = store.getEstablishmentPrice(pid, establishmentId);
        price = ep?.$1;
      }
      if ((price == null || price <= 0) && ing.productName.trim().isNotEmpty) {
        final nameNorm = norm(ing.productName);
        for (final p in products) {
          if (norm(p.name) == nameNorm ||
              p.names?.values.any((n) => norm(n) == nameNorm) == true) {
            pid = p.id;
            price = store.getEstablishmentPrice(p.id, establishmentId)?.$1;
            break;
          }
        }
      }
      if (price == null || price <= 0) continue;
      final newCost = (price / 1000) * ing.grossWeight;
      updated[i] = ing.copyWith(
        productId: pid ?? ing.productId,
        cost: newCost,
        pricePerKg: price,
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

  void _scheduleDraftSave() => scheduleSave();

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
              title: Text('Уточните ПФ для: $ingredientName'),
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
                                          Text(loc.t('ttk_view') ?? 'Состав'),
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
                  child: Text(loc.t('cancel') ?? 'Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final picked =
                        candidates.where((c) => c.id == selectedId).firstOrNull;
                    Navigator.of(ctx).pop(picked);
                  },
                  child: Text(loc.t('apply') ?? 'Применить'),
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
        final items = tc.ingredients
            .where((i) => i.productName.trim().isNotEmpty)
            .toList();
        return AlertDialog(
          title: Text(tc.getDisplayNameInLists(lang)),
          content: SizedBox(
            width: 620,
            height: 420,
            child: items.isEmpty
                ? const Center(child: Text('Состав пуст'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, idx) {
                      final ing = items[idx];
                      final name = ing.sourceTechCardId != null &&
                              ing.sourceTechCardId!.isNotEmpty
                          ? (ing.sourceTechCardName ?? ing.productName)
                          : ing.productName;
                      final w = ing.outputWeight > 0
                          ? ing.outputWeight
                          : ing.netWeight;
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Выход: ${w.toStringAsFixed(0)} г'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Ок')),
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
      setState(() {});
      _scheduleDraftSave();
    });
    _technologyController.addListener(() {
      setState(() {});
      _scheduleDraftSave();
    });
    _descriptionForHallController.addListener(_scheduleDraftSave);
    _compositionForHallController.addListener(_scheduleDraftSave);
    _sellingPriceController.addListener(_scheduleDraftSave);
    // Сразу 2 строки для внесения продуктов; при заполнении последней добавится следующая
    _ingredients.add(TTIngredient.emptyPlaceholder());
    _ingredients.add(TTIngredient.emptyPlaceholder());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();

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

  @override
  void dispose() {
    _reconcileOpenCardTimer?.cancel();
    if (_reconcileNotifier != null) {
      _reconcileNotifier!.removeListener(_handleTechCardsReconcileSignal);
    }
    _nameController.dispose();
    _technologyController.dispose();
    _descriptionForHallController.dispose();
    _compositionForHallController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  void _handleTechCardsReconcileSignal() {
    if (!mounted) return;
    final notifier =
        _reconcileNotifier ?? context.read<TechCardsReconcileNotifier>();
    if (notifier.version == _lastReconcileNotifierVersion) return;
    _lastReconcileNotifierVersion = notifier.version;
    _tryReconcileOpenCard(force: true);
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
      final hydrated = (estPriceId != null && estPriceId.isNotEmpty)
          ? TechCardCostHydrator.hydrate([fixed, ...all], productStore, estPriceId)
          : [fixed, ...all];
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

    // Найти исходный язык технологии (первый непустой ключ в technologyLocalized)
    final techMap = tc.technologyLocalized ?? {};
    final sourceLang = techMap.entries
        .where((e) => e.value.trim().isNotEmpty && e.key != targetLang)
        .map((e) => e.key)
        .firstOrNull;
    final sourceText = sourceLang != null ? techMap[sourceLang]! : '';

    // Уже есть перевод на целевой язык — ничего не делать
    final existing = techMap[targetLang]?.trim() ?? '';
    if (existing.isNotEmpty) return;

    // Нет исходного текста — нечего переводить
    if (sourceText.trim().isEmpty || sourceLang == null) return;
    if (sourceLang == targetLang) return;

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
        sourceLanguage: sourceLang,
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

  Future<void> _showAddCustomCategoryDialog() async {
    final loc = context.read<LocalizationService>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('ttk_add_custom_category') ?? 'Свой вариант'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: loc.t('ttk_custom_category_hint') ??
                  'Название своей категории',
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc.t('back') ?? 'Назад')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(loc.t('save') ?? 'Сохранить'),
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
            content: Text(loc.t('ttk_custom_category_save_error') ??
                'Не удалось сохранить. Проверьте, что в Supabase применена миграция tech_card_custom_categories.'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('ttk_no_custom_categories') ?? 'Нет своих категорий')));
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
            Text(
                loc.t('ttk_manage_custom_categories') ??
                    'Управление своими категориями',
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
                              content: Text((loc
                                          .t('ttk_custom_category_in_use') ??
                                      'Используется в %s ТТК — удалить нельзя')
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
            content: Text(loc.t('ttk_saving') ?? 'Сохранение...'),
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
        // Филиал создаёт ТТК в своём заведении (доп от филиала); головное — в своём.
        final created = await svc.createTechCard(
          dishName: name,
          category: category,
          sections: _selectedSections,
          isSemiFinished: _isSemiFinished,
          establishmentId: est.isBranch ? est.id : est.dataEstablishmentId,
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
        // Обучение: при изменении — ищем corrected в rows, сохраняем позиции (название + колонки)
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
          );
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
          );
        }
        // Переводим название и технологию фоново. Используем updated (с фото и ингредиентами),
        // иначе перезапись через created удалит photoUrls и ingredients.
        final savedForTranslation = updated;
        final techText = _technologyController.text.trim();
        final fieldsToTranslate = <String, String>{'dish_name': name};
        if (techText.isNotEmpty) fieldsToTranslate['technology'] = techText;
        translationManager
            .handleEntitySave(
          entityType: TranslationEntityType.techCard,
          entityId: created.id,
          textFields: fieldsToTranslate,
          sourceLanguage: curLang,
          userId: emp.id,
        )
            .then((_) async {
          final otherLang = curLang == 'ru' ? 'en' : 'ru';
          final translatedName = await translationManager.getLocalizedText(
            entityType: TranslationEntityType.techCard,
            entityId: created.id,
            fieldName: 'dish_name',
            sourceText: name,
            sourceLanguage: curLang,
            targetLanguage: otherLang,
          );
          final nameMap = Map<String, String>.from(
              savedForTranslation.dishNameLocalized ?? {});
          nameMap[curLang] = name;
          if (translatedName != name) nameMap[otherLang] = translatedName;
          final newTechMap = Map<String, String>.from(techMap);
          if (techText.isNotEmpty) {
            final translatedTech = await translationManager.getLocalizedText(
              entityType: TranslationEntityType.techCard,
              entityId: created.id,
              fieldName: 'technology',
              sourceText: techText,
              sourceLanguage: curLang,
              targetLanguage: otherLang,
            );
            if (translatedTech != techText)
              newTechMap[otherLang] = translatedTech;
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
          if (AiServiceSupabase.lastLearningSuccess != null) {
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
              dishName: name,
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
            context.pop(true); // Новая карточка сохранена — список обновит в фоне
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
        await svc.saveTechCard(updated,
            changedByEmployeeId: emp.id, changedByName: emp.fullName);
        // Переводим название и технологию фоново
        final techText = _technologyController.text.trim();
        final fieldsToTranslate = <String, String>{'dish_name': name};
        if (techText.isNotEmpty) fieldsToTranslate['technology'] = techText;
        translationManager
            .handleEntitySave(
          entityType: TranslationEntityType.techCard,
          entityId: tc.id,
          textFields: fieldsToTranslate,
          sourceLanguage: curLang,
          userId: emp.id,
        )
            .then((_) async {
          final otherLang = curLang == 'ru' ? 'en' : 'ru';
          final translatedName = await translationManager.getLocalizedText(
            entityType: TranslationEntityType.techCard,
            entityId: tc.id,
            fieldName: 'dish_name',
            sourceText: name,
            sourceLanguage: curLang,
            targetLanguage: otherLang,
          );
          final nameMap =
              Map<String, String>.from(updated.dishNameLocalized ?? {});
          nameMap[curLang] = name;
          if (translatedName != name) nameMap[otherLang] = translatedName;
          // Обновляем technologyLocalized
          final newTechMap =
              Map<String, String>.from(updated.technologyLocalized ?? techMap);
          if (techText.isNotEmpty) {
            final translatedTech = await translationManager.getLocalizedText(
              entityType: TranslationEntityType.techCard,
              entityId: tc.id,
              fieldName: 'technology',
              sourceText: techText,
              sourceLanguage: curLang,
              targetLanguage: otherLang,
            );
            if (translatedTech != techText)
              newTechMap[otherLang] = translatedTech;
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
          AppToastService.show(
              context.read<LocalizationService>().t('save') + ' ✓');
          context.pop(true); // Список обновит данные в фоне, без полного перезагруза
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
              ? Text(loc.t('ttk_history_empty') ?? 'Нет записей',
                  style: Theme.of(ctx).textTheme.bodyMedium)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final dateStr =
                        '${e.changedAt.day.toString().padLeft(2, '0')}.${e.changedAt.month.toString().padLeft(2, '0')}.${e.changedAt.year} ${e.changedAt.hour.toString().padLeft(2, '0')}:${e.changedAt.minute.toString().padLeft(2, '0')}';
                    final who = e.changedByName ??
                        (loc.t('ttk_history_unknown') ?? '—');
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('error_with_message').replaceAll('%s', e.toString()))));
    }
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
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    await productStore.loadProducts();
    await productStore.loadNomenclature(est.dataEstablishmentId);

    if (!mounted) return;
    final nomenclatureProducts =
        productStore.getNomenclatureProducts(est.dataEstablishmentId);
    final allProducts = productStore.allProducts;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(replaceIndex != null
                  ? loc.t('change_ingredient')
                  : loc.t('add_ingredient')),
              bottom: TabBar(
                tabs: [
                  Tab(text: loc.t('nomenclature')),
                  Tab(text: loc.t('all_products')),
                  Tab(text: loc.t('semi_finished')),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _ProductPicker(
                  products: nomenclatureProducts,
                  onPick: (p, w, proc, waste, unit, gpp,
                          {cookingLossPctOverride}) =>
                      _addProductIngredient(p, w, proc, waste, unit, gpp,
                          replaceIndex: replaceIndex,
                          cookingLossPctOverride: cookingLossPctOverride),
                ),
                _ProductPicker(
                  products: allProducts,
                  onPick: (p, w, proc, waste, unit, gpp,
                          {cookingLossPctOverride}) =>
                      _addProductIngredient(p, w, proc, waste, unit, gpp,
                          replaceIndex: replaceIndex,
                          cookingLossPctOverride: cookingLossPctOverride),
                ),
                _TechCardPicker(
                    techCards: _pickerTechCards,
                    onPick: (t, w, unit, gpp) => _addTechCardIngredient(
                        t, w, unit, gpp,
                        replaceIndex: replaceIndex)),
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
                                  child: Text(
                                      CulinaryUnits.displayName(u.id, lang))))
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
                                '${proc.getLocalizedName(lang)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
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
    if (lang == 'ru') return;
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

  /// Подсказка ИИ: процент отхода по названию продукта (для ручной строки).
  Future<void> _suggestWasteForRow(int i) async {
    if (i < 0 || i >= _ingredients.length) return;
    final ing = _ingredients[i];
    if (ing.productId != null) return;
    final name = ing.productName.trim();
    if (name.isEmpty) return;
    final ai = context.read<AiService>();
    final result = await ai.recognizeProduct(name);
    if (!mounted || result?.suggestedWastePct == null) return;
    final waste = result!.suggestedWastePct!.clamp(0.0, 99.9);
    final net = ing.grossWeight * (1.0 - waste / 100.0);
    setState(() => _ingredients[i] = ing.copyWith(
        primaryWastePct: waste, netWeight: net, isNetWeightManual: false));
  }

  /// Блок фото: ПФ — сетка до 10, блюдо — 1 фото. Под технологией.
  /// Ширина как у блока "Технология" (max 1000px).
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

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: screenWidth > 1000 ? 1000 : screenWidth,
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
                child: Text(loc.t('hall_menu_info') ?? 'Для меню зала',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.t('description_for_hall') ?? 'Описание для гостей',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    effectiveCanEdit
                        ? TextField(
                            controller: _descriptionForHallController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: loc.t('description_for_hall_hint') ??
                                  'Краткое описание блюда для гостей',
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
                    Text(loc.t('composition_for_hall') ?? 'Состав для гостей',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    effectiveCanEdit
                        ? TextField(
                            controller: _compositionForHallController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: loc.t('composition_for_hall_hint') ??
                                  'Состав: ингредиенты для меню (например: курица, рис, соус)',
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
                      Text(loc.t('selling_price') ?? 'Продажная цена',
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
                      Text(loc.t('selling_price') ?? 'Продажная цена',
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
    final isMobile = MediaQuery.of(context).size.width < 600;
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
    final employee = context.watch<AccountManagerSupabase>().currentEmployee;
    final isCook = employee?.department == 'kitchen' &&
        !effectiveCanEdit; // Повар - кухня без прав редактирования

    // Определяем, является ли устройство мобильным
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isNew && !effectiveCanEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement('/tech-cards');
      });
      return Scaffold(
        appBar: AppBar(
            leading: appBarBackButton(context),
            title: Text(loc.t('tech_cards'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
            leading: appBarBackButton(context),
            title:
                Text(_isNew ? loc.t('create_tech_card') : loc.t('tech_cards'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
            leading: appBarBackButton(context),
            title:
                Text(_isNew ? loc.t('create_tech_card') : loc.t('tech_cards'))),
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
          title:
              Text(_techCard!.getDisplayNameInLists(loc.currentLanguageCode)),
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
                Text(loc.t('description_for_hall') ?? 'Описание',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (comp.isNotEmpty) ...[
                Text(loc.t('composition_for_hall') ?? 'Состав',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(comp, style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 16),
              ],
              if (sellingPrice != null && sellingPrice > 0) ...[
                Text(loc.t('selling_price') ?? 'Цена',
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
                    loc.t('hall_info_empty') ??
                        'Описание и состав для зала не заполнены в ТТК.',
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
        title: Text(_isNew
            ? loc.t('create_tech_card')
            : (_techCard?.getDisplayNameInLists(loc.currentLanguageCode) ??
                loc.t('tech_cards'))),
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
          // Кнопка экспорта текущей ТТК
          if (!_isNew && _techCard != null)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () async {
                try {
                  await ExcelExportService().exportSingleTechCard(_techCard!);
                  if (mounted) {
                    final loc = context.read<LocalizationService>();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(loc
                              .t('ttk_exported')
                              .replaceFirst('%s', _techCard!.dishName))),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final loc = context.read<LocalizationService>();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(loc
                              .t('ttk_export_error')
                              .replaceFirst('%s', '$e'))),
                    );
                  }
                }
              },
              tooltip:
                  context.read<LocalizationService>().t('ttk_export_excel'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 500;
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Шапка: название, категория, тип — на узком экране колонкой, на широком строкой
                      if (narrow) ...[
                        TextField(
                          controller: _nameController,
                          readOnly: !effectiveCanEdit,
                          style: TextStyle(fontSize: isMobile ? 12 : 14),
                          decoration: InputDecoration(
                            labelText: loc.t('ttk_name'),
                            isDense: true,
                            filled: false,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CategoryPickerField(
                          selectedCategory:
                              _categoryOptions.contains(_selectedCategory)
                                  ? _selectedCategory
                                  : 'misc',
                          categoryOptions: _categoryDepartment == 'bar'
                              ? _barCategoryOptions
                              : _kitchenCategoryOptions,
                          customCategories: _customCategories,
                          categoryLabel: (c) =>
                              _categoryLabel(c, loc.currentLanguageCode),
                          canEdit: effectiveCanEdit,
                          onCategorySelected: (v) {
                            setState(() => _selectedCategory = v);
                            _scheduleDraftSave();
                          },
                          onAddCustom: _showAddCustomCategoryDialog,
                          onRefreshCustom: _refreshCustomCategories,
                          onManageCustom: _showManageCustomCategoriesDialog,
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
                                    labelText: loc.t('tt_type_hint'),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))),
                                items: [
                                  DropdownMenuItem(
                                      value: true,
                                      child: Row(children: [
                                        const Icon(Icons.inventory_2, size: 20),
                                        const SizedBox(width: 8),
                                        Text(loc.t('tt_type_pf'))
                                      ])),
                                  DropdownMenuItem(
                                      value: false,
                                      child: Row(children: [
                                        const Icon(Icons.restaurant, size: 20),
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
                                      final sum = _ingredients.fold<double>(
                                          0, (s, i) => s + i.outputWeight);
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
                                      borderRadius: BorderRadius.circular(8)),
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
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1),
                                  ],
                                ),
                              ),
                      ] else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 320,
                                height: 56,
                                child: TextField(
                                  controller: _nameController,
                                  readOnly: !effectiveCanEdit,
                                  style: TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: loc.t('ttk_name'),
                                    isDense: true,
                                    filled: false,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 180,
                                child: _CategoryPickerField(
                                  selectedCategory: _categoryOptions
                                          .contains(_selectedCategory)
                                      ? _selectedCategory
                                      : 'misc',
                                  categoryOptions: _categoryDepartment == 'bar'
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
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 180,
                                child: _SectionPicker(
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
                                  compact: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minWidth: 160, maxWidth: 220),
                                child: SizedBox(
                                  height: 56,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: effectiveCanEdit
                                        ? Tooltip(
                                            message: loc.t('tt_type_hint'),
                                            child: SegmentedButton<bool>(
                                              style: SegmentedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                minimumSize: const Size(80, 44),
                                              ).copyWith(
                                                shape: WidgetStateProperty.all(
                                                    const StadiumBorder()),
                                              ),
                                              expandedInsets:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              segments: [
                                                ButtonSegment(
                                                  value: true,
                                                  label: Text(
                                                      loc.t('tt_type_pf'),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  icon: const Icon(
                                                      Icons.inventory_2,
                                                      size: 16),
                                                ),
                                                ButtonSegment(
                                                  value: false,
                                                  label: Text(
                                                      loc.t('tt_type_dish'),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  icon: const Icon(
                                                      Icons.restaurant,
                                                      size: 16),
                                                ),
                                              ],
                                              selected: {_isSemiFinished},
                                              onSelectionChanged: (v) {
                                                setState(() {
                                                  final toPf = v.first;
                                                  _isSemiFinished = toPf;
                                                  _typeManuallyChanged = true;
                                                  if (toPf) {
                                                    _portionWeight =
                                                        100; // ТТК ПФ: вес порции по умолчанию 100
                                                  } else {
                                                    final sum = _ingredients
                                                        .fold<double>(
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
                                              showSelectedIcon: false,
                                            ),
                                          )
                                        : InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: loc.t('tt_type_hint'),
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 14),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
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
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(loc.t('ttk_composition'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      // Таблица ТТК на странице: без «окна», при росте числа продуктов страница скроллится, технология остаётся ниже
                      Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 0,
                                minHeight: 220,
                              ),
                              child: effectiveCanEdit
                                  ? ExcelStyleTtkTable(
                                      loc: loc,
                                      dishName: _nameController.text,
                                      isSemiFinished: _isSemiFinished,
                                      ingredients: _ingredients,
                                      canEdit: effectiveCanEdit,
                                      dishNameController: _nameController,
                                      technologyController:
                                          _technologyController,
                                      productStore:
                                          context.read<ProductStoreSupabase>(),
                                      establishmentId: (() {
                                        final est = context
                                            .read<AccountManagerSupabase>()
                                            .establishment;
                                        return est != null && est.isBranch
                                            ? est.id
                                            : (est?.dataEstablishmentId ?? '');
                                      })(),
                                      semiFinishedProducts:
                                          _semiFinishedProducts,
                                      isCook: isCook,
                                      weightPerPortion: _portionWeight,
                                      onWeightPerPortionChanged: (v) {
                                        setState(() => _portionWeight = v);
                                        _scheduleDraftSave();
                                      },
                                      onAdd: _showAddIngredient,
                                      onUpdate: (i, ing) {
                                        setState(() {
                                          if (_ingredients.isEmpty && i == 0) {
                                            _ingredients.add(ing);
                                            if (ing.hasData) {
                                              _ingredients[0] =
                                                  ing.isPlaceholder
                                                      ? ing.withRealId()
                                                      : ing;
                                            }
                                            _ensurePlaceholderRowAtEnd();
                                            return;
                                          }
                                          if (i >= _ingredients.length) return;
                                          _ingredients[i] =
                                              ing.isPlaceholder && ing.hasData
                                                  ? ing.withRealId()
                                                  : ing;
                                          _ensurePlaceholderRowAtEnd();
                                        });
                                        _scheduleDraftSave();
                                      },
                                      onRemove: _removeIngredient,
                                      onSuggestWaste: _suggestWasteForRow,
                                      hideTechnologyBlock: true,
                                      onTapPfIngredient: (id) => context
                                          .push('/tech-cards/$id'),
                                    )
                                  : ConstrainedBox(
                                      constraints: const BoxConstraints(
                                          minWidth:
                                              1145), // как в режиме создания
                                      child: _TtkCookTable(
                                        loc: loc,
                                        dishName: _nameController.text,
                                        ingredients: _ingredients
                                            .where((i) =>
                                                !i.isPlaceholder || i.hasData)
                                            .toList(),
                                        technology: _technologyController.text,
                                        weightPerPortion: _portionWeight,
                                        hideTechnologyInTable: true,
                                        productStore: context
                                            .read<ProductStoreSupabase>(),
                                        onTapPfIngredient: (id) => context
                                            .push('/tech-cards/$id?view=1'),
                                        onIngredientsChanged: (list) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            setState(() {
                                              _ingredients.clear();
                                              _ingredients.addAll(list);
                                              _ensurePlaceholderRowAtEnd();
                                            });
                                            _scheduleDraftSave();
                                          });
                                        },
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // Кнопка «Подстроить % отхода под целевой выход» — отдельно под таблицей, не на панели, компактная
                      Builder(
                        builder: (context) {
                          final totalOutput = _ingredients
                              .where((i) => i.productName.trim().isNotEmpty)
                              .fold<double>(0, (s, i) => s + i.outputWeight);
                          final showAdjust = effectiveCanEdit &&
                              _portionWeight > 0 &&
                              totalOutput > 0 &&
                              (totalOutput - _portionWeight).abs() > 1;
                          if (!showAdjust) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                        loc.t('ttk_adjust_waste_title') ??
                                            'Подстроить отход'),
                                    content: Text(
                                      (loc.t('ttk_adjust_waste_confirm') ??
                                              'Подстроить процент отхода у всех ингредиентов, чтобы итоговый выход был %s г? Текущая сумма выходов: %s г.')
                                          .replaceFirst('%s',
                                              _portionWeight.toStringAsFixed(0))
                                          .replaceFirst('%s',
                                              totalOutput.toStringAsFixed(0)),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text(
                                              MaterialLocalizations.of(ctx)
                                                  .cancelButtonLabel)),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: Text(loc.t('ok') ?? 'Да')),
                                    ],
                                  ),
                                );
                                if (ok == true && mounted)
                                  _adjustWasteToMatchOutput(_portionWeight);
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 6),
                                  Text(
                                      loc.t('ttk_adjust_waste_to_output') ??
                                          'Подстроить % отхода под целевой выход',
                                      style: const TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      // Блок технологии сразу под таблицей, на странице (без ограничения по высоте «окном»)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width > 1000
                              ? 1000
                              : MediaQuery.of(context).size.width,
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.outline),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    border: const Border(
                                        bottom: BorderSide(
                                            color: Colors.grey, width: 1)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(loc.t('ttk_technology'),
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold)),
                                      if (_technologyTranslating) ...[
                                        const SizedBox(width: 8),
                                        const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                        const SizedBox(width: 6),
                                        Text(loc.t('loading'),
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                ),
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: effectiveCanEdit
                                      ? TextField(
                                          controller: _technologyController,
                                          maxLines: null,
                                          minLines: 2,
                                          style: const TextStyle(fontSize: 13),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            filled: false,
                                            hintText: loc.t('ttk_technology'),
                                          ),
                                        )
                                      : Text(
                                          _technologyController.text.isEmpty
                                              ? '—'
                                              : _technologyController.text,
                                          style: const TextStyle(
                                              fontSize: 13, height: 1.4),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // КБЖУ и аллергены (только для блюда)
                      if (!_isSemiFinished)
                        Builder(
                          builder: (ctx) {
                            final totalCal = _ingredients.fold<double>(
                                0, (s, i) => s + i.finalCalories);
                            final totalProt = _ingredients.fold<double>(
                                0, (s, i) => s + i.finalProtein);
                            final totalFatVal = _ingredients.fold<double>(
                                0, (s, i) => s + i.finalFat);
                            final totalCarbVal = _ingredients.fold<double>(
                                0, (s, i) => s + i.finalCarbs);
                            if (totalCal == 0 &&
                                totalProt == 0 &&
                                totalFatVal == 0 &&
                                totalCarbVal == 0)
                              return const SizedBox.shrink();
                            final store = context.read<ProductStoreSupabase>();
                            final allergens = <String>[];
                            for (final ing in _ingredients
                                .where((i) => i.productId != null)) {
                              final p = store.findProductForIngredient(
                                  ing.productId, ing.productName);
                              if (p?.containsGluten == true &&
                                  !allergens.contains('глютен'))
                                allergens.add('глютен');
                              if (p?.containsLactose == true &&
                                  !allergens.contains('лактоза'))
                                allergens.add('лактоза');
                            }
                            final allergenStr = allergens.isEmpty
                                ? (loc.currentLanguageCode == 'ru'
                                    ? 'нет'
                                    : 'none')
                                : allergens.join(', ');
                            return Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.3)),
                              ),
                              child: Text(
                                loc
                                    .t('kbju_allergens_in_dish')
                                    .replaceFirst(
                                        '%s', totalCal.round().toString())
                                    .replaceFirst(
                                        '%s', totalProt.toStringAsFixed(1))
                                    .replaceFirst(
                                        '%s', totalFatVal.toStringAsFixed(1))
                                    .replaceFirst(
                                        '%s', totalCarbVal.toStringAsFixed(1))
                                    .replaceFirst('%s', allergenStr),
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          },
                        ),
                      // Блок фото: ПФ — сетка до 10, блюдо — 1 фото
                      _buildPhotoSection(loc, effectiveCanEdit),
                      // Описание и состав для зала (только для блюд)
                      if (!_isSemiFinished)
                        _buildHallFieldsSection(loc, effectiveCanEdit),
                      if (effectiveCanEdit)
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    FilledButton(
                                      onPressed: _saving ? null : _save,
                                      child: _saving
                                          ? SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary))
                                          : Text(loc.t('save')),
                                      style: FilledButton.styleFrom(
                                          minimumSize: const Size(120, 48),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 14)),
                                    ),
                                    const SizedBox(width: 16),
                                    TextButton.icon(
                                      icon: Icon(Icons.clear_all,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                      label: Text(loc.t('clear_ttk_form')),
                                      onPressed: () =>
                                          _confirmClearForm(context, loc),
                                      style: TextButton.styleFrom(
                                          minimumSize: const Size(100, 48),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16)),
                                    ),
                                    if (!_isNew) ...[
                                      const SizedBox(width: 16),
                                      TextButton.icon(
                                        icon: Icon(Icons.delete_outline,
                                            size: 20,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error),
                                        label: Text(loc.t('delete_tech_card'),
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error)),
                                        onPressed: () =>
                                            _confirmDelete(context, loc),
                                        style: TextButton.styleFrom(
                                            minimumSize: const Size(120, 48),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16)),
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
                                    label: Text(loc.t('ttk_history'),
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)),
                                    onPressed: () =>
                                        _showTechCardHistory(context),
                                    style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 0)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (!_isNew && !effectiveCanEdit)
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            child: TextButton.icon(
                              icon: Icon(Icons.history,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                              label: Text(loc.t('ttk_history'),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                              onPressed: () => _showTechCardHistory(context),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0)),
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
    );
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
    final product = widget.productStore
        .findProductForIngredient(ing.productId, ing.productName);
    if (product != null)
      return ing.sourceTechCardName ?? product.getLocalizedName(lang);
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

    final hasDeleteCol = widget.effectiveCanEdit;
    // Порядок колонок как в образце. Ширины подобраны так, чтобы вся строка с полями ввода помещалась на экране без горизонтальной прокрутки.
    const colType = 64.0; // Тип ТТК
    const colName = 100.0; // Наименование
    const colProduct = 120.0;
    const colGross = 70.0; // Брутто г. (как столбец Цена)
    const colWaste = 64.0; // Отход %
    const colNet = 70.0; // Нетто г.
    const colMethod = 100.0; // Способ
    const colShrink = 64.0; // Ужарка %
    const colOutput = 70.0; // Выход г. (как столбец Цена)
    const colCost = 82.0; // Стоимость
    const colPriceKg = 88.0; // Цена за 1 кг/шт
    const colTech = 180.0; // Технология
    const colDel = 44.0;
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(colType),
      1: const FixedColumnWidth(colName),
      2: const FixedColumnWidth(colProduct),
      3: const FixedColumnWidth(colGross),
      4: const FixedColumnWidth(colWaste),
      5: const FixedColumnWidth(colNet),
      6: const FixedColumnWidth(colMethod),
      7: const FixedColumnWidth(colShrink),
      8: const FixedColumnWidth(colOutput),
      9: const FixedColumnWidth(colCost),
      10: const FixedColumnWidth(colPriceKg),
      11: const FixedColumnWidth(colTech),
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
                  headerCell(loc.t('ttk_gross_gr')),
                  headerCell(loc.t('ttk_waste_pct')),
                  headerCell(loc.t('ttk_net_gr')),
                  headerCell(loc.t('ttk_cooking_method')),
                  headerCell(loc.t('ttk_shrink_pct')),
                  headerCell(loc.t('ttk_output_gr')),
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
                                                style: const TextStyle(
                                                    fontSize: 12),
                                                overflow:
                                                    TextOverflow.ellipsis),
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
                                                style: const TextStyle(
                                                    fontSize: 12),
                                                overflow:
                                                    TextOverflow.ellipsis))),
                                    fillColor: firstColsBg,
                                    dataCell: true)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: _EditableGrossCell(
                                  grams: ing.grossWeight,
                                  onChanged: (g) {
                                    if (g != null && g >= 0)
                                      widget.onUpdate(
                                          i, ing.copyWith(grossWeight: g));
                                  },
                                ),
                              ),
                            )),
                          )
                        : _cell(ing.grossWeight.toStringAsFixed(0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Expanded(
                                          child: _EditableWasteCell(
                                            value: ing.primaryWastePct,
                                            onChanged: (v) {
                                              if (v != null)
                                                widget.onUpdate(
                                                    i,
                                                    ing.copyWith(
                                                        primaryWastePct: v
                                                            .clamp(0.0, 99.9)));
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
                                                minimumSize:
                                                    const Size(28, 28)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )),
                          )
                        : _cell(ing.primaryWastePct.toStringAsFixed(0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: _EditableNetCell(
                                  value: ing.effectiveGrossWeight,
                                  onChanged: (v) {
                                    if (v != null && v >= 0)
                                      widget.onUpdate(
                                          i,
                                          ing.copyWith(
                                              manualEffectiveGross: v));
                                  },
                                ),
                              ),
                            )),
                          )
                        : _cell(
                            '${ing.effectiveGrossWeight.toStringAsFixed(0)}'),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: ing.cookingProcessId,
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
                                                          p.getLocalizedName(
                                                              lang),
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
                                                          p.getLocalizedName(
                                                              lang),
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    )),
                                            DropdownMenuItem(
                                                value: 'custom',
                                                child: Text(
                                                    loc.t('cooking_custom'),
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                          ],
                                    onChanged: (id) {
                                      if (id == null) {
                                        widget.onUpdate(
                                            i,
                                            ing.copyWith(
                                                cookingProcessId: null,
                                                cookingProcessName: null));
                                      } else if (id == 'custom') {
                                        widget.onUpdate(
                                            i,
                                            ing.copyWith(
                                                cookingProcessId: 'custom',
                                                cookingProcessName:
                                                    loc.t('cooking_custom')));
                                      } else {
                                        final p = CookingProcess.findById(id);
                                        if (p != null) {
                                          widget.onUpdate(
                                              i,
                                              ing.copyWith(
                                                cookingProcessId: p.id,
                                                cookingProcessName:
                                                    p.getLocalizedName(lang),
                                              ));
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                            )),
                          )
                        : _cell(ing.cookingProcessName ?? loc.t('dash')),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _EditableShrinkageCell(
                                      value: product != null
                                          ? ing.weightLossPercentage
                                          : (ing.cookingLossPctOverride ?? 0),
                                      onChanged: (pct) {
                                        if (pct != null) {
                                          final eff = ing.effectiveGrossWeight;
                                          final output = eff > 0
                                              ? eff *
                                                  (1.0 -
                                                      pct.clamp(0.0, 99.9) /
                                                          100.0)
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
                                  ],
                                ),
                              ),
                            )),
                          )
                        : _cell(ing.weightLossPercentage.toStringAsFixed(0)),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
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
                            )),
                          )
                        : _cell(
                            '${(ing.outputWeight > 0 ? ing.outputWeight : ing.effectiveGrossWeight * (1.0 - (ing.cookingLossPctOverride ?? ing.weightLossPercentage) / 100.0)).toStringAsFixed(0)}'),
                    widget.effectiveCanEdit
                        ? TableCell(
                            child: wrapCell(ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Padding(
                                padding: _cellPad,
                                child: _EditableCostCell(
                                  cost: ing.effectiveCost,
                                  symbol: sym,
                                  onChanged: (v) {
                                    if (v != null && v >= 0)
                                      widget.onUpdate(i, ing.copyWith(cost: v));
                                  },
                                ),
                              ),
                            )),
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

  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);
  // Ширины как в _TtkTable (таблица создания)
  static const _colDish = 100.0;
  static const _colProduct = 120.0;
  static const _colGross = 70.0; // как столбец Цена
  static const _colNet = 70.0;
  static const _colMethod = 100.0;
  static const _colOutput = 70.0;
  static const _colPortions = 56.0;

  @override
  State<_TtkCookTable> createState() => _TtkCookTableState();
}

class _TtkCookTableState extends State<_TtkCookTable> {
  late List<TTIngredient> _ingredients;
  late double _totalOutput;
  double _portionsCount =
      1; // количество порций в итого (ввод пользователя), допускаются дробные (0.3)

  @override
  void initState() {
    super.initState();
    _ingredients = List.from(widget.ingredients);
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
  }

  @override
  void didUpdateWidget(covariant _TtkCookTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ingredients != widget.ingredients) {
      _ingredients = List.from(widget.ingredients);
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

  Widget _cell(String text, {bool bold = false}) {
    return TableCell(
      child: Padding(
        padding: _TtkCookTable._cellPad,
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: bold ? FontWeight.bold : null),
            overflow: TextOverflow.ellipsis,
            maxLines: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = Colors.grey;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Table(
          border: TableBorder.all(width: 0.5, color: borderColor),
          columnWidths: {
            0: const FixedColumnWidth(_TtkCookTable._colDish),
            1: const FixedColumnWidth(_TtkCookTable._colProduct),
            2: const FixedColumnWidth(_TtkCookTable._colGross),
            3: const FixedColumnWidth(_TtkCookTable._colNet),
            4: const FixedColumnWidth(_TtkCookTable._colMethod),
            5: const FixedColumnWidth(_TtkCookTable._colOutput),
            6: const FixedColumnWidth(_TtkCookTable._colPortions),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)),
              children: [
                TableCell(
                  child: SizedBox(
                      height: 44,
                      child: Center(
                          child: Text(widget.loc.t('ttk_name'),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)))),
                ),
                _cell(widget.loc.t('ttk_product'), bold: true),
                _cell(widget.loc.t('ttk_gross_gr'), bold: true),
                _cell(widget.loc.t('ttk_net_gr'), bold: true),
                _cell(widget.loc.t('ttk_cooking_method'), bold: true),
                _cell(widget.loc.t('ttk_output_gr'), bold: true),
                _cell(widget.loc.t('ttk_portions_pcs'), bold: true),
              ],
            ),
            if (_ingredients.isEmpty)
              TableRow(
                children: List.filled(
                    7,
                    TableCell(
                        child: Padding(
                            padding: _TtkCookTable._cellPad,
                            child: Text(widget.loc.t('dash'),
                                style: const TextStyle(fontSize: 12))))),
              )
            else
              ..._ingredients.asMap().entries.map((e) {
                final i = e.key;
                final ing = e.value;
                final cookProduct = widget.productStore
                    ?.findProductForIngredient(ing.productId, ing.productName);
                final cookLang = widget.loc.currentLanguageCode;
                final cookDisplayName = ing.sourceTechCardName ??
                    cookProduct?.getLocalizedName(cookLang) ??
                    ing.productName;
                // Название — placeholder (объединённая ячейка рисуется поверх в Stack)
                return TableRow(
                  children: [
                    TableCell(
                      child: Container(
                        height: 44,
                        color: Colors.white,
                      ),
                    ),
                    ing.sourceTechCardId != null &&
                            ing.sourceTechCardId!.isNotEmpty &&
                            widget.onTapPfIngredient != null
                        ? TableCell(
                            child: InkWell(
                              onTap: () => widget
                                  .onTapPfIngredient!(ing.sourceTechCardId!),
                              child: Padding(
                                padding: _TtkCookTable._cellPad,
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
                                                TextDecoration.underline),
                                      ),
                                      TextSpan(
                                          text:
                                              ' (${ing.outputWeight.toStringAsFixed(0)} ${widget.loc.t('gram')})'),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ),
                          )
                        : _cell(cookDisplayName),
                    TableCell(
                      child: Padding(
                        padding: _TtkCookTable._cellPad,
                        child: _EditableNetCell(
                          value: ing.grossWeight,
                          onChanged: (v) =>
                              _updateGrossAt(i, v ?? ing.grossWeight),
                        ),
                      ),
                    ),
                    TableCell(
                      child: Padding(
                        padding: _TtkCookTable._cellPad,
                        child: _EditableNetCell(
                          value: ing.netWeight,
                          onChanged: (v) => _updateNetAt(i, v ?? ing.netWeight),
                        ),
                      ),
                    ),
                    _cell(ing.cookingProcessName ?? widget.loc.t('dash')),
                    _cell(ing.outputWeight.toStringAsFixed(0)),
                    _cell(_portionsAmount(ing)),
                  ],
                );
              }),
            TableRow(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest),
              children: [
                _cell(widget.loc.t('ttk_total'), bold: true),
                _cell(''),
                _cell(''),
                TableCell(
                  child: Padding(
                    padding: _TtkCookTable._cellPad,
                    child: Text(
                        '${_totalOutput.toStringAsFixed(0)} ${widget.loc.t('gram')}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                _cell(''),
                TableCell(
                  child: Padding(
                    padding: _TtkCookTable._cellPad,
                    child: _EditableNetCell(
                      value: _totalOutput,
                      onChanged: (v) {
                        if (v != null && v > 0) _scaleByOutput(v);
                      },
                    ),
                  ),
                ),
                TableCell(
                  child: Padding(
                    padding: _TtkCookTable._cellPad,
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
            top: 44,
            width: _TtkCookTable._colDish,
            height: _ingredients.length * 44 + 1,
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
                overflow: TextOverflow.ellipsis,
                maxLines: 10,
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
  });

  final double value;
  final void Function(double? v) onChanged;

  /// Количество знаков после запятой (0 = целые, 1 = 0.3 и т.д.)
  final int decimalPlaces;

  /// Целые без .0 (1, 2), дробные с одним знаком (0.5, 0.3).
  String _format(double v) {
    if (decimalPlaces == 0) return v.toStringAsFixed(0);
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(decimalPlaces);
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
    _debounce = Timer(const Duration(milliseconds: 250), _submit);
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: TextField(
        focusNode: _focusNode,
        controller: _ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLow
              .withValues(alpha: 0.7),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (_) => _scheduleSubmit(),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
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
        final products = await getProducts();
        if (!context.mounted || products.isEmpty) return;
        final selected = await showDialog<Product>(
          context: context,
          builder: (ctx) =>
              _ProductSelectDialog(products: products, lang: lang),
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
                  subtitle: Text(CulinaryUnits.displayName(
                      (p.unit ?? 'g').trim().toLowerCase(),
                      loc.currentLanguageCode)),
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
                                    child: Text(
                                        CulinaryUnits.displayName(u.id, lang)),
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
                                '${proc.getLocalizedName(lang)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
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
  const _TechCardPicker({required this.techCards, required this.onPick});

  final List<TechCard> techCards;
  final void Function(
      TechCard t, double value, String unit, double? gramsPerPiece) onPick;

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
            subtitle: Text(
                '${t.ingredients.length} ${loc.t('ingredients_short')} · ${t.totalCalories.round()} ${loc.t('kcal')}'),
          ),
        );
      },
    );
  }

  void _askWeight(BuildContext context, TechCard t) {
    final c = TextEditingController(text: '100');
    final gppController = TextEditingController(text: '50');
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    String selectedUnit = 'g';
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDlg) => AlertDialog(
          title: Text(t.getDisplayNameInLists(lang)),
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
                                child:
                                    Text(CulinaryUnits.displayName(u.id, lang)),
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
                  onPick(t, v, selectedUnit, gpp);
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
