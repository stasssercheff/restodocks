import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/culinary_units.dart';
import '../models/tt_ingredient.dart';
import '../services/ai_service.dart';
import '../services/services.dart';

/// Создание или редактирование ТТК. Ингредиенты — из номенклатуры или из других ТТК (ПФ).

class _EditableShrinkageCell extends StatefulWidget {
  const _EditableShrinkageCell({required this.value, required this.onChanged});

  final double value;
  final void Function(double? pct) onChanged;

  @override
  State<_EditableShrinkageCell> createState() => _EditableShrinkageCellState();
}

class _EditableShrinkageCellState extends State<_EditableShrinkageCell> {
  late TextEditingController _ctrl;

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
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: '%',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
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
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: '%',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
    );
  }
}

/// Редактируемая ячейка названия продукта (для ручной строки без продукта из справочника).
class _EditableProductNameCell extends StatefulWidget {
  const _EditableProductNameCell({required this.value, required this.onChanged});

  final String value;
  final void Function(String) onChanged;

  @override
  State<_EditableProductNameCell> createState() => _EditableProductNameCellState();
}

class _EditableProductNameCellState extends State<_EditableProductNameCell> {
  late TextEditingController _ctrl;

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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Редактируемая ячейка брутто (граммы)
class _EditableGrossCell extends StatefulWidget {
  const _EditableGrossCell({required this.grams, required this.onChanged});

  final double grams;
  final void Function(double? g) onChanged;

  @override
  State<_EditableGrossCell> createState() => _EditableGrossCellState();
}

class _EditableGrossCellState extends State<_EditableGrossCell> {
  late TextEditingController _ctrl;

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
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: 'г',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
    );
  }
}

/// Редактируемая ячейка «Цена за кг» (пересчёт стоимости из цены и нетто)
class _EditablePricePerKgCell extends StatefulWidget {
  const _EditablePricePerKgCell({
    required this.pricePerKg,
    required this.netWeight,
    required this.symbol,
    required this.onChanged,
  });

