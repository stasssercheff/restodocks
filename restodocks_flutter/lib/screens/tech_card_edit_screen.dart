import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'excel_style_ttk_table.dart';

/// Создание или редактирование ТТК. Ингредиенты — из номенклатуры или из других ТТК (ПФ).
///
/// Составление/редактирование карточек остаётся как реализовано (таблица, ингредиенты, технология).
/// Отображение для сотрудников (режим просмотра, !canEdit) должно соответствовать референсу:
/// https://github.com/stasssercheff/shbb326 — kitchen/kitchen/ttk/Preps (ТТК ПФ), dish (карточки блюд), sv (су-вид).

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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _EditableShrinkageCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value.toStringAsFixed(1)) {
      _ctrl.text = widget.value.toStringAsFixed(1);
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
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7);
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _EditableWasteCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value.toStringAsFixed(1)) {
      _ctrl.text = widget.value.toStringAsFixed(1);
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
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7);
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
    );
  }
}

/// Редактируемая ячейка названия продукта: ввод вручную и/или выбор из списка.
class _EditableProductNameCell extends StatefulWidget {
  const _EditableProductNameCell({required this.value, required this.onChanged, this.hintText});

  final String value;
  final void Function(String) onChanged;
  final String? hintText;

  @override
  State<_EditableProductNameCell> createState() => _EditableProductNameCellState();
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.grams.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _EditableGrossCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grams != widget.grams && _ctrl.text != widget.grams.toStringAsFixed(0)) {
      _ctrl.text = widget.grams.toStringAsFixed(0);
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
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7);
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: fill,
        ),
        style: const TextStyle(fontSize: 12),
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
  State<_EditablePricePerKgCell> createState() => _EditablePricePerKgCellState();
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
    if (oldWidget.pricePerKg != widget.pricePerKg && _ctrl.text != widget.pricePerKg.toStringAsFixed(2)) {
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
    final fill = Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7);
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
  const _EditableCostCell({required this.cost, required this.symbol, required this.onChanged});

  final double cost;
  final String symbol;
  final void Function(double? v) onChanged;

  @override
  State<_EditableCostCell> createState() => _EditableCostCellState();
}

class _EditableCostCellState extends State<_EditableCostCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.cost.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _EditableCostCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cost != widget.cost && _ctrl.text != widget.cost.toStringAsFixed(2)) {
      _ctrl.text = widget.cost.toStringAsFixed(2);
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
        ),
        style: const TextStyle(fontSize: 12),
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _submit(),
      ),
    );
  }
}

TechCard _applyEdits(
  TechCard t, {
  String? dishName,
  String? category,
  bool? isSemiFinished,
  double? portionWeight,
  double? yieldGrams,
  Map<String, String>? technologyLocalized,
  List<TTIngredient>? ingredients,
}) {
  return t.copyWith(
    dishName: dishName,
    category: category,
    isSemiFinished: isSemiFinished,
    portionWeight: portionWeight,
    yield: yieldGrams,
    technologyLocalized: technologyLocalized,
    ingredients: ingredients,
  );
}

class TechCardEditScreen extends StatefulWidget {
  const TechCardEditScreen({super.key, required this.techCardId, this.initialFromAi});

  /// Пусто для «новой», иначе id существующей ТТК.
  final String techCardId;
  /// Предзаполнение из ИИ (фото/Excel). Используется только при techCardId == 'new'.
  final TechCardRecognitionResult? initialFromAi;

  @override
  State<TechCardEditScreen> createState() => _TechCardEditScreenState();
}

class _TechCardEditScreenState extends State<TechCardEditScreen> {
  TechCard? _techCard;
  bool _loading = true;
  String? _error;
  /// 'photo' | 'excel' — какая кнопка сейчас загружает (чтобы показывать правильный текст).
  final _nameController = TextEditingController();
  static const _categoryOptions = ['sauce', 'vegetables', 'meat', 'seafood', 'side', 'subside', 'bakery', 'dessert', 'decor', 'soup', 'misc', 'beverages'];
  String _selectedCategory = 'misc';
  bool _isSemiFinished = true; // ПФ или блюдо (порция — в карточках блюд, отдельно)
  final _technologyController = TextEditingController();
  final List<TTIngredient> _ingredients = [];
  List<TechCard> _pickerTechCards = [];
  List<TechCard> _semiFinishedProducts = [];

  bool get _isNew => widget.techCardId.isEmpty || widget.techCardId == 'new';

  String _categoryLabel(String c, String lang) {
    final Map<String, Map<String, String>> categoryTranslations = {
      'sauce': {'ru': 'Соус', 'en': 'Sauce'},
      'vegetables': {'ru': 'Овощи', 'en': 'Vegetables'},
      'meat': {'ru': 'Мясо', 'en': 'Meat'},
      'seafood': {'ru': 'Рыба', 'en': 'Seafood'},
      'side': {'ru': 'Гарнир', 'en': 'Side dish'},
      'subside': {'ru': 'Подгарнир', 'en': 'Sub-side dish'},
      'bakery': {'ru': 'Выпечка', 'en': 'Bakery'},
      'dessert': {'ru': 'Десерт', 'en': 'Dessert'},
      'decor': {'ru': 'Декор', 'en': 'Decor'},
      'soup': {'ru': 'Суп', 'en': 'Soup'},
      'misc': {'ru': 'Разное', 'en': 'Misc'},
      'beverages': {'ru': 'Напитки', 'en': 'Beverages'},
    };

    return categoryTranslations[c]?[lang] ?? c;
  }

