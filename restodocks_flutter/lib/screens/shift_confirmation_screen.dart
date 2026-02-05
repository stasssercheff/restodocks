import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/schedule_storage_service.dart';
import '../services/services.dart';

/// Подтверждение присутствия на смене: сегодня (или выбранная дата) — список людей по графику, галочки «присутствовал».
/// Доступно шефу и су-шефу.
class ShiftConfirmationScreen extends StatefulWidget {
  const ShiftConfirmationScreen({super.key});

  @override
  State<ShiftConfirmationScreen> createState() => _ShiftConfirmationScreenState();
}

class _ShiftConfirmationScreenState extends State<ShiftConfirmationScreen> {
  ScheduleModel _model = ScheduleModel(startDate: DateTime.now(), numWeeks: 1);
  DateTime _selectedDate = DateTime.now();
  String? _establishmentId;
  bool _loading = true;
  bool _saving = false;

  static String _dateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    setState(() { _loading = true; _establishmentId = est.id; });
    try {
      final model = await loadSchedule(est.id);
      if (mounted) {
        setState(() {
          _model = model;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  /// Слоты, у которых на выбранную дату стоит смена (не выходной).
  List<ScheduleSlot> get _slotsOnShift {
    final list = <ScheduleSlot>[];
    for (final slot in _model.slots) {
      final a = _model.getAssignment(slot.id, _selectedDate);
      if (a == '1') list.add(slot);
    }
    return list;
  }

  bool _isConfirmed(ScheduleSlot slot) {
    return _model.getConfirmation(slot.id, _selectedDate) == '1';
  }

  void _setConfirmed(ScheduleSlot slot, bool value) {
    setState(() {
      _model = _model.setConfirmation(slot.id, _selectedDate, value ? '1' : '0');
    });
  }

  Future<void> _save() async {
    if (_establishmentId == null) return;
    setState(() => _saving = true);
    try {
      await saveSchedule(_establishmentId!, _model);
      if (mounted) {
        setState(() => _saving = false);
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('shift_confirmations_saved') ?? 'Подтверждения смены сохранены')));
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canEdit = emp?.canEditSchedule ?? false;

    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('shift_confirmation') ?? 'Подтверждение смены'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  loc.t('shift_confirmation_chef_only') ?? 'Подтверждать смены могут только шеф-повар и су-шеф.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('shift_confirmation') ?? 'Подтверждение смены')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final slotsOnShift = _slotsOnShift;
    final dateStr = DateFormat('d MMM yyyy', loc.currentLanguageCode == 'ru' ? 'ru' : 'en').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('shift_confirmation') ?? 'Подтверждение смены'),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(loc.t('shift_date') ?? 'Дата смены:', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(_selectedDate.year - 1),
                      lastDate: DateTime(_selectedDate.year + 1),
                    );
                    if (picked != null && mounted) setState(() => _selectedDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 20),
                  label: Text(dateStr),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              loc.t('shift_confirmation_hint') ?? 'Отметьте, кто действительно был на смене. Сохраните после закрытия смены.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: slotsOnShift.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            loc.t('shift_no_one_scheduled') ?? 'На эту дату в графике нет смен',
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: slotsOnShift.length,
                    itemBuilder: (_, i) {
                      final slot = slotsOnShift[i];
                      final confirmed = _isConfirmed(slot);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          title: Text(slot.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: _model.getTimeRange(slot.id, _selectedDate) != null
                              ? Text(loc.t('schedule_shift') ?? 'Смена', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
                              : null,
                          value: confirmed,
                          onChanged: (v) => _setConfirmed(slot, v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: slotsOnShift.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(loc.t('save') ?? 'Сохранить'),
                ),
              ),
            )
          : null,
    );
  }
}
