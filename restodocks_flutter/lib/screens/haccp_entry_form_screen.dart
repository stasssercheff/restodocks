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

  Map<String, dynamic> _buildPayload() {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
      case HaccpLogType.pediculosis:
        return {'healthy': _healthy, 'note': _getText('note')};
      case HaccpLogType.uvLamps:
        return {'hours': _getText('hours'), 'note': _getText('note')};
      case HaccpLogType.fridgeTemperature:
        return {'temp': _tempValue, 'equipment': _getText('equipment'), 'note': _getText('note')};
      case HaccpLogType.warehouseTempHumidity:
        return {'temp': _tempValue, 'humidity': _humidityValue, 'note': _getText('note')};
      case HaccpLogType.dishwasherControl:
        return {'wash_temp_ok': _washTempOk, 'rinse_temp_ok': _rinseTempOk, 'note': _getText('note')};
      case HaccpLogType.greaseTrapCleaning:
        return {'done': true, 'note': _getText('note')};
      case HaccpLogType.finishedProductBrakerage:
      case HaccpLogType.incomingRawBrakerage:
        return {'result': _getText('result'), 'product': _getText('product'), 'note': _getText('note')};
      case HaccpLogType.fryingOil:
        return {'action': _getText('action'), 'oil_name': _getText('oil_name'), 'note': _getText('note')};
      case HaccpLogType.foodWaste:
        return {'weight': _getText('weight'), 'reason': _getText('reason'), 'note': _getText('note')};
      case HaccpLogType.glassCeramicsBreakage:
        return {'description': _getText('description'), 'location': _getText('location')};
      case HaccpLogType.emergencyIncidents:
        return {'type': _getText('type'), 'duration': _getText('duration'), 'note': _getText('note')};
      case HaccpLogType.disinsectionDeratization:
        return {'agent': _getText('agent'), 'company': _getText('company'), 'note': _getText('note')};
      case HaccpLogType.generalCleaningSchedule:
        return {'zone': _getText('zone'), 'done': true, 'note': _getText('note')};
      case HaccpLogType.disinfectantConcentration:
        return {'agent': _getText('agent'), 'concentration': _getText('concentration'), 'note': _getText('note')};
    }
  }

  String _getText(String key) => _controllers[key]?.text.trim() ?? '';

  List<Widget> _buildFields() {
    final loc = context.read<LocalizationService>();
    final list = <Widget>[];

    switch (_logType) {
      case HaccpLogType.healthHygiene:
      case HaccpLogType.pediculosis:
        list.addAll([
          SwitchListTile(
            title: Text(loc.t('haccp_healthy') ?? 'Здоров'),
            value: _healthy,
            onChanged: (v) => setState(() => _healthy = v),
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
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    setState(() => _saving = true);
    try {
      await context.read<HaccpLogServiceSupabase>().insert(
            establishmentId: est.id,
            createdByEmployeeId: emp.id,
            logType: _logType,
            payload: _buildPayload(),
          );
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
