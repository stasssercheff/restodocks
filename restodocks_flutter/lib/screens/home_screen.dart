import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import '../services/services.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/getting_started_document.dart';

/// Главный экран — контент домашней вкладки по роли.
/// Нижняя навигация управляется AppShell (ShellRoute).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _firstEntryCheckDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstEntry());
  }

  Future<void> _checkFirstEntry() async {
    if (_firstEntryCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    if (emp == null) return;
    _firstEntryCheckDone = true;
    // Показываем только если не было ни одной сессии в этой учётной записи.
    if (emp.firstSessionAt != null) return;
    // Фиксируем первую сессию на сервере, затем показываем окно (один раз).
    try {
      await accountManager.supabase.client
          .from('employees')
          .update({'first_session_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', emp.id);
    } catch (_) {
      // При ошибке сети не показываем, чтобы не спамить при каждом входе.
      return;
    }
    if (!mounted) return;
    await GettingStartedReadService.setRead(emp.id);
    if (!mounted) return;
    _showFirstEntryDialog(context, emp.id);
  }

  static void _showFirstEntryDialog(BuildContext context, String employeeId) {
    final loc = context.read<LocalizationService>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FirstEntryDialog(
        employeeId: employeeId,
        loc: loc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: GoRouter.of(context).canPop() ? appBarBackButton(context) : null,
        title: Text(loc.t('app_name')),
      ),
      body: _buildContent(context, currentEmployee),
    );
  }

  Widget _buildContent(BuildContext context, Employee employee) {
    if (employee.hasRole('owner')) {
      final pref = context.read<OwnerViewPreferenceService>();
      if (employee.positionRole != null && !pref.viewAsOwner) {
        if (employee.canViewDepartment('management')) {
          return ManagementHomeContent(employee: employee);
        }
        return StaffHomeContent(employee: employee);
      }
      return const OwnerHomeContent();
    }
    if (employee.canViewDepartment('management')) {
      return ManagementHomeContent(employee: employee);
    }
    return StaffHomeContent(employee: employee);
  }
}

/// Диалог первого входа: документ «Начало работы» с раскрытием разделов и галочка о прочтении.
class _FirstEntryDialog extends StatefulWidget {
  const _FirstEntryDialog({required this.employeeId, required this.loc});

  final String employeeId;
  final LocalizationService loc;

  @override
  State<_FirstEntryDialog> createState() => _FirstEntryDialogState();
}

class _FirstEntryDialogState extends State<_FirstEntryDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: screenHeight * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                widget.loc.t('getting_started') ?? 'Начало работы с Restodocks',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 400,
              child: const GettingStartedDocument(showTitle: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    title: Text(
                      widget.loc.t('getting_started_confirmed') ?? 'Я прочитал(а) инструкцию',
                      style: theme.textTheme.bodyMedium,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _confirmed
                        ? () async {
                            await GettingStartedReadService.setRead(widget.employeeId);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        : null,
                    child: Text(widget.loc.t('start_work') ?? 'Начать работу'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран личного кабинета — меню: Профиль, Настройки, Выход.
class PersonalCabinetScreen extends StatelessWidget {
  const PersonalCabinetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (employee == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('personal_cabinet'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(loc.t('profile')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(loc.t('settings')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(loc.t('logout'), style: const TextStyle(color: Colors.red)),
              onTap: () async {
                await accountManager.logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