  /// Простой вывод категории из названия блюда (для предзаполнения из ИИ).
  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (lower.contains('соус') || lower.contains('sauce')) return 'sauce';
    if (lower.contains('овощ') || lower.contains('vegetable') || lower.contains('салат')) return 'vegetables';
    if (lower.contains('мяс') || lower.contains('meat') || lower.contains('куриц') || lower.contains('говядин')) return 'meat';
    if (lower.contains('рыб') || lower.contains('fish') || lower.contains('море') || lower.contains('seafood')) return 'seafood';
    if (lower.contains('гарнир') || lower.contains('side')) return 'side';
    if (lower.contains('подгарнир') || lower.contains('subside')) return 'subside';
    if (lower.contains('выпеч') || lower.contains('bakery') || lower.contains('хлеб') || lower.contains('тест')) return 'bakery';
    if (lower.contains('десерт') || lower.contains('dessert')) return 'dessert';
    if (lower.contains('декор') || lower.contains('decor')) return 'decor';
    if (lower.contains('суп') || lower.contains('soup')) return 'soup';
    if (lower.contains('напит') || lower.contains('beverage') || lower.contains('сок') || lower.contains('компот')) return 'beverages';
    return 'misc';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<ProductStoreSupabase>().loadProducts();
      final est = context.read<AccountManagerSupabase>().establishment;
      if (est != null) {
        await context.read<ProductStoreSupabase>().loadNomenclature(est.id);
        final tcs = await context.read<TechCardServiceSupabase>().getTechCardsForEstablishment(est.id);
        if (mounted) {
          _pickerTechCards = _isNew ? tcs : tcs.where((t) => t.id != widget.techCardId).toList();
          _semiFinishedProducts = tcs.where((t) => t.isSemiFinished).toList();
        }
      }
      if (_isNew) {
        if (mounted) {
          final ai = widget.initialFromAi;
          final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
          if (ai != null) {
            _nameController.text = ai.dishName?.trim() ?? '';
            _technologyController.text = ai.technologyText?.trim() ?? '';
            if (ai.isSemiFinished != null) _isSemiFinished = ai.isSemiFinished!;
            if (ai.dishName != null && ai.dishName!.isNotEmpty) {
              final cat = _inferCategory(ai.dishName!);
              if (_categoryOptions.contains(cat)) _selectedCategory = cat;
            }
            _ingredients.clear();
            for (final line in ai.ingredients) {
              if (line.productName.trim().isEmpty) continue;
              final gross = line.grossGrams ?? 0.0;
              final net = line.netGrams ?? line.grossGrams ?? gross;
              final unit = line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
              final wastePct = (line.primaryWastePct ?? 0).clamp(0.0, 99.9);
              _ingredients.add(TTIngredient(
                id: DateTime.now().millisecondsSinceEpoch.toString() + _ingredients.length.toString(),
                productId: null,
                productName: line.productName.trim(),
                grossWeight: gross > 0 ? gross : 100,
                netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
                unit: unit,
                primaryWastePct: wastePct,
                cookingLossPctOverride: line.cookingLossPct != null ? line.cookingLossPct!.clamp(0.0, 99.9) : null,
                isNetWeightManual: line.netGrams != null,
                finalCalories: 0,
                finalProtein: 0,
                finalFat: 0,
                finalCarbs: 0,
                cost: 0,
              ));
            }
            if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
              _ingredients.add(TTIngredient.emptyPlaceholder());
            }
          } else if (canEdit && _ingredients.isEmpty) {
            _ingredients.add(TTIngredient.emptyPlaceholder());
          }
          setState(() { _loading = false; });
        }
        return;
      }
      final svc = context.read<TechCardServiceSupabase>();
      final tc = await svc.getTechCardById(widget.techCardId);
      if (!mounted) return;
      final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
      // Откладываем тяжёлый setState на следующий кадр, чтобы не блокировать UI при большом числе ингредиентов
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _techCard = tc;
          _loading = false;
          if (tc != null) {
            _nameController.text = tc.dishName;
            _selectedCategory = _categoryOptions.contains(tc.category) ? tc.category : 'misc';
            _isSemiFinished = tc.isSemiFinished;
            _technologyController.text = tc.getLocalizedTechnology(context.read<LocalizationService>().currentLanguageCode);
            _ingredients
              ..clear()
              ..addAll(tc.ingredients);
            if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
              _ingredients.add(TTIngredient.emptyPlaceholder());
            }
          }
        });
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    // Добавляем listener для обновления таблицы при изменении названия
    _nameController.addListener(() {
      setState(() {}); // Обновляем UI при изменении названия
    });
    // Добавляем listener для обновления таблицы при изменении технологии
    _technologyController.addListener(() {
      setState(() {}); // Обновляем UI при изменении технологии
    });
    // Добавляем placeholder сразу, чтобы таблица отображалась
    _ingredients.add(TTIngredient.emptyPlaceholder());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _technologyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('dish_name_required_ttk'))));
      return;
    }
    const portion = 100.0; // порция — в карточках блюд
    final toSaveIngredients = _ingredients.where((i) => !i.isPlaceholder).toList();
    final yieldVal = toSaveIngredients.isEmpty ? 0.0 : toSaveIngredients.fold(0.0, (s, i) => s + i.netWeight);
    final category = _selectedCategory;
    final curLang = context.read<LocalizationService>().currentLanguageCode;
    final tc = _techCard;
    final techMap = Map<String, String>.from(tc?.technologyLocalized ?? {});
    techMap[curLang] = _technologyController.text.trim();
    for (final c in LocalizationService.productLanguageCodes) {
      techMap.putIfAbsent(c, () => '');
    }
    final svc = context.read<TechCardServiceSupabase>();

    try {
      if (_isNew || tc == null) {
        final created = await svc.createTechCard(
          dishName: name,
          category: category,
          isSemiFinished: _isSemiFinished,
          establishmentId: est.id,
          createdBy: emp.id,
        );
        var updated = _applyEdits(created, portionWeight: portion, yieldGrams: yieldVal, technologyLocalized: techMap, ingredients: toSaveIngredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('tech_card_created'))));
          context.go('/tech-cards');
        }
      } else {
        final updated = _applyEdits(tc, dishName: name, category: category, isSemiFinished: _isSemiFinished, portionWeight: portion, yieldGrams: yieldVal, technologyLocalized: techMap, ingredients: toSaveIngredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocalizationService>().t('save') + ' ✓')));
          context.go('/tech-cards');
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
    }
  }

  Future<void> _confirmDelete(BuildContext context, LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_tech_card')),
        content: Text(loc.t('delete_tech_card_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.t('delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<TechCardServiceSupabase>().deleteTechCard(widget.techCardId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('tech_card_deleted'))));
        context.go('/tech-cards');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
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
    final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
    final hadPlaceholder = _ingredients.isNotEmpty && _ingredients.last.isPlaceholder;
    if (ai.ingredients.isNotEmpty) {
      _ingredients.removeWhere((e) => e.isPlaceholder);
      for (final line in ai.ingredients) {
        if (line.productName.trim().isEmpty) continue;
        final gross = line.grossGrams ?? 0.0;
        final net = line.netGrams ?? line.grossGrams ?? gross;
        final unit = line.unit?.trim().isNotEmpty == true ? line.unit! : 'g';
        final wastePct = (line.primaryWastePct ?? 0).clamp(0.0, 99.9);
        _ingredients.add(TTIngredient(
          id: DateTime.now().millisecondsSinceEpoch.toString() + _ingredients.length.toString(),
          productId: null,
          productName: line.productName.trim(),
          grossWeight: gross > 0 ? gross : 100,
          netWeight: net > 0 ? net : (gross > 0 ? gross : 100),
          unit: unit,
          primaryWastePct: wastePct,
          cookingLossPctOverride: line.cookingLossPct != null ? line.cookingLossPct!.clamp(0.0, 99.9) : null,
          isNetWeightManual: line.netGrams != null,
          finalCalories: 0,
          finalProtein: 0,
          finalFat: 0,
          finalCarbs: 0,
          cost: 0,
        ));
      }
      if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
        _ingredients.add(TTIngredient.emptyPlaceholder());
      }
    } else if (hadPlaceholder && _ingredients.isNotEmpty) {
      // сохраняем плейсхолдер
    } else if (canEdit && _ingredients.isEmpty) {
      _ingredients.add(TTIngredient.emptyPlaceholder());
    }
  }




  /// Загрузить номенклатуру и вернуть список продуктов (для выпадающего списка в ячейке).
  Future<List<Product>> _getProductsForDropdown() async {
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return [];
    final productStore = context.read<ProductStoreSupabase>();
    await productStore.loadProducts();
    await productStore.loadNomenclature(est.id);
    if (!mounted) return [];
    return productStore.getNomenclatureProducts(est.id);
  }

  /// [replaceIndex] — если задан, заменяем строку вместо добавления (тап по ячейке «Продукт»).
  Future<void> _showAddIngredient([int? replaceIndex]) async {
    final loc = context.read<LocalizationService>();
    final productStore = context.read<ProductStoreSupabase>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    await productStore.loadProducts();
    await productStore.loadNomenclature(est.id);

    if (!mounted) return;
    final nomenclatureProducts = productStore.getNomenclatureProducts(est.id);
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
              title: Text(replaceIndex != null ? loc.t('change_ingredient') : loc.t('add_ingredient')),
              bottom: TabBar(
                tabs: [
                  Tab(text: loc.t('ingredient_from_product')),
                  Tab(text: loc.t('ingredient_from_ttk')),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _ProductPicker(
                  products: nomenclatureProducts,
                  onPick: (p, w, proc, waste, unit, gpp, {cookingLossPctOverride}) => _addProductIngredient(p, w, proc, waste, unit, gpp, replaceIndex: replaceIndex, cookingLossPctOverride: cookingLossPctOverride),
                ),
                _TechCardPicker(techCards: _pickerTechCards, onPick: (t, w, unit, gpp) => _addTechCardIngredient(t, w, unit, gpp, replaceIndex: replaceIndex)),
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
    const defaultUnit = 'g';
    final c = TextEditingController(text: '100');
    final gppController = TextEditingController(text: '50');
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
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: loc.t('quantity_label')),
                          autofocus: true,
                          onSubmitted: (_) {
                            final v = double.tryParse(c.text.replaceFirst(',', '.')) ?? 0;
                            final waste = (p.primaryWastePct ?? 0).clamp(0.0, 99.9);
                            double? gpp = CulinaryUnits.isCountable(selectedUnit) ? (double.tryParse(gppController.text) ?? 50) : null;
                            if (gpp != null && gpp <= 0) gpp = 50;
                            double? cookLossOverride;
                            if (selectedProcess != null) {
                              final entered = double.tryParse(shrinkageController.text.replaceFirst(',', '.'));
                              if (entered != null && (entered - selectedProcess!.weightLossPercentage).abs() > 0.01) {
                                cookLossOverride = entered.clamp(0.0, 99.9);
                              }
                            }
                            Navigator.of(ctx).pop();
                            if (v > 0) _addProductIngredient(p, v, selectedProcess, waste, selectedUnit, gpp, replaceIndex: replaceIndex, cookingLossPctOverride: cookLossOverride, popNavigator: false);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: InputDecoration(isDense: true, labelText: loc.t('unit_short')),
                          items: CulinaryUnits.all.map((u) => DropdownMenuItem(value: u.id, child: Text(CulinaryUnits.displayName(u.id, lang)))).toList(),
                          onChanged: (v) => setStateDlg(() => selectedUnit = v ?? 'g'),
                        ),
                      ),
                    ],
                  ),
                  if (CulinaryUnits.isCountable(selectedUnit)) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: gppController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: loc.t('g_pc'), hintText: loc.t('hint_50')),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(loc.t('cooking_process'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<CookingProcess?>(
                    value: selectedProcess,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      DropdownMenuItem(value: null, child: Text(loc.t('no_process'))),
                      ...processes.map((proc) => DropdownMenuItem(
                            value: proc,
                            child: Text('${proc.getLocalizedName(lang)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
                          )),
                    ],
                    onChanged: (v) => setStateDlg(() {
                      selectedProcess = v;
                      if (v != null) shrinkageController.text = v.weightLossPercentage.toStringAsFixed(1);
                      else shrinkageController.text = '';
                    }),
                  ),
                  if (selectedProcess != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: shrinkageController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('ttk_cook_loss'),
                        hintText: selectedProcess?.weightLossPercentage.toStringAsFixed(1),
                        helperText: loc.t('ttk_cook_loss_override_hint'),
                      ),
                      onChanged: (_) => setStateDlg(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.t('back'))),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(c.text.replaceFirst(',', '.')) ?? 0;
                  final waste = (p.primaryWastePct ?? 0).clamp(0.0, 99.9);
                  double? gpp = CulinaryUnits.isCountable(selectedUnit) ? (double.tryParse(gppController.text) ?? 50) : null;
                  if (gpp != null && gpp <= 0) gpp = 50;
                  double? cookLossOverride;
                  if (selectedProcess != null) {
                    final entered = double.tryParse(shrinkageController.text.replaceFirst(',', '.'));
                    if (entered != null && (entered - selectedProcess!.weightLossPercentage).abs() > 0.01) {
                      cookLossOverride = entered.clamp(0.0, 99.9);
                    }
                  }
                  Navigator.of(ctx).pop();
                  if (v > 0) _addProductIngredient(p, v, selectedProcess, waste, selectedUnit, gpp, replaceIndex: replaceIndex, cookingLossPctOverride: cookLossOverride, popNavigator: false);
                },
                child: Text(loc.t('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addProductIngredient(Product p, double value, CookingProcess? cookingProcess, double primaryWastePct, String unit, double? gramsPerPiece, {int? replaceIndex, double? cookingLossPctOverride, bool popNavigator = true}) {
    if (popNavigator) Navigator.of(context).pop();
    final loc = context.read<LocalizationService>();
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final productStore = context.read<ProductStoreSupabase>();
    final establishmentId = context.read<AccountManagerSupabase>().establishment?.id;
    final hasProSubscription = context.read<AccountManagerSupabase>().currentEmployee?.hasProSubscription ?? false;
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
      hasProSubscription: hasProSubscription,
      defaultCurrency: currency,
    );
    setState(() {
      if (replaceIndex != null && replaceIndex >= 0 && replaceIndex < _ingredients.length) {
        _ingredients[replaceIndex] = ing;
      } else {
        _ingredients.add(ing);
      }
      final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
      if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
        _ingredients.add(TTIngredient.emptyPlaceholder());
      }
    });
  }

  /// Подстановка продукта из поиска по номенклатуре в строку [replaceIndex] (или добавление новой).
  /// Отложенный кадр, чтобы закрытие попапа DropdownSearch не приводило к Navigator.pop экрана редактирования.
  void _addProductIngredientAt(int replaceIndex, Product p, {double? grossGrams}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocalizationService>();
      final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
      final productStore = context.read<ProductStoreSupabase>();
      final establishmentId = context.read<AccountManagerSupabase>().establishment?.id;
      final hasProSubscription = context.read<AccountManagerSupabase>().currentEmployee?.hasProSubscription ?? false;
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
        hasProSubscription: hasProSubscription,
      );
      setState(() {
        if (replaceIndex >= 0 && replaceIndex < _ingredients.length) {
          _ingredients[replaceIndex] = ing;
          final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
          if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
            _ingredients.add(TTIngredient.emptyPlaceholder());
          }
        } else {
          _ingredients.add(ing);
        }
      });
    });
  }

  void _addTechCardIngredient(TechCard t, double weightG, String unit, double? gramsPerPiece, {int? replaceIndex}) {
    Navigator.of(context).pop();
    final totalNet = t.totalNetWeight;
    if (totalNet <= 0) return;
    final loc = context.read<LocalizationService>();
    final weightConv = CulinaryUnits.toGrams(weightG, unit, gramsPerPiece: gramsPerPiece);
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
      if (replaceIndex != null && replaceIndex >= 0 && replaceIndex < _ingredients.length) {
        _ingredients[replaceIndex] = ing;
      } else {
        _ingredients.add(ing);
      }
      final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
      if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
        _ingredients.add(TTIngredient.emptyPlaceholder());
      }
    });
  }

  /// Добавить первый ингредиент по введённому названию (пустая строка при ingredients.isEmpty) и новую пустую строку.
  void _addIngredientFromName(String productName) {
    final name = productName.trim();
    if (name.isEmpty) return;
    final ing = TTIngredient.emptyPlaceholder().copyWith(productName: name).withRealId();
    setState(() {
      _ingredients.add(ing);
      _ingredients.add(TTIngredient.emptyPlaceholder());
    });
  }

  void _removeIngredient(int i) {
    setState(() {
      _ingredients.removeAt(i);
      final canEdit = context.read<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;
      if (canEdit && (_ingredients.isEmpty || !_ingredients.last.isPlaceholder)) {
        _ingredients.add(TTIngredient.emptyPlaceholder());
      }
    });
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
    setState(() => _ingredients[i] = ing.copyWith(primaryWastePct: waste, netWeight: net, isNetWeightManual: false));
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context.watch<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;

    if (_isNew && !canEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement('/tech-cards');
      });
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('tech_cards'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(_isNew ? loc.t('create_tech_card') : loc.t('tech_cards'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(_isNew ? loc.t('create_tech_card') : loc.t('tech_cards'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(_error!), const SizedBox(height: 16), FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back')))]))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop(), style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
        title: Text(_isNew ? loc.t('create_tech_card') : (_techCard?.getDisplayNameInLists(loc.currentLanguageCode) ?? loc.t('tech_cards'))),
        actions: [
          if (canEdit) IconButton(icon: const Icon(Icons.save), onPressed: _save, tooltip: loc.t('save'), style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
          if (canEdit && !_isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirmDelete(context, loc), tooltip: loc.t('delete_tech_card'), style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
          // Кнопка экспорта текущей ТТК
          if (!_isNew && _techCard != null) IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                await ExcelExportService().exportSingleTechCard(_techCard!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ТТК "${_techCard!.dishName}" успешно экспортирована')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка экспорта: $e')),
                  );
                }
              }
            },
            tooltip: 'Экспорт в Excel',
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home'), style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 500;
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Шапка: название, категория, тип — на узком экране колонкой, на широком строкой
                if (narrow) ...[
                  TextField(
                    controller: _nameController,
                    readOnly: !canEdit,
                    decoration: InputDecoration(
                      labelText: loc.t('ttk_name'),
                      isDense: true,
                      filled: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  canEdit
                      ? DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: InputDecoration(labelText: loc.t('category'), isDense: true, border: const OutlineInputBorder()),
                          items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c, loc.currentLanguageCode)))).toList(),
                          onChanged: (v) => setState(() => _selectedCategory = v ?? 'misc'),
                        )
                      : InputDecorator(
                          decoration: InputDecoration(labelText: loc.t('category'), isDense: true, border: const OutlineInputBorder()),
                          child: Text(_categoryLabel(_selectedCategory, loc.currentLanguageCode)),
                        ),
                  const SizedBox(height: 12),
                  canEdit
                      ? DropdownButtonFormField<bool>(
                          value: _isSemiFinished,
                          decoration: InputDecoration(labelText: loc.t('tt_type_hint'), isDense: true, border: const OutlineInputBorder()),
                          items: [
                            DropdownMenuItem(value: true, child: Row(children: [const Icon(Icons.inventory_2, size: 20), const SizedBox(width: 8), Text(loc.t('tt_type_pf'))])),
                            DropdownMenuItem(value: false, child: Row(children: [const Icon(Icons.restaurant, size: 20), const SizedBox(width: 8), Text(loc.t('tt_type_dish'))])),
                          ],
                          onChanged: (v) => setState(() => _isSemiFinished = v ?? true),
                        )
                      : ListTile(
                          dense: true,
                          leading: Icon(_isSemiFinished ? Icons.inventory_2 : Icons.restaurant, size: 20),
                          title: Text(_isSemiFinished ? loc.t('tt_type_pf') : loc.t('tt_type_dish')),
                        ),
                ] else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 200,
                          height: 56,
                          child: TextField(
                            controller: _nameController,
                            readOnly: !canEdit,
                            decoration: InputDecoration(
                              labelText: loc.t('ttk_name'),
                              isDense: true,
                              filled: true,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 140,
                          child: canEdit
                              ? DropdownButtonFormField<String>(
                                  value: _selectedCategory,
                                  decoration: InputDecoration(labelText: loc.t('category'), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                  items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c, loc.currentLanguageCode)))).toList(),
                                  onChanged: (v) => setState(() => _selectedCategory = v ?? 'misc'),
                                )
                              : InputDecorator(
                                  decoration: InputDecoration(labelText: loc.t('category'), isDense: true),
                                  child: Text(_categoryLabel(_selectedCategory, loc.currentLanguageCode)),
                                ),
                        ),
                        const SizedBox(width: 8),
                        if (canEdit)
                          Tooltip(
                            message: loc.t('tt_type_hint'),
                            child: SegmentedButton<bool>(
                              segments: [
                                ButtonSegment(value: true, label: Text(loc.t('tt_type_pf')), icon: const Icon(Icons.inventory_2, size: 16)),
                                ButtonSegment(value: false, label: Text(loc.t('tt_type_dish')), icon: const Icon(Icons.restaurant, size: 16)),
                              ],
                              selected: {_isSemiFinished},
                              onSelectionChanged: (v) => setState(() => _isSemiFinished = v.first),
                              showSelectedIcon: false,
                            ),
                          )
                        else
                          Chip(
                            avatar: Icon(_isSemiFinished ? Icons.inventory_2 : Icons.restaurant, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            label: Text(_isSemiFinished ? loc.t('tt_type_pf') : loc.t('tt_type_dish'), style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
            const SizedBox(height: 16),
            Text(loc.t('ttk_composition'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Таблица на весь экран без ограничений
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
                      child: canEdit
                            ? ExcelStyleTtkTable(
                            loc: loc,
                            dishName: _nameController.text,
                            isSemiFinished: _isSemiFinished,
                            ingredients: _ingredients,
                            canEdit: true,
                            dishNameController: _nameController,
                            technologyController: _technologyController,
                            productStore: context.read<ProductStoreSupabase>(),
                            establishmentId: context.read<AccountManagerSupabase>().establishment?.id,
                            semiFinishedProducts: _semiFinishedProducts,
                            onAdd: _showAddIngredient,
                            onUpdate: (i, ing) {
                              setState(() {
                                if (_ingredients.isEmpty && i == 0) {
                                  _ingredients.add(ing);
                                  if (ing.isPlaceholder && ing.hasData) {
                                    _ingredients[0] = ing.withRealId();
                                    _ingredients.add(TTIngredient.emptyPlaceholder());
                                  }
                                  return;
                                }
                                if (i >= _ingredients.length) return;
                                _ingredients[i] = ing;
                                if (ing.isPlaceholder && ing.hasData) {
                                  _ingredients[i] = ing.withRealId();
                                  _ingredients.add(TTIngredient.emptyPlaceholder());
                                }
                              });
                            },
                            onRemove: _removeIngredient,
                            onSuggestWaste: _suggestWasteForRow,
                          )
                            : _TtkCookTable(
                                loc: loc,
                                dishName: _nameController.text,
                                ingredients: _ingredients.where((i) => !i.isPlaceholder || i.hasData).toList(),
                                technology: _technologyController.text,
                                onIngredientsChanged: (list) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    setState(() {
                                      _ingredients.clear();
                                      _ingredients.addAll(list);
                                    });
                                  });
                                },
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
            if (canEdit)
              SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      children: [
                        FilledButton(
                          onPressed: _save,
                          child: Text(loc.t('save')),
                          style: FilledButton.styleFrom(minimumSize: const Size(120, 48), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                        ),
                        if (!_isNew) ...[
                          const SizedBox(width: 16),
                          TextButton.icon(
                            icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                            label: Text(loc.t('delete_tech_card'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            onPressed: () => _confirmDelete(context, loc),
                            style: TextButton.styleFrom(minimumSize: const Size(120, 48), padding: const EdgeInsets.symmetric(horizontal: 16)),
                          ),
                        ],
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
    required this.canEdit,
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
  final bool canEdit;
  final void Function(int i) onRemove;
  final void Function(int i, TTIngredient ing) onUpdate;
  final VoidCallback onAdd;
  /// Когда в пустой строке (при ingredients.isEmpty) вводят название продукта — добавить ингредиент и новую пустую строку.
  final void Function(String productName)? onAddFromText;
  final ProductStoreSupabase productStore;
  final void Function(int index, Product product, {double? grossGrams})? onPickProductFromSearch;
  /// Загрузка списка продуктов для выпадающего списка из ячейки.
  final Future<List<Product>> Function()? getProductsForDropdown;
  /// Выбран продукт из выпадающего списка в ячейке — показать диалог количества и добавить.
  final void Function(int index, Product product)? onProductSelectedFromDropdown;
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
        child: dataCell ? ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: child) : child,
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
    final totalCost = ingredients.fold<double>(0, (s, ing) => s + ing.cost);
    final totalCalories = ingredients.fold<double>(0, (s, ing) => s + ing.finalCalories);
    final totalProtein = ingredients.fold<double>(0, (s, ing) => s + ing.finalProtein);
    final totalFat = ingredients.fold<double>(0, (s, ing) => s + ing.finalFat);
    final totalCarbs = ingredients.fold<double>(0, (s, ing) => s + ing.finalCarbs);
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final sym = currency == 'RUB' ? '₽' : currency == 'VND' ? '₫' : currency == 'USD' ? '\$' : currency;
    final hasProSubscription = context.read<AccountManagerSupabase>().currentEmployee?.hasProSubscription ?? false;

    final hasDeleteCol = widget.canEdit;
    // Порядок колонок как в образце. Ширины подобраны так, чтобы вся строка с полями ввода помещалась на экране без горизонтальной прокрутки.
    const colType = 64.0;   // Тип ТТК
    const colName = 100.0;  // Наименование
    const colProduct = 120.0;
    const colGross = 70.0;  // Брутто г
    const colWaste = 64.0;  // Отход %
    const colNet = 70.0;    // Нетто г
    const colMethod = 100.0;// Способ
    const colShrink = 64.0; // Ужарка %
    const colOutput = 70.0; // Выход г
    const colCost = 82.0;   // Стоимость
    const colPriceKg = 88.0;// Цена за 1 кг/шт
    const colTech = 180.0;  // Технология
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
    final tableWidth = colType + colName + colProduct + colGross + colWaste + colNet + colMethod + colShrink + colOutput + colCost + colPriceKg + colTech + (hasDeleteCol ? colDel : 0.0);

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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerTextColor),
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
    return SizedBox(
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
            headerCell('Отход %'),
            headerCell(loc.t('ttk_net_gr')),
            headerCell(loc.t('ttk_cooking_method')),
            headerCell('Ужарка %'),
            headerCell(loc.t('ttk_output_gr')),
            headerCell(loc.t('ttk_cost')),
            headerCell(loc.t('ttk_price_per_1kg_dish')),
            headerCell(loc.t('ttk_technology')),
            if (hasDeleteCol) TableCell(child: wrapCell(Padding(padding: _cellPad, child: const SizedBox.shrink()), fillColor: headerBg, dataCell: false)),
          ],
        ),
        // 2. Строки данных (каждая строка = те же 13 колонок по шаблону; пустая строка — те же ячейки, без данных)
        ...ingredients.asMap().entries.map((e) {
          final i = e.key;
          final ing = e.value;
          final product = ing.productId != null ? widget.productStore.allProducts.where((p) => p.id == ing.productId).firstOrNull : null;
          final proc = ing.cookingProcessId != null ? CookingProcess.findById(ing.cookingProcessId!) : null;
          final pricePerUnit = product?.basePrice ?? (ing.netWeight > 0 ? ing.cost * 1000 / ing.netWeight : 0.0);
          final isFirstRow = i == 0;
          return TableRow(
            decoration: BoxDecoration(color: cellBg),
            children: [
              // Тип ТТК — ПФ или Блюдо (светло-серый как в образце)
              TableCell(child: wrapCell(Container(color: firstColsBg, constraints: const BoxConstraints(minHeight: 44), padding: _cellPad, alignment: Alignment.center, child: Text(widget.isSemiFinished ? 'ПФ' : loc.t('ttk_dish'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))), fillColor: firstColsBg, dataCell: true)),
              // Название — одна объединённая ячейка поверх всех строк (рисуется в Stack ниже); здесь — пустая ячейка без границы
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.fill,
                child: Container(
                  color: firstColsBg,
                  constraints: const BoxConstraints(minHeight: 44),
                ),
              ),
              // Продукт: выпадающий список из ячейки (не снизу экрана). Пустая строка = кнопка «Выбрать продукт».
              widget.canEdit && (ing.productName.isEmpty && !ing.hasData)
                  ? TableCell(
                      child: wrapCell(
                        Container(
                          color: firstColsBg,
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: _cellPad,
                          alignment: Alignment.centerLeft,
                          child: (widget.getProductsForDropdown != null && widget.onProductSelectedFromDropdown != null)
                              ? _ProductDropdownInCell(
                                  index: i,
                                  label: loc.t('ttk_choose_product'),
                                  getProducts: widget.getProductsForDropdown!,
                                  onSelected: widget.onProductSelectedFromDropdown!,
                                  lang: lang,
                                )
                              : const SizedBox.shrink(),
                        ),
                        fillColor: firstColsBg,
                      ),
                    )
                  : widget.canEdit && product == null
                      ? TableCell(
                          child: wrapCell(
                            Container(
                              color: firstColsBg,
                              constraints: const BoxConstraints(minHeight: 44),
                              padding: _cellPad,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Expanded(child: Text(ing.productName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                  if (widget.getProductsForDropdown != null && widget.onProductSelectedFromDropdown != null) ...[
                                    const SizedBox(width: 6),
                                    _ProductDropdownInCell(
                                      index: i,
                                      label: loc.t('ttk_choose_product'),
                                      getProducts: widget.getProductsForDropdown!,
                                      onSelected: widget.onProductSelectedFromDropdown!,
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
                      : TableCell(child: wrapCell(Container(color: firstColsBg, constraints: const BoxConstraints(minHeight: 44), padding: _cellPad, alignment: Alignment.centerLeft, child: Text(ing.sourceTechCardName ?? ing.productName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)), fillColor: firstColsBg, dataCell: true)),
              widget.canEdit
                  ? TableCell(
                      child: wrapCell(ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableGrossCell(
                            grams: ing.grossWeight,
                            onChanged: (g) {
                              if (g != null && g >= 0) widget.onUpdate(i, ing.copyWith(grossWeight: g));
                            },
                          ),
                        ),
                      )),
                    )
                  : _cell(ing.grossWeight.toStringAsFixed(0)),
              widget.canEdit
                  ? TableCell(
                      child: wrapCell(ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: _cellPad,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: _EditableWasteCell(
                                      value: ing.primaryWastePct,
                                      onChanged: (v) {
                                        if (v != null) widget.onUpdate(i, ing.copyWith(primaryWastePct: v.clamp(0.0, 99.9)));
                                      },
                                    ),
                                  ),
                                  if (product == null && ing.productName.trim().isNotEmpty && widget.onSuggestWaste != null)
                                    IconButton(
                                      icon: const Icon(Icons.auto_awesome, size: 18),
                                      tooltip: loc.t('ttk_suggest_waste'),
                                      onPressed: () => widget.onSuggestWaste!(i),
                                      style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(28, 28)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                    )
                  : _cell(ing.primaryWastePct.toStringAsFixed(0)),
              widget.canEdit
                  ? TableCell(
                      child: wrapCell(ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableNetCell(
                            value: ing.effectiveGrossWeight,
                            onChanged: (v) {
                              if (v != null && v >= 0) widget.onUpdate(i, ing.copyWith(manualEffectiveGross: v));
                            },
                          ),
                        ),
                      )),
                    )
                  : _cell('${ing.effectiveGrossWeight.toStringAsFixed(0)}'),
              widget.canEdit
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
                                      DropdownMenuItem(value: null, child: Text(loc.t('dash'))),
                                      ...CookingProcess.forCategory(product!.category).map((p) => DropdownMenuItem(
                                            value: p.id,
                                            child: Text(p.getLocalizedName(lang), overflow: TextOverflow.ellipsis),
                                          )),
                                    ]
                                  : [
                                      const DropdownMenuItem(value: null, child: Text('—')),
                                      ...CookingProcess.defaultProcesses.map((p) => DropdownMenuItem(
                                            value: p.id,
                                            child: Text(p.getLocalizedName(lang), overflow: TextOverflow.ellipsis),
                                          )),
                                      DropdownMenuItem(value: 'custom', child: Text(loc.t('cooking_custom'), overflow: TextOverflow.ellipsis)),
                                    ],
                              onChanged: (id) {
                                if (id == null) {
                                  widget.onUpdate(i, ing.copyWith(cookingProcessId: null, cookingProcessName: null));
                                } else if (id == 'custom') {
                                  widget.onUpdate(i, ing.copyWith(cookingProcessId: 'custom', cookingProcessName: loc.t('cooking_custom')));
                                } else {
                                  final p = CookingProcess.findById(id);
                                  if (p != null) {
                                    widget.onUpdate(i, ing.copyWith(
                                      cookingProcessId: p.id,
                                      cookingProcessName: p.getLocalizedName(lang),
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
              widget.canEdit
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
                                value: product != null ? ing.weightLossPercentage : (ing.cookingLossPctOverride ?? 0),
                                onChanged: (pct) {
                                  if (pct != null) widget.onUpdate(i, ing.copyWith(cookingLossPctOverride: pct.clamp(0.0, 99.9)));
                                },
                              ),
                            ],
                          ),
                        ),
                      )),
                    )
                  : _cell(ing.cookingProcessName != null ? ing.weightLossPercentage.toStringAsFixed(0) : loc.t('dash')),
              widget.canEdit
                  ? TableCell(
                      child: wrapCell(ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableNetCell(
                            value: ing.netWeight,
                            onChanged: (v) {
                              if (v != null && v >= 0) widget.onUpdate(i, ing.copyWith(netWeight: v));
                            },
                          ),
                        ),
                      )),
                    )
                  : _cell('${ing.netWeight.toStringAsFixed(0)}'),
              widget.canEdit
                  ? TableCell(
                      child: wrapCell(ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableCostCell(
                            cost: ing.cost,
                            symbol: sym,
                            onChanged: (v) {
                              if (v != null && v >= 0) widget.onUpdate(i, ing.copyWith(cost: v));
                            },
                          ),
                        ),
                      )),
                    )
                  : _cell(ing.cost.toStringAsFixed(2)),
              // Цена за 1 кг/шт блюда (по ингредиенту: стоимость за кг при выходе)
              _cell(ing.netWeight > 0 ? (ing.cost * 1000 / ing.netWeight).toStringAsFixed(2) : ''),
              // Колонка «Технология» — только в первой строке контент, в остальных пустая ячейка
              isFirstRow && widget.technologyController != null
                  ? TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: wrapCell(Container(
                        constraints: const BoxConstraints(minHeight: 120),
                        padding: _cellPad,
                        alignment: Alignment.topLeft,
                        child: TextField(
                          controller: widget.technologyController,
                          readOnly: !widget.canEdit,
                          maxLines: 8,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: loc.t('ttk_technology'),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  )
                  : TableCell(
                      child: wrapCell(Container(
                        constraints: const BoxConstraints(minHeight: 48, minWidth: 1),
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
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => widget.onRemove(i),
                      tooltip: loc.t('delete'),
                      style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(32, 32)),
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
            _totalCell(ingredients.fold<double>(0, (s, ing) => s + ing.effectiveGrossWeight).toStringAsFixed(0)),
            _totalCell(''),
            _totalCell(''),
            _totalCell(totalNet.toStringAsFixed(0)),
            _totalCell(totalCost.toStringAsFixed(2)),
            _totalCell(totalNet > 0 ? (totalCost * 1000 / totalNet).toStringAsFixed(2) : ''),
            _totalCell(''),
            if (hasDeleteCol) _totalCell(''),
          ],
        ),
      ],
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
              child: widget.canEdit && widget.dishNameController != null
                  ? TextField(
                      controller: widget.dishNameController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
                      ),
                      style: const TextStyle(fontSize: 12),
                    )
                  : Text(
                      widget.dishName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 10,
                    ),
            ),
          ),
        ],
      ),
    );

    // Панель с КБЖУ для PRO подписки
    if (hasProSubscription && (totalCalories > 0 || totalProtein > 0 || totalFat > 0 || totalCarbs > 0)) {
      return Column(
        children: [
          table,
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Питательная ценность блюда (на 100г)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _nutritionChip('Калории', '${totalCalories.round()} ккал', Colors.orange),
                    const SizedBox(width: 12),
                    _nutritionChip('Белки', '${totalProtein.toStringAsFixed(1)} г', Colors.red),
                    const SizedBox(width: 12),
                    _nutritionChip('Жиры', '${totalFat.toStringAsFixed(1)} г', Colors.yellow.shade700),
                    const SizedBox(width: 12),
                    _nutritionChip('Углеводы', '${totalCarbs.toStringAsFixed(1)} г', Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

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
              style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null),
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
        fillColor: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        dataCell: true,
      ),
    );
  }
}

