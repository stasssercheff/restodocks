import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';
import '../widgets/app_bar_home_button.dart';

/// Заполнение чеклиста: шапка, №, наименование (ссылками на ТТК ПФ), окно действия, комментарии.
/// Сохранение: localStorage + сервер каждые 15 сек. Кнопка «Завершить» — во входящие шефу и су-шефу.
class ChecklistFillScreen extends StatefulWidget {
  const ChecklistFillScreen({super.key, required this.checklistId});

  final String checklistId;

  @override
  State<ChecklistFillScreen> createState() => _ChecklistFillScreenState();
}

class _ChecklistFillScreenState extends State<ChecklistFillScreen>
    with AutoSaveMixin<ChecklistFillScreen>, InputChangeListenerMixin<ChecklistFillScreen> {
  Checklist? _checklist;
  bool _loading = true;
  String? _error;
  bool _completed = false;
  DateTime? _startTime;
  DateTime? _endTime;
  late List<bool> _done;
  late List<String?> _numericValues;
  late List<String?> _dropdownValues;
  late TextEditingController _commentsController;
  final Map<int, TextEditingController> _numericControllers = {};
  Timer? _serverAutoSaveTimer;
  // Переведённые заголовки пунктов: оригинал -> перевод
  final Map<String, String> _translatedTitles = {};
  String? _translatedChecklistName;

  void saveNow() => saveImmediately();

  @override
  void initState() {
    super.initState();
    _commentsController = createTrackedController();
    _startTime = DateTime.now();
    _done = [];
    _numericValues = [];
    _dropdownValues = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    setOnInputChanged(saveNow);

    _serverAutoSaveTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && !_completed) _autoSaveToServer();
    });
  }

  @override
  String get draftKey => 'checklist_fill_${widget.checklistId}';

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'checklistId': widget.checklistId,
      'startTime': _startTime?.toIso8601String(),
      'endTime': _endTime?.toIso8601String(),
      'completed': _completed,
      'done': _done,
      'numericValues': _numericValues,
      'dropdownValues': _dropdownValues,
      'comments': _commentsController.text,
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (data['checklistId'] != widget.checklistId) return;
    setState(() {
      _startTime = data['startTime'] != null ? DateTime.parse(data['startTime'] as String) : DateTime.now();
      _endTime = data['endTime'] != null ? DateTime.parse(data['endTime'] as String) : null;
      _completed = data['completed'] == true;
      final doneList = data['done'] as List<dynamic>? ?? [];
      _done = doneList.map((e) => e == true).toList();
      final numList = data['numericValues'] as List<dynamic>? ?? [];
      _numericValues = numList.map((e) => e?.toString()).toList();
      for (final ctrl in _numericControllers.values) ctrl.dispose();
      _numericControllers.clear();
      final ddList = data['dropdownValues'] as List<dynamic>? ?? [];
      _dropdownValues = ddList.map((e) => e?.toString()).toList();
      _commentsController.text = data['comments'] as String? ?? '';
    });
  }

  @override
  void dispose() {
    _serverAutoSaveTimer?.cancel();
    for (final c in _numericControllers.values) c.dispose();
    _numericControllers.clear();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final c = await svc.getChecklistById(widget.checklistId);
      if (!mounted) return;
      final n = c?.items.length ?? 0;
      setState(() {
        _checklist = c;
        if (_done.length != n) _done = List.filled(n, false);

        // Инициализируем "Цифру" из targetQuantity, если пользователь еще не вводил
        // значения (или после восстановления черновика значения отсутствуют).
        if (_numericValues.length != n) {
          _numericValues = List.filled(n, null);
        }

        final hasNumeric = c?.actionConfig.hasNumeric == true;
        if (hasNumeric) {
          final allNull = _numericValues.isEmpty || _numericValues.every((e) => e == null || (e?.trim().isEmpty ?? true));
          if (allNull && c != null) {
            _numericValues = c.items
                .map((it) => it.targetQuantity?.toString())
                .toList(growable: false);
          }
        }
        if (_dropdownValues.length != n) _dropdownValues = List.filled(n, null);
        _loading = false;
      });
      // Переводим заголовки пунктов если язык UI != русский
      if (c != null) _translateTitles(c);
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Переводим название чеклиста и title каждого пункта через TranslationService (кешируется).
  Future<void> _translateTitles(Checklist checklist) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    if (targetLang == 'ru') return; // title хранятся на русском

    final translationSvc = context.read<TranslationService>();
    final updated = <String, String>{};

    // Перевод названия чеклиста
    final nameText = checklist.name.trim();
    if (nameText.isNotEmpty) {
      try {
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.checklist,
          entityId: checklist.id,
          fieldName: 'checklist_name',
          text: nameText,
          from: 'ru',
          to: targetLang,
        );
        if (translated != null && translated != nameText && mounted) {
          setState(() => _translatedChecklistName = translated);
        }
      } catch (_) {}
    }

    for (final item in checklist.items) {
      final title = item.title.trim();
      if (title.isEmpty) continue;
      if (_translatedTitles.containsKey(title)) continue;

      try {
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.ui,
          entityId: 'checklist_item_${item.id}',
          fieldName: 'title',
          text: title,
          from: 'ru',
          to: targetLang,
        );
        if (translated != null && translated.trim().isNotEmpty && translated != title) {
          updated[title] = translated;
        }
      } catch (_) {}
      if (!mounted) return;
    }

    if (mounted && updated.isNotEmpty) {
      setState(() => _translatedTitles.addAll(updated));
    }
  }

  String _getTitle(ChecklistItem item) {
    final t = _translatedTitles[item.title.trim()];
    return t ?? item.title;
  }

  Future<void> _autoSaveToServer() async {
    if (_completed || _checklist == null) return;
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      final emp = acc.currentEmployee;
      if (est == null || emp == null) return;

      final draftData = getCurrentState();
      await Supabase.instance.client.from('checklist_drafts').upsert({
        'establishment_id': est.id,
        'checklist_id': widget.checklistId,
        'employee_id': emp.id,
        'draft_data': draftData,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'checklist_id,employee_id');
    } catch (e) {
      devLog('Checklist fill draft server save failed: $e');
    }
  }

  bool get _allActionCellsFilled {
    final c = _checklist;
    if (c == null) return false;
    final cfg = c.actionConfig;
    for (var i = 0; i < c.items.length; i++) {
      if (cfg.hasToggle && i >= _done.length) return false;
      if (cfg.hasNumeric && (i >= _numericValues.length || (_numericValues[i] == null || _numericValues[i]!.trim().isEmpty))) return false;
      if (cfg.dropdownOptions != null && cfg.dropdownOptions!.isNotEmpty) {
        if (i >= _dropdownValues.length || (_dropdownValues[i] == null || _dropdownValues[i]!.isEmpty)) return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    final c = _checklist;
    if (c == null) return;
    if (!_allActionCellsFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocalizationService>().t('checklist_fill_all_required') ?? 'Заполните все поля окна действия')),
      );
      return;
    }

    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    _endTime = DateTime.now();

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < c.items.length; i++) {
      items.add({
        'title': c.items[i].title,
        'techCardId': c.items[i].techCardId,
        'done': i < _done.length ? _done[i] : false,
        'numericValue': i < _numericValues.length ? _numericValues[i] : null,
        'dropdownValue': i < _dropdownValues.length ? _dropdownValues[i] : null,
        if (c.items[i].targetQuantity != null) 'targetQuantity': c.items[i].targetQuantity,
        if (c.items[i].targetUnit != null) 'targetUnit': c.items[i].targetUnit,
      });
    }

    try {
      final emps = await acc.getEmployeesForEstablishment(est.id);
      final chefIds = emps
          .where((e) => e.hasRole('executive_chef') || e.hasRole('sous_chef'))
          .map((e) => e.id)
          .toList();
      if (chefIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('checklist_no_chefs') ?? 'Нет шефа/су-шефа для отправки')),
        );
        return;
      }
      final subSvc = context.read<ChecklistSubmissionService>();
      await subSvc.submit(
        establishmentId: est.id,
        checklistId: c.id,
        submittedByEmployeeId: emp.id,
        submittedByName: emp.fullName,
        checklistName: c.name,
        additionalName: c.additionalName,
        section: c.assignedSection,
        recipientChefIds: chefIds,
        startTime: _startTime,
        endTime: _endTime,
        department: emp.department,
        position: emp.primaryRole?.displayName,
        workshop: emp.section,
        items: items,
        comments: _commentsController.text.trim(),
        sourceLang: loc.currentLanguageCode,
      );
      if (mounted) {
        setState(() => _completed = true);
        clearDraft();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canAccessChecklists = emp?.canViewDepartment('kitchen') ?? false;

    if (emp != null && !canAccessChecklists) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(loc.t('checklists_kitchen_only'), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home),
                  label: Text(loc.t('home')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _checklist == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? 'Чеклист не найден', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: Text(loc.t('back')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = _checklist!;
    final cfg = c.actionConfig;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(_translatedChecklistName ?? c.name),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(loc, emp, c),
                  const SizedBox(height: 24),
                  _buildTableHeader(loc, cfg),
                  const Divider(height: 24),
                  ...List.generate(c.items.length, (i) => _buildRow(loc, c, cfg, i)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _commentsController,
                    decoration: InputDecoration(
                      labelText: loc.t('checklist_comments') ?? 'Комментарии',
                      hintText: loc.t('checklist_comments_hint'),
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    minLines: 2,
                    onChanged: (_) => saveNow(),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _allActionCellsFilled ? _submit : null,
                  icon: const Icon(Icons.check_circle, size: 24),
                  label: Text(loc.t('checklist_complete') ?? 'Завершить', style: const TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    disabledForegroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(LocalizationService loc, Employee? emp, Checklist checklist) {
    final formatTime = (DateTime? t) => t != null ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}' : '—';
    final formatDate = (DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final formatDateTime = (DateTime d) {
      final utc = d.toUtc();
      final hasTime = utc.hour != 0 || utc.minute != 0;
      final local = d.toLocal();
      return hasTime ? '${formatTime(local)} ${formatDate(local)}' : formatDate(utc);
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emp?.fullName ?? '—', style: Theme.of(context).textTheme.bodyLarge),
            Text(loc.t('department') ?? 'Отдел: ${emp?.department ?? '—'}', style: Theme.of(context).textTheme.bodySmall),
            Text(loc.t('role') ?? 'Должность: ${emp?.primaryRole?.displayName ?? '—'}', style: Theme.of(context).textTheme.bodySmall),
            if (emp?.department == 'kitchen' && emp?.section != null)
              Text('${loc.t('kitchen_section') ?? 'Цех'}: ${KitchenSection.fromCode(emp!.section!)?.displayName ?? emp.section}', style: Theme.of(context).textTheme.bodySmall),
            if (checklist.deadlineAt != null || checklist.scheduledForAt != null) ...[
              const SizedBox(height: 6),
              if (checklist.scheduledForAt != null)
                Text('${loc.t('checklist_scheduled_for') ?? 'На когда'}: ${formatDateTime(checklist.scheduledForAt!)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              if (checklist.deadlineAt != null)
                Text('${loc.t('checklist_complete_by') ?? 'Завершить до'}: ${formatDateTime(checklist.deadlineAt!)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 4),
            Text('${loc.t('checklist_start_time') ?? 'Начало'}: ${formatTime(_startTime)}', style: Theme.of(context).textTheme.labelSmall),
            Text('${loc.t('checklist_end_time') ?? 'Конец'}: ${formatTime(_endTime)}', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(LocalizationService loc, ChecklistActionConfig cfg) {
    final children = <Widget>[
      SizedBox(width: 28, child: Text(loc.t('checklist_number') ?? '№', style: Theme.of(context).textTheme.labelLarge)),
      Expanded(child: Text(loc.t('checklist_name') ?? 'Наименование', style: Theme.of(context).textTheme.labelLarge)),
    ];
    if (cfg.hasNumeric) {
      children.add(SizedBox(
          width: 86,
          child: Text(loc.t('checklist_action_numeric') ?? 'Цифра',
              style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center)));
    }
    if (cfg.dropdownOptions != null && cfg.dropdownOptions!.isNotEmpty) {
      children.add(SizedBox(
          width: 96,
          child: Text(loc.t('checklist_action_choice') ?? 'Выбор',
              style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center)));
    }
    if (cfg.hasToggle) {
      children.add(Expanded(
        child: Text(loc.t('checklist_status') ?? 'Статус',
            style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center),
      ));
    }
    return Row(children: children);
  }

  Widget _buildRow(LocalizationService loc, Checklist checklist, ChecklistActionConfig cfg, int i) {
    final it = checklist.items[i];
    final done = i < _done.length ? _done[i] : false;
    final numVal = i < _numericValues.length ? _numericValues[i] ?? '' : '';
    final ddVal = i < _dropdownValues.length ? _dropdownValues[i] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text('${i + 1}', style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (it.techCardId != null)
                    InkWell(
                      onTap: () => context.push('/tech-cards/${it.techCardId}?view=1'),
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(child: Text(_getTitle(it), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline))),
                        ],
                      ),
                    )
                  else
                    Text(_getTitle(it), style: Theme.of(context).textTheme.bodyMedium),
                  // Если есть колонка "Цифра", количество показываем в ней, а не "под" названием.
                  if (!cfg.hasNumeric && it.quantityLabel != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        it.quantityLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (cfg.hasNumeric)
              SizedBox(
                width: 86,
                child: Builder(
                  builder: (_) {
                    if (!_numericControllers.containsKey(i)) {
                      _numericControllers[i] = TextEditingController(text: numVal);
                    } else if (_numericControllers[i]!.text != numVal) {
                      _numericControllers[i]!.text = numVal;
                    }
                    return TextField(
                      key: ValueKey('num_$i'),
                      keyboardType: TextInputType.number,
                      controller: _numericControllers[i],
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        // Показываем единицу измерения "рядом" с числом в той же колонке.
                        suffixText: it.targetUnit?.isNotEmpty == true ? ' ${it.targetUnit!}' : null,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (v) {
                        setState(() {
                          while (_numericValues.length <= i) _numericValues.add(null);
                          _numericValues[i] = v.isEmpty ? null : v;
                          saveNow();
                        });
                      },
                    );
                  },
                ),
              ),
            if (cfg.dropdownOptions != null && cfg.dropdownOptions!.isNotEmpty)
              SizedBox(
                width: 96,
                child: DropdownButtonFormField<String>(
                  value: ddVal != null && cfg.dropdownOptions!.contains(ddVal) ? ddVal : null,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                  items: cfg.dropdownOptions!.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) {
                    setState(() {
                      while (_dropdownValues.length <= i) _dropdownValues.add(null);
                      _dropdownValues[i] = v;
                      saveNow();
                    });
                  },
                ),
              ),
            if (cfg.hasToggle)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: done,
                      tristate: false,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) {
                        setState(() {
                          if (i < _done.length) _done[i] = v ?? false;
                          saveNow();
                        });
                      },
                    ),
                    Expanded(
                      child: Text(
                        done ? (loc.t('done') ?? 'Сделано') : (loc.t('not_done') ?? 'Не сделано'),
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
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
