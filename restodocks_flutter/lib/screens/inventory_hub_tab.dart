import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Вкладка «Инвентаризация» внутри KitchenHubScreen.
/// Показывает кнопку «Новая инвентаризация» и историю отправленных документов.
class InventoryHubTab extends StatefulWidget {
  const InventoryHubTab({super.key});

  @override
  State<InventoryHubTab> createState() => _InventoryHubTabState();
}

class _InventoryHubTabState extends State<InventoryHubTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final acc = context.read<AccountManagerSupabase>();
      final emp = acc.currentEmployee;
      if (emp == null) {
        setState(() => _loading = false);
        return;
      }
      final docs = await InventoryDocumentService().listForChef(emp.id);
      if (mounted) setState(() { _docs = docs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/inventory'),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(loc.t('inventory_new')),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/inventory-pf'),
                    icon: const Icon(Icons.science_outlined),
                    label: Text(loc.t('inventory_pf') ?? 'Инвентаризация ПФ'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_docs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        loc.t('no_inventory_docs') ?? 'Нет отправленных документов',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final doc = _docs[i];
                    final createdAt = doc['created_at'] != null
                        ? DateTime.tryParse(doc['created_at'].toString())
                        : null;
                    final dateStr = createdAt != null
                        ? '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}'
                        : '—';
                    final payload = doc['payload'] as Map<String, dynamic>?;
                    final header = payload?['header'] as Map<String, dynamic>? ?? {};
                    final name = header['employeeName']?.toString() ?? '—';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(name),
                        subtitle: Text(dateStr),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/inbox/inventory/${doc['id']}'),
                      ),
                    );
                  },
                  childCount: _docs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
