import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../models/tech_card.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Одна строка формы гигиенического журнала (сотрудник + должность + допуск).
class _HealthHygieneRow {
  _HealthHygieneRow({
    required this.employeeId,
    this.positionOverride,
    this.positionIsCustom = false,
    this.statusOk = true,
    this.status2Ok = true,
  });
  final String employeeId;
  String? positionOverride;
  bool positionIsCustom;
  bool statusOk;
  bool status2Ok;
}

/// Форма добавления записи в журнал ХАССП.
/// Только 5 журналов по СанПиН 2.3/2.4.3590-20, макет как в рекомендуемых образцах.
class HaccpEntryFormScreen extends StatefulWidget {
  const HaccpEntryFormScreen({super.key, required this.logTypeCode});

  final String logTypeCode;

  @override
  State<HaccpEntryFormScreen> createState() => _HaccpEntryFormScreenState();
}

class _HaccpEntryFormScreenState extends State<HaccpEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  double _tempValue = 4.0;
  double _humidityValue = 60;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  DateTime? _expiryDate;
  DateTime? _dateSold;
  /// Разрешение к реализации: true = разрешено, false = запрещено, null = не выбрано.
  bool? _approvalToSell;
  /// Журнал медкнижек: даты.
  DateTime? _medBookValidUntil;
  DateTime? _medBookIssuedAt;
  DateTime? _medBookReturnedAt;
  /// Медосмотры, дезсредства, генуборки, сита.
  DateTime? _medExamHireDate;
  DateTime? _medExamDate;
  DateTime? _medExamNextDate;
  DateTime? _medExamExclusionDate;
  DateTime? _disinfReceiptDate;
  DateTime? _disinfExpiryDate;
  DateTime? _genCleanDate;
  DateTime? _sieveCleaningDate;

  /// Гигиенический журнал: список сотрудников заведения и строки таблицы (каждая — один сотрудник).
  List<Employee> _healthEmployees = [];
  List<_HealthHygieneRow> _healthRows = [];

  /// Журнал бракеража готовой продукции: ТТК для выбора блюда.
  List<TechCard> _finishedBrakerageTechCards = [];
  String? _selectedFinishedBrakerageTechCardId;

  HaccpLogType? get _logType {
    final t = HaccpLogType.fromCode(widget.logTypeCode);
    return t != null && HaccpLogType.supportedInApp.contains(t) ? t : null;
  }

  @override
  void initState() {
    super.initState();
    if (_logType == HaccpLogType.healthHygiene) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHealthEmployees());
    } else if (_logType == HaccpLogType.finishedProductBrakerage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFinishedBrakerageTechCards());
    }
  }

  Future<void> _loadHealthEmployees() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final current = acc.currentEmployee;
    if (est == null || current == null) return;
    try {
      final list = await acc.getEmployeesForEstablishment(est.id);
      if (mounted) {
        setState(() {
          _healthEmployees = list.where((e) => e.isActive).toList();
          if (_healthRows.isEmpty && _healthEmployees.isNotEmpty) {
            _healthRows = _healthEmployees.map((e) => _HealthHygieneRow(
              employeeId: e.id,
              positionOverride: null,
              positionIsCustom: false,
              statusOk: true,
              status2Ok: true,
            )).toList();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFinishedBrakerageTechCards() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    final dataEstId = est?.dataEstablishmentId;
    if (dataEstId == null) return;
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final all = await svc.getTechCardsForEstablishment(dataEstId);
      final visible = emp == null ? all : all.where((tc) => emp.canSeeTechCard(tc.sections)).toList();
      if (!mounted) return;
      setState(() {
        _finishedBrakerageTechCards = visible;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  String _getText(String key) => _controllers[key]?.text.trim() ?? '';

  double? _getNum(String key) {
    final s = _getText(key);
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  Widget _tableHeaderCell(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );

  Widget _tableCell(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: child,
      );

  Widget _textField(String key, String label, {bool multiline = false, TextInputType? keyboardType}) {
    _controllers[key] ??= TextEditingController();
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      maxLines: multiline ? 2 : 1,
      keyboardType: keyboardType,
    );
  }

  /// Селектор «Разрешение к реализации»: разрешено / запрещено.
  Widget _approvalSelector() {
    return DropdownButtonFormField<bool>(
      value: _approvalToSell,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: const Text('Выберите'),
      items: const [
        DropdownMenuItem(value: true, child: Text('разрешено')),
        DropdownMenuItem(value: false, child: Text('запрещено')),
      ],
      onChanged: (v) => setState(() => _approvalToSell = v),
    );
  }

  /// Подпись — ФИО сотрудника из учётной записи (только отображение).
  Widget _signatureFromAccount() {
    return Consumer<AccountManagerSupabase>(
      builder: (_, acc, __) {
        final emp = acc.currentEmployee;
        final name = emp != null
            ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName)
            : '—';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        );
      },
    );
  }

  static const String _customPositionValue = '__custom_position__';

  /// Список должностей: все из EmployeeRole + уникальные из карточек сотрудников всех подразделений.
  List<String> get _healthPositionOptions {
    final fromRoles = EmployeeRole.values.map((r) => r.displayName).toSet();
    final fromEmployees = _healthEmployees.map((e) => e.roleDisplayName).where((s) => s.isNotEmpty).toSet();
    final combined = [...fromRoles, ...fromEmployees.where((s) => !fromRoles.contains(s))]..sort();
    return combined;
  }

  Employee? _healthEmployeeById(String id) => _healthEmployees.cast<Employee?>().firstWhere((e) => e?.id == id, orElse: () => null);

  String _healthPositionDisplayForRow(_HealthHygieneRow row) {
    final emp = _healthEmployeeById(row.employeeId);
    if (row.positionIsCustom && row.positionOverride != null && row.positionOverride!.isNotEmpty) return row.positionOverride!;
    return emp?.roleDisplayName ?? '';
  }

  Widget _healthPositionDropdownForRow(int index) {
    final row = _healthRows[index];
    final positionOptions = _healthPositionOptions;
    final currentDisplay = _healthPositionDisplayForRow(row);
    final effectiveValue = row.positionIsCustom
        ? _customPositionValue
        : (positionOptions.contains(currentDisplay) ? currentDisplay : (positionOptions.isNotEmpty ? positionOptions.first : _customPositionValue));
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: effectiveValue,
        isExpanded: true,
        isDense: true,
        items: [
          ...positionOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))),
          DropdownMenuItem(
            value: _customPositionValue,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(row.positionIsCustom && (row.positionOverride ?? '').isNotEmpty ? 'Свой вариант: ${row.positionOverride}' : 'Свой вариант', overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
        onChanged: (v) async {
          if (v == _customPositionValue) {
            final text = await _showCustomPositionDialog(initial: row.positionOverride);
            if (text != null && mounted) setState(() {
              row.positionOverride = text;
              row.positionIsCustom = true;
            });
            return;
          }
          if (v != null) setState(() {
            row.positionOverride = v;
            row.positionIsCustom = false;
          });
        },
      ),
    );
  }

  Future<String?> _showCustomPositionDialog({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Должность (свой вариант)'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Введите название должности',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  /// Ячейка выбора блюда для журнала бракеража готовой продукции: выпадающий список с поиском по ТТК.
  Widget _finishedProductPickerCell(LocalizationService loc) {
    _controllers['product'] ??= TextEditingController();
    final controller = _controllers['product']!;
    final title = controller.text.isNotEmpty ? controller.text : (loc.t('haccp_product') ?? 'Выбрать блюдо');
    return InkWell(
      onTap: () async {
        if (_finishedBrakerageTechCards.isEmpty) {
          await _loadFinishedBrakerageTechCards();
        }
        final picked = await showDialog<TechCard?>(
          context: context,
          builder: (ctx) {
            final searchCtrl = TextEditingController();
            List<TechCard> filtered = List.of(_finishedBrakerageTechCards);
            void applyFilter() {
              final q = searchCtrl.text.trim().toLowerCase();
              filtered = q.isEmpty
                  ? List.of(_finishedBrakerageTechCards)
                  : _finishedBrakerageTechCards
                      .where((tc) => tc.dishName.toLowerCase().contains(q))
                      .toList();
            }
            applyFilter();
            return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                return AlertDialog(
                  title: Text(loc.t('haccp_product') ?? 'Наименование блюда'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Поиск по названию ТТК',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            setStateDialog(() {
                              applyFilter();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: filtered.isEmpty
                              ? Text(loc.t('no_results') ?? 'Ничего не найдено')
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, index) {
                                    final tc = filtered[index];
                                    return ListTile(
                                      title: Text(tc.dishName),
                                      subtitle: tc.category.isNotEmpty ? Text(tc.category) : null,
                                      onTap: () => Navigator.of(ctx).pop(tc),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (picked != null && mounted) {
          setState(() {
            controller.text = picked.dishName;
            _selectedFinishedBrakerageTechCardId = picked.id;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  /// Форма по макету Приложения 1: Гигиенический журнал (сотрудники). Несколько строк — по одной на сотрудника; можно добавлять/удалять.
  Widget _buildHealthHygieneForm(LocalizationService loc) {
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final currentEmp = context.watch<AccountManagerSupabase>().currentEmployee;
    final creatorName = currentEmp != null
        ? (currentEmp.surname != null ? '${currentEmp.surname} ${currentEmp.fullName}' : currentEmp.fullName)
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.4),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1.8),
            5: FlexColumnWidth(1.8),
            6: FlexColumnWidth(1.2),
            7: FlexColumnWidth(1),
            8: FlexColumnWidth(0.35),
          },
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(
              children: [
                _tableHeaderCell('№ п/п'),
                _tableHeaderCell('Дата'),
                _tableHeaderCell('Ф. И. О. работника (последнее при наличии)'),
                _tableHeaderCell('Должность'),
                _tableHeaderCell('Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
                _tableHeaderCell('Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
                _tableHeaderCell('Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)'),
                _tableHeaderCell('Подпись медицинского работника (ответственного лица)'),
                _tableHeaderCell(''),
              ],
            ),
            ...List.generate(_healthRows.length, (i) {
              final row = _healthRows[i];
              final emp = _healthEmployeeById(row.employeeId);
              final name = emp != null ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName) : '—';
              return TableRow(
                children: [
                  _tableCell(Text('${i + 1}')),
                  _tableCell(Text(dateStr)),
                  _tableCell(Text(name)),
                  _tableCell(_healthPositionDropdownForRow(i)),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: row.statusOk, onChanged: (v) => setState(() => row.statusOk = v ?? true)),
                      Text(row.statusOk ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: row.statusOk ? Colors.green : Colors.orange)),
                    ],
                  )),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: row.status2Ok, onChanged: (v) => setState(() => row.status2Ok = v ?? true)),
                      Text(row.status2Ok ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: row.status2Ok ? Colors.green : Colors.orange)),
                    ],
                  )),
                  _tableCell(Text(row.statusOk ? 'допущен' : 'отстранен', style: const TextStyle(fontSize: 12))),
                  _tableCell(Text(creatorName, style: const TextStyle(fontSize: 11))),
                  _tableCell(IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    onPressed: () => setState(() => _healthRows.removeAt(i)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  )),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final usedIds = _healthRows.map((r) => r.employeeId).toSet();
            final available = _healthEmployees.where((e) => !usedIds.contains(e.id)).toList();
            if (available.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.t('haccp_all_employees_added') ?? 'Все сотрудники уже добавлены')),
              );
              return;
            }
            final picked = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.t('haccp_add_employee_row') ?? 'Добавить сотрудника'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: available.map((e) {
                      final name = e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(e.roleDisplayName),
                        onTap: () => Navigator.of(ctx).pop(e.id),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
            if (picked != null && mounted) setState(() {
              _healthRows.add(_HealthHygieneRow(employeeId: picked, positionOverride: null, positionIsCustom: false, statusOk: true, status2Ok: true));
            });
          },
          icon: const Icon(Icons.add),
          label: Text(loc.t('haccp_add_row') ?? 'Добавить строку'),
        ),
        const SizedBox(height: 8),
        _textField('note', loc.t('haccp_note') ?? 'Примечание'),
      ],
    );
  }

  /// Форма по макету Приложения 2: Журнал учета температурного режима холодильного оборудования.
  Widget _buildFridgeTemperatureForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell('Наименование производственного помещения'),
            _tableHeaderCell('Наименование холодильного оборудования'),
            _tableHeaderCell('Температура °C'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => Text(acc.establishment?.name ?? '—'),
            )),
            _tableCell(_textField('equipment', loc.t('haccp_equipment') ?? 'Оборудование')),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_tempValue.toStringAsFixed(1)} °C'),
                Slider(
                  value: _tempValue,
                  min: -25,
                  max: 15,
                  divisions: 80,
                  onChanged: (v) => setState(() => _tempValue = v),
                ),
              ],
            )),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 3: 5 обязательных колонок. Наименование помещения — в шапке журнала (сохраняется в записи).
  Widget _buildWarehouseTempHumidityForm(LocalizationService loc) {
    _controllers['warehouse_premises'] ??= TextEditingController();
    final tempOutOfRange = _tempValue > 25;
    final humidityOutOfRange = _humidityValue > 75;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            controller: _controllers['warehouse_premises'],
            decoration: InputDecoration(
              labelText: 'Наименование складского помещения',
              hintText: 'Например: Склад сухих продуктов, Овощной цех',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Укажите помещение';
              return null;
            },
          ),
        ),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.5),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
          },
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(
              children: [
                _tableHeaderCell('№ п/п'),
                _tableHeaderCell('Дата'),
                _tableHeaderCell('Температура, °C'),
                _tableHeaderCell('Относительная влажность, %'),
                _tableHeaderCell('Подпись ответственного лица'),
              ],
            ),
            TableRow(
              children: [
                _tableCell(const Text('1')),
                _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
                _tableCell(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tempValue.toStringAsFixed(0),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tempOutOfRange ? Colors.red : null,
                      ),
                    ),
                    Slider(
                      value: _tempValue,
                      min: -5,
                      max: 35,
                      divisions: 80,
                      onChanged: (v) => setState(() => _tempValue = v),
                    ),
                  ],
                )),
                _tableCell(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_humidityValue.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: humidityOutOfRange ? Colors.red : null,
                      ),
                    ),
                    Slider(
                      value: _humidityValue,
                      min: 20,
                      max: 95,
                      divisions: 75,
                      onChanged: (v) => setState(() => _humidityValue = v),
                    ),
                  ],
                )),
                _tableCell(_signatureFromAccount()),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 4: Журнал бракеража готовой пищевой продукции.
  Widget _buildFinishedProductBrakerageForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(0.8),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell('Дата и час изготовления блюда'),
            _tableHeaderCell('Время снятия бракеража'),
            _tableHeaderCell('Наименование готового блюда'),
            _tableHeaderCell('Результаты органолептической оценки'),
            _tableHeaderCell('Разрешение к реализации'),
            _tableHeaderCell('Подписи членов бракеражной комиссии'),
            _tableHeaderCell('Результаты взвешивания порционных блюд'),
            _tableHeaderCell('Примечание'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()))),
            _tableCell(_textField('time_brakerage', 'Время (например 12:00)')),
            _tableCell(_finishedProductPickerCell(loc)),
            _tableCell(_textField('result', loc.t('haccp_result') ?? 'Результат оценки', multiline: true)),
            _tableCell(_approvalSelector()),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('weighing_result', 'Взвешивание')),
            _tableCell(_textField('note', loc.t('haccp_note') ?? 'Примечание')),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 5: Журнал бракеража скоропортящейся пищевой продукции.
  Widget _buildIncomingRawBrakerageForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(0.6),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(0.5),
        5: FlexColumnWidth(0.8),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(0.8),
        8: FlexColumnWidth(0.8),
        9: FlexColumnWidth(0.6),
        10: FlexColumnWidth(0.6),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell('Дата и час поступления'),
            _tableHeaderCell('Наименование'),
            _tableHeaderCell('Фасовка'),
            _tableHeaderCell('Изготовитель/поставщик'),
            _tableHeaderCell('Кол-во'),
            _tableHeaderCell('№ документа'),
            _tableHeaderCell('Органолептическая оценка'),
            _tableHeaderCell('Условия хранения, срок реализации'),
            _tableHeaderCell('Дата реализации'),
            _tableHeaderCell('Подпись'),
            _tableHeaderCell('Прим.'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()))),
            _tableCell(_textField('product', loc.t('haccp_product') ?? 'Наименование')),
            _tableCell(_textField('packaging', 'Фасовка')),
            _tableCell(_textField('manufacturer_supplier', 'Изготовитель/поставщик')),
            _tableCell(_textField('quantity_kg', 'кг/л/шт', keyboardType: TextInputType.number)),
            _tableCell(_textField('document_number', '№ док.')),
            _tableCell(_textField('result', loc.t('haccp_result') ?? 'Оценка', multiline: true)),
            _tableCell(_textField('storage_conditions', 'Условия, срок')),
            _tableCell(InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dateSold ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _dateSold = d);
              },
              child: Text(_dateSold != null ? DateFormat('dd.MM.yyyy').format(_dateSold!) : 'Выбрать'),
            )),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('note', loc.t('haccp_note') ?? 'Прим.')),
          ],
        ),
      ],
    );
  }

  /// Форма по бланку: Журнал учёта личных медицинских книжек (1:1 с бумагой).
  Widget _buildMedBookForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.2),
        5: FlexColumnWidth(1.2),
        6: FlexColumnWidth(1.2),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell('№ п/п'),
            _tableHeaderCell('Фамилия, имя, отчество'),
            _tableHeaderCell('Должность'),
            _tableHeaderCell('Номер медицинской книжки'),
            _tableHeaderCell('Срок действия медицинской книжки'),
            _tableHeaderCell('Расписка и дата получения медицинской книжки'),
            _tableHeaderCell('Расписка и дата возврата медицинской книжки'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(const Text('1')),
            _tableCell(_textField('med_book_employee_name', 'Ф. И. О.')),
            _tableCell(_textField('med_book_position', 'Должность')),
            _tableCell(_textField('med_book_number', 'Номер медкнижки')),
            _tableCell(InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _medBookValidUntil ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _medBookValidUntil = d);
              },
              child: Text(_medBookValidUntil != null ? DateFormat('dd.MM.yyyy').format(_medBookValidUntil!) : 'Выбрать дату'),
            )),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _medBookIssuedAt ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _medBookIssuedAt = d);
                  },
                  child: Text(_medBookIssuedAt != null ? DateFormat('dd.MM.yyyy').format(_medBookIssuedAt!) : 'Дата получения'),
                ),
                _signatureFromAccount(),
              ],
            )),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _medBookReturnedAt ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _medBookReturnedAt = d);
                  },
                  child: Text(_medBookReturnedAt != null ? DateFormat('dd.MM.yyyy').format(_medBookReturnedAt!) : 'Дата возврата'),
                ),
                _signatureFromAccount(),
              ],
            )),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 8: Учёт фритюрных жиров.
  Widget _buildFryingOilForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.9),
        1: FlexColumnWidth(0.7),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(0.8),
        6: FlexColumnWidth(1.2),
        7: FlexColumnWidth(0.7),
        8: FlexColumnWidth(0.7),
        9: FlexColumnWidth(0.7),
        10: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell('Дата'),
            _tableHeaderCell('Время начала использования жира'),
            _tableHeaderCell('Вид фритюрного жира'),
            _tableHeaderCell('Органолептическая оценка на начало жарки'),
            _tableHeaderCell('Тип жарочного оборудования'),
            _tableHeaderCell('Вид продукции'),
            _tableHeaderCell('Время окончания жарки'),
            _tableHeaderCell('Органолептическая оценка по окончании жарки'),
            _tableHeaderCell('Переходящий остаток, кг'),
            _tableHeaderCell('Утилизированный жир, кг'),
            _tableHeaderCell('Должность, Ф.И.О. контролера'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
            _tableCell(Text(DateFormat('HH:mm').format(DateTime.now()))),
            _tableCell(_textField('oil_name', 'Вид жира')),
            _tableCell(_textField('organoleptic_start', 'Оценка на начало', multiline: true)),
            _tableCell(_textField('frying_equipment_type', 'Тип оборудования')),
            _tableCell(_textField('frying_product_type', 'Вид продукции')),
            _tableCell(_textField('frying_end_time', 'Время (например 14:00)')),
            _tableCell(_textField('organoleptic_end', 'Оценка по окончании', multiline: true)),
            _tableCell(_textField('carry_over_kg', 'кг', keyboardType: TextInputType.number)),
            _tableCell(_textField('utilized_kg', 'кг', keyboardType: TextInputType.number)),
            _tableCell(_signatureFromAccount()),
          ],
        ),
      ],
    );
  }

  Widget _buildMedExaminationsForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Данные работника', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Ф. И. О.'), _tableHeaderCell('Возраст (дата рождения)')]),
            TableRow(children: [_tableCell(_textField('med_exam_employee_name', 'Ф. И. О.')), _tableCell(_textField('med_exam_dob', 'Дата рождения'))]),
            TableRow(children: [_tableHeaderCell('Пол'), _tableHeaderCell('Должность')]),
            TableRow(children: [_tableCell(_textField('med_exam_gender', 'Пол')), _tableCell(_textField('med_exam_position', 'Должность'))]),
            TableRow(children: [_tableHeaderCell('Структурное подразделение'), _tableHeaderCell('Дата приёма на работу')]),
            TableRow(children: [
              _tableCell(_textField('med_exam_department', 'Подразделение')),
              _tableCell(_datePickerCell('med_exam_hire_date', _medExamHireDate, (d) => setState(() => _medExamHireDate = d))),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        Text('Медицинский осмотр', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Вид (предварительный/периодический)'), _tableHeaderCell('ЛПУ')]),
            TableRow(children: [_tableCell(_textField('med_exam_type', 'Вид')), _tableCell(_textField('med_exam_institution', 'Лечебное учреждение'))]),
            TableRow(children: [_tableHeaderCell('Вредный фактор №90'), _tableHeaderCell('Вредный фактор №83')]),
            TableRow(children: [_tableCell(_textField('med_exam_harmful_1', '№ по приказу 90')), _tableCell(_textField('med_exam_harmful_2', '№ по приказу 83'))]),
            TableRow(children: [_tableHeaderCell('Дата прохождения'), _tableHeaderCell('Заключение')]),
            TableRow(children: [
              _tableCell(_datePickerCell('med_exam_date', _medExamDate, (d) => setState(() => _medExamDate = d))),
              _tableCell(_textField('med_exam_conclusion', 'Заключение')),
            ]),
            TableRow(children: [_tableHeaderCell('Решение работодателя'), _tableHeaderCell('Дата следующего осмотра')]),
            TableRow(children: [
              _tableCell(_textField('med_exam_employer_decision', 'Допущен/отстранён/переведён/уволен')),
              _tableCell(_datePickerCell('med_exam_next_date', _medExamNextDate, (d) => setState(() => _medExamNextDate = d))),
            ]),
            TableRow(children: [_tableHeaderCell('Дата исключения из списков'), _tableHeaderCell('Примечание')]),
            TableRow(children: [
              _tableCell(_datePickerCell('med_exam_exclusion_date', _medExamExclusionDate, (d) => setState(() => _medExamExclusionDate = d))),
              _tableCell(_textField('med_exam_note', 'Примечание')),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _datePickerCell(String key, DateTime? value, void Function(DateTime) onDate) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (d != null) onDate(d);
      },
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Text(value != null ? DateFormat('dd.MM.yyyy').format(value) : 'Выбрать дату')),
    );
  }

  Widget _buildDisinfectantAccountingForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Расчёт потребности в дезинфицирующих средствах', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(0.6), 1: FlexColumnWidth(0.8), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.5),
              4: FlexColumnWidth(0.4), 5: FlexColumnWidth(0.5), 6: FlexColumnWidth(0.6), 7: FlexColumnWidth(0.5),
              8: FlexColumnWidth(0.5), 9: FlexColumnWidth(0.5), 10: FlexColumnWidth(0.5), 11: FlexColumnWidth(0.5), 12: FlexColumnWidth(0.5),
            },
            border: TableBorder.all(color: Theme.of(context).dividerColor),
            children: [
              TableRow(children: [
                _tableHeaderCell('Объект'), _tableHeaderCell('Кол-во'), _tableHeaderCell('Площадь м²'), _tableHeaderCell('Вид Т/Г'),
                _tableHeaderCell('Кратность/мес'), _tableHeaderCell('Дезсредство'), _tableHeaderCell('Конц.%'), _tableHeaderCell('Расход/м²'),
                _tableHeaderCell('Раствор на 1 обр.'), _tableHeaderCell('Потребность 1 обр.'), _tableHeaderCell('В месяц'), _tableHeaderCell('В год'),
              ]),
              TableRow(children: [
                _tableCell(_textField('disinf_object_name', 'Объект')),
                _tableCell(_textField('disinf_object_count', 'Кол-во', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_area_sqm', 'м²', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_treatment_type', 'Т/Г')),
                _tableCell(_textField('disinf_frequency', 'Кратность', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_agent_name', 'Дезсредство')),
                _tableCell(_textField('disinf_concentration_pct', '%')),
                _tableCell(_textField('disinf_consumption_per_sqm', 'Расход', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_solution_per_treatment', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_treatment', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_month', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_year', 'л/кг', keyboardType: TextInputType.number)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Поступление дезинфицирующих средств', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(0.6), 5: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Дата'), _tableHeaderCell('Наименование'), _tableHeaderCell('Счёт, дата'), _tableHeaderCell('Кол-во'), _tableHeaderCell('Срок годности'), _tableHeaderCell('Ответственный')]),
            TableRow(children: [
              _tableCell(_datePickerCell('disinf_receipt_date', _disinfReceiptDate, (d) => setState(() => _disinfReceiptDate = d))),
              _tableCell(_textField('disinf_agent_name_receipt', 'Наименование')),
              _tableCell(_textField('disinf_invoice_number', '№ счёта')),
              _tableCell(_textField('disinf_quantity', 'Кол-во', keyboardType: TextInputType.number)),
              _tableCell(_datePickerCell('disinf_expiry_date', _disinfExpiryDate, (d) => setState(() => _disinfExpiryDate = d))),
              _tableCell(_signatureFromAccount()),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildEquipmentWashingForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.6), 1: FlexColumnWidth(0.5), 2: FlexColumnWidth(1), 3: FlexColumnWidth(0.9), 4: FlexColumnWidth(0.5),
        5: FlexColumnWidth(0.9), 6: FlexColumnWidth(0.5), 7: FlexColumnWidth(0.5), 8: FlexColumnWidth(0.8), 9: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [
          _tableHeaderCell('Дата'), _tableHeaderCell('Время мойки'), _tableHeaderCell('Оборудование'), _tableHeaderCell('Моющий раствор'),
          _tableHeaderCell('Конц.%'), _tableHeaderCell('Дез. раствор'), _tableHeaderCell('Конц.%'), _tableHeaderCell('Ополаскивание t°'),
          _tableHeaderCell('Ф.И.О. мойщика'), _tableHeaderCell('Контроль'),
        ]),
        TableRow(children: [
          _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
          _tableCell(_textField('wash_time', 'Время')),
          _tableCell(_textField('wash_equipment_name', 'Оборудование')),
          _tableCell(_textField('wash_solution_name', 'Моющее')),
          _tableCell(_textField('wash_solution_concentration_pct', '%')),
          _tableCell(_textField('wash_disinfectant_name', 'Дез. раствор')),
          _tableCell(_textField('wash_disinfectant_concentration_pct', '%')),
          _tableCell(_textField('wash_rinsing_temp', 't°')),
          _tableCell(_signatureFromAccount()),
          _tableCell(_textField('wash_controller_signature', 'Контролёр')),
        ]),
      ],
    );
  }

  Widget _buildGeneralCleaningForm(LocalizationService loc) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [_tableHeaderCell('№'), _tableHeaderCell('Помещение / зона'), _tableHeaderCell('Дата проведения'), _tableHeaderCell('Ответственный')]),
        TableRow(children: [
          _tableCell(const Text('1')),
          _tableCell(_textField('gen_clean_premises', 'Помещение')),
          _tableCell(_datePickerCell('gen_clean_date', _genCleanDate, (d) => setState(() => _genCleanDate = d))),
          _tableCell(_signatureFromAccount()),
        ]),
      ],
    );
  }

  Widget _buildSieveFilterMagnetForm(LocalizationService loc) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.8), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(0.8)},
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [_tableHeaderCell('№ сита/магнита'), _tableHeaderCell('Наименование / Расположение'), _tableHeaderCell('Состояние'), _tableHeaderCell('Дата очистки'), _tableHeaderCell('ФИО, Подпись'), _tableHeaderCell('Комментарии')]),
        TableRow(children: [
          _tableCell(_textField('sieve_no', '№')),
          _tableCell(_textField('sieve_name_location', 'Наименование')),
          _tableCell(_textField('sieve_condition', 'Состояние')),
          _tableCell(_datePickerCell('sieve_cleaning_date', _sieveCleaningDate, (d) => setState(() => _sieveCleaningDate = d))),
          _tableCell(_signatureFromAccount()),
          _tableCell(_textField('sieve_comments', 'Комментарии')),
        ]),
      ],
    );
  }

  Widget _buildFormByType(LocalizationService loc) {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        return _buildHealthHygieneForm(loc);
      case HaccpLogType.fridgeTemperature:
        return _buildFridgeTemperatureForm(loc);
      case HaccpLogType.warehouseTempHumidity:
        return _buildWarehouseTempHumidityForm(loc);
      case HaccpLogType.finishedProductBrakerage:
        return _buildFinishedProductBrakerageForm(loc);
      case HaccpLogType.incomingRawBrakerage:
        return _buildIncomingRawBrakerageForm(loc);
      case HaccpLogType.fryingOil:
        return _buildFryingOilForm(loc);
      case HaccpLogType.medBookRegistry:
        return _buildMedBookForm(loc);
      case HaccpLogType.medExaminations:
        return _buildMedExaminationsForm(loc);
      case HaccpLogType.disinfectantAccounting:
        return _buildDisinfectantAccountingForm(loc);
      case HaccpLogType.equipmentWashing:
        return _buildEquipmentWashingForm(loc);
      case HaccpLogType.generalCleaningSchedule:
        return _buildGeneralCleaningForm(loc);
      case HaccpLogType.sieveFilterMagnet:
        return _buildSieveFilterMagnetForm(loc);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _save() async {
    if (_logType == null) return;
    if (!_formKey.currentState!.validate()) return;

    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_establishment_not_selected') ?? 'Заведение не выбрано')),
      );
      return;
    }
    if (emp == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_employee_required') ?? 'Войдите под учётной записью сотрудника заведения')),
      );
      return;
    }

    final svc = context.read<HaccpLogServiceSupabase>();
    setState(() => _saving = true);
    try {
      switch (_logType!.targetTable) {
        case HaccpLogTable.numeric:
          await _saveNumeric(svc, est.id, emp.id);
          break;
        case HaccpLogTable.status:
          await _saveStatus(svc, est.id, emp.id);
          break;
        case HaccpLogTable.quality:
          await _saveQuality(svc, est.id, emp.id);
          break;
      }
      if (mounted) context.pop({'saved': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocalizationService>().t('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNumeric(HaccpLogServiceSupabase svc, String estId, String empId) async {
    switch (_logType!) {
      case HaccpLogType.fridgeTemperature:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          value1: _tempValue,
          equipment: _getText('equipment').isNotEmpty ? _getText('equipment') : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.warehouseTempHumidity:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          value1: _tempValue,
          value2: _humidityValue,
          equipment: _getText('warehouse_premises').trim().isNotEmpty ? _getText('warehouse_premises').trim() : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      default:
        throw StateError('Unexpected numeric type: $_logType');
    }
  }

  Future<void> _saveStatus(HaccpLogServiceSupabase svc, String estId, String empId) async {
    if (_logType == HaccpLogType.healthHygiene) {
      if (_healthRows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('haccp_add_at_least_one') ?? 'Добавьте хотя бы одного сотрудника')),
        );
        return;
      }
      final note = _getText('note').isNotEmpty ? _getText('note') : null;
      for (final row in _healthRows) {
        final posOverride = (row.positionOverride ?? '').trim().isEmpty ? null : (row.positionOverride ?? '').trim();
        final description = HaccpLog.buildHealthHygieneDescription(employeeId: row.employeeId, positionOverride: posOverride);
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          statusOk: row.statusOk,
          status2Ok: row.status2Ok,
          description: description,
          note: note,
        );
      }
    } else {
      throw StateError('Unexpected status type: $_logType');
    }
  }

  Future<void> _saveQuality(HaccpLogServiceSupabase svc, String estId, String empId) async {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final signatureName = emp != null
        ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName)
        : null;
    final approvalStr = _logType == HaccpLogType.finishedProductBrakerage && _approvalToSell != null
        ? (_approvalToSell! ? 'разрешено' : 'запрещено')
        : null;
    final isFryingOil = _logType == HaccpLogType.fryingOil;
    final isFinishedBrakerage = _logType == HaccpLogType.finishedProductBrakerage;
    final isMedBook = _logType == HaccpLogType.medBookRegistry;
    final isMedExam = _logType == HaccpLogType.medExaminations;
    final isDisinf = _logType == HaccpLogType.disinfectantAccounting;
    final isWash = _logType == HaccpLogType.equipmentWashing;
    final isGenClean = _logType == HaccpLogType.generalCleaningSchedule;
    final isSieve = _logType == HaccpLogType.sieveFilterMagnet;
    await svc.insertQuality(
      establishmentId: estId,
      createdByEmployeeId: empId,
      logType: _logType!,
      techCardId: isFinishedBrakerage ? _selectedFinishedBrakerageTechCardId : null,
      productName: _getText('product').isNotEmpty ? _getText('product') : null,
      result: _getText('result').isNotEmpty ? _getText('result') : null,
      timeBrakerage: _getText('time_brakerage').isNotEmpty ? _getText('time_brakerage') : null,
      approvalToSell: approvalStr ?? (_getText('approval_to_sell').isNotEmpty ? _getText('approval_to_sell') : null),
      commissionSignatures: signatureName,
      weighingResult: _getText('weighing_result').isNotEmpty ? _getText('weighing_result') : null,
      packaging: _getText('packaging').isNotEmpty ? _getText('packaging') : null,
      manufacturerSupplier: _getText('manufacturer_supplier').isNotEmpty ? _getText('manufacturer_supplier') : null,
      quantityKg: _getNum('quantity_kg'),
      documentNumber: _getText('document_number').isNotEmpty ? _getText('document_number') : null,
      storageConditions: _getText('storage_conditions').isNotEmpty ? _getText('storage_conditions') : null,
      dateSold: _dateSold,
      oilName: isFryingOil && _getText('oil_name').isNotEmpty ? _getText('oil_name') : null,
      organolepticStart: isFryingOil && _getText('organoleptic_start').isNotEmpty ? _getText('organoleptic_start') : null,
      fryingEquipmentType: isFryingOil && _getText('frying_equipment_type').isNotEmpty ? _getText('frying_equipment_type') : null,
      fryingProductType: isFryingOil && _getText('frying_product_type').isNotEmpty ? _getText('frying_product_type') : null,
      fryingEndTime: isFryingOil && _getText('frying_end_time').isNotEmpty ? _getText('frying_end_time') : null,
      organolepticEnd: isFryingOil && _getText('organoleptic_end').isNotEmpty ? _getText('organoleptic_end') : null,
      carryOverKg: isFryingOil ? _getNum('carry_over_kg') : null,
      utilizedKg: isFryingOil ? _getNum('utilized_kg') : null,
      medBookEmployeeName: isMedBook && _getText('med_book_employee_name').isNotEmpty ? _getText('med_book_employee_name') : null,
      medBookPosition: isMedBook && _getText('med_book_position').isNotEmpty ? _getText('med_book_position') : null,
      medBookNumber: isMedBook && _getText('med_book_number').isNotEmpty ? _getText('med_book_number') : null,
      medBookValidUntil: isMedBook ? _medBookValidUntil : null,
      medBookIssuedAt: isMedBook ? _medBookIssuedAt : null,
      medBookReturnedAt: isMedBook ? _medBookReturnedAt : null,
      medExamEmployeeName: isMedExam && _getText('med_exam_employee_name').isNotEmpty ? _getText('med_exam_employee_name') : null,
      medExamDob: isMedExam && _getText('med_exam_dob').isNotEmpty ? _getText('med_exam_dob') : null,
      medExamGender: isMedExam && _getText('med_exam_gender').isNotEmpty ? _getText('med_exam_gender') : null,
      medExamPosition: isMedExam && _getText('med_exam_position').isNotEmpty ? _getText('med_exam_position') : null,
      medExamDepartment: isMedExam && _getText('med_exam_department').isNotEmpty ? _getText('med_exam_department') : null,
      medExamHireDate: isMedExam ? _medExamHireDate : null,
      medExamType: isMedExam && _getText('med_exam_type').isNotEmpty ? _getText('med_exam_type') : null,
      medExamInstitution: isMedExam && _getText('med_exam_institution').isNotEmpty ? _getText('med_exam_institution') : null,
      medExamHarmful1: isMedExam && _getText('med_exam_harmful_1').isNotEmpty ? _getText('med_exam_harmful_1') : null,
      medExamHarmful2: isMedExam && _getText('med_exam_harmful_2').isNotEmpty ? _getText('med_exam_harmful_2') : null,
      medExamDate: isMedExam ? _medExamDate : null,
      medExamConclusion: isMedExam && _getText('med_exam_conclusion').isNotEmpty ? _getText('med_exam_conclusion') : null,
      medExamEmployerDecision: isMedExam && _getText('med_exam_employer_decision').isNotEmpty ? _getText('med_exam_employer_decision') : null,
      medExamNextDate: isMedExam ? _medExamNextDate : null,
      medExamExclusionDate: isMedExam ? _medExamExclusionDate : null,
      disinfObjectName: isDisinf && _getText('disinf_object_name').isNotEmpty ? _getText('disinf_object_name') : null,
      disinfObjectCount: isDisinf ? _getNum('disinf_object_count') : null,
      disinfAreaSqm: isDisinf ? _getNum('disinf_area_sqm') : null,
      disinfTreatmentType: isDisinf && _getText('disinf_treatment_type').isNotEmpty ? _getText('disinf_treatment_type') : null,
      disinfFrequencyPerMonth: isDisinf ? _getInt('disinf_frequency') : null,
      disinfAgentName: isDisinf && (_getText('disinf_agent_name').isNotEmpty || _getText('disinf_agent_name_receipt').isNotEmpty) ? (_getText('disinf_agent_name').isNotEmpty ? _getText('disinf_agent_name') : _getText('disinf_agent_name_receipt')) : null,
      disinfConcentrationPct: isDisinf && _getText('disinf_concentration_pct').isNotEmpty ? _getText('disinf_concentration_pct') : null,
      disinfConsumptionPerSqm: isDisinf ? _getNum('disinf_consumption_per_sqm') : null,
      disinfSolutionPerTreatment: isDisinf ? _getNum('disinf_solution_per_treatment') : null,
      disinfNeedPerTreatment: isDisinf ? _getNum('disinf_need_per_treatment') : null,
      disinfNeedPerMonth: isDisinf ? _getNum('disinf_need_per_month') : null,
      disinfNeedPerYear: isDisinf ? _getNum('disinf_need_per_year') : null,
      disinfReceiptDate: isDisinf ? _disinfReceiptDate : null,
      disinfInvoiceNumber: isDisinf && _getText('disinf_invoice_number').isNotEmpty ? _getText('disinf_invoice_number') : null,
      disinfQuantity: isDisinf ? _getNum('disinf_quantity') : null,
      disinfExpiryDate: isDisinf ? _disinfExpiryDate : null,
      disinfResponsibleName: isDisinf ? signatureName : null,
      washTime: isWash && _getText('wash_time').isNotEmpty ? _getText('wash_time') : null,
      washEquipmentName: isWash && _getText('wash_equipment_name').isNotEmpty ? _getText('wash_equipment_name') : null,
      washSolutionName: isWash && _getText('wash_solution_name').isNotEmpty ? _getText('wash_solution_name') : null,
      washSolutionConcentrationPct: isWash && _getText('wash_solution_concentration_pct').isNotEmpty ? _getText('wash_solution_concentration_pct') : null,
      washDisinfectantName: isWash && _getText('wash_disinfectant_name').isNotEmpty ? _getText('wash_disinfectant_name') : null,
      washDisinfectantConcentrationPct: isWash && _getText('wash_disinfectant_concentration_pct').isNotEmpty ? _getText('wash_disinfectant_concentration_pct') : null,
      washRinsingTemp: isWash && _getText('wash_rinsing_temp').isNotEmpty ? _getText('wash_rinsing_temp') : null,
      washControllerSignature: isWash && _getText('wash_controller_signature').isNotEmpty ? _getText('wash_controller_signature') : null,
      genCleanPremises: isGenClean && _getText('gen_clean_premises').isNotEmpty ? _getText('gen_clean_premises') : null,
      genCleanDate: isGenClean ? _genCleanDate : null,
      genCleanResponsible: isGenClean ? signatureName : null,
      sieveNo: isSieve && _getText('sieve_no').isNotEmpty ? _getText('sieve_no') : null,
      sieveNameLocation: isSieve && _getText('sieve_name_location').isNotEmpty ? _getText('sieve_name_location') : null,
      sieveCondition: isSieve && _getText('sieve_condition').isNotEmpty ? _getText('sieve_condition') : null,
      sieveCleaningDate: isSieve ? _sieveCleaningDate : null,
      sieveSignature: isSieve ? signatureName : null,
      sieveComments: isSieve && _getText('sieve_comments').isNotEmpty ? _getText('sieve_comments') : null,
      note: _getText('note').isNotEmpty ? _getText('note') : null,
    );
  }

  int? _getInt(String key) {
    final s = _getText(key);
    if (s.isEmpty) return null;
    return int.tryParse(s.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    if (_logType == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('haccp_journals') ?? 'Журналы ХАССП')),
        body: Center(child: Text(loc.t('error') ?? 'Неизвестный тип журнала')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('haccp_add_entry') ?? 'Добавить'} — ${_logType!.displayNameRu}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (emp != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(emp.fullName),
                  subtitle: Text(emp.roleDisplayName),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Рекомендуемый образец',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Таблица по форме СанПиН — при необходимости прокрутите вправо',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1400,
                child: _buildFormByType(loc),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
