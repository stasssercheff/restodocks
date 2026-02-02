import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/culinary_units.dart';
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
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceFirst(',', '.'));
    setState(() => _editing = false);
    widget.onChanged(v != null ? v.clamp(0.0, 99.9) : null);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 56,
        child: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(isDense: true, suffixText: '%'),
          style: const TextStyle(fontSize: 13),
          onSubmitted: (_) => _submit(),
          onTapOutside: (_) => _submit(),
        ),
      );
    }
    return InkWell(
      onTap: () => setState(() {
        _editing = true;
        _ctrl.text = widget.value.toStringAsFixed(1);
        _ctrl.selectAll();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('−${widget.value.toStringAsFixed(0)}%'),
      ),
    );
  }
}

TechCard _applyEdits(
  TechCard t, {
  String? dishName,
  String? category,
  double? portionWeight,
  double? yieldGrams,
  List<TTIngredient>? ingredients,
}) {
  return t.copyWith(
    dishName: dishName,
    category: category,
    portionWeight: portionWeight,
    yield: yieldGrams,
    ingredients: ingredients,
  );
}

class TechCardEditScreen extends StatefulWidget {
  const TechCardEditScreen({super.key, required this.techCardId});

  /// Пусто для «новой», иначе id существующей ТТК.
  final String techCardId;

  @override
  State<TechCardEditScreen> createState() => _TechCardEditScreenState();
}

class _TechCardEditScreenState extends State<TechCardEditScreen> {
  TechCard? _techCard;
  bool _loading = true;
  String? _error;
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController(text: 'misc');
  final _portionController = TextEditingController(text: '100');
  final _yieldController = TextEditingController(text: '0');
  final List<TTIngredient> _ingredients = [];

  bool get _isNew => widget.techCardId.isEmpty || widget.techCardId == 'new';

