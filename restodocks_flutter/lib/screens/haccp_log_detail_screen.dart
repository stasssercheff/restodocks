import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр записи журнала ХАССП — только чтение. Редактирование запрещено.
class HaccpLogDetailScreen extends StatelessWidget {
  const HaccpLogDetailScreen({
    super.key,
    required this.log,
    this.employee,
  });

  final HaccpLog log;
  final Employee? employee;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('haccp_entry_view') ?? 'Запись'} — ${log.logType.displayNameRu}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateTimeFmt.format(log.createdAt),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (employee != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${employee!.fullName}${employee!.surname != null ? ' ${employee!.surname}' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      employee!.roleDisplayName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._buildFields(context, loc),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.t('haccp_entry_immutable_hint') ?? 'Только просмотр. Редактирование записей журнала недоступно.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFields(BuildContext context, LocalizationService loc) {
    final theme = Theme.of(context);
    final rows = <Widget>[];

    void addRow(String label, String? value) {
      if (value == null || value.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.bodyLarge),
          ],
        ),
      ));
    }

    switch (log.logType.targetTable) {
      case HaccpLogTable.numeric:
        if (log.value1 != null) addRow(loc.t('haccp_temp') ?? 'Значение', log.value1!.toStringAsFixed(1));
        if (log.value2 != null) addRow(loc.t('haccp_humidity') ?? 'Влажность %', log.value2!.toStringAsFixed(1));
        addRow(loc.t('haccp_equipment') ?? 'Оборудование', log.equipment);
        break;
      case HaccpLogTable.status:
        if (log.logType == HaccpLogType.healthHygiene) {
          if (log.statusOk != null) addRow(loc.t('haccp_result_exam') ?? 'Результат осмотра', log.statusOk! ? 'допущен' : 'отстранен');
          if (log.status2Ok != null) addRow(loc.t('haccp_no_arvi_ok') ?? 'Отсутствие ОРВИ и гнойничковых заболеваний', log.status2Ok! ? 'Да' : 'Нет');
        } else {
          if (log.statusOk != null) addRow(loc.t('haccp_healthy') ?? 'Статус', log.statusOk! ? 'Да' : 'Нет');
          if (log.status2Ok != null) addRow(loc.t('haccp_rinse_temp_ok') ?? 'Статус 2', log.status2Ok! ? 'Да' : 'Нет');
          addRow(loc.t('haccp_description') ?? 'Описание', log.description);
          addRow(loc.t('haccp_location') ?? 'Место', log.location);
        }
        break;
      case HaccpLogTable.quality:
        addRow(loc.t('haccp_product') ?? 'Продукция', log.productName);
        addRow(loc.t('haccp_result') ?? 'Результат', log.result);
        if (log.weight != null) addRow(loc.t('haccp_weight') ?? 'Вес', log.weight!.toString());
        addRow(loc.t('haccp_reason') ?? 'Причина', log.reason);
        addRow(loc.t('haccp_action') ?? 'Действие', log.action);
        addRow(loc.t('haccp_oil_name') ?? 'Масло', log.oilName);
        addRow(loc.t('haccp_agent') ?? 'Средство', log.agent);
        addRow(loc.t('haccp_concentration') ?? 'Концентрация', log.concentration);
        break;
    }
    addRow(loc.t('haccp_note') ?? 'Примечание', log.note);

    return rows;
  }
}
