import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../services/profile_service.dart';
import '../services/inbox_service.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран профиля пользователя
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  double? _earnedSalary;
  double? _currentMonthSalary;
  bool _loadingSalary = true;

  @override
  void initState() {
    super.initState();
    _loadSalaryData();
  }

  Future<void> _loadSalaryData() async {
    final account = context.read<AccountManagerSupabase>();
    final employee = account.currentEmployee;
    final establishment = account.establishment;

    if (employee == null || establishment == null) {
      setState(() => _loadingSalary = false);
      return;
    }

    // Рассчитываем зарплату только если у сотрудника есть должность (не владелец без роли)
    if (employee.hasRole('owner') && employee.roles.length <= 1) {
      setState(() => _loadingSalary = false);
      return;
    }

    try {
      final earned = await ProfileService.calculateEarnedSalary(employee, establishment.id);
      final currentMonth = await ProfileService.calculateCurrentMonthSalary(employee, establishment.id);

      if (mounted) {
        setState(() {
          _earnedSalary = earned;
          _currentMonthSalary = currentMonth;
          _loadingSalary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingSalary = false);
      }
    }
  }

  void _showEditProfile(BuildContext context) {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final establishment = account.establishment;
    if (emp == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProfileEditDialog(
        employee: emp,
        onSaved: (updated) async {
          if (establishment != null &&
              updated.birthday != null &&
              _birthdayChanged(emp.birthday, updated.birthday)) {
            final inboxService = InboxService(context.read<AccountManagerSupabase>().supabase);
            await inboxService.insertBirthdayChangeNotification(
              establishmentId: establishment.id,
              employeeId: emp.id,
              employeeName: updated.fullName.trim().isNotEmpty ? updated.fullName : emp.fullName,
              newBirthday: updated.birthday,
              previousBirthday: emp.birthday,
            );
          }
          await account.updateEmployee(updated);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
            setState(() {});
          }
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  static bool _birthdayChanged(DateTime? a, DateTime? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final establishment = accountManager.establishment;
    final localization = context.watch<LocalizationService>();
    final pref = context.watch<OwnerViewPreferenceService>();

    if (currentEmployee == null || establishment == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isOwner = currentEmployee.hasRole('owner');
    final hasPosition = currentEmployee.positionRole != null;
    // Личный график и ЗП: у собственника — только когда выбрана роль «должность»; у сотрудников — всегда при наличии должности
    final showScheduleAndSalary = hasPosition && (isOwner ? !pref.viewAsOwner : true);

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ??
            (GoRouter.of(context).canPop() ? appBarBackButton(context) : null),
        title: Text(localization.t('profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditProfile(context),
            tooltip: localization.t('edit_profile'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Компания
            _buildCompanySection(establishment, localization),

            if (isOwner) ...[
              const SizedBox(height: 24),
              _buildPinCodeSection(establishment, localization),
            ],

            const SizedBox(height: 24),

            // Профиль: Собственник/должность, фото, имя, фамилия, почта
            _buildProfileInfo(currentEmployee, establishment, localization, isOwner),

            const SizedBox(height: 24),

            // Личный график и ЗП — только когда выбрана роль должности (не собственник)
            if (showScheduleAndSalary) ...[
              _buildScheduleAndSalarySection(currentEmployee, establishment, localization),
              const SizedBox(height: 24),
            ],

            // Смена пароля
            _buildChangePasswordSection(localization),
            const SizedBox(height: 24),

            if (isOwner) ...[
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(localization.t('establishments')),
                subtitle: Text(localization.t('delete_profile_owner_hint')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/establishments'),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  localization.t('delete_profile'),
                  style: const TextStyle(color: Colors.red),
                ),
                subtitle: Text(localization.t('delete_owner_account_hint')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmDeleteOwnerAccount(context, localization, accountManager),
              ),
              const SizedBox(height: 24),
            ] else ...[
              _buildDeleteProfileSection(localization, accountManager, currentEmployee),
              const SizedBox(height: 24),
            ],

            // Выход
            _buildLogoutSection(localization),
          ],
        ),
      ),
    );
  }

  void _copyPin(BuildContext context, String pinCode) {
    Clipboard.setData(ClipboardData(text: pinCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('pin_copied'))),
    );
  }

  Widget _buildPinCodeSection(Establishment establishment, LocalizationService localization) {
    final loc = localization;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t('generated_pin'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              loc.t('pin_auto_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      establishment.pinCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: () => _copyPin(context, establishment.pinCode),
                  icon: const Icon(Icons.copy),
                  tooltip: loc.t('copy_pin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanySection(Establishment establishment, LocalizationService localization) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localization.t('company'),
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              establishment.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _showPositionPicker(BuildContext context, Employee employee, LocalizationService loc, AccountManagerSupabase accountManager) {
    const visiblePositionCodes = [
      'executive_chef',
      'bar_manager',
      'floor_manager',
      'general_manager',
    ];
    String getDisplayName(String? code) {
      if (code == null || code.isEmpty) return loc.t('no_position');
      final key = 'role_$code';
      final t = loc.t(key);
      return (t != key && t.isNotEmpty) ? t : code;
    }
    final availablePositions = [
      {'code': null, 'name': loc.t('no_position')},
      ...visiblePositionCodes.map((code) => {'code': code, 'name': getDisplayName(code)}),
    ];
    final currentPosition = employee.positionRole;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('select_position')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: availablePositions.map((pos) {
            final code = pos['code'] as String?;
            final isSelected = code == currentPosition;
            return ListTile(
              title: Text(pos['name']!),
              trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                if (isSelected) {
                  Navigator.of(ctx).pop();
                  return;
                }
                final newRoles = ['owner'];
                if (code != null && code.isNotEmpty) newRoles.add(code);
                final updated = employee.copyWith(roles: newRoles, updatedAt: DateTime.now());
                try {
                  await accountManager.updateEmployee(updated);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${loc.t('error') ?? 'Ошибка'}: $e')),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProfileInfo(Employee employee, Establishment establishment, LocalizationService localization, bool isOwner) {
    final position = employee.positionRole;
    final accountManager = context.read<AccountManagerSupabase>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Собственник и должность — тап по области для смены должности
            GestureDetector(
              onTap: isOwner
                  ? () => _showPositionPicker(context, employee, localization, accountManager)
                  : null,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  if (isOwner)
                    Chip(
                      label: Text(localization.t('owner'), style: const TextStyle(fontSize: 12)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  Chip(
                    label: Text(
                      position != null && position.isNotEmpty
                          ? localization.roleDisplayName(position)
                          : localization.t('no_position'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Фото (можно изменить по тапу)
            Center(
              child: GestureDetector(
                onTap: () => _showEditProfile(context),
                child: _buildAvatar(employee, 80),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              localization.t('tap_to_change_photo'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Имя и фамилия
            Builder(
              builder: (_) {
                final displayFullName =
                    localization.displayPersonNameForUi(employee.fullName);
                final parts = displayFullName.trim().split(RegExp(r'\s+'));
                final name =
                    parts.isNotEmpty ? parts.first : displayFullName;
                final displaySurname = employee.surname?.trim().isNotEmpty == true
                    ? localization.displayPersonNameForUi(employee.surname!)
                    : null;
                final surname = employee.surname?.trim().isNotEmpty == true
                    ? displaySurname
                    : (parts.length > 1 ? parts.sublist(1).join(' ') : null);
                return Column(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    if (surname != null && surname.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        surname,
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
              },
            ),

            // Email
            const SizedBox(height: 8),
            Text(
              employee.email,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (employee.birthday != null) ...[
              const SizedBox(height: 8),
              Text(
                '${localization.t('birthday') ?? 'День рождения'}: ${DateFormat('dd.MM.yyyy').format(employee.birthday!)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleAndSalarySection(Employee employee, Establishment establishment, LocalizationService localization) {
    final currencySymbol = establishment.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Личный график (1 строка — только этот сотрудник)
        ListTile(
          leading: const Icon(Icons.calendar_month),
          title: Text(localization.t('personal_schedule')),
          subtitle: Text(localization.t('personal_schedule_subtitle')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/schedule?personal=1'),
        ),

        // ЗП за отработанный период
        ListTile(
          leading: const Icon(Icons.payments),
          title: Text(localization.t('earned_salary')),
          subtitle: _loadingSalary
              ? Text(localization.t('loading'))
              : Text(_earnedSalary != null
                  ? ProfileService.formatSalary(_earnedSalary!, currencySymbol)
                  : localization.t('salary_unavailable')),
        ),

        // ЗП за текущий календарный месяц
        ListTile(
          leading: const Icon(Icons.account_balance_wallet),
          title: Text(localization.t('current_month_salary')),
          subtitle: _loadingSalary
              ? Text(localization.t('loading'))
              : Text(_currentMonthSalary != null
                  ? ProfileService.formatSalary(_currentMonthSalary!, currencySymbol)
                  : localization.t('salary_unavailable')),
        ),

        // Зарплата за выбранный период
        ListTile(
          leading: const Icon(Icons.date_range),
          title: Text(localization.t('salary_for_period') ?? 'Зарплата за период'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showSalaryPeriodPicker(context, employee, establishment, localization),
        ),
      ],
    );
  }

  Future<void> _showSalaryPeriodPicker(BuildContext context, Employee employee, Establishment establishment, LocalizationService loc) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      helpText: loc.t('salary_period') ?? 'Период',
    );
    if (range == null || !context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    final amount = await ProfileService.calculateSalaryForPeriod(
      employee,
      establishment.id,
      DateTime(range.start.year, range.start.month, range.start.day),
      DateTime(range.end.year, range.end.month, range.end.day),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading
    final df = DateFormat('dd.MM.yyyy');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('salary_for_period') ?? 'Зарплата за период'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${df.format(range.start)} — ${df.format(range.end)}', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              ProfileService.formatSalary(amount, establishment.currencySymbol),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('close') ?? 'Закрыть'),
          ),
        ],
      ),
    );
  }

  static List<Establishment> _ownerDeletionRoots(List<Establishment> all) {
    final ids = all.map((e) => e.id).toSet();
    final roots = all.where((e) {
      final p = e.parentEstablishmentId;
      if (p == null || p.isEmpty) return true;
      return !ids.contains(p);
    }).toList();
    roots.sort((a, b) => a.name.compareTo(b.name));
    return roots;
  }

  Map<ShortcutActivator, Intent> get _noPasteShortcuts =>
      <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const DoNothingAndStopPropagationIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const DoNothingAndStopPropagationIntent(),
        const SingleActivator(LogicalKeyboardKey.insert, shift: true):
            const DoNothingAndStopPropagationIntent(),
      };

  bool get _disablePasteForDeleteConfirm =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;

  Widget _buildManualOnlyRestrictedInput({required Widget child}) {
    if (!_disablePasteForDeleteConfirm) return child;
    return Shortcuts(
      shortcuts: _noPasteShortcuts,
      child: child,
    );
  }

  Future<void> _confirmDeleteOwnerAccount(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase account,
  ) async {
    void closeProgressDialogIfOpen() {
      if (!context.mounted) return;
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    List<Establishment> list;
    try {
      list = await account.getEstablishmentsForOwner().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('owner_delete_establishments_timeout'),
      );
    } catch (e) {
      closeProgressDialogIfOpen();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('error')}: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    closeProgressDialogIfOpen();

    final roots = _ownerDeletionRoots(list);
    final emailController = TextEditingController(
      text: (account.currentEmployee?.email ??
              Supabase.instance.client.auth.currentUser?.email ??
              '')
          .trim(),
    );
    final passwordController = TextEditingController();
    final pinControllers = <String, TextEditingController>{
      for (final r in roots) r.id: TextEditingController(),
    };

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_owner_account_confirm_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.t('delete_owner_account_confirm_body')),
              const SizedBox(height: 8),
              Text(
                loc.t('delete_owner_account_confirm_warning'),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('delete_owner_account_confirm_final_check'),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildManualOnlyRestrictedInput(
                child: TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  enableInteractiveSelection: !_disablePasteForDeleteConfirm,
                  decoration: InputDecoration(
                    labelText: loc.t('delete_owner_account_email_label'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildManualOnlyRestrictedInput(
                child: TextField(
                  controller: passwordController,
                  obscureText: true,
                  enableInteractiveSelection: !_disablePasteForDeleteConfirm,
                  decoration: InputDecoration(
                    labelText: loc.t('password'),
                    hintText: loc.t('enter_password'),
                  ),
                ),
              ),
              ...roots.map((r) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: pinControllers[r.id],
                    obscureText: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: loc.t('delete_owner_account_pin_for').replaceAll('%s', r.name),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete_owner_account')),
          ),
        ],
      ),
    );

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final pins = <String, String>{};
    for (final r in roots) {
      pins[r.id] = pinControllers[r.id]!.text.trim();
    }
    emailController.dispose();
    passwordController.dispose();
    for (final c in pinControllers.values) {
      c.dispose();
    }

    if (ok != true || !context.mounted) return;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('delete_owner_account_email_required'))),
      );
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('password_required'))),
      );
      return;
    }
    for (final r in roots) {
      if ((pins[r.id] ?? '').isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('company_pin_required'))),
        );
        return;
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(loc.t('delete_owner_account_progress'))),
          ],
        ),
      ),
    );
    try {
      await account.deleteOwnerAccount(
        email: email,
        password: password,
        pinsByEstablishmentId: pins,
      );
      closeProgressDialogIfOpen();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('delete_owner_account_done'))),
        );
        context.go('/login');
      }
    } catch (e) {
      closeProgressDialogIfOpen();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.t('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDeleteProfileSection(
    LocalizationService loc,
    AccountManagerSupabase account,
    Employee employee,
  ) {
    return ListTile(
      leading: const Icon(Icons.person_off, color: Colors.red),
      title: Text(
        loc.t('delete_profile'),
        style: const TextStyle(color: Colors.red),
      ),
      subtitle: Text(loc.t('delete_profile_hint')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _confirmDeleteEmployeeProfile(context, loc, account, employee),
    );
  }

  Future<void> _confirmDeleteEmployeeProfile(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase account,
    Employee employee,
  ) async {
    void closeProgressDialogIfOpen() {
      if (!context.mounted) return;
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_profile_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('delete_profile_confirm_body')),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              obscureText: true,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: loc.t('company_pin'),
                hintText: loc.t('enter_company_pin'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete_profile')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      pinController.dispose();
      return;
    }
    final pin = pinController.text.trim();
    pinController.dispose();
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('company_pin_required'))),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(loc.t('delete_profile_progress'))),
          ],
        ),
      ),
    );
    try {
      await account
          .deleteEmployeeWithPin(employeeId: employee.id, pinCode: pin)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception('delete_profile_timeout'),
          );
      closeProgressDialogIfOpen();
      await account.logout().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('delete_profile_logout_timeout'),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('delete_profile_done'))),
        );
        context.go('/login');
      }
    } catch (e) {
      closeProgressDialogIfOpen();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.t('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildChangePasswordSection(LocalizationService localization) {
    return ListTile(
      leading: const Icon(Icons.lock),
      title: Text(localization.t('change_password') ?? 'Сменить пароль'),
      subtitle: Text(localization.t('change_password_hint') ?? 'Введите старый пароль и новый дважды'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showChangePasswordDialog(context),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ChangePasswordDialog(
        onCancel: () => Navigator.of(ctx).pop(),
        onSuccess: () {
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LocalizationService>().t('change_password_email_sent') ??
                    'Письмо с подтверждением отправлено. Перейдите по ссылке.',
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogoutSection(LocalizationService localization) {
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: Text(
        localization.t('logout'),
        style: const TextStyle(color: Colors.red),
      ),
      onTap: () => _logout(context),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.logout();
    if (context.mounted) context.go('/login');
  }

  Widget _buildAvatar(Employee emp, double size) {
    final url = emp.avatarUrl;
    if (url != null && url.isNotEmpty) {
      // Используем Image.network на вебе — CachedNetworkImage иногда кэширует 404
      return ClipOval(
        child: kIsWeb
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarPlaceholder(size),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : Container(color: Colors.grey[300],
                        child: const Icon(Icons.person, size: 40)),
              )
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey[300],
                    child: const Icon(Icons.person, size: 40)),
                errorWidget: (_, __, ___) => _avatarPlaceholder(size),
              ),
      );
    }
    return _avatarPlaceholder(size);
  }

  Widget _avatarPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: size * 0.5, color: Colors.grey),
    );
  }
}

