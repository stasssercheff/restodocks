import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Форма добавления записи в журнал ХАССП.
/// Быстрый ввод: слайдеры температуры, чекбоксы здоровья.
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
  bool _washTempOk = true;
  bool _rinseTempOk = true;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  HaccpLogType get _logType => HaccpLogType.fromCode(widget.logTypeCode) ?? HaccpLogType.healthHygiene;

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

  List<Widget> _buildFields() {
    final loc = context.read<LocalizationService>();
    final list = <Widget>[];

    switch (_logType) {
      case HaccpLogType.healthHygiene:
        list.addAll([
          SwitchListTile(
            title: Text(loc.t('haccp_result_exam') ?? 'Результат осмотра (допущен / отстранен)'),
            subtitle: Text(_healthy ? 'допущен' : 'отстранен', style: TextStyle(color: _healthy ? Colors.green : Colors.orange)),
            value: _healthy,
            onChanged: (v) => setState(() => _healthy = v ?? true),
          ),
          SwitchListTile(
            title: Text(loc.t('haccp_no_arvi_ok') ?? 'Отсутствие заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук'),
            subtitle: Text(_noArviOk ? 'Да' : 'Нет', style: TextStyle(color: _noArviOk ? Colors.green : Colors.orange)),
            value: _noArviOk,
            onChanged: (v) => setState(() => _noArviOk = v ?? true),
          ),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.pediculosis:
        list.addAll([
          SwitchListTile(
            title: Text(loc.t('haccp_healthy') ?? 'Здоров'),
            value: _healthy,
            onChanged: (v) => setState(() => _healthy = v ?? true),
          ),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.uvLamps:
        list.addAll([
          _textField('hours', loc.t('haccp_hours') ?? 'Часы работы', keyboardType: TextInputType.number),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.fridgeTemperature:
        list.addAll([
          _tempSlider(loc.t('haccp_temp') ?? 'Температура °C', -10, 15, _tempValue, (v) => setState(() => _tempValue = v)),
          _textField('equipment', loc.t('haccp_equipment') ?? 'Оборудование'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.warehouseTempHumidity:
        list.addAll([
          _tempSlider(loc.t('haccp_temp') ?? 'Температура °C', -5, 30, _tempValue, (v) => setState(() => _tempValue = v)),
          _tempSlider(loc.t('haccp_humidity') ?? 'Влажность %', 20, 90, _humidityValue, (v) => setState(() => _humidityValue = v)),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.dishwasherControl:
        list.addAll([
          SwitchListTile(
            title: Text(loc.t('haccp_wash_temp_ok') ?? 't° мойки в норме'),
            value: _washTempOk,
            onChanged: (v) => setState(() => _washTempOk = v),
          ),
          SwitchListTile(
            title: Text(loc.t('haccp_rinse_temp_ok') ?? 't° ополаскивания в норме'),
            value: _rinseTempOk,
            onChanged: (v) => setState(() => _rinseTempOk = v),
          ),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.greaseTrapCleaning:
      case HaccpLogType.generalCleaningSchedule:
        list.add(_textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true));
        break;
      case HaccpLogType.finishedProductBrakerage:
      case HaccpLogType.incomingRawBrakerage:
        list.addAll([
          _textField('product', loc.t('haccp_product') ?? 'Продукция / Сырьё'),
          _textField('result', loc.t('haccp_result') ?? 'Результат бракеража'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.fryingOil:
        list.addAll([
          _textField('action', loc.t('haccp_action') ?? 'Действие (замена/долив)'),
          _textField('oil_name', loc.t('haccp_oil_name') ?? 'Марка масла'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.foodWaste:
        list.addAll([
          _textField('weight', loc.t('haccp_weight') ?? 'Вес, кг'),
          _textField('reason', loc.t('haccp_reason') ?? 'Причина списания'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.glassCeramicsBreakage:
        list.addAll([
          _textField('description', loc.t('haccp_description') ?? 'Описание'),
          _textField('location', loc.t('haccp_location') ?? 'Место (цех)'),
        ]);
        break;
      case HaccpLogType.emergencyIncidents:
        list.addAll([
          _textField('type', loc.t('haccp_incident_type') ?? 'Тип (вода/свет/канализация)'),
          _textField('duration', loc.t('haccp_duration') ?? 'Длительность'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.disinsectionDeratization:
        list.addAll([
          _textField('agent', loc.t('haccp_agent') ?? 'Средство'),
          _textField('company', loc.t('haccp_company') ?? 'Организация'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
      case HaccpLogType.disinfectantConcentration:
        list.addAll([
          _textField('agent', loc.t('haccp_agent') ?? 'Средство'),
          _textField('concentration', loc.t('haccp_concentration') ?? 'Концентрация'),
          _textField('note', loc.t('haccp_note') ?? 'Примечание', multiline: true),
        ]);
        break;
    }

    return list;
  }

  Widget _tempSlider(String label, double min, double max, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.toStringAsFixed(1)}'),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 2).toInt(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _textField(String key, String label, {bool multiline = false, TextInputType? keyboardType}) {
    _controllers[key] ??= TextEditingController();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[key],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        maxLines: multiline ? 3 : 1,
        keyboardType: keyboardType,
      ),
    );
  }

  Future<void> _save() async {
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
      switch (_logType.targetTable) {
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
      if (mounted) {
        context.pop({'saved': true});
      }
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
    switch (_logType) {
      case HaccpLogType.uvLamps:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          value1: _getNum('hours') ?? 0,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.fridgeTemperature:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          value1: _tempValue,
          equipment: _getText('equipment').isNotEmpty ? _getText('equipment') : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.warehouseTempHumidity:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          value1: _tempValue,
          value2: _humidityValue,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.disinfectantConcentration:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          value1: _getNum('concentration') ?? 0,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      default:
        throw StateError('Unexpected numeric type: $_logType');
    }
  }

  Future<void> _saveStatus(HaccpLogServiceSupabase svc, String estId, String empId) async {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: _healthy,
          status2Ok: _noArviOk,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.pediculosis:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: _healthy,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.dishwasherControl:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: _washTempOk,
          status2Ok: _rinseTempOk,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.greaseTrapCleaning:
      case HaccpLogType.generalCleaningSchedule:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: true,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      case HaccpLogType.glassCeramicsBreakage:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: true,
          description: _getText('description').isNotEmpty ? _getText('description') : null,
          location: _getText('location').isNotEmpty ? _getText('location') : null,
        );
        break;
      case HaccpLogType.emergencyIncidents:
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType,
          statusOk: true,
          description: _getText('type').isNotEmpty ? _getText('type') : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        break;
      default:
        throw StateError('Unexpected status type: $_logType');
    }
  }

  Future<void> _saveQuality(HaccpLogServiceSupabase svc, String estId, String empId) async {
    await svc.insertQuality(
      establishmentId: estId,
      createdByEmployeeId: empId,
      logType: _logType,
      techCardId: _getText('tech_card_id').isNotEmpty ? _getText('tech_card_id') : null,
      productName: _getText('product').isNotEmpty ? _getText('product') : null,
      result: _getText('result').isNotEmpty ? _getText('result') : null,
      weight: _getNum('weight'),
      reason: _getText('reason').isNotEmpty ? _getText('reason') : null,
      action: _getText('action').isNotEmpty ? _getText('action') : null,
      oilName: _getText('oil_name').isNotEmpty ? _getText('oil_name') : null,
      agent: _getText('agent').isNotEmpty ? _getText('agent') : null,
      concentration: _getText('concentration').isNotEmpty ? _getText('concentration') : null,
      note: _getText('note').isNotEmpty ? _getText('note') : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('haccp_add_entry') ?? 'Добавить'} — ${_logType.displayNameRu}'),
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
            ..._buildFields(),
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
