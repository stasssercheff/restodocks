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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _list.length,
        itemBuilder: (_, i) {
          final tc = _list[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: Text(tc.dishName),
              subtitle: Text('${tc.ingredients.length} ингр. · ${tc.totalCalories.round()} ккал'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/tech-cards/${tc.id}'),
            ),
          );
        },
      ),
    );
  }
}
