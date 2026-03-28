import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

const _kDefaultFloor = '__fd__';
const _kDefaultRoom = '__rm__';

/// Карточки столов зала: группировка по этажу и залу, вкладки только если больше одного этажа / зала.
class HallTablesScreen extends StatefulWidget {
  const HallTablesScreen({super.key});

  @override
  State<HallTablesScreen> createState() => _HallTablesScreenState();
}

class _HallTablesScreenState extends State<HallTablesScreen> {
  bool _loading = true;

  /// null | исключение | строка-код 'no_establishment'
  Object? _error;
  List<PosDiningTable> _tables = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_hall_tables_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              if (_error != 'no_establishment') ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: Text(loc.t('retry'))),
              ],
            ],
          ),
        ),
      );
    }
    if (_tables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.table_restaurant,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('pos_tables_empty_title'),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('pos_tables_empty_body'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final floors = _buildFloorGroups(_tables, loc);
    if (floors.length == 1 && floors.first.rooms.length == 1) {
      return _TableGrid(
        tables: floors.first.rooms.first.tables,
        loc: loc,
      );
    }
    if (floors.length == 1) {
      final f = floors.first;
      return _RoomTabsOrGrid(floor: f, loc: loc);
    }
    return DefaultTabController(
      length: floors.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              for (final f in floors) Tab(text: f.tabLabel(loc)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final f in floors) _RoomTabsOrGrid(floor: f, loc: loc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_FloorGroup> _buildFloorGroups(
      List<PosDiningTable> tables, LocalizationService loc) {
    String fKey(PosDiningTable t) {
      final n = t.floorName?.trim();
      return (n == null || n.isEmpty) ? _kDefaultFloor : n;
    }

    String rKey(PosDiningTable t) {
      final n = t.roomName?.trim();
      return (n == null || n.isEmpty) ? _kDefaultRoom : n;
    }

    final byFloor = <String, List<PosDiningTable>>{};
    for (final t in tables) {
      byFloor.putIfAbsent(fKey(t), () => []).add(t);
    }
    final floorKeys = byFloor.keys.toList()
      ..sort((a, b) {
        if (a == _kDefaultFloor) return -1;
        if (b == _kDefaultFloor) return 1;
        return a.compareTo(b);
      });

    final out = <_FloorGroup>[];
    for (final fk in floorKeys) {
      final list = byFloor[fk]!;
      list.sort((a, b) {
        final s = a.sortOrder.compareTo(b.sortOrder);
        if (s != 0) return s;
        return a.tableNumber.compareTo(b.tableNumber);
      });
      final byRoom = <String, List<PosDiningTable>>{};
      for (final t in list) {
        byRoom.putIfAbsent(rKey(t), () => []).add(t);
      }
      final roomKeys = byRoom.keys.toList()
        ..sort((a, b) {
          if (a == _kDefaultRoom) return -1;
          if (b == _kDefaultRoom) return 1;
          return a.compareTo(b);
        });
      final rooms = <_RoomGroup>[];
      for (final rk in roomKeys) {
        rooms.add(_RoomGroup(
          key: rk,
          tables: byRoom[rk]!,
        ));
      }
      out.add(_FloorGroup(key: fk, rooms: rooms));
    }
    return out;
  }
}

class _FloorGroup {
  _FloorGroup({required this.key, required this.rooms});
  final String key;
  final List<_RoomGroup> rooms;

  String tabLabel(LocalizationService loc) {
    if (key == _kDefaultFloor) {
      return loc.t('pos_tables_tab_floor_default');
    }
    return loc.t('pos_tables_tab_floor_named', args: {'name': key});
  }
}

class _RoomGroup {
  _RoomGroup({required this.key, required this.tables});
  final String key;
  final List<PosDiningTable> tables;

  String tabLabel(LocalizationService loc) {
    if (key == _kDefaultRoom) {
      return loc.t('pos_tables_tab_room_default');
    }
    return loc.t('pos_tables_tab_room_named', args: {'name': key});
  }
}

class _RoomTabsOrGrid extends StatelessWidget {
  const _RoomTabsOrGrid({required this.floor, required this.loc});

  final _FloorGroup floor;
  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    if (floor.rooms.length == 1) {
      return _TableGrid(tables: floor.rooms.first.tables, loc: loc);
    }
    return DefaultTabController(
      length: floor.rooms.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              for (final r in floor.rooms) Tab(text: r.tabLabel(loc)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final r in floor.rooms)
                  _TableGrid(tables: r.tables, loc: loc),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableGrid extends StatelessWidget {
  const _TableGrid({required this.tables, required this.loc});

  final List<PosDiningTable> tables;
  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cross = w >= 600 ? 4 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: tables.length,
          itemBuilder: (context, i) => _TableCard(table: tables[i], loc: loc),
        );
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.loc});

  final PosDiningTable table;
  final LocalizationService loc;

  Color _statusColor(BuildContext context) {
    switch (table.status) {
      case PosTableStatus.free:
        return Colors.green.shade700;
      case PosTableStatus.occupied:
        return Colors.blue.shade700;
      case PosTableStatus.billRequested:
        return Colors.amber.shade800;
    }
  }

  String _statusLabel() {
    switch (table.status) {
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
    final scheme = Theme.of(context).colorScheme;
    final border = _statusColor(context);
    final title = loc.t(
      'pos_table_number',
      args: {'n': '${table.tableNumber}'},
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: border.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