  final double pricePerKg;
  final double netWeight;
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
    if (v != null && v >= 0 && widget.netWeight > 0) {
      widget.onChanged(v * widget.netWeight / 1000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.symbol,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
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
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.symbol,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
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
  final _nameController = TextEditingController();
  static const _categoryOptions = ['misc', 'vegetables', 'fruits', 'meat', 'seafood', 'dairy', 'grains', 'bakery', 'pantry', 'spices', 'beverages', 'eggs', 'legumes', 'nuts'];
  String _selectedCategory = 'misc';
  bool _isSemiFinished = true; // ПФ или блюдо (порция — в карточках блюд, отдельно)
  final _technologyController = TextEditingController();
  final List<TTIngredient> _ingredients = [];
  List<TechCard> _pickerTechCards = [];

  bool get _isNew => widget.techCardId.isEmpty || widget.techCardId == 'new';

  String _categoryLabel(String c, String lang) {
    if (lang == 'ru') {
      const map = {
        'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
        'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
        'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
        'nuts': 'Орехи', 'misc': 'Разное',
      };
      return map[c] ?? c;
    }
    return c == 'misc' ? 'misc' : c;
  }

  /// Простой вывод категории из названия блюда (для предзаполнения из ИИ).
  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (lower.contains('овощ') || lower.contains('vegetable') || lower.contains('салат')) return 'vegetables';
    if (lower.contains('фрукт') || lower.contains('fruit') || lower.contains('ягод')) return 'fruits';
    if (lower.contains('мяс') || lower.contains('meat') || lower.contains('куриц') || lower.contains('говядин')) return 'meat';
    if (lower.contains('рыб') || lower.contains('fish') || lower.contains('море')) return 'seafood';
    if (lower.contains('молок') || lower.contains('dairy') || lower.contains('сыр') || lower.contains('cream')) return 'dairy';
    if (lower.contains('круп') || lower.contains('grain') || lower.contains('рис') || lower.contains('макарон')) return 'grains';
    if (lower.contains('выпеч') || lower.contains('bakery') || lower.contains('хлеб') || lower.contains('тест')) return 'bakery';
    if (lower.contains('напит') || lower.contains('beverage') || lower.contains('сок') || lower.contains('компот')) return 'beverages';
    if (lower.contains('специ') || lower.contains('spice')) return 'spices';
    if (lower.contains('яйц') || lower.contains('egg')) return 'eggs';
    if (lower.contains('боб') || lower.contains('legume')) return 'legumes';
    if (lower.contains('орех') || lower.contains('nut')) return 'nuts';
    return 'misc';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<ProductStoreSupabase>().loadProducts();
      final est = context.read<AccountManagerSupabase>().establishment;
      if (est != null) {
        final tcs = await context.read<TechCardServiceSupabase>().getTechCardsForEstablishment(est.id);
        if (mounted) {
          _pickerTechCards = _isNew ? tcs : tcs.where((t) => t.id != widget.techCardId).toList();
        }
      }
      if (_isNew) {
        if (mounted) {
          final ai = widget.initialFromAi;
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
          }
          setState(() { _loading = false; });
        }
        return;
      }
      final svc = context.read<TechCardServiceSupabase>();
      final tc = await svc.getTechCardById(widget.techCardId);
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
        }
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _technologyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
    final yieldVal = _ingredients.isEmpty ? 0.0 : _ingredients.fold(0.0, (s, i) => s + i.netWeight);
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
        var updated = _applyEdits(created, portionWeight: portion, yieldGrams: yieldVal, technologyLocalized: techMap, ingredients: _ingredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('tech_card_created'))));
          context.pushReplacement('/tech-cards/${created.id}');
        }
      } else {
        final updated = _applyEdits(tc, dishName: name, category: category, isSemiFinished: _isSemiFinished, portionWeight: portion, yieldGrams: yieldVal, technologyLocalized: techMap, ingredients: _ingredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocalizationService>().t('save') + ' ✓')));
          _load();
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

  /// [replaceIndex] — если задан, заменяем строку вместо добавления (тап по ячейке «Продукт»).
  Future<void> _showAddIngredient([int? replaceIndex]) async {
    final loc = context.read<LocalizationService>();
    final productStore = context.read<ProductStoreSupabase>();
    await productStore.loadProducts();

    if (!mounted) return;
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
                  products: productStore.allProducts,
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

  void _addProductIngredient(Product p, double value, CookingProcess? cookingProcess, double primaryWastePct, String unit, double? gramsPerPiece, {int? replaceIndex, double? cookingLossPctOverride}) {
    Navigator.of(context).pop();
    final loc = context.read<LocalizationService>();
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final ing = TTIngredient.fromProduct(
      product: p,
      cookingProcess: cookingProcess,
      grossWeight: value,
      netWeight: null,
      primaryWastePct: primaryWastePct,
      defaultCurrency: currency,
      languageCode: loc.currentLanguageCode,
      unit: unit,
      gramsPerPiece: gramsPerPiece,
      cookingLossPctOverride: cookingLossPctOverride,
    );
    setState(() {
      if (replaceIndex != null && replaceIndex >= 0 && replaceIndex < _ingredients.length) {
        _ingredients[replaceIndex] = ing;
      } else {
        _ingredients.add(ing);
      }
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
      techCardName: t.getLocalizedDishName(loc.currentLanguageCode),
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
    });
  }

  /// Добавить пустую строку ингредиента (ввод вручную: название, брутто, отход %, нетто, способ приготовления, стоимость).
  void _addEmptyIngredientRow() {
    final ing = TTIngredient.fromProduct(
      product: null,
      grossWeight: 0,
      netWeight: 0,
      primaryWastePct: 0,
      defaultCurrency: 'RUB',
      unit: 'g',
    );
    setState(() => _ingredients.add(ing));
  }

  void _removeIngredient(int i) {
    setState(() => _ingredients.removeAt(i));
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
    if (_loading && !_isNew) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('tech_cards'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && !_isNew) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('tech_cards'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(_error!), const SizedBox(height: 16), FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back')))]))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(_isNew ? loc.t('create_tech_card') : (_techCard?.getLocalizedDishName(loc.currentLanguageCode) ?? loc.t('tech_cards'))),
        actions: [
          if (canEdit) IconButton(icon: const Icon(Icons.save), onPressed: _save, tooltip: loc.t('save')),
          if (canEdit && !_isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirmDelete(context, loc), tooltip: loc.t('delete_tech_card')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 500;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Шапка: название, категория, тип — на узком экране колонкой, на широком строкой
                if (narrow) ...[
                  TextField(
                    controller: _nameController,
                    readOnly: !canEdit,
                    decoration: InputDecoration(
                      labelText: loc.t('dish_name'),
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
                              labelText: loc.t('dish_name'),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(loc.t('ttk_composition'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                if (canEdit) ...[
                  FilledButton.tonalIcon(
                    onPressed: _addEmptyIngredientRow,
                    icon: const Icon(Icons.edit_note, size: 20),
                    label: Text(loc.t('ttk_add_row_manual')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _showAddIngredient,
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(loc.t('add_ingredient')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Таблица: высота растёт с числом строк (шапка + строки + итого), но не больше ~70% экрана; при 20+ ингредиентах прокрутка внутри
            LayoutBuilder(
              builder: (context, c) {
                final screenH = MediaQuery.of(context).size.height;
                final rowCount = 1 + (_ingredients.isEmpty ? 1 : _ingredients.length) + 1 + 1;
                const rowHeight = 44.0;
                final maxH = (screenH * 0.7).clamp(300.0, 900.0);
                final desiredH = (rowCount * rowHeight).clamp(220.0, maxH);
                return SizedBox(
                  height: desiredH,
                  child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1400),
                      child: canEdit
                        ? _TtkTable(
                            loc: loc,
                            dishName: _nameController.text,
                            isSemiFinished: _isSemiFinished,
                            ingredients: _ingredients,
                            canEdit: true,
                            onRemove: _removeIngredient,
                            onUpdate: (i, ing) => setState(() => _ingredients[i] = ing),
                            onAdd: _showAddIngredient,
                            onReplaceIngredient: (i) => _showAddIngredient(i),
                            dishNameController: canEdit ? _nameController : null,
                            onSuggestWaste: _suggestWasteForRow,
                            productStore: context.read<ProductStoreSupabase>(),
                            technologyField: TextField(
                              controller: _technologyController,
                              maxLines: 4,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: loc.t('ttk_technology'),
                                isDense: true,
                                contentPadding: const EdgeInsets.all(8),
                                border: InputBorder.none,
                                filled: true,
                                fillColor: Colors.transparent,
                              ),
                            ),
                          )
                        : _TtkCookTable(
                            loc: loc,
                            dishName: _nameController.text,
                            ingredients: _ingredients,
                            technology: _technologyController.text,
                            onIngredientsChanged: (list) => setState(() {
                              _ingredients.clear();
                              _ingredients.addAll(list);
                            }),
                          ),
                  ),
                ),
              ),
            );
          },
            ),
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  controller: _technologyController,
                  readOnly: true,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: loc.t('ttk_technology'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (canEdit) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(onPressed: _save, child: Text(loc.t('save'))),
                  if (!_isNew) ...[
                    const SizedBox(width: 16),
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                      label: Text(loc.t('delete_tech_card'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      onPressed: () => _confirmDelete(context, loc),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    },
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
    required this.productStore,
    this.technologyField,
    this.onReplaceIngredient,
    this.dishNameController,
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
  final ProductStoreSupabase productStore;
  final Widget? technologyField;
  /// Тап по ячейке «Продукт» — замена ингредиента (поиск + выбор продукта/ПФ).
  final void Function(int i)? onReplaceIngredient;
  /// Контроллер названия блюда — первая ячейка первой строки редактируется по нему.
  final TextEditingController? dishNameController;
  /// Для ручной строки (без продукта): подсказка ИИ по проценту отхода.
  final void Function(int i)? onSuggestWaste;

  @override
  State<_TtkTable> createState() => _TtkTableState();
}

class _TtkTableState extends State<_TtkTable> {
  /// Пустых строк в конце: при начале заполнения последней добавляется ещё одна
  int _emptyRowCount = 1;

  @override
  void didUpdateWidget(covariant _TtkTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ingredients.length > oldWidget.ingredients.length) {
      setState(() => _emptyRowCount = 1);
    }
  }

  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = widget.loc;
    final lang = loc.currentLanguageCode;
    final ingredients = widget.ingredients;
    final totalNet = ingredients.fold<double>(0, (s, ing) => s + ing.netWeight);
    final totalCost = ingredients.fold<double>(0, (s, ing) => s + ing.cost);
    final pricePerKgDish = totalNet > 0 ? totalCost * 1000 / totalNet : 0.0;
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final sym = currency == 'RUB' ? '₽' : currency == 'VND' ? '₫' : currency == 'USD' ? '\$' : currency;

    const colCount = 12;
    final hasDeleteCol = widget.canEdit;
    final totalCols = hasDeleteCol ? colCount + 1 : colCount;
    return Table(
      border: TableBorder.all(width: 0.5, color: Colors.grey),
      columnWidths: {
        0: const FlexColumnWidth(1.4),   // Наименование блюда
        1: const FlexColumnWidth(2.2),   // Продукт (поиск + список)
        2: const FlexColumnWidth(0.9),   // Брутто гр/шт
        3: const FlexColumnWidth(0.6),   // Отход %
        4: const FlexColumnWidth(0.9),   // Нетто гр/шт
        5: const FlexColumnWidth(1.4),   // Способ приготовления
        6: const FlexColumnWidth(0.6),   // Ужарка %
        7: const FlexColumnWidth(0.9),   // Выход гр/шт
        8: const FlexColumnWidth(1.0),   // Цена за кг/шт
        9: const FlexColumnWidth(0.9),   // Стоимость
        10: const FlexColumnWidth(1.0),  // Цена за 1 кг/шт блюда
        11: const FlexColumnWidth(2.0),  // Технология
        if (hasDeleteCol) 12: const FlexColumnWidth(0.4),
      },
      defaultColumnWidth: const FlexColumnWidth(0.6),
      children: [
        // Серая шапка как в документе
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade300),
          children: [
            _cell(loc.t('ttk_dish_name_col'), bold: true),
            _cell(loc.t('ttk_product'), bold: true),
            _cell(loc.t('ttk_gross_gr'), bold: true),
            _cell(loc.t('ttk_waste_pct'), bold: true),
            _cell(loc.t('ttk_net_gr'), bold: true),
            _cell(loc.t('ttk_cooking_method'), bold: true),
            _cell(loc.t('ttk_cook_loss'), bold: true),
            _cell(loc.t('ttk_output_gr'), bold: true),
            _cell(loc.t('ttk_price_per_kg'), bold: true),
            _cell(loc.t('ttk_cost'), bold: true),
            _cell(loc.t('ttk_price_per_1kg_dish_full'), bold: true),
            _cell(loc.t('ttk_technology'), bold: true),
            if (hasDeleteCol) _cell('', bold: true),
          ],
        ),
        // Если ингредиентов нет — одна строка с названием блюда и технологией (всегда показываем при пустом составе)
        if (ingredients.isEmpty)
          TableRow(
            children: [
              widget.canEdit && widget.dishNameController != null
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: TextField(
                            controller: widget.dishNameController,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              filled: true,
                              fillColor: Colors.transparent,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  : _cell(widget.dishName),
              ...List.generate(10, (_) => _cell('')),
              widget.technologyField != null
                  ? TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: SizedBox.expand(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 80),
                          padding: _cellPad,
                          alignment: Alignment.topLeft,
                          child: widget.technologyField,
                        ),
                      ),
                    )
                  : _cell(''),
              if (hasDeleteCol) _cell(''),
            ],
          ),
        ...ingredients.asMap().entries.map((e) {
          final i = e.key;
          final ing = e.value;
          final product = ing.productId != null ? widget.productStore.allProducts.where((p) => p.id == ing.productId).firstOrNull : null;
          final proc = ing.cookingProcessId != null ? CookingProcess.findById(ing.cookingProcessId!) : null;
          final pricePerUnit = product?.basePrice ?? (ing.netWeight > 0 ? ing.cost * 1000 / ing.netWeight : 0.0);
          final nettoG = ing.effectiveGrossWeight;
          final isFirstRow = i == 0;
          return TableRow(
            children: [
              // Наименование блюда — в первой строке редактируемое поле (или текст)
              widget.canEdit && isFirstRow && widget.dishNameController != null
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: TextField(
                            controller: widget.dishNameController,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              filled: true,
                              fillColor: Colors.transparent,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  : _cell(isFirstRow ? widget.dishName : ''),
              widget.canEdit && product == null
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableProductNameCell(
                            value: ing.productName,
                            onChanged: (s) => widget.onUpdate(i, ing.copyWith(productName: s)),
                          ),
                        ),
                      ),
                    )
                  : widget.canEdit && widget.onReplaceIngredient != null
                      ? TableCell(
                          child: InkWell(
                            onTap: () => widget.onReplaceIngredient!(i),
                            child: Padding(
                              padding: _cellPad,
                              child: Text(
                                ing.sourceTechCardName ?? ing.productName,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                      : _cell(ing.sourceTechCardName ?? ing.productName),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableGrossCell(
                            grams: ing.grossWeight,
                            onChanged: (g) {
                              if (g != null && g >= 0) {
                                if (product != null) {
                                  widget.onUpdate(i, ing.updateGrossWeight(g, product, proc));
                                } else {
                                  final net = g * (1.0 - ing.primaryWastePct.clamp(0.0, 99.9) / 100.0);
                                  widget.onUpdate(i, ing.copyWith(grossWeight: g, netWeight: net));
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    )
                  : _cell(ing.grossWeightDisplay(lang)),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: _EditableWasteCell(
                                  value: ing.primaryWastePct,
                                  onChanged: (v) {
                                    final waste = (v ?? ing.primaryWastePct).clamp(0.0, 99.9);
                                    if (product != null) {
                                      widget.onUpdate(i, ing.updatePrimaryWastePct(waste, product, proc));
                                    } else {
                                      final net = ing.grossWeight * (1.0 - waste / 100.0);
                                      widget.onUpdate(i, ing.copyWith(primaryWastePct: waste, netWeight: net, isNetWeightManual: false));
                                    }
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
                        ),
                      ),
                    )
                  : _cell(ing.primaryWastePct.toStringAsFixed(0)),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableNetCell(
                            value: ing.netWeight,
                            onChanged: (v) {
                              if (v != null && v >= 0) {
                                if (product != null) {
                                  widget.onUpdate(i, ing.updateNetWeight(v, product));
                                } else {
                                  widget.onUpdate(i, ing.copyWith(netWeight: v, isNetWeightManual: true));
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    )
                  : _cell('${nettoG.toStringAsFixed(0)}'),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
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
                                if (product != null) {
                                  final p = id != null && id != 'custom' ? CookingProcess.findById(id) : null;
                                  widget.onUpdate(i, ing.updateCookingProcess(p, product, languageCode: lang));
                                } else {
                                  if (id == null) {
                                    widget.onUpdate(i, ing.copyWith(cookingProcessId: null, cookingProcessName: null, cookingLossPctOverride: null));
                                  } else if (id == 'custom') {
                                    widget.onUpdate(i, ing.copyWith(cookingProcessId: 'custom', cookingProcessName: loc.t('cooking_custom'), cookingLossPctOverride: ing.cookingLossPctOverride));
                                  } else {
                                    final p = CookingProcess.findById(id);
                                    if (p != null) {
                                      widget.onUpdate(i, ing.copyWith(
                                        cookingProcessId: p.id,
                                        cookingProcessName: p.getLocalizedName(lang),
                                        cookingLossPctOverride: p.weightLossPercentage,
                                      ));
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    )
                  : _cell(ing.cookingProcessName ?? loc.t('dash')),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableShrinkageCell(
                            value: product != null ? ing.weightLossPercentage : (ing.cookingLossPctOverride ?? 0),
                            onChanged: (pct) {
                              if (product != null && proc != null) {
                                widget.onUpdate(i, ing.updateCookingLossPct(pct, product, proc, languageCode: lang));
                              } else {
                                widget.onUpdate(i, ing.copyWith(cookingLossPctOverride: pct));
                              }
                            },
                          ),
                        ),
                      ),
                    )
                  : _cell(ing.cookingProcessName != null ? '−${ing.weightLossPercentage.toStringAsFixed(0)}%' : loc.t('dash')),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditableNetCell(
                            value: ing.netWeight,
                            onChanged: (v) {
                              if (v != null && v >= 0) widget.onUpdate(i, ing.updateNetWeight(v, product));
                            },
                          ),
                        ),
                      ),
                    )
                  : _cell('${ing.netWeight.toStringAsFixed(0)}'),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: _cellPad,
                          child: _EditablePricePerKgCell(
                          pricePerKg: pricePerUnit,
                          netWeight: ing.netWeight,
                          symbol: sym,
                          onChanged: (cost) {
                            if (cost != null && cost >= 0) widget.onUpdate(i, ing.copyWith(cost: cost));
                          },
                        ),
                      ),
                      ),
                    )
                  : _cell('$pricePerUnit $sym'),
              widget.canEdit
                  ? TableCell(
                      child: SizedBox.expand(
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
                      ),
                    )
                  : _cell('${ing.cost.toStringAsFixed(2)} $sym'),
              _cell(pricePerKgDish.toStringAsFixed(2) + ' $sym'),
              // Технология — только в первой строке, высокая ячейка
              isFirstRow && widget.technologyField != null
                  ? TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 80),
                        padding: _cellPad,
                        alignment: Alignment.topLeft,
                        child: widget.technologyField,
                      ),
                    )
                  : _cell(''),
              if (hasDeleteCol)
                TableCell(
                  child: Padding(
                    padding: _cellPad,
                    child: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => widget.onRemove(i),
                      tooltip: loc.t('delete'),
                      style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(32, 32)),
                    ),
                  ),
                ),
            ],
          );
        }),
        // Пустые строки: при начале заполнения последней появляется ещё одна (без кнопки «+»)
        if (widget.canEdit)
          ...List.generate(_emptyRowCount, (int k) {
            final isLastEmpty = k == _emptyRowCount - 1;
            return TableRow(
              children: [
                _cell(''),
                TableCell(
                  child: InkWell(
                    onTap: () {
                      if (isLastEmpty) setState(() => _emptyRowCount++);
                      widget.onAdd();
                    },
                    child: Padding(
                      padding: _cellPad,
                      child: Text(
                        loc.t('ttk_add_hint'),
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
                ),
                ...List.generate(totalCols - 2, (_) => _cell('')),
                if (hasDeleteCol) _cell(''),
              ],
            );
          }),
        // Итого — жёлтая строка как в документе
        TableRow(
          decoration: BoxDecoration(color: Colors.amber.shade100),
          children: [
            _cell('', bold: true),
            _cell(loc.t('ttk_total'), bold: true),
            _cell('', bold: true),
            _cell('', bold: true),
            _cell('${ingredients.fold<double>(0, (s, ing) => s + ing.effectiveGrossWeight).toStringAsFixed(0)}', bold: true),
            _cell('', bold: true),
            _cell('', bold: true),
            _cell('${totalNet.toStringAsFixed(0)}', bold: true),
            _cell('', bold: true),
            _cell('${totalCost.toStringAsFixed(2)} $sym', bold: true),
            _cell('${pricePerKgDish.toStringAsFixed(2)} $sym', bold: true),
            _cell('', bold: true),
            if (hasDeleteCol) _cell('', bold: true),
          ],
        ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) {
    return TableCell(
      child: Padding(
        padding: _cellPad,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null), overflow: TextOverflow.ellipsis, maxLines: 2),
      ),
    );
  }
}

/// Упрощённая таблица для повара: Блюдо, Продукт, Нетто (редакт.), Способ, Выход (редакт.), Технология
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
    setState(() {
      _totalOutput = newOutput;
      _ingredients = _ingredients.map((i) => i.scaleBy(factor)).toList();
      widget.onIngredientsChanged(_ingredients);
    });
  }

  void _updateNetAt(int index, double newNet) {
    if (index < 0 || index >= _ingredients.length) return;
    setState(() {
      _ingredients[index] = _ingredients[index].updateNetWeightForCook(newNet);
      _totalOutput = _ingredients.fold<double>(0, (s, i) => s + i.netWeight);
      widget.onIngredientsChanged(_ingredients);
    });
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
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(0.9),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)),
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
              _cell('${ing.netWeight.toStringAsFixed(0)} г'),
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
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    widget.onChanged(v != null && v >= 0 ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: 'г',
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
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
                subtitle: Text('${p.calories?.round() ?? 0} ${loc.t('kcal')} · ${p.unit ?? loc.t('kg')}'),
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
    String defaultUnit = _productUnitToCulinary(p.unit);
    final c = TextEditingController(text: defaultUnit == 'pcs' ? '1' : '100');
    final wasteController = TextEditingController(text: '${p.primaryWastePct?.toStringAsFixed(1) ?? '0'}');
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
                          onSubmitted: (_) => _submit(p, c.text, wasteController.text, gppController.text, selectedProcess, selectedUnit, ctx, shrinkageController),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: wasteController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: loc.t('waste_pct'), hintText: '0'),
                  ),
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
                onPressed: () => _submit(p, c.text, wasteController.text, gppController.text, selectedProcess, selectedUnit, ctx, shrinkageController),
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

  void _submit(Product p, String val, String wasteStr, String gppStr, CookingProcess? proc, String unit, BuildContext ctx, TextEditingController shrinkageController) {
    final v = double.tryParse(val.replaceFirst(',', '.')) ?? 0;
    final waste = (double.tryParse(wasteStr) ?? 0).clamp(0.0, 99.9);
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
          title: Text(t.getLocalizedDishName(lang)),
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
          title: Text(t.getLocalizedDishName(lang)),
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