/// Редактирование профиля: имя, фамилия, фото — виджет по центру экрана
class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.employee, required this.onSaved, required this.onCancel});

  final Employee employee;
  final Future<void> Function(Employee) onSaved;
  final VoidCallback onCancel;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  String? _avatarUrl;
  DateTime? _birthday;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fn = widget.employee.fullName;
    final parts = fn.split(' ');
    _nameController = TextEditingController(text: parts.isNotEmpty ? parts.first : fn);
    _surnameController = TextEditingController(
      text: widget.employee.surname ?? (parts.length > 1 ? parts.sublist(1).join(' ') : ''),
    );
    _avatarUrl = widget.employee.avatarUrl;
    _birthday = widget.employee.birthday;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    Uint8List? bytes;

    if (kIsWeb) {
      // На вебе FilePicker надёжнее чем image_picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      bytes = result.files.single.bytes;
    } else {
      // На мобильных — показываем выбор галерея/камера
      final loc = context.read<LocalizationService>();
      final isGallery = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(loc.t('photo_from_gallery')),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(loc.t('photo_from_camera')),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
      if (isGallery == null || !mounted) return;
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: isGallery ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      bytes = await file.readAsBytes();
    }

    if (bytes == null || bytes.isEmpty || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final compressed = await ImageService().compressToMaxBytes(bytes, maxBytes: 250 * 1024) ?? bytes;
      final supabase = SupabaseService();
      const bucket = 'avatars';
      final fileName = '${widget.employee.id}.jpg';
      await supabase.client.storage
          .from(bucket)
          .uploadBinary(fileName, compressed, fileOptions: FileOptions(upsert: true));
      // Cache-busting: добавляем timestamp чтобы CachedNetworkImage не брал старый кэш
      final baseUrl = supabase.client.storage.from(bucket).getPublicUrl(fileName);
      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        final isBucketNotFound = errStr.contains('Bucket not found') || errStr.contains('404');
        setState(() {
          _error = isBucketNotFound
              ? '${context.read<LocalizationService>().t('photo_upload_error')}: bucket "avatars" не найден.'
              : '${context.read<LocalizationService>().t('photo_upload_error')}: $e';
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.read<LocalizationService>().t('name_required'));
      return;
    }
    final surname = _surnameController.text.trim();
    final fullName = surname.isEmpty ? name : '$name $surname';
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Сохраняем чистый URL без cache-busting параметра
      final cleanAvatarUrl = _avatarUrl?.split('?t=').first;
      final updated = widget.employee.copyWith(
        fullName: fullName,
        surname: surname.isEmpty ? '' : surname,
        avatarUrl: cleanAvatarUrl ?? widget.employee.avatarUrl,
        birthday: _birthday,
      );
      await widget.onSaved(updated);
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        final msg = e.toString().toLowerCase();
        if (msg.contains('birthday')) {
          _error = context.read<LocalizationService>().t('employee_save_error_birthday_migration')
              ?? 'Не удалось сохранить день рождения. В Supabase SQL Editor выполните миграцию 20260317100000_employee_birthday_and_notifications.sql';
        } else if (msg.contains('payment') || msg.contains('column') || msg.contains('pgrst')) {
          _error = context.read<LocalizationService>().t('employee_save_error_schema');
        } else {
          _error = e.toString();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.read<LocalizationService>();
    final screenH = MediaQuery.of(context).size.height;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: (screenH * 0.85).clamp(520.0, 800.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(loc.t('edit_profile'), style: theme.textTheme.titleLarge),
                    IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _pickPhoto,
                    child: Stack(
                      children: [
                        _avatarUrl != null
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: _avatarUrl!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _avatarPlaceholder(120),
                                  errorWidget: (_, __, ___) => _avatarPlaceholder(120),
                                ),
                              )
                            : _avatarPlaceholder(120),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(Icons.camera_alt, color: theme.colorScheme.onPrimary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text(loc.t('tap_to_change_photo'), style: theme.textTheme.bodySmall)),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: loc.t('name'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _surnameController,
                  decoration: InputDecoration(
                    labelText: loc.t('surname'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cake),
                  title: Text(
                    _birthday == null
                        ? (loc.t('birthday') ?? 'День рождения') + ' — ' + (loc.t('not_specified') ?? 'не указано')
                        : DateFormat('dd.MM.yyyy').format(_birthday!),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_birthday != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
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
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: widget.onCancel, child: Text(loc.t('cancel') ?? 'Отмена'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _save,
                        child: _isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(loc.t('save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle),
      child: Icon(Icons.person, size: size * 0.5, color: Colors.grey[600]),
    );
  }
}

/// Диалог смены пароля: старый пароль, новый, подтверждение.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.onCancel,
    required this.onSuccess,
  });

  final VoidCallback onCancel;
  final VoidCallback onSuccess;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final loc = context.read<LocalizationService>();
    final result = await context.read<EmailService>().requestChangePassword(
      oldPassword: _oldController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.ok) {
        widget.onSuccess();
      } else {
        final e = result.error;
        _error = e == 'invalid_old_password'
            ? (loc.t('invalid_old_password') ?? 'Неверный текущий пароль')
            : e == 'password_min_6_chars'
                ? (loc.t('password_min_6') ?? 'Пароль не менее 6 символов')
                : e == 'invalid_session'
                    ? (loc.t('session_expired') ?? 'Сессия истекла. Войдите снова.')
                    : e ?? loc.t('error') ?? 'Ошибка';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.read<LocalizationService>();

    return AlertDialog(
      title: Text(loc.t('change_password') ?? 'Сменить пароль'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('change_password_description') ?? 'Введите текущий пароль и новый дважды. На почту придёт ссылка для подтверждения.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _oldController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: loc.t('current_password') ?? 'Текущий пароль',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return loc.t('password_required') ?? 'Введите пароль';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: loc.t('new_password') ?? 'Новый пароль',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                ),
                validator: (v) {
                  if (v == null || v.length < 6) return loc.t('password_min_6') ?? 'Минимум 6 символов';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: loc.t('confirm_password') ?? 'Подтвердите пароль',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v != _newController.text) return loc.t('passwords_mismatch') ?? 'Пароли не совпадают';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : widget.onCancel,
          child: Text(loc.t('cancel') ?? 'Отмена'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(loc.t('send_confirmation') ?? 'Отправить'),
        ),
      ],
    );
  }
}
