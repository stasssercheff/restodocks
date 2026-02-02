import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen({super.key});

  @override
  State<TechCardsListScreen> createState() => _TechCardsListScreenState();
}

class _TechCardsListScreenState extends State<TechCardsListScreen> {
  List<TechCard> _list = [];
  bool _loading = true;
  String? _error;

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': '—',
    };
    return map[c] ?? c;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() { _loading = false; _error = 'Нет заведения'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final list = await svc.getTechCardsForEstablishment(est.id);
      if (mounted) setState(() { _list = list; _loading = false; });
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
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context.watch<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('tech_cards')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _buildBody(loc),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _loading ? null : () => context.push('/tech-cards/new'),
              child: const Icon(Icons.add),
              tooltip: loc.t('create_tech_card'),
            )
          : null,
    );
  }

  Widget _buildBody(LocalizationService loc) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('refresh'))),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(loc.t('tech_cards'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Нет технологических карт. Создайте первую.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final lang = loc.currentLanguageCode;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer),
            columns: const [
              DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Название', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Категория', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Ингр.', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Ккал', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Выход, г', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(_list.length, (i) {
              final tc = _list[i];
              return DataRow(
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(tc.getLocalizedDishName(lang))),
                  DataCell(Text(_categoryLabel(tc.category))),
                  DataCell(Text('${tc.ingredients.length}')),
                  DataCell(Text('${tc.totalCalories.round()}')),
                  DataCell(Text(tc.yield.toStringAsFixed(0))),
                  DataCell(IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => context.push('/tech-cards/${tc.id}'),
                  )),
                ],
                onSelectChanged: (_) => context.push('/tech-cards/${tc.id}'),
              );
            }),
          ),
        ),
      ),
    );
  }
}