  Future<void> _load() async {
    if (_isNew) {
      setState(() { _loading = false; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<ProductStoreSupabase>().loadProducts();
      final svc = context.read<TechCardServiceSupabase>();
      final tc = await svc.getTechCardById(widget.techCardId);
      if (!mounted) return;
      setState(() {
        _techCard = tc;
        _loading = false;
        if (tc != null) {
          _nameController.text = tc.dishName;
          _categoryController.text = tc.category;
          _portionController.text = tc.portionWeight.toStringAsFixed(0);
          _yieldController.text = tc.yield.toStringAsFixed(0);
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
    _categoryController.dispose();
    _portionController.dispose();
    _yieldController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название блюда')));
      return;
    }
    final portion = double.tryParse(_portionController.text) ?? 100;
    final yieldVal = double.tryParse(_yieldController.text) ?? 0;
    final category = _categoryController.text.trim().isEmpty ? 'misc' : _categoryController.text.trim();

    final tc = _techCard;
    final svc = context.read<TechCardServiceSupabase>();

    try {
      if (_isNew || tc == null) {
        final created = await svc.createTechCard(
          dishName: name,
          category: category,
          establishmentId: est.id,
          createdBy: emp.id,
        );
        var updated = _applyEdits(created, portionWeight: portion, yieldGrams: yieldVal, ingredients: _ingredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ТТК создана')));
          context.pushReplacement('/tech-cards/${created.id}');
        }
      } else {
        final updated = _applyEdits(tc, dishName: name, category: category, portionWeight: portion, yieldGrams: yieldVal, ingredients: _ingredients);
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocalizationService>().t('save') + ' ✓')));
          _load();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _showAddIngredient() async {
    final loc = context.read<LocalizationService>();
    final productStore = context.read<ProductStoreSupabase>();
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    await productStore.loadProducts();
    final techCards = await techCardSvc.getTechCardsForEstablishment(est.id);
    final excludeId = _isNew ? null : widget.techCardId;
    final tcs = excludeId == null ? techCards : techCards.where((t) => t.id != excludeId).toList();

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
              title: Text(loc.t('add_ingredient')),
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
                  onPick: (p, w, proc, waste, unit, gpp, {cookingLossPctOverride}) => _addProductIngredient(p, w, proc, waste, unit, gpp, cookingLossPctOverride: cookingLossPctOverride),
                ),
                _TechCardPicker(techCards: tcs, onPick: (t, w, unit, gpp) => _addTechCardIngredient(t, w, unit, gpp)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addProductIngredient(Product p, double value, CookingProcess? cookingProcess, double primaryWastePct, String unit, double? gramsPerPiece, {double? cookingLossPctOverride}) {
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
    setState(() => _ingredients.add(ing));
  }

  void _addTechCardIngredient(TechCard t, double weightG) {
    Navigator.of(context).pop();
    final totalNet = t.totalNetWeight;
    if (totalNet <= 0) return;
    final loc = context.read<LocalizationService>();
    final ing = TTIngredient.fromTechCardData(
      techCardId: t.id,
      techCardName: t.getLocalizedDishName(loc.currentLanguageCode),
      totalNetWeight: totalNet,
      totalCalories: t.totalCalories,
      totalProtein: t.totalProtein,
      totalFat: t.totalFat,
      totalCarbs: t.totalCarbs,
      totalCost: t.totalCost,
      grossWeight: weightG,
    );
    setState(() => _ingredients.add(ing));
  }

  void _removeIngredient(int i) {
    setState(() => _ingredients.removeAt(i));
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
        title: Text(_isNew ? loc.t('create_tech_card') : loc.t('tech_cards')),
        actions: [
          if (canEdit) IconButton(icon: const Icon(Icons.save), onPressed: _save, tooltip: loc.t('save')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              readOnly: !canEdit,
              decoration: InputDecoration(labelText: loc.t('dish_name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              readOnly: !canEdit,
              decoration: const InputDecoration(labelText: 'Категория'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portionController,
              readOnly: !canEdit,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: loc.t('portion_weight')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yieldController,
              readOnly: !canEdit,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: loc.t('yield_g')),
            ),
            if (canEdit) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loc.t('add_ingredient'), style: Theme.of(context).textTheme.titleMedium),
                  FilledButton.icon(
                    onPressed: _showAddIngredient,
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(loc.t('add_ingredient')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
                columns: [
                  DataColumn(label: Text(loc.t('ttk_product'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_gross'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_waste_pct'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_net'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_process'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_cook_loss'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_output'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text(loc.t('ttk_price'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (canEdit) const DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: List.generate(_ingredients.length + 1, (i) {
                  if (i == _ingredients.length) {
                    final totalNet = _ingredients.fold<double>(0, (s, ing) => s + ing.netWeight);
                    final totalCost = _ingredients.fold<double>(0, (s, ing) => s + ing.cost);
                    final totalCal = _ingredients.fold<double>(0, (s, ing) => s + ing.finalCalories);
                    return DataRow(
                      color: WidgetStateProperty.all(Colors.amber.shade100),
                      cells: [
                        DataCell(Text(loc.t('ttk_total'), style: const TextStyle(fontWeight: FontWeight.bold))),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        DataCell(Text(totalNet.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w600))),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        DataCell(Text(totalNet.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('${totalCost.toStringAsFixed(2)} ₽', style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (canEdit) const DataCell(Text('')),
                      ],
                    );
                  }
                  final ing = _ingredients[i];
                  final product = ing.productId != null ? context.read<ProductStoreSupabase>().allProducts.where((p) => p.id == ing.productId).firstOrNull : null;
                  final proc = ing.cookingProcessId != null ? CookingProcess.findById(ing.cookingProcessId!) : null;
                  return DataRow(
                    cells: [
                      DataCell(Text(ing.productName)),
                      DataCell(Text(ing.grossWeightDisplay(loc.currentLanguageCode))),
                      DataCell(Text(ing.primaryWastePct == 0 ? '0' : ing.primaryWastePct.toStringAsFixed(1))),
                      DataCell(Text('${ing.netWeight.toStringAsFixed(0)} г')),
                      DataCell(Text(ing.cookingProcessName ?? '—')),
                      DataCell(
                        canEdit && ing.cookingProcessName != null && proc != null
                            ? _EditableShrinkageCell(
                                value: ing.weightLossPercentage,
                                onChanged: (pct) {
                                  final updated = ing.updateCookingLossPct(pct, product, proc, languageCode: loc.currentLanguageCode);
                                  setState(() => _ingredients[i] = updated);
                                },
                              )
                            : Text(ing.cookingProcessName != null ? '−${ing.weightLossPercentage.toStringAsFixed(0)}%' : '—'),
                      ),
                      DataCell(Text('${ing.netWeight.toStringAsFixed(0)} г')),
                      DataCell(Text('${ing.cost.toStringAsFixed(2)} ₽')),
                      if (canEdit)
                        DataCell(IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: () => _removeIngredient(i),
                          tooltip: loc.t('delete'),
                        )),
                    ],
                  );
                }),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: Text(loc.t('save'))),
            ],
          ],
        ),
      ),
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
                subtitle: Text('${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}'),
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
    final wasteController = TextEditingController(text: '0');
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
                          onSubmitted: (_) => _submit(p, c.text, wasteController.text, gppController.text, selectedProcess, selectedUnit, ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          decoration: const InputDecoration(isDense: true, labelText: 'Ед.'),
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
                        labelText: 'г/шт',
                        hintText: '50',
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
      return Center(child: Text('Нет других ТТК. Создайте полуфабрикаты и добавляйте их как ингредиенты.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: techCards.length,
      itemBuilder: (_, i) {
        final t = techCards[i];
        return ListTile(
          title: Text(t.getLocalizedDishName(lang)),
          subtitle: Text('${t.ingredients.length} ингр. · ${t.totalCalories.round()} ккал'),
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
                      decoration: const InputDecoration(isDense: true, labelText: 'Ед.'),
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
                    decoration: const InputDecoration(labelText: 'г/шт', hintText: '50'),
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
