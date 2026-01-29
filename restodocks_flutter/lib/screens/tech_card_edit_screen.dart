import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Создание или редактирование ТТК. Ингредиенты — из номенклатуры или из других ТТК (ПФ).
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
        var updated = created.copyWith(
          portionWeight: portion,
          yield: yieldVal,
          ingredients: _ingredients,
        );
        await svc.saveTechCard(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ТТК создана')));
          context.pushReplacement('/tech-cards/${created.id}');
        }
      } else {
        final updated = tc.copyWith(
          dishName: name,
          category: category,
          portionWeight: portion,
          yield: yieldVal,
          ingredients: _ingredients,
        );
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
                _ProductPicker(products: productStore.allProducts, onPick: (p, w) => _addProductIngredient(p, w)),
                _TechCardPicker(techCards: tcs, onPick: (t, w) => _addTechCardIngredient(t, w)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addProductIngredient(Product p, double weightG) {
    Navigator.of(context).pop();
    final loc = context.read<LocalizationService>();
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final ing = TTIngredient.fromProduct(
      product: p,
      cookingProcess: null,
      grossWeight: weightG,
      netWeight: null,
      defaultCurrency: currency,
    );
    setState(() => _ingredients.add(ing));
  }

  void _addTechCardIngredient(TechCard t, double weightG) {
    Navigator.of(context).pop();
    final totalNet = t.totalNetWeight;
    if (totalNet <= 0) return;
    final ing = TTIngredient.fromTechCardData(
      techCardId: t.id,
      techCardName: t.dishName,
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
            ...List.generate(_ingredients.length, (i) {
              final ing = _ingredients[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(ing.productName),
                  subtitle: Text('${ing.grossWeight.toStringAsFixed(0)} г · ${ing.finalCalories.round()} ккал · ${ing.cost.toStringAsFixed(2)} ₽'),
                  trailing: canEdit
                      ? IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeIngredient(i), tooltip: loc.t('delete'))
                      : null,
                ),
              );
            }),
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
  final void Function(Product p, double weightG) onPick;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    var list = widget.products;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q) || (p.names?['ru'] ?? '').toLowerCase().contains(q)).toList();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(labelText: 'Поиск', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return ListTile(
                title: Text(p.name),
                subtitle: Text('${p.calories?.round() ?? 0} ккал · ${p.unit ?? 'кг'}'),
                onTap: () => _askWeight(p),
              );
            },
          ),
        ),
      ],
    );
  }

  void _askWeight(Product p) {
    final c = TextEditingController(text: '100');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.read<LocalizationService>().t('weight_g')),
          autofocus: true,
          onSubmitted: (_) => _submitWeight(p, c.text, ctx),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.read<LocalizationService>().t('back'))),
          FilledButton(onPressed: () => _submitWeight(p, c.text, ctx), child: Text(context.read<LocalizationService>().t('save'))),
        ],
      ),
    );
  }

  void _submitWeight(Product p, String s, BuildContext ctx) {
    final w = double.tryParse(s) ?? 0;
    Navigator.of(ctx).pop();
    if (w > 0) widget.onPick(p, w);
  }
}

class _TechCardPicker extends StatelessWidget {
  const _TechCardPicker({required this.techCards, required this.onPick});

  final List<TechCard> techCards;
  final void Function(TechCard t, double weightG) onPick;

  @override
  Widget build(BuildContext context) {
    if (techCards.isEmpty) {
      return Center(child: Text('Нет других ТТК. Создайте полуфабрикаты и добавляйте их как ингредиенты.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: techCards.length,
      itemBuilder: (_, i) {
        final t = techCards[i];
        return ListTile(
          title: Text(t.dishName),
          subtitle: Text('${t.ingredients.length} ингр. · ${t.totalCalories.round()} ккал'),
          onTap: () => _askWeight(context, t),
        );
      },
    );
  }

  void _askWeight(BuildContext context, TechCard t) {
    final c = TextEditingController(text: '100');
    final loc = context.read<LocalizationService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.dishName),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: loc.t('weight_g')),
          autofocus: true,
          onSubmitted: (_) => _submit(t, c.text, ctx),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(loc.t('back'))),
          FilledButton(onPressed: () => _submit(t, c.text, ctx), child: Text(loc.t('save'))),
        ],
      ),
    );
  }

  void _submit(TechCard t, String s, BuildContext ctx) {
    final w = double.tryParse(s) ?? 0;
    Navigator.of(ctx).pop();
    if (w > 0) onPick(t, w);
  }
}