/// Упрощённая таблица для повара (режим просмотра для сотрудников): Блюдо, Продукт, Нетто, Способ, Выход.
/// Внешний вид и структура — по референсу GitHub (Preps / dish / sv).
class _TtkCookTable extends StatefulWidget {
  const _TtkCookTable({
    required this.loc,
    required this.dishName,
    required this.ingredients,
    required this.technology,
    required this.onIngredientsChanged,
  });

  final LocalizationService loc;
  final String dishName;
  final List<TTIngredient> ingredients;
  final String technology;
  final void Function(List<TTIngredient> list) onIngredientsChanged;

  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  @override
  State<_TtkCookTable> createState() => _TtkCookTableState();
}

class _TtkCookTableState extends State<_TtkCookTable> {
  late List<TTIngredient> _ingredients;
  late double _totalOutput;

  @override
  void initState() {
    super.initState();
    _ingredients = List.from(widget.ingredients);
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.netWeight);
  }

  @override
  void didUpdateWidget(covariant _TtkCookTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ingredients != widget.ingredients) {
      _ingredients = List.from(widget.ingredients);
      _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.netWeight);
    }
  }

  void _scaleByOutput(double newOutput) {
    if (newOutput <= 0 || _totalOutput <= 0) return;
    final factor = newOutput / _totalOutput;
    _totalOutput = newOutput;
    _ingredients = _ingredients.map((i) => i.scaleBy(factor)).toList();
    widget.onIngredientsChanged(_ingredients);
  }

  void _updateNetAt(int index, double newNet) {
    if (index < 0 || index >= _ingredients.length) return;
    _ingredients[index] = _ingredients[index].updateNetWeightForCook(newNet);
    _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.netWeight);
    widget.onIngredientsChanged(_ingredients);
  }

  Widget _cell(String text, {bool bold = false}) {
    return TableCell(
      child: Padding(
        padding: _TtkCookTable._cellPad,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null), overflow: TextOverflow.ellipsis, maxLines: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.loc.currentLanguageCode;
    final totalCost = _ingredients.fold<double>(0, (s, i) => s + i.cost);
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final sym = currency == 'RUB' ? '₽' : currency == 'VND' ? '₫' : currency == 'USD' ? '\$' : currency;

    return Table(
      border: TableBorder.all(width: 0.5, color: Colors.grey),
      columnWidths: const {
        0: FixedColumnWidth(150),
        1: FixedColumnWidth(220),
        2: FixedColumnWidth(90),
        3: FixedColumnWidth(140),
        4: FixedColumnWidth(90),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)),
          children: [
            _cell(widget.loc.t('ttk_dish'), bold: true),
            _cell(widget.loc.t('ttk_product'), bold: true),
            _cell(widget.loc.t('ttk_net'), bold: true),
            _cell(widget.loc.t('ttk_cooking_method'), bold: true),
            _cell(widget.loc.t('ttk_output'), bold: true),
          ],
        ),
        if (_ingredients.isEmpty)
          TableRow(
            children: List.filled(5, TableCell(child: Padding(padding: _TtkCookTable._cellPad, child: Text(widget.loc.t('dash'), style: const TextStyle(fontSize: 12))))),
          )
        else
        ..._ingredients.asMap().entries.map((e) {
          final i = e.key;
          final ing = e.value;
          return TableRow(
            children: [
              _cell(i == 0 ? widget.dishName : (ing.sourceTechCardName ?? widget.loc.t('dash'))),
              _cell(ing.productName),
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
              _cell(ing.netWeight.toStringAsFixed(0)),
            ],
          );
        }),
        TableRow(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          children: [
            _cell(widget.loc.t('ttk_total'), bold: true),
            _cell(''),
            TableCell(
              child: Padding(
                padding: _TtkCookTable._cellPad,
                child: Text('${_totalOutput.toStringAsFixed(0)} ${widget.loc.t('gram')}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          ],
        ),
      ],
    );
  }
}

class _EditableNetCell extends StatefulWidget {
  const _EditableNetCell({required this.value, required this.onChanged});

  final double value;
  final void Function(double? v) onChanged;

  @override
  State<_EditableNetCell> createState() => _EditableNetCellState();
}

class _EditableNetCellState extends State<_EditableNetCell> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _EditableNetCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value.toStringAsFixed(0)) {
      _ctrl.text = widget.value.toStringAsFixed(0);
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
        ),
        style: const TextStyle(fontSize: 12),
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
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.products
        : widget.products
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.getLocalizedName(widget.lang).toLowerCase().contains(q))
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                      p.getLocalizedName(widget.lang),
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
          builder: (ctx) => _ProductSelectDialog(products: products, lang: lang),
        );
        if (selected != null && context.mounted) onSelected(index, selected);
      },
      icon: const Icon(Icons.arrow_drop_down, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: const Size(0, 36)),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.onPick});

  final List<Product> products;
  final void Function(Product p, double value, CookingProcess? proc, double waste, String unit, double? gramsPerPiece, {double? cookingLossPctOverride}) onPick;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    var list = widget.products;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q) || p.getLocalizedName(lang).toLowerCase().contains(q)).toList();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: InputDecoration(labelText: loc.t('search'), prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return ListTile(
                title: Text(p.getLocalizedName(lang)),
                subtitle: Text('${p.calories?.round() ?? 0} ${loc.t('kcal')} · ${CulinaryUnits.displayName((p.unit ?? 'g').trim().toLowerCase(), loc.currentLanguageCode)}'),
                onTap: () => _askWeight(p, loc),
              );
            },
          ),
        ),
      ],
    );
  }

  void _askWeight(Product p, LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    // По умолчанию на сайте везде граммы, не кг
    const defaultUnit = 'g';
    final c = TextEditingController(text: defaultUnit == 'pcs' ? '1' : '100');
    final gppController = TextEditingController(text: '50');
    final shrinkageController = TextEditingController();
    final processes = CookingProcess.forCategory(p.category);
    CookingProcess? selectedProcess;
    String selectedUnit = defaultUnit;
    showDialog<void>(
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
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: loc.t('quantity_label')),
                          autofocus: true,
                          onSubmitted: (_) => _submit(p, c.text, gppController.text, selectedProcess, selectedUnit, ctx, shrinkageController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: InputDecoration(isDense: true, labelText: loc.t('unit_short')),
                          items: CulinaryUnits.all.map((u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(CulinaryUnits.displayName(u.id, lang)),
                              )).toList(),
                          onChanged: (v) => setStateDlg(() => selectedUnit = v ?? 'g'),
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
                  Text(loc.t('cooking_process'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<CookingProcess?>(
                    value: selectedProcess,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      DropdownMenuItem(value: null, child: Text(loc.t('no_process'))),
                      ...processes.map((proc) => DropdownMenuItem(
                            value: proc,
                            child: Text('${proc.getLocalizedName(lang)} (−${proc.weightLossPercentage.toStringAsFixed(0)}%)'),
                          )),
                    ],
                    onChanged: (v) => setStateDlg(() {
                      selectedProcess = v;
                      if (v != null) shrinkageController.text = v.weightLossPercentage.toStringAsFixed(1);
                      else shrinkageController.text = '';
                    }),
                  ),
                  if (selectedProcess != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: shrinkageController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('ttk_cook_loss'),
                        hintText: selectedProcess?.weightLossPercentage.toStringAsFixed(1),
                        helperText: loc.t('ttk_cook_loss_override_hint'),
                      ),
                      onChanged: (_) => setStateDlg(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.t('back'))),
              FilledButton(
                onPressed: () => _submit(p, c.text, gppController.text, selectedProcess, selectedUnit, ctx, shrinkageController),
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
    if (x.contains('шт') || x.contains('pcs') || x.contains('штук')) return 'pcs';
    if (x.contains('кг') || x == 'kg') return 'kg';
    if (x.contains('л') || x == 'l') return 'l';
    if (x.contains('мл') || x == 'ml') return 'ml';
    return 'g';
  }

  void _submit(Product p, String val, String gppStr, CookingProcess? proc, String unit, BuildContext ctx, TextEditingController shrinkageController) {
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
      final entered = double.tryParse(shrinkageController.text.replaceFirst(',', '.'));
      if (entered != null && (entered - proc.weightLossPercentage).abs() > 0.01) {
        cookLossOverride = entered.clamp(0.0, 99.9);
      }
    }
    Navigator.of(ctx).pop();
    if (v > 0) widget.onPick(p, v, proc, waste, unit, gpp, cookingLossPctOverride: cookLossOverride);
  }
}

class _TechCardPicker extends StatelessWidget {
  const _TechCardPicker({required this.techCards, required this.onPick});

  final List<TechCard> techCards;
  final void Function(TechCard t, double value, String unit, double? gramsPerPiece) onPick;

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (techCards.isEmpty) {
      return Center(child: Text(loc.t('ttk_no_other_pf'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: techCards.length,
      itemBuilder: (_, i) {
        final t = techCards[i];
        return ListTile(
          title: Text(t.getDisplayNameInLists(lang)),
          subtitle: Text('${t.ingredients.length} ${loc.t('ingredients_short')} · ${t.totalCalories.round()} ${loc.t('kcal')}'),
          onTap: () => _askWeight(context, t),
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
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: loc.t('quantity_label')),
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: InputDecoration(isDense: true, labelText: loc.t('unit_short')),
                      items: CulinaryUnits.all.map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(CulinaryUnits.displayName(u.id, lang)),
                          )).toList(),
                      onChanged: (v) => setStateDlg(() => selectedUnit = v ?? 'g'),
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
                    decoration: InputDecoration(labelText: loc.t('g_pc'), hintText: loc.t('hint_50')),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.t('back'))),
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

