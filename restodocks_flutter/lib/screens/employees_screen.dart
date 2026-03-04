import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/config/roles_config.dart';
import '../models/models.dart';
import '../utils/number_format_utils.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Список сотрудников. Владелец видит всех; остальные — по своему отделу. Редактирование для шефа/владельца. Добавление — только личная регистрация по PIN.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _list = [];
  bool _loading = true;
  String? _error;

  bool _canEditEmployees(Employee? current) {
    if (current == null) return false;
    return current.hasRole('owner') || current.hasRole('executive_chef') || current.hasRole('sous_chef');
  }

  /// Может ли переключать доступ к данным и редактирование графика (в карточке сотрудника): собственник, шеф, су-шеф, менеджер зала, барменеджер.
  bool _canToggleDataAccess(Employee? current) {
    if (current == null) return false;
    return current.hasRole('owner') ||
        current.hasRole('executive_chef') ||
        current.hasRole('sous_chef') ||
        current.hasRole('bar_manager') ||
        current.hasRole('floor_manager');
  }

  bool _canToggleScheduleEdit(Employee? current) => _canToggleDataAccess(current);

  bool _canConfirmShifts(Employee? current) {
    return current?.canEditSchedule ?? false;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final current = acc.currentEmployee;
    final est = acc.establishment;
    if (current == null || est == null) {
      setState(() { _loading = false; _error = 'Нет заведения'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final all = await acc.getEmployeesForEstablishment(est.id);
      // Скрываем только собственника без должности; остальных показываем
      final visible = all.where((e) => !(e.hasRole('owner') && e.positionRole == null)).toList();
      // Владелец, шеф, су-шеф видят всех; остальные — только свой отдел
      final filtered = (current.hasRole('owner') || current.hasRole('executive_chef') || current.hasRole('sous_chef'))
          ? visible
          : (current.department.isEmpty ? visible : visible.where((e) => e.department == current.department).toList());
      // Дедупликация по id (на случай дублей из БД)
      final seen = <String>{};
      final list = filtered.where((e) => seen.add(e.id)).toList();
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
    final theme = Theme.of(context);
    final acc = context.watch<AccountManagerSupabase>();
    final canEdit = _canEditEmployees(acc.currentEmployee);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('employees')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
        ],
      ),
      body: _buildBody(loc, theme, canEdit, canConfirmShifts: _canConfirmShifts(acc.currentEmployee)),
    );
  }

  Widget _buildBody(LocalizationService loc, ThemeData theme, bool canEdit, {bool canConfirmShifts = false}) {
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('employees_empty_hint'),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                loc.t('employees_register_by_pin_hint') ?? 'Сотрудники регистрируются самостоятельно по PIN компании.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.person_add),
                label: Text(loc.t('register_employee') ?? 'Регистрация сотрудника'),
                onPressed: () => context.push('/register'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canConfirmShifts)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(Icons.how_to_reg, color: theme.colorScheme.primary),
              title: Text(loc.t('shift_confirmation')),
              subtitle: Text(loc.t('shift_confirmation_hint')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/shift-confirmation'),
            ),
          ),
        _EmployeeTableHeader(loc: loc, canEdit: canEdit),
        const SizedBox(height: 4),
        ...List.generate(_list.length, (i) => _EmployeeCard(
        employee: _list[i],
        loc: loc,
        canEdit: canEdit,
        onEdit: () => _openEditEmployee(context, _list[i]),
        onDelete: () => _deleteEmployee(context, _list[i]),
      )),
      ],
    );
  }

  void _deleteEmployee(BuildContext context, Employee employee) async {
    final loc = context.read<LocalizationService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_employee') ?? 'Удалить сотрудника'),
        content: Text('Вы уверены, что хотите удалить сотрудника "${employee.fullName}"? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.t('cancel') ?? 'Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(loc.t('delete') ?? 'Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final acc = context.read<AccountManagerSupabase>();
        await acc.deleteEmployee(employee.id);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Сотрудник "${employee.fullName}" удален')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка удаления: $e')),
          );
        }
      }
    }
  }

  void _openEditEmployee(BuildContext context, Employee employee) {
    final canToggle = _canToggleDataAccess(context.read<AccountManagerSupabase>().currentEmployee);
    showDialog<void>(
      context: context,
      builder: (ctx) => _EmployeeEditSheet(
        employee: employee,
        canToggleDataAccess: canToggle,
        canToggleScheduleEdit: _canToggleScheduleEdit(context.read<AccountManagerSupabase>().currentEmployee),
        onSaved: () {
          Navigator.of(ctx).pop();
          _load();
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }
}

class _EmployeeTableHeader extends StatelessWidget {
  const _EmployeeTableHeader({
    required this.loc,
    required this.canEdit,
  });

  final LocalizationService loc;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    // На мобильном заголовок таблицы не нужен — карточки многострочные
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 36 + 10), // аватар + отступ
          Expanded(flex: 5, child: Text(loc.t('full_name') ?? 'Сотрудник', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(loc.t('subdivision') ?? 'Подразделение', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(loc.t('position') ?? 'Должность', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text(loc.t('rate') ?? 'Ставка', style: style)),
          if (canEdit) const SizedBox(width: 64),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.loc,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final Employee employee;
  final LocalizationService loc;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String positionDisplay(Employee e, LocalizationService loc) {
    final pos = e.positionRole;
    if (pos == null || pos.isEmpty) return '—';
    return loc.roleDisplayName(pos);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return isMobile ? _buildMobile(context) : _buildDesktop(context);
  }

  /// ПК: одна горизонтальная строка, все колонки вертикально по центру
  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    final est = context.read<AccountManagerSupabase>().establishment;
    final currencySymbol = est?.currencySymbol ?? Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
    final isPerShift = employee.paymentType == 'per_shift';
    final rate = isPerShift ? employee.ratePerShift : employee.hourlyRate;
    final rateStr = rate != null && rate > 0
        ? '${NumberFormatUtils.formatInt(rate)} $currencySymbol'
        : '—';
    final sectionStr = (employee.department == 'kitchen' && employee.section != null && employee.section!.isNotEmpty)
        ? (loc.t('section_${employee.section}') != 'section_${employee.section}'
            ? loc.t('section_${employee.section}')
            : (employee.sectionDisplayName ?? employee.section!))
        : null;
    final deptLabel = loc.departmentDisplayName(employee.department) != employee.department
        ? loc.departmentDisplayName(employee.department)
        : employee.departmentDisplayName;
    final deptStr = sectionStr != null ? '$deptLabel · $sectionStr' : deptLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Аватар
              _EmployeeAvatar(employee: employee, radius: 18),
              const SizedBox(width: 10),
              // Имя + email
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      employee.fullName,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (employee.email.isNotEmpty)
                      Text(
                        employee.email,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Подразделение (+ цех)
              Expanded(
                flex: 3,
                child: Text(
                  deptStr,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Должность
              Expanded(
                flex: 3,
                child: Text(
                  positionDisplay(employee, loc),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Ставка
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.payments_outlined, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        rateStr,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопки редактирования
              if (canEdit) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: loc.t('edit'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: onDelete,
                  tooltip: loc.t('delete'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Мобильный: компактная карточка в несколько строк
  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    final est = context.read<AccountManagerSupabase>().establishment;
    final currencySymbol = est?.currencySymbol ?? Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
    final isPerShift = employee.paymentType == 'per_shift';
    final rate = isPerShift ? employee.ratePerShift : employee.hourlyRate;
    final rateStr = rate != null && rate > 0
        ? '${NumberFormatUtils.formatInt(rate)} $currencySymbol'
        : '—';
    final sectionStr = (employee.department == 'kitchen' && employee.section != null && employee.section!.isNotEmpty)
        ? (loc.t('section_${employee.section}') != 'section_${employee.section}'
            ? loc.t('section_${employee.section}')
            : (employee.sectionDisplayName ?? employee.section!))
        : null;
    final deptLabel = loc.departmentDisplayName(employee.department) != employee.department
        ? loc.departmentDisplayName(employee.department)
        : employee.departmentDisplayName;
    final deptStr = sectionStr != null ? '$deptLabel · $sectionStr' : deptLabel;
    final posStr = positionDisplay(employee, loc);
    final subStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Аватар
              _EmployeeAvatar(employee: employee, radius: 18),
              const SizedBox(width: 10),
              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Имя
                    Text(
                      employee.fullName,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (employee.email.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(employee.email, style: subStyle),
                    ],
                    const SizedBox(height: 4),
                    // Подразделение + должность в одну строку
                    Row(
                      children: [
                        Icon(Icons.business_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            deptStr + (posStr != '—' ? ' · $posStr' : ''),
                            style: subStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Ставка
                    Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(rateStr, style: subStyle?.copyWith(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              // Правая часть: кнопки (центрируем по вертикали)
              if (canEdit)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: onEdit,
                          tooltip: loc.t('edit'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: onDelete,
                          tooltip: loc.t('delete'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Редактирование сотрудника ---

const _departmentKeys = ['kitchen', 'bar', 'dining_room', 'management'];
const _departmentLabels = {'kitchen': 'Кухня', 'bar': 'Бар', 'dining_room': 'Зал', 'management': 'Управление'};
const _roleOptions = [
  'owner', 'executive_chef', 'sous_chef', 'cook', 'bartender', 'waiter',
  'bar_manager', 'floor_manager', 'general_manager', 'brigadier', 'senior_cook', 'pizzaiolo', 'pastry_chef',
];
String _roleLabel(String code, LocalizationService loc) {
  final key = 'role_$code';
  final t = loc.t(key);
  return (t != key && t.isNotEmpty) ? t : code;
}

class _EmployeeEditSheet extends StatefulWidget {
  const _EmployeeEditSheet({
    required this.employee,
    required this.canToggleDataAccess,
    required this.canToggleScheduleEdit,
    required this.onSaved,
    required this.onCancel,
  });

  final Employee employee;
  final bool canToggleDataAccess;
  final bool canToggleScheduleEdit;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_EmployeeEditSheet> createState() => _EmployeeEditSheetState();
}

class _EmployeeEditSheetState extends State<_EmployeeEditSheet> {
  late TextEditingController _nameController;
  late TextEditingController _rateController;
  late String _department;
  late String? _section;
  late List<String> _roles;
  late String _paymentType;
  late bool _isActive;
  late bool _dataAccessEnabled;
  late bool _canEditOwnSchedule;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee.fullName);
    _rateController = TextEditingController(
      text: widget.employee.paymentType == 'per_shift'
          ? (widget.employee.ratePerShift?.toString() ?? '')
          : (widget.employee.hourlyRate?.toString() ?? ''),
    );
    _department = widget.employee.department;
    _section = widget.employee.section;
    _roles = List.from(widget.employee.roles);
    _paymentType = widget.employee.paymentType ?? 'hourly';
    _isActive = widget.employee.isActive;
    _dataAccessEnabled = widget.employee.dataAccessEnabled;
    _canEditOwnSchedule = widget.employee.canEditOwnSchedule;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loc = context.read<LocalizationService>();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите имя');
      return;
    }
    if (_roles.isEmpty) {
      setState(() => _error = 'Выберите хотя бы одну роль');
      return;
    }
    final rate = double.tryParse(_rateController.text.trim());
    setState(() { _saving = true; _error = null; });
    try {
      final updated = widget.employee.copyWith(
        fullName: name,
        department: _department,
        section: _department == 'kitchen' ? _section : null,
        roles: _roles,
        paymentType: _paymentType,
        ratePerShift: _paymentType == 'per_shift' ? (rate ?? 0) : null,
        hourlyRate: _paymentType == 'hourly' ? rate : null,
        isActive: _isActive,
        dataAccessEnabled: _dataAccessEnabled,
        canEditOwnSchedule: _canEditOwnSchedule,
      );
      await context.read<AccountManagerSupabase>().updateEmployee(updated);
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final isSchemaError = msg.contains('hourly_rate') ||
            msg.contains('rate_per_shift') ||
            msg.contains('payment_type') ||
            msg.contains('PGRST204') ||
            (msg.contains('column') && msg.contains('exist'));
        setState(() {
          _error = isSchemaError
              ? (loc.t('employee_save_error_schema') ?? 'Не удалось сохранить. В БД нет колонок оплаты. Выполните в Supabase SQL Editor миграцию из файла supabase_migration_employee_payment.sql')
              : msg;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: media.size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loc.t('edit_employee') ?? 'Редактировать сотрудника', style: theme.textTheme.titleLarge),
                  TextButton(onPressed: widget.onCancel, child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: loc.t('full_name') ?? 'ФИО',
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _department,
                        decoration: InputDecoration(labelText: loc.t('department') ?? 'Отдел', border: const OutlineInputBorder(), filled: true),
                        items: _departmentKeys.map((k) => DropdownMenuItem(value: k, child: Text(_departmentLabels[k] ?? k))).toList(),
                        onChanged: (v) => setState(() {
                          _department = v ?? _department;
                          if (_department != 'kitchen') _section = null;
                        }),
                      ),
                      if (_department == 'kitchen') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          value: _section,
                          decoration: InputDecoration(labelText: loc.t('section') ?? 'Цех', border: const OutlineInputBorder(), filled: true),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('—')),
                            ...RolesConfig.kitchenSections().map((s) => DropdownMenuItem(value: s, child: Text(loc.t('section_$s') != 'section_$s' ? loc.t('section_$s') : s))),
                          ],
                          onChanged: (v) => setState(() => _section = v),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(loc.t('roles') ?? 'Роли', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _roleOptions.map((code) {
                          final selected = _roles.contains(code);
                          return FilterChip(
                            label: Text(_roleLabel(code, loc)),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) _roles.add(code); else _roles.remove(code);
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _paymentType,
                        decoration: InputDecoration(labelText: loc.t('payment_type') ?? 'Тип оплаты', border: const OutlineInputBorder(), filled: true),
                        items: [
                          DropdownMenuItem(value: 'hourly', child: Text(loc.t('payment_hourly') ?? 'Почасовая')),
                          DropdownMenuItem(value: 'per_shift', child: Text(loc.t('payment_per_shift') ?? 'За смену')),
                        ],
                        onChanged: (v) => setState(() => _paymentType = v ?? 'hourly'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _paymentType == 'per_shift' ? (loc.t('rate_per_shift') ?? 'Ставка за смену') : (loc.t('hourly_rate') ?? 'Ставка в час'),
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      if (_paymentType == 'per_shift')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            loc.t('payment_per_shift_hint') ?? 'Время смены задаётся в графике по дням.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: Text(loc.t('active') ?? 'Активен'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      if (widget.canToggleDataAccess && !widget.employee.hasRole('owner'))
                        SwitchListTile(
                          title: Text(loc.t('data_access') ?? 'Доступ к данным'),
                          subtitle: Text(loc.t('data_access_hint') ?? 'Без доступа сотрудник видит только график'),
                          value: _dataAccessEnabled,
                          onChanged: (v) => setState(() => _dataAccessEnabled = v),
                        ),
                      if (widget.canToggleScheduleEdit && !widget.employee.hasRole('owner') && widget.employee.positionRole != null)
                        SwitchListTile(
                          title: Text(loc.t('schedule_edit_own') ?? 'Менять график'),
                          subtitle: Text(loc.t('schedule_edit_own_hint') ?? 'Сотрудник может редактировать свой личный график'),
                          value: _canEditOwnSchedule,
                          onChanged: (v) => setState(() => _canEditOwnSchedule = v),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        if (_error!.contains('миграцию') || _error!.contains('migration')) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              const sql = '''ALTER TABLE employees ADD COLUMN IF NOT EXISTS payment_type TEXT DEFAULT 'hourly';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS rate_per_shift REAL;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS hourly_rate REAL;''';
                              await Clipboard.setData(const ClipboardData(text: sql));
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('copied') ?? 'SQL скопирован в буфер')));
                            },
                            icon: const Icon(Icons.copy, size: 18),
                            label: Text(loc.t('copy_migration_sql') ?? 'Скопировать SQL миграции'),
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(loc.t('save')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  const _EmployeeAvatar({required this.employee, this.radius = 18});

  final Employee employee;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = (employee.fullName.isNotEmpty ? employee.fullName[0] : '?').toUpperCase();
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: radius * 0.78,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final url = employee.avatarUrl;
    if (url == null || url.isEmpty) return placeholder;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}
