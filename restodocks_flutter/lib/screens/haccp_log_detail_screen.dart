import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр записи журнала ХАССП — в виде строки таблицы по макету СанПиН (только чтение).
class HaccpLogDetailScreen extends StatelessWidget {
  const HaccpLogDetailScreen({
    super.key,
    required this.log,
    this.employee,
  });

  final HaccpLog log;
  final Employee? employee;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');
  static final _timeFmt = DateFormat('HH:mm');

  Widget _header(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          border: Border(
            right: BorderSide(color: Colors.grey.shade400),
            bottom: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _cell(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.grey.shade400),
            bottom: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );

  /// Приложение 1: Гигиенический журнал (сотрудники).
  Widget _buildHealthHygieneTable(BuildContext context) {
    final empName = employee != null
        ? '${employee!.fullName}${employee!.surname != null ? ' ${employee!.surname}' : ''}'
        : '—';
    final position = employee?.roleDisplayName ?? '—';
    final sign1 = log.status2Ok == true ? 'Да' : (log.status2Ok == false ? 'Нет' : '—');
    final sign2 = log.statusOk == true ? 'Да' : (log.statusOk == false ? 'Нет' : '—');
    final result = log.statusOk == true ? 'допущен' : (log.statusOk == false ? 'отстранен' : '—');
    return Table(
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
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('№ п/п'),
            _header('Дата'),
            _header('Ф.И.О. работника'),
            _header('Должность'),
            _header('Подпись об отсутствии признаков инфекционных заболеваний'),
            _header('Подпись об отсутствии заболеваний верхних дыхательных путей и кожи'),
            _header('Результат осмотра (допущен / отстранен)'),
            _header('Подпись медработника'),
          ],
        ),
        TableRow(
          children: [
            _cell('1'),
            _cell(_dateFmt.format(log.createdAt)),
            _cell(empName),
            _cell(position),
            _cell(sign2),
            _cell(sign1),
            _cell(result),
            _cell(empName),
          ],
        ),
      ],
    );
  }

  /// Приложение 2: Журнал учета температурного режима холодильного оборудования.
  Widget _buildFridgeTemperatureTable(BuildContext context, String establishmentName) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('Наименование производственного помещения'),
            _header('Наименование холодильного оборудования'),
            _header('Температура °C'),
          ],
        ),
        TableRow(
          children: [
            _cell(establishmentName),
            _cell(log.equipment ?? '—'),
            _cell(log.value1 != null ? log.value1!.toStringAsFixed(1) : '—'),
          ],
        ),
      ],
    );
  }

  /// Приложение 3: Журнал учета температуры и влажности в складских помещениях.
  Widget _buildWarehouseTempHumidityTable(BuildContext context, String establishmentName) {
    final temp = log.value1 != null ? '+${log.value1!.toStringAsFixed(0)}' : '—';
    final hum = log.value2 != null ? '${log.value2!.toStringAsFixed(0)}%' : '—';
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.5),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('№ п/п'),
            _header('Наименование складского помещения'),
            _header('Температура °C'),
            _header('Влажность %'),
          ],
        ),
        TableRow(
          children: [
            _cell('1'),
            _cell(establishmentName),
            _cell(temp),
            _cell(hum),
          ],
        ),
      ],
    );
  }

  /// Приложение 4: Журнал бракеража готовой пищевой продукции.
  Widget _buildFinishedProductBrakerageTable(BuildContext context) {
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
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('Дата и час изготовления блюда'),
            _header('Время снятия бракеража'),
            _header('Наименование готового блюда'),
            _header('Результаты органолептической оценки'),
            _header('Разрешение к реализации'),
            _header('Подписи членов бракеражной комиссии'),
            _header('Результаты взвешивания порционных блюд'),
            _header('Примечание'),
          ],
        ),
        TableRow(
          children: [
            _cell(_dateTimeFmt.format(log.createdAt)),
            _cell(log.timeBrakerage ?? '—'),
            _cell(log.productName ?? '—'),
            _cell(log.result ?? '—'),
            _cell(log.approvalToSell ?? '—'),
            _cell(log.commissionSignatures ?? '—'),
            _cell(log.weighingResult ?? '—'),
            _cell(log.note ?? '—'),
          ],
        ),
      ],
    );
  }

  /// Приложение 5: Журнал бракеража скоропортящейся пищевой продукции.
  Widget _buildIncomingRawBrakerageTable(BuildContext context) {
    final dateSoldStr = log.dateSold != null ? _dateFmt.format(log.dateSold!) : '—';
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
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('Дата и час поступления'),
            _header('Наименование'),
            _header('Фасовка'),
            _header('Изготовитель/поставщик'),
            _header('Кол-во'),
            _header('№ документа'),
            _header('Органолептическая оценка'),
            _header('Условия хранения, срок реализации'),
            _header('Дата реализации'),
            _header('Подпись'),
            _header('Прим.'),
          ],
        ),
        TableRow(
          children: [
            _cell(_dateTimeFmt.format(log.createdAt)),
            _cell(log.productName ?? '—'),
            _cell(log.packaging ?? '—'),
            _cell(log.manufacturerSupplier ?? '—'),
            _cell(log.quantityKg != null ? log.quantityKg!.toStringAsFixed(2) : '—'),
            _cell(log.documentNumber ?? '—'),
            _cell(log.result ?? '—'),
            _cell(log.storageConditions ?? '—'),
            _cell(dateSoldStr),
            _cell(employee?.fullName ?? '—'),
            _cell(log.note ?? '—'),
          ],
        ),
      ],
    );
  }

  Widget _buildFryingOilTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1),
        4: FlexColumnWidth(1), 5: FlexColumnWidth(0.8), 6: FlexColumnWidth(1.2), 7: FlexColumnWidth(0.7),
        8: FlexColumnWidth(0.7), 9: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('Дата (час) начала'), _header('Вид жира'), _header('Оценка на начало'),
            _header('Оборудование'), _header('Вид продукции'), _header('Время окончания'),
            _header('Оценка по окончании'), _header('Переходящий остаток, кг'), _header('Утилизировано, кг'), _header('Контролёр'),
          ],
        ),
        TableRow(
          children: [
            _cell(_dateTimeFmt.format(log.createdAt)),
            _cell(log.oilName ?? '—'),
            _cell(log.organolepticStart ?? '—'),
            _cell(log.fryingEquipmentType ?? '—'),
            _cell(log.fryingProductType ?? '—'),
            _cell(log.fryingEndTime ?? '—'),
            _cell(log.organolepticEnd ?? '—'),
            _cell(log.carryOverKg != null ? log.carryOverKg!.toStringAsFixed(2) : '—'),
            _cell(log.utilizedKg != null ? log.utilizedKg!.toStringAsFixed(2) : '—'),
            _cell(log.commissionSignatures ?? employee?.fullName ?? '—'),
          ],
        ),
      ],
    );
  }

  Widget _buildTableForType(BuildContext context, String establishmentName) {
    if (!HaccpLogType.supportedInApp.contains(log.logType)) {
      return const SizedBox.shrink();
    }
    switch (log.logType) {
      case HaccpLogType.healthHygiene:
        return _buildHealthHygieneTable(context);
      case HaccpLogType.fridgeTemperature:
        return _buildFridgeTemperatureTable(context, establishmentName);
      case HaccpLogType.warehouseTempHumidity:
        return _buildWarehouseTempHumidityTable(context, establishmentName);
      case HaccpLogType.finishedProductBrakerage:
        return _buildFinishedProductBrakerageTable(context);
      case HaccpLogType.incomingRawBrakerage:
        return _buildIncomingRawBrakerageTable(context);
      case HaccpLogType.fryingOil:
        return _buildFryingOilTable(context);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final establishmentName = context.watch<AccountManagerSupabase>().establishment?.name ?? '—';

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('haccp_entry_view') ?? 'Запись'} — ${log.logType.displayNameRu}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Рекомендуемый образец',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1200,
              child: _buildTableForType(context, establishmentName),
            ),
          ),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
