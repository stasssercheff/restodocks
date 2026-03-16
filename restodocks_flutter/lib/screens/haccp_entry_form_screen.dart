import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

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
  bool _healthy = true;
  bool _noArviOk = true;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  DateTime? _expiryDate;
  DateTime? _dateSold;
  /// Разрешение к реализации: true = разрешено, false = запрещено, null = не выбрано.
  bool? _approvalToSell;

  /// Гигиенический журнал: список сотрудников заведения, выбранный сотрудник и должность.
  List<Employee> _healthEmployees = [];
  String? _selectedHealthEmployeeId;
  String _healthPositionDisplay = '';
  bool _healthPositionIsCustom = false;

  HaccpLogType? get _logType {
    final t = HaccpLogType.fromCode(widget.logTypeCode);
    return t != null && HaccpLogType.supportedInApp.contains(t) ? t : null;
  }

  @override
  void initState() {
    super.initState();
    if (_logType == HaccpLogType.healthHygiene) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHealthEmployees());
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
          if (_selectedHealthEmployeeId == null && _healthEmployees.isNotEmpty) {
            final idx = _healthEmployees.indexWhere((e) => e.id == current.id);
            _selectedHealthEmployeeId = idx >= 0 ? _healthEmployees[idx].id : _healthEmployees.first.id;
            final emp = _healthEmployees.firstWhere((e) => e.id == _selectedHealthEmployeeId, orElse: () => _healthEmployees.first);
            _healthPositionDisplay = emp.roleDisplayName;
            _healthPositionIsCustom = false;
          }
        });
      }
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

  Widget _healthEmployeeDropdown() {
    final options = _healthEmployees;
    if (options.isEmpty) {
      return _tableCell(const Text('—'));
    }
    final value = _selectedHealthEmployeeId ?? options.first.id;
    return _tableCell(
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: options.map((e) {
            final name = e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName;
            return DropdownMenuItem(value: e.id, child: Text(name, overflow: TextOverflow.ellipsis));
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final emp = options.firstWhere((e) => e.id == id, orElse: () => options.first);
            setState(() {
              _selectedHealthEmployeeId = id;
              if (!_healthPositionIsCustom) _healthPositionDisplay = emp.roleDisplayName;
            });
          },
        ),
      ),
    );
  }

  Widget _healthPositionDropdown() {
    final roleNames = EmployeeRole.values.map((r) => r.displayName).toList();
    final effectiveValue = _healthPositionIsCustom ? _customPositionValue : (roleNames.contains(_healthPositionDisplay) ? _healthPositionDisplay : (roleNames.isNotEmpty ? roleNames.first : _customPositionValue));
    return _tableCell(
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          isExpanded: true,
          isDense: true,
          items: [
            ...roleNames.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))),
            DropdownMenuItem(
              value: _customPositionValue,
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(_healthPositionIsCustom && _healthPositionDisplay.isNotEmpty ? 'Свой вариант: $_healthPositionDisplay' : 'Свой вариант', overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
          onChanged: (v) async {
            if (v == _customPositionValue) {
              final text = await _showCustomPositionDialog();
              if (text != null && mounted) setState(() {
                _healthPositionDisplay = text;
                _healthPositionIsCustom = true;
              });
              return;
            }
            if (v != null) setState(() {
              _healthPositionDisplay = v;
              _healthPositionIsCustom = false;
            });
          },
        ),
      ),
    );
  }

  Future<String?> _showCustomPositionDialog() async {
    final ctrl = TextEditingController(text: _healthPositionIsCustom ? _healthPositionDisplay : '');
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

  /// Форма по макету Приложения 1: Гигиенический журнал (сотрудники).
  Widget _buildHealthHygieneForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
      columnWidths: const {
        0: FlexColumnWidth(0.5),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1.8),
        5: FlexColumnWidth(1.8),
        6: FlexColumnWidth(1.2),
        7: FlexColumnWidth(1),
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
          ],
        ),
        TableRow(
          children: [
            _tableCell(const Text('1')),
            _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
            _tableCell(_healthEmployeeDropdown()),
            _tableCell(_healthPositionDropdown()),
            _tableCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: _healthy, onChanged: (v) => setState(() => _healthy = v ?? true)),
                Text(_healthy ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: _healthy ? Colors.green : Colors.orange)),
              ],
            )),
            _tableCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: _noArviOk, onChanged: (v) => setState(() => _noArviOk = v ?? true)),
                Text(_noArviOk ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: _noArviOk ? Colors.green : Colors.orange)),
              ],
            )),
            _tableCell(Text(_healthy ? 'допущен' : 'отстранен', style: const TextStyle(fontSize: 12))),
            _tableCell(Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => Text(acc.currentEmployee?.fullName ?? '—', style: const TextStyle(fontSize: 11)),
            )),
          ],
        ),
      ],
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
            _tableCell(_textField('product', loc.t('haccp_product') ?? 'Наименование блюда')),
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
      final subjectId = _selectedHealthEmployeeId ?? empId;
      final description = HaccpLog.buildHealthHygieneDescription(
        employeeId: subjectId,
        positionOverride: _healthPositionDisplay.trim().isEmpty ? null : _healthPositionDisplay.trim(),
      );
      await svc.insertStatus(
        establishmentId: estId,
        createdByEmployeeId: empId,
        logType: _logType!,
        statusOk: _healthy,
        status2Ok: _noArviOk,
        description: description,
        note: _getText('note').isNotEmpty ? _getText('note') : null,
      );
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
    await svc.insertQuality(
      establishmentId: estId,
      createdByEmployeeId: empId,
      logType: _logType!,
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
      note: _getText('note').isNotEmpty ? _getText('note') : null,
    );
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
