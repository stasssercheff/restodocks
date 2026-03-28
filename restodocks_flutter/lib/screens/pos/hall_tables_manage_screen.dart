import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart';

/// Редактирование списка столов зала (владелец, управляющий, менеджер зала).
class HallTablesManageScreen extends StatefulWidget {
  const HallTablesManageScreen({super.key});

  @override
  State<HallTablesManageScreen> createState() => _HallTablesManageScreenState();
}

class _HallTablesManageScreenState extends State<HallTablesManageScreen> {
  bool _loading = true;
  Object? _error;
  List<PosDiningTable> _tables = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final e = context.read<AccountManagerSupabase>().currentEmployee;
      if (!posCanManageHallTables(e)) {
        context.pop();
        return;
      }
      _load();
    });
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'no_establishment';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PosDiningLayoutService.instance.ensureDefaultDiningLayoutIfEmpty(est.id);
      final list = await PosDiningLayoutService.instance.fetchTables(est.id);
      if (!mounted) return;
      setState(() {
        _tables = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _delete(PosDiningTable t, LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_tables_delete_title')),
        content: Text(loc.t('pos_tables_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PosDiningLayoutService.instance.deleteTable(t.id);
      AppToastService.show(loc.t('pos_tables_deleted'));
      await _load();
    } catch (e) {
      AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _openForm(
      LocalizationService loc, PosDiningTable? existing) async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;

    final floorCtrl = TextEditingController(text: existing?.floorName ?? '');
    final roomCtrl = TextEditingController(text: existing?.roomName ?? '');
    final numCtrl = TextEditingController(
        text: existing != null ? '${existing.tableNumber}' : '1');
    final sortCtrl = TextEditingController(
        text: existing != null ? '${existing.sortOrder}' : '0');
    PosTableStatus status = existing?.status ?? PosTableStatus.free;

    _TableFormResult? result;
    try {
      result = await showDialog<_TableFormResult>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(existing == null
                ? loc.t('pos_tables_manage_add')
                : loc.t('pos_tables_manage_edit')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: floorCtrl,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_tables_field_floor')),
                  ),
                  TextField(
                    controller: roomCtrl,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_tables_field_room')),
                  ),
                  TextField(
                    controller: numCtrl,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_tables_field_number')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  TextField(
                    controller: sortCtrl,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_tables_field_sort')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'-?[0-9]*'))
                    ],
                  ),
                  DropdownButtonFormField<PosTableStatus>(
                    key: ValueKey(status),
                    initialValue: status,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_tables_field_status')),
                    items: PosTableStatus.values.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(_statusLabel(loc, s)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => status = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(loc.t('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final n = int.tryParse(numCtrl.text.trim());
                  if (n == null || n < 1) {
                    AppToastService.show(loc.t('pos_tables_error_number'));
                    return;
                  }
                  final so = int.tryParse(sortCtrl.text.trim()) ?? 0;
                  var fn = floorCtrl.text.trim();
                  var rn = roomCtrl.text.trim();
                  if (fn.isEmpty) fn = '';
                  if (rn.isEmpty) rn = '';
                  Navigator.pop(
                    ctx,
                    _TableFormResult(
                      floorName: fn.isEmpty ? null : fn,
                      roomName: rn.isEmpty ? null : rn,
                      tableNumber: n,
                      sortOrder: so,
                      status: status,
                    ),
                  );
                },
                child: Text(loc.t('save')),
              ),
            ],
          ),
        ),
      );
    } finally {
      floorCtrl.dispose();
      roomCtrl.dispose();
      numCtrl.dispose();
      sortCtrl.dispose();
    }

    if (result == null || !mounted) return;

    try {
      if (existing == null) {
        await PosDiningLayoutService.instance.insertTable(
          establishmentId: est.id,
          floorName: result.floorName,
          roomName: result.roomName,
          tableNumber: result.tableNumber,
          sortOrder: result.sortOrder,
          status: result.status,
        );
      } else {
        final updated = PosDiningTable(
          id: existing.id,
          establishmentId: existing.establishmentId,
          floorName: result.floorName,
          roomName: result.roomName,
          tableNumber: result.tableNumber,
          sortOrder: result.sortOrder,
          status: result.status,
        );
        await PosDiningLayoutService.instance.updateTable(updated);
      }
      AppToastService.show(loc.t('pos_tables_saved'));
      await _load();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('23505') ||
          msg.contains('unique') ||
          msg.contains('duplicate')) {
        AppToastService.show(loc.t('pos_tables_error_duplicate'));
      } else {
        AppToastService.show('${loc.t('error')}: $e');
      }
    }
  }

  String _statusLabel(LocalizationService loc, PosTableStatus s) {
    switch (s) {
      case PosTableStatus.free:
        return loc.t('pos_table_status_free');
      case PosTableStatus.occupied:
        return loc.t('pos_table_status_occupied');
      case PosTableStatus.billRequested:
        return loc.t('pos_table_status_bill');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    if (!posCanManageHallTables(emp)) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('pos_tables_manage_title')),
            Text(
              loc.t('pos_tables_manage_owner_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : () => _openForm(loc, null),
        tooltip: loc.t('pos_tables_manage_add'),
        child: const Icon(Icons.add),
      ),
      body: _body(loc),
    );
  }

  Widget _body(LocalizationService loc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final message = _error == 'no_establishment'
          ? loc.t('error_no_establishment_or_employee')
          : loc.t('pos_tables_load_error');
      return Center(child: Text(message, textAlign: TextAlign.center));
    }
    if (_tables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_tables_manage_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tables.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = _tables[i];
        final sub = [
          if (t.floorName != null && t.floorName!.isNotEmpty) t.floorName,
          if (t.roomName != null && t.roomName!.isNotEmpty) t.roomName,
        ].join(' · ');
        return ListTile(
          title:
              Text(loc.t('pos_table_number', args: {'n': '${t.tableNumber}'})),
          subtitle: Text(
            [
              if (sub.isNotEmpty) sub,
              _statusLabel(loc, t.status),
            ].join(' · '),
          ),
          isThreeLine: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _openForm(loc, t),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                onPressed: () => _delete(t, loc),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TableFormResult {
  const _TableFormResult({
    required this.floorName,
    required this.roomName,
    required this.tableNumber,
    required this.sortOrder,
    required this.status,
  });

  final String? floorName;
  final String? roomName;
  final int tableNumber;
  final int sortOrder;
  final PosTableStatus status;
}
