import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/config/roles_config.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Список сотрудников. Владелец видит всех; остальные — по своему отделу. Редактирование и добавление для шефа/владельца.
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
      // Владелец видит всех сотрудников (и кухня, и менеджмент), иначе — только свой отдел
      final filtered = current.hasRole('owner')
          ? all
          : (current.department.isEmpty ? all : all.where((e) => e.department == current.department).toList());
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

  String _roleDisplay(Employee e, LocalizationService loc) {
    if (e.roles.isEmpty) return '—';
    final roleKeys = <String, String>{
      'owner': 'Владелец', 'executive_chef': 'Шеф-повар', 'sous_chef': 'Су-шеф', 'cook': 'Повар',
      'bartender': 'Бармен', 'waiter': 'Официант', 'bar_manager': 'Менеджер бара',
      'general_manager': 'Управляющий', 'brigadier': 'Бригадир',
    };
    return e.roles.map((r) => roleKeys[r] ?? r).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final acc = context.watch<AccountManagerSupabase>();
    final canEdit = _canEditEmployees(acc.currentEmployee);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('employees')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _buildBody(loc, theme, canEdit, canConfirmShifts: _canConfirmShifts(acc.currentEmployee)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openAddEmployee(context),
              icon: const Icon(Icons.person_add),
              label: Text(loc.t('add_employee')),
            )
          : null,
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
        ...List.generate(_list.length, (i) => _EmployeeCard(
        employee: _list[i],
        loc: loc,
        canEdit: canEdit,
        currentEmployeeId: acc.currentEmployee?.id,
        onUpdated: _load,
        onEdit: () => _openEditEmployee(context, _list[i]),
        onDelete: () => _deleteEmployee(context, _list[i]),
      )),
      ],
    );
  }

  void _openEditEmployee(BuildContext context, Employee employee) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _EmployeeEditSheet(
        employee: employee,
        onSaved: () {
          Navigator.of(ctx).pop();
          _load();
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Future<void> _deleteEmployee(BuildContext context, Employee employee) async {
    final loc = context.read<LocalizationService>();
    if (employee.roles.contains('owner')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('employee_cannot_delete_owner') ?? 'Нельзя удалить владельца')));
      return;
    }
    if (employee.id == context.read<AccountManagerSupabase>().currentEmployee?.id) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('employee_cannot_delete_self') ?? 'Нельзя удалить самого себя')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete') ?? 'Удалить'),
        content: Text('${loc.t('employee_delete_confirm') ?? 'Удалить сотрудника'} «${employee.fullName}»?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.t('cancel') ?? 'Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete') ?? 'Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AccountManagerSupabase>().deleteEmployee(employee);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('employee_deleted') ?? 'Сотрудник удалён')));
        _load();
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openAddEmployee(BuildContext context) {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _EmployeeAddSheet(
        establishment: est,
        onSaved: () {
          Navigator.of(ctx).pop();
          _load();
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.loc,
    required this.canEdit,
    required this.currentEmployeeId,
    required this.onUpdated,
    required this.onEdit,
    required this.onDelete,
  });

  final Employee employee;
  final LocalizationService loc;
  final bool canEdit;
  final String? currentEmployeeId;
  final VoidCallback onUpdated;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String roleDisplay(Employee e) {
    const roleKeys = {
      'owner': 'Владелец', 'executive_chef': 'Шеф-повар', 'sous_chef': 'Су-шеф', 'cook': 'Повар',
      'bartender': 'Бармен', 'waiter': 'Официант', 'bar_manager': 'Менеджер бара',
      'general_manager': 'Управляющий', 'brigadier': 'Бригадир',
      'senior_cook': 'Старший повар', 'pizzaiolo': 'Пиццайоло', 'pastry_chef': 'Кондитер',
    };
    return e.roles.isEmpty ? '—' : e.roles.map((r) => roleKeys[r] ?? r).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPerShift = employee.paymentType == 'per_shift';
    final rate = isPerShift ? employee.ratePerShift : employee.hourlyRate;
    final rateLabel = isPerShift ? loc.t('payment_per_shift') : loc.t('payment_hourly');
    final rateStr = rate != null && rate > 0
        ? '${rate.toStringAsFixed(0)} ${loc.t('currency_rub_short')}'
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (employee.fullName.isNotEmpty ? employee.fullName[0] : '?').toUpperCase(),
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee.fullName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        if (employee.email.isNotEmpty)
                          Text(employee.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(roleDisplay(employee), style: theme.textTheme.bodySmall),
                        if (employee.section != null && employee.section!.isNotEmpty)
                          Text(employee.section!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                  if (canEdit)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: onEdit,
                          tooltip: loc.t('edit'),
                        ),
                        if (!employee.roles.contains('owner') && employee.id != currentEmployeeId)
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                            onPressed: onDelete,
                            tooltip: loc.t('delete'),
                          ),
                      ],
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('$rateLabel: $rateStr', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
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
  'bar_manager', 'general_manager', 'brigadier', 'senior_cook', 'pizzaiolo', 'pastry_chef',
];
const _roleLabels = {
  'owner': 'Владелец', 'executive_chef': 'Шеф-повар', 'sous_chef': 'Су-шеф', 'cook': 'Повар',
  'bartender': 'Бармен', 'waiter': 'Официант', 'bar_manager': 'Менеджер бара',
  'general_manager': 'Управляющий', 'brigadier': 'Бригадир',
  'senior_cook': 'Старший повар', 'pizzaiolo': 'Пиццайоло', 'pastry_chef': 'Кондитер',
};

class _EmployeeEditSheet extends StatefulWidget {
  const _EmployeeEditSheet({required this.employee, required this.onSaved, required this.onCancel});

  final Employee employee;
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
                            ...RolesConfig.kitchenSections().map((s) => DropdownMenuItem(value: s, child: Text(s))),
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
                            label: Text(_roleLabels[code] ?? code),
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

// --- Добавление сотрудника ---

class _EmployeeAddSheet extends StatefulWidget {
  const _EmployeeAddSheet({required this.establishment, required this.onSaved, required this.onCancel});

  final Establishment establishment;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_EmployeeAddSheet> createState() => _EmployeeAddSheetState();
}

class _EmployeeAddSheetState extends State<_EmployeeAddSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _department = 'kitchen';
  String? _section = 'hot_kitchen';
  final List<String> _roles = ['cook'];
  bool _saving = false;
  String? _error;

  static const _chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _generatePassword() {
    final r = Random.secure();
    return List.generate(12, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  static String _appUrl() {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty) return origin;
      } catch (_) {}
    }
    return 'https://restodocks.com';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final loc = context.read<LocalizationService>();
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = loc.t('full_name_required') ?? 'Введите ФИО');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = loc.t('email_required') ?? 'Введите email');
      return;
    }
    if (_roles.isEmpty) {
      setState(() => _error = loc.t('role_required') ?? 'Выберите роль');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final taken = await acc.isEmailTakenInEstablishment(email, widget.establishment.id);
      if (taken && mounted) {
        setState(() { _error = loc.t('email_already_registered') ?? 'Этот email уже зарегистрирован'; _saving = false; });
        return;
      }
      final password = _generatePassword();
      await acc.createEmployeeForCompany(
        company: widget.establishment,
        fullName: name,
        email: email,
        password: password,
        department: _department,
        section: _department == 'kitchen' ? _section : null,
        roles: _roles,
      );
      context.read<EmailService>().sendRegistrationEmail(
        isOwner: false,
        to: email,
        companyName: widget.establishment.name,
        email: email,
        password: password,
        loginUrl: _appUrl(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('employee_invite_sent') ?? 'Сотрудник создан. Письмо с данными для входа отправлено на $email')),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
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
                  Text(loc.t('add_employee') ?? 'Добавить сотрудника', style: theme.textTheme.titleLarge),
                  TextButton(onPressed: widget.onCancel, child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: loc.t('full_name') ?? 'ФИО',
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: loc.t('email') ?? 'Email',
                          hintText: loc.t('employee_invite_hint') ?? 'На почту придёт письмо со ссылкой и временным паролем',
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
                          if (_department != 'kitchen') _section = null; else _section = 'hot_kitchen';
                        }),
                      ),
                      if (_department == 'kitchen') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          value: _section,
                          decoration: InputDecoration(labelText: loc.t('section') ?? 'Цех', border: const OutlineInputBorder(), filled: true),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('—')),
                            ...RolesConfig.kitchenSections().map((s) => DropdownMenuItem(value: s, child: Text(s))),
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
                            label: Text(_roleLabels[code] ?? code),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) _roles.add(code); else _roles.remove(code);
                            }),
                          );
                        }).toList(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _create,
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
