import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/config/roles_config.dart';
import '../models/models.dart';
import '../utils/layout_breakpoints.dart';
import '../utils/number_format_utils.dart';
import '../utils/employee_display_utils.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

const double _desktopEmployeeAvatarAndGapWidth = 46; // 36 avatar + 10 gap
const double _desktopEmployeeColumnGap = 8;
const double _desktopEmployeeRowHorizontalPadding = 12;
const int _desktopEmployeeNameFlex = 4;
const int _desktopEmployeeDepartmentFlex = 3;
const int _desktopEmployeeHeaderPositionFlex = 2;
const int _desktopEmployeeHeaderRateFlex = 2;
const int _desktopEmployeeRowPositionFlex = 1;
const int _desktopEmployeeRowRateFlex = 3;
const double _desktopEmployeeRateRowLeftInset = 66;
const double _desktopEmployeeDeptRowLeftShift = 0;
const double _desktopEmployeePositionHeaderLeftShift = -6;
const double _desktopEmployeePositionRowLeftShift = -18;

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
  int _employeeUsedCount = 0;
  int _employeeCap = 0;

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
      int cap = 0;
      try {
        final capRaw = await acc.supabase.client.rpc(
          'establishment_active_employee_cap',
          params: {'p_establishment_id': est.id},
        );
        cap = int.tryParse('${capRaw ?? ''}') ?? 0;
      } catch (_) {
        cap = 0;
      }
      final usedCount = all.where(_countsTowardEmployeeCap).length;
      // Скрываем только собственника без должности; остальных показываем
      final visible = all.where((e) => !(e.hasRole('owner') && e.positionRole == null)).toList();
      // Владелец, шеф, су-шеф видят всех; остальные — только свой отдел
      final filtered = (current.hasRole('owner') || current.hasRole('executive_chef') || current.hasRole('sous_chef'))
          ? visible
          : (current.department.isEmpty ? visible : visible.where((e) => e.department == current.department).toList());
      // Дедупликация по id (на случай дублей из БД)
      final seen = <String>{};
      final list = filtered.where((e) => seen.add(e.id)).toList();
      if (mounted) {
        setState(() {
          _list = list;
          _employeeUsedCount = usedCount;
          _employeeCap = cap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  bool _countsTowardEmployeeCap(Employee e) {
    if (!e.isActive) return false;
    final hasOnlyOwnerRole =
        e.roles.length == 1 && e.roles.first.trim().toLowerCase() == 'owner';
    return !(hasOnlyOwnerRole && (e.positionRole == null || e.positionRole!.trim().isEmpty));
  }

  String _resolvedRateHeader(LocalizationService loc) {
    final translated = loc.t('rate').trim();
    if (translated.isEmpty || translated == 'rate') return 'Ставка';
    return translated;
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
    final showTranslit = context.watch<ScreenLayoutPreferenceService>().showNameTranslit ||
        loc.currentLanguageCode != 'ru';
    final canEdit = _canEditEmployees(acc.currentEmployee);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('employees')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
        ],
      ),
      body: _buildBody(loc, theme, canEdit, showTranslit, _resolvedRateHeader(loc)),
    );
  }

  Widget _buildBody(
    LocalizationService loc,
    ThemeData theme,
    bool canEdit,
    bool showTranslit,
    String rateHeader,
  ) {
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
        if (_employeeCap > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$_employeeUsedCount из $_employeeCap',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        _EmployeeTableHeader(loc: loc, canEdit: canEdit, rateHeader: rateHeader),
        const SizedBox(height: 4),
        ...List.generate(_list.length, (i) => _EmployeeCard(
        employee: _list[i],
        loc: loc,
        showTranslit: showTranslit,
        canEdit: canEdit,
        rateHeader: rateHeader,
        onEdit: () => _openEditEmployee(context, _list[i]),
        onDelete: () => _deleteEmployee(context, _list[i]),
      )),
      ],
    );
  }

  void _deleteEmployee(BuildContext context, Employee employee) async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final establishment = acc.establishment;
    if (establishment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('establishment') ?? 'Заведение не найдено')),
      );
      return;
    }

    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_employee') ?? 'Удалить сотрудника'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${loc.t('delete_employee_confirm') ?? 'Вы уверены, что хотите удалить сотрудника'} "${employee.fullName}"? '
                '${loc.t('delete_employee_pin_hint') ?? 'Введите PIN компании для подтверждения:'}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: pinController,
                  obscureText: true,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: loc.t('company_pin') ?? 'PIN компании',
                    hintText: loc.t('enter_company_pin') ?? 'Введите PIN компании',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return loc.t('company_pin_required') ?? 'PIN обязателен';
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(loc.t('cancel') ?? 'Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(ctx).pop(pinController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.t('delete') ?? 'Удалить'),
          ),
        ],
      ),
    );

    pinController.dispose();
    if (result == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(loc.t('delete_employee_progress') ?? 'Удаление сотрудника...')),
          ],
        ),
      ),
    );
    try {
      await acc.deleteEmployeeWithPin(employeeId: employee.id, pinCode: result);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('employee_deleted_success') ?? 'Сотрудник удалён'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (mounted) {
        final msg = e.toString();
        String snack = msg;
        if (msg.toLowerCase().contains('invalid') && msg.toLowerCase().contains('pin')) {
          snack = loc.t('delete_establishment_wrong_pin') ?? 'Неверный PIN';
        } else if (msg.toLowerCase().contains('owner')) {
          snack = loc.t('cannot_delete_owner') ?? 'Нельзя удалить владельца';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snack), backgroundColor: Colors.red),
        );
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
    required this.rateHeader,
  });

  final LocalizationService loc;
  final bool canEdit;
  final String rateHeader;

  @override
  Widget build(BuildContext context) {
    // На мобильном заголовок таблицы не нужен — карточки многострочные
    final isMobile = isHandheldNarrowLayout(context);
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
          const SizedBox(width: _desktopEmployeeAvatarAndGapWidth),
          Expanded(
            flex: _desktopEmployeeNameFlex,
            child: Text(loc.t('full_name') ?? 'Сотрудник', style: style),
          ),
          const SizedBox(width: _desktopEmployeeColumnGap),
          Expanded(
            flex: _desktopEmployeeDepartmentFlex,
            child: Text(loc.t('subdivision') ?? 'Подразделение', style: style),
          ),
          const SizedBox(width: _desktopEmployeeColumnGap),
          Expanded(
            flex: _desktopEmployeeHeaderPositionFlex,
            child: Transform.translate(
              offset: const Offset(_desktopEmployeePositionHeaderLeftShift, 0),
              child: Text(loc.t('position') ?? 'Должность', style: style),
            ),
          ),
          const SizedBox(width: _desktopEmployeeColumnGap),
          Expanded(
            flex: _desktopEmployeeHeaderRateFlex,
            child: Text(rateHeader, style: style, textAlign: TextAlign.left),
          ),
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
    required this.showTranslit,
    required this.canEdit,
    required this.rateHeader,
    required this.onEdit,
    required this.onDelete,
  });

  final Employee employee;
  final LocalizationService loc;
  final bool showTranslit;
  final bool canEdit;
  final String rateHeader;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String positionDisplay(Employee e, LocalizationService loc) {
    final pos = e.positionRole;
    if (pos == null || pos.isEmpty) return '—';
    return loc.roleDisplayName(pos);
  }

  String _rateUnitLabel() {
    final isRu = loc.currentLanguageCode == 'ru';
    final isPerShift = employee.paymentType == 'per_shift';
    if (isRu) return isPerShift ? 'за смену' : 'за час';
    return isPerShift
        ? (loc.t('payment_per_shift') ?? 'per shift').toLowerCase()
        : (loc.t('payment_hourly') ?? 'hourly').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = isHandheldNarrowLayout(context);
    return isMobile ? _buildMobile(context) : _buildDesktop(context);
  }

  /// ПК: одна горизонтальная строка, все колонки вертикально по центру
  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    final est = context.read<AccountManagerSupabase>().establishment;
    final currencySymbol = est?.currencySymbol ?? Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
    final isPerShift = employee.paymentType == 'per_shift';
    final rate = isPerShift ? employee.ratePerShift : employee.hourlyRate;
    final rateUnit = _rateUnitLabel();
    final rateStr = rate != null && rate > 0
        ? '${NumberFormatUtils.formatInt(rate)} $currencySymbol · ${rateUnit.toLowerCase()}'
        : '—';
    final sectionStr = (employee.department == 'kitchen' && employee.section != null && employee.section!.isNotEmpty)
        ? (loc.t('section_${employee.section}') != 'section_${employee.section}'
            ? loc.t('section_${employee.section}')
            : (employee.kitchenSection?.getLocalizedName(loc.currentLanguageCode) ?? employee.section!))
        : null;
    final deptLabel = loc.departmentDisplayName(employee.department) != employee.department
        ? loc.departmentDisplayName(employee.department)
        : employee.departmentDisplayName;
    final deptStr = sectionStr != null ? '$deptLabel · $sectionStr' : deptLabel;
    final displayName = employeeDisplayName(employee, translit: showTranslit);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _desktopEmployeeRowHorizontalPadding,
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Аватар
              _EmployeeAvatar(employee: employee, radius: 18),
              const SizedBox(width: 10),
              // Имя + email
              Expanded(
                flex: _desktopEmployeeNameFlex,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
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
              const SizedBox(width: _desktopEmployeeColumnGap),
              // Подразделение (+ цех)
              Expanded(
                flex: _desktopEmployeeDepartmentFlex,
                child: Transform.translate(
                  offset: const Offset(_desktopEmployeeDeptRowLeftShift, 0),
                  child: Text(
                    deptStr,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: _desktopEmployeeColumnGap),
              // Должность
              Expanded(
                flex: _desktopEmployeeRowPositionFlex,
                child: Transform.translate(
                  offset: const Offset(_desktopEmployeePositionRowLeftShift, 0),
                  child: Text(
                    positionDisplay(employee, loc),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: _desktopEmployeeColumnGap),
              // Ставка (без иконки на ПК — экономит ширину и убирает overflow)
              Expanded(
                flex: _desktopEmployeeRowRateFlex,
                child: rateStr == '—'
                    ? Align(
                        alignment: Alignment.center,
                        child: Transform.translate(
                          offset: const Offset(-57, 0),
                          child: Text(
                            rateStr,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(left: _desktopEmployeeRateRowLeftInset),
                        child: Text(
                          rateStr,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                        ),
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
    final rateUnit = _rateUnitLabel();
    final rateStr = rate != null && rate > 0
        ? '${NumberFormatUtils.formatInt(rate)} $currencySymbol · ${rateUnit.toLowerCase()}'
        : '—';
    final sectionStr = (employee.department == 'kitchen' && employee.section != null && employee.section!.isNotEmpty)
        ? (loc.t('section_${employee.section}') != 'section_${employee.section}'
            ? loc.t('section_${employee.section}')
            : (employee.kitchenSection?.getLocalizedName(loc.currentLanguageCode) ?? employee.section!))
        : null;
    final deptLabel = loc.departmentDisplayName(employee.department) != employee.department
        ? loc.departmentDisplayName(employee.department)
        : employee.departmentDisplayName;
    final deptStr = sectionStr != null ? '$deptLabel · $sectionStr' : deptLabel;
    final posStr = positionDisplay(employee, loc);
    final subStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final displayName = employeeDisplayName(employee, translit: showTranslit);

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
                      displayName,
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
                        Text(
                          '${rateHeader.toLowerCase()}: $rateStr',
                          style: subStyle?.copyWith(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
  late bool _isOwner;
  String? _positionRole;
  late String _paymentType;
  late bool _isActive;
  late bool _dataAccessEnabled;
  late bool _canEditOwnSchedule;
  late String _employmentStatus;
  DateTime? _employmentStartDate;
  DateTime? _employmentEndDate;
  DateTime? _birthday;
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
    _isOwner = widget.employee.hasRole('owner');
    _positionRole = widget.employee.positionRole;
    _paymentType = widget.employee.paymentType ?? 'hourly';
    _isActive = widget.employee.isActive;
    _dataAccessEnabled = widget.employee.dataAccessEnabled;
    _canEditOwnSchedule = widget.employee.canEditOwnSchedule;
    _employmentStatus = widget.employee.employmentStatus ?? 'permanent';
    _employmentStartDate = widget.employee.employmentStartDate;
    _employmentEndDate = widget.employee.employmentEndDate;
    _birthday = widget.employee.birthday;

    // Если должность ещё не задана (например, только owner) — подставляем первую из доступных.
    _positionRole ??= _positionOptionsFor(_department, _section).firstOrNull;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  List<String> _positionOptionsFor(String department, String? section) {
    if (department == 'kitchen') {
      final sec = (section?.trim().isNotEmpty == true)
          ? section!.trim()
          : (RolesConfig.kitchenSections().firstOrNull ?? 'hot_kitchen');
      return RolesConfig.kitchenRolesForSection(sec).map((e) => e.roleCode).toList();
    }
    if (department == 'bar') return RolesConfig.barRoles().map((e) => e.roleCode).toList();
    if (department == 'dining_room') return RolesConfig.hallRoles().map((e) => e.roleCode).toList();
    // management
    final base = RolesConfig.managementRoles().map((e) => e.roleCode).toList();
    for (final extra in ['general_manager', 'bar_manager', 'sous_chef']) {
      if (!base.contains(extra)) base.add(extra);
    }
    return base;
  }

  Future<void> _save() async {
    final loc = context.read<LocalizationService>();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите имя');
      return;
    }
    if (_positionRole == null || _positionRole!.trim().isEmpty) {
      setState(() => _error = (loc.t('position') ?? 'Должность') + ': ' + (loc.t('required') ?? 'обязательно'));
      return;
    }
    final rate = double.tryParse(_rateController.text.trim());
    setState(() { _saving = true; _error = null; });
    try {
      final roles = <String>[];
      if (_isOwner) roles.add('owner');
      roles.add(_positionRole!.trim());
      final updated = widget.employee.copyWith(
        fullName: name,
        department: _department,
        section: _department == 'kitchen' ? _section : null,
        roles: roles,
        paymentType: _paymentType,
        ratePerShift: _paymentType == 'per_shift' ? (rate ?? 0) : null,
        hourlyRate: _paymentType == 'hourly' ? rate : null,
        isActive: _isActive,
        dataAccessEnabled: _dataAccessEnabled,
        canEditOwnSchedule: _canEditOwnSchedule,
        employmentStatus: _employmentStatus,
        employmentStartDate: _employmentStartDate,
        employmentEndDate: _employmentEndDate,
        birthday: _birthday,
      );
      await context.read<AccountManagerSupabase>().updateEmployee(updated);
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final lower = msg.toLowerCase();
        final isPaymentSchemaError = lower.contains('hourly_rate') ||
            lower.contains('rate_per_shift') ||
            lower.contains('payment_type');
        final isSchemaError = isPaymentSchemaError ||
            lower.contains('pgrst204') ||
            (lower.contains('column') && lower.contains('exist'));
        setState(() {
          _error = isPaymentSchemaError
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
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: loc.t('full_name') ?? 'ФИО',
                          border: const OutlineInputBorder(),
                          filled: true,
                          isDense: false,
                          contentPadding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                          floatingLabelAlignment: FloatingLabelAlignment.start,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cake, size: 22),
                        title: Text(
                          _birthday == null
                              ? (loc.t('birthday') ?? 'День рождения') + ' — ' + (loc.t('not_specified') ?? 'не указано')
                              : '${loc.t('birthday') ?? 'День рождения'}: ${_birthday!.day.toString().padLeft(2, '0')}.${_birthday!.month.toString().padLeft(2, '0')}.${_birthday!.year}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_birthday != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () => setState(() => _birthday = null),
                                tooltip: loc.t('clear') ?? 'Очистить',
                              ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _birthday ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
                                  firstDate: DateTime(1920),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null && mounted) setState(() => _birthday = picked);
                              },
                              child: Text(_birthday == null ? (loc.t('set') ?? 'Указать') : (loc.t('change') ?? 'Изменить')),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _department,
                        decoration: InputDecoration(labelText: loc.t('department') ?? 'Отдел', border: const OutlineInputBorder(), filled: true),
                        items: _departmentKeys
                            .map((k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(loc.departmentDisplayName(k)),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _department = v ?? _department;
                          if (_department != 'kitchen') _section = null;
                          final opts = _positionOptionsFor(_department, _section);
                          if (_positionRole == null || !opts.contains(_positionRole)) {
                            _positionRole = opts.isNotEmpty ? opts.first : null;
                          }
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
                          onChanged: (v) => setState(() {
                            _section = v;
                            final opts = _positionOptionsFor(_department, _section);
                            if (_positionRole == null || !opts.contains(_positionRole)) {
                              _positionRole = opts.isNotEmpty ? opts.first : null;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _positionRole,
                        decoration: InputDecoration(
                          labelText: loc.t('position') ?? 'Должность',
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
                        items: _positionOptionsFor(_department, _section)
                            .map((code) => DropdownMenuItem(value: code, child: Text(_roleLabel(code, loc))))
                            .toList(),
                        onChanged: (v) => setState(() => _positionRole = v),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(loc.t('role_owner') ?? 'Собственник'),
                        value: _isOwner,
                        onChanged: (v) => setState(() => _isOwner = v),
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
                      if (widget.canToggleDataAccess &&
                          !widget.employee.hasRole('owner') &&
                          (_department == 'kitchen' || _department == 'bar' || _department == 'dining_room')) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _employmentStatus,
                          decoration: InputDecoration(labelText: loc.t('employment_status') ?? 'Статус', border: const OutlineInputBorder(), filled: true),
                          items: [
                            DropdownMenuItem(value: 'permanent', child: Text(loc.t('employment_permanent') ?? 'Постоянный')),
                            DropdownMenuItem(value: 'temporary', child: Text(loc.t('employment_temporary') ?? 'Временный')),
                          ],
                          onChanged: (v) => setState(() {
                            _employmentStatus = v ?? 'permanent';
                            if (_employmentStatus == 'permanent') {
                              _employmentStartDate = null;
                              _employmentEndDate = null;
                            }
                          }),
                        ),
                        if (_employmentStatus == 'temporary') ...[
                          const SizedBox(height: 8),
                          ListTile(
                            title: Text(loc.t('employment_period') ?? 'Период доступа'),
                            subtitle: Text(
                              (_employmentStartDate != null ? '${_employmentStartDate!.day}.${_employmentStartDate!.month}.${_employmentStartDate!.year}' : '—') +
                                  ' – ' +
                                  (_employmentEndDate != null ? '${_employmentEndDate!.day}.${_employmentEndDate!.month}.${_employmentEndDate!.year}' : '—'),
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                final start = await showDatePicker(
                                  context: context,
                                  initialDate: _employmentStartDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (start != null && mounted) {
                                  final end = await showDatePicker(
                                    context: context,
                                    initialDate: _employmentEndDate ?? start.add(const Duration(days: 30)),
                                    firstDate: start,
                                    lastDate: DateTime(2030),
                                  );
                                  if (mounted) setState(() {
                                    _employmentStartDate = start;
                                    _employmentEndDate = end;
                                  });
                                }
                              },
                              child: Text(loc.t('set_period') ?? 'Задать период'),
                            ),
                          ),
                        ],
                      ],
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
