import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../utils/translit_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран создания группового чата: выбор участников и название.
class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;
    if (_selectedIds.isEmpty) {
      final loc = context.read<LocalizationService>();
      AppToastService.show(loc.t('group_chat_select_at_least_one') ?? 'Выберите хотя бы одного участника', duration: const Duration(seconds: 2));
      return;
    }
    setState(() => _creating = true);
    try {
      final memberIds = _selectedIds.toList();
      if (!memberIds.contains(emp.id)) memberIds.add(emp.id);
      final room = await context.read<GroupChatService>().createRoom(
            establishmentId: est.id,
            createdByEmployeeId: emp.id,
            memberEmployeeIds: memberIds,
            name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          );
      if (mounted && room != null) {
        context.pop();
        context.push('/inbox/group/${room.id}');
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        AppToastService.show('${loc.t('error_short') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;

    return FutureBuilder<List<Employee>>(
      future: est == null ? Future.value([]) : acc.getEmployeesForEstablishment(est.id),
      builder: (context, snapshot) {
        final employees = snapshot.data ?? [];
        final others = employees.where((e) => e.id != emp?.id).toList();
        final showTranslit = context.read<ScreenLayoutPreferenceService>().showNameTranslit;

        return Scaffold(
          appBar: AppBar(
            leading: appBarBackButton(context),
            title: Text(loc.t('group_chat_new') ?? 'Новый групповой чат'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: loc.t('group_chat_name') ?? 'Название чата (необязательно)',
                    border: const OutlineInputBorder(),
                    hintText: loc.t('group_chat_name_hint') ?? 'Например: Кухня, Смена 15.03',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    loc.t('group_chat_select_members') ?? 'Участники',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: others.length,
                  itemBuilder: (context, index) {
                    final e = others[index];
                    final selected = _selectedIds.contains(e.id);
                    final name = showTranslit ? cyrillicToLatin(e.fullName) : e.fullName;
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedIds.add(e.id);
                          } else {
                            _selectedIds.remove(e.id);
                          }
                        });
                      },
                      title: Text(name),
                      subtitle: e.roles.isNotEmpty
                          ? Text(e.roles.map((r) => loc.roleDisplayName(r)).where((s) => s.isNotEmpty).join(', '))
                          : null,
                      secondary: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          (e.fullName.isNotEmpty ? e.fullName[0] : '?').toUpperCase(),
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _creating ? null : _create,
                      icon: _creating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.group_add),
                      label: Text(loc.t('group_chat_create') ?? 'Создать чат'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
