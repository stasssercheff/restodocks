import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

class PosOrdersDisplayHubScreen extends StatefulWidget {
  const PosOrdersDisplayHubScreen({super.key});

  @override
  State<PosOrdersDisplayHubScreen> createState() => _PosOrdersDisplayHubScreenState();
}

class _PosOrdersDisplayHubScreenState extends State<PosOrdersDisplayHubScreen> {
  bool _loading = true;
  Object? _error;
  bool _shiftOpen = false;
  List<Map<String, dynamic>> _kitchenEmployees = const [];
  Set<String> _allowedKitchenEmployeeIds = <String>{};
  bool _savingPermissions = false;

  bool _canManagePermissions(Employee? e) =>
      e != null && (e.hasRole('owner') || e.hasRole('executive_chef'));

  bool _canOpenShift(Employee? e) {
    if (e == null) return false;
    if (e.hasRole('owner') ||
        e.hasRole('executive_chef') ||
        e.hasRole('general_manager') ||
        e.hasRole('floor_manager')) {
      return true;
    }
    if (e.department == 'hall' || e.department == 'dining_room') return true;
    return _allowedKitchenEmployeeIds.contains(e.id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      if (!mounted) return;
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
      final shift = await PosCashHallService.instance.fetchActiveShift(est.id);
      final allowed =
          await PosKdsShiftAccessService.instance.fetchAllowedEmployeeIds(est.id);
      List<Map<String, dynamic>> employees = const [];
      if (_canManagePermissions(acc.currentEmployee)) {
        final rows = await SupabaseService()
            .client
            .from('employees')
            .select('id, full_name, surname, department, roles, is_active')
            .eq('establishment_id', est.id)
            .eq('department', 'kitchen')
            .eq('is_active', true)
            .order('full_name');
        employees = (rows as List<dynamic>)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _shiftOpen = shift != null;
        _allowedKitchenEmployeeIds = allowed;
        _kitchenEmployees = employees;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _savePermissions() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    setState(() => _savingPermissions = true);
    try {
      await PosKdsShiftAccessService.instance.replaceAllowedEmployeeIds(
        establishmentId: est.id,
        managerEmployeeId: emp.id,
        employeeIds: _allowedKitchenEmployeeIds,
      );
      if (!mounted) return;
      setState(() => _savingPermissions = false);
      AppToastService.show('Права доступа сохранены');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPermissions = false);
      AppToastService.show('Ошибка: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canOpenShift = _canOpenShift(emp);
    final canManagePermissions = _canManagePermissions(emp);
    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ?? appBarBackButton(context),
        title: const Text('Экран заказов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(_shiftOpen ? 'Смена открыта' : 'Смена закрыта'),
                      subtitle: const Text('Открытие/закрытие смены и доступ к заказам'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: canOpenShift
                          ? () => context.push('/pos/hall/cash-register?tab=shift')
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.cast_connected),
                      title: const Text('Подключение экрана'),
                      subtitle: const Text('Ссылка для ТВ/планшета без входа'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: canOpenShift
                          ? () => context.push('/settings/kitchen-display-link')
                          : null,
                    ),
                    if (!canOpenShift)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Нет прав на открытие смены или подключение экрана.',
                        ),
                      ),
                    if (canManagePermissions) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Доступы сотрудников кухни',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Кто может открыть смену и пользоваться разделом "Экран заказов".',
                      ),
                      const SizedBox(height: 10),
                      for (final row in _kitchenEmployees)
                        CheckboxListTile(
                          value: _allowedKitchenEmployeeIds
                              .contains(row['id']?.toString() ?? ''),
                          onChanged: (v) {
                            final id = row['id']?.toString() ?? '';
                            if (id.isEmpty) return;
                            setState(() {
                              if (v == true) {
                                _allowedKitchenEmployeeIds.add(id);
                              } else {
                                _allowedKitchenEmployeeIds.remove(id);
                              }
                            });
                          },
                          title: Text(
                            [
                              row['full_name']?.toString() ?? '',
                              if ((row['surname']?.toString() ?? '').isNotEmpty)
                                row['surname']!.toString(),
                            ].join(' '),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _savingPermissions ? null : _savePermissions,
                        child: Text(_savingPermissions ? 'Сохранение...' : 'Сохранить доступы'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
