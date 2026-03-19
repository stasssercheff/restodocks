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
    this.creator,
    this.subjectNameSnapshot,
    this.subjectPositionSnapshot,
  });

  final HaccpLog log;
  final Employee? employee;

  /// Для гигиенического журнала: кто заполнил запись (подпись медработника).
  final Employee? creator;

  /// Снимок ФИО субъекта (для гигиенического журнала при удалённом сотруднике).
  final String? subjectNameSnapshot;

  /// Снимок должности субъекта (для гигиенического журнала при удалённом сотруднике).
  final String? subjectPositionSnapshot;

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
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _cell(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color != null ? color.withValues(alpha: 0.15) : null,
          border: Border(
            right: BorderSide(color: Colors.grey.shade400),
            bottom: BorderSide(color: Colors.grey.shade400),
          ),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );

  /// Приложение 1: Гигиенический журнал (сотрудники).
  Widget _buildHealthHygieneTable(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
    final empName = subjectNameSnapshot ??
        parsed.employeeNameSnapshot ??
        (employee != null
            ? '${employee!.fullName}${employee!.surname != null ? ' ${employee!.surname}' : ''}'
            : null) ??
        '—';
    final position = (subjectPositionSnapshot != null &&
            subjectPositionSnapshot!.trim().isNotEmpty)
        ? loc.formatStoredHealthPosition(subjectPositionSnapshot)
        : loc.healthHygienePositionLabel(
            storedPosition: parsed.positionOverride,
            employee: employee,
          );
    final creatorName = creator != null
        ? '${creator!.fullName}${creator!.surname != null ? ' ${creator!.surname}' : ''}'
        : '—';
    final sign1 =
        log.status2Ok == true ? 'Да' : (log.status2Ok == false ? 'Нет' : '—');
    final sign2 =
        log.statusOk == true ? 'Да' : (log.statusOk == false ? 'Нет' : '—');
    final result = log.statusOk == true
        ? 'допущен'
        : (log.statusOk == false ? 'отстранен' : '—');
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
            _header('Ф. И. О. работника (последнее при наличии)'),
            _header('Должность'),
            _header(
                'Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
            _header(
                'Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
            _header(
                'Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)'),
            _header('Подпись медицинского работника (ответственного лица)'),
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
            _cell(creatorName),
          ],
        ),
      ],
    );
  }

  /// Приложение 2: Журнал учета температурного режима холодильного оборудования.
  Widget _buildFridgeTemperatureTable(
      BuildContext context, String establishmentName) {
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

  /// Приложение 3: 5 обязательных колонок. Наименование помещения — в шапке.
  Widget _buildWarehouseTempHumidityTable(
      BuildContext context, String establishmentName) {
    final tempVal = log.value1;
    final humVal = log.value2;
    final temp = tempVal != null ? tempVal.toStringAsFixed(0) : '—';
    final hum = humVal != null ? '${humVal.toStringAsFixed(0)}%' : '—';
    final tempAlert = tempVal != null && tempVal > 25;
    final humAlert = humVal != null && humVal > 75;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (log.equipment != null && log.equipment!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Наименование складского помещения: ${log.equipment}',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.5),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(0.8),
            3: FlexColumnWidth(0.8),
            4: FlexColumnWidth(1.2),
          },
          border: TableBorder.all(color: Colors.grey),
          children: [
            TableRow(
              children: [
                _header('№ п/п'),
                _header('Дата'),
                _header('Температура, °C'),
                _header('Относительная влажность, %'),
                _header('Подпись ответственного лица'),
              ],
            ),
            TableRow(
              children: [
                _cell('1'),
                _cell(DateFormat('dd.MM.yyyy').format(log.createdAt)),
                _cell(temp, color: tempAlert ? Colors.red : null),
                _cell(hum, color: humAlert ? Colors.red : null),
                _cell(employee?.fullName ?? '—'),
              ],
            ),
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
    final dateSoldStr =
        log.dateSold != null ? _dateFmt.format(log.dateSold!) : '—';
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
            _cell(log.quantityKg != null
                ? log.quantityKg!.toStringAsFixed(2)
                : '—'),
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
        0: FlexColumnWidth(0.9),
        1: FlexColumnWidth(0.6),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(0.8),
        7: FlexColumnWidth(1.2),
        8: FlexColumnWidth(0.7),
        9: FlexColumnWidth(0.7),
        10: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('Дата'),
            _header('Время начала'),
            _header('Вид жира'),
            _header('Оценка на начало'),
            _header('Оборудование'),
            _header('Вид продукции'),
            _header('Время окончания'),
            _header('Оценка по окончании'),
            _header('Переходящий остаток, кг'),
            _header('Утилизировано, кг'),
            _header('Контролёр'),
          ],
        ),
        TableRow(
          children: [
            _cell(_dateFmt.format(log.createdAt)),
            _cell(_timeFmt.format(log.createdAt)),
            _cell(log.oilName ?? '—'),
            _cell(log.organolepticStart ?? '—'),
            _cell(log.fryingEquipmentType ?? '—'),
            _cell(log.fryingProductType ?? '—'),
            _cell(log.fryingEndTime ?? '—'),
            _cell(log.organolepticEnd ?? '—'),
            _cell(log.carryOverKg != null
                ? log.carryOverKg!.toStringAsFixed(2)
                : '—'),
            _cell(log.utilizedKg != null
                ? log.utilizedKg!.toStringAsFixed(2)
                : '—'),
            _cell(log.commissionSignatures ?? employee?.fullName ?? '—'),
          ],
        ),
      ],
    );
  }

  Widget _buildMedBookTable(BuildContext context) {
    final sign = creator != null
        ? '${creator!.fullName}${creator!.surname != null ? ' ${creator!.surname}' : ''}'
        : '—';
    final issued = log.medBookIssuedAt != null
        ? _dateFmt.format(log.medBookIssuedAt!)
        : '—';
    final returned = log.medBookReturnedAt != null
        ? _dateFmt.format(log.medBookReturnedAt!)
        : '—';
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.9),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(
          children: [
            _header('№ п/п'),
            _header('Фамилия, имя, отчество'),
            _header('Должность'),
            _header('Номер медицинской книжки'),
            _header('Срок действия медицинской книжки'),
            _header('Расписка и дата получения медицинской книжки'),
            _header('Расписка и дата возврата медицинской книжки'),
          ],
        ),
        TableRow(
          children: [
            _cell('1'),
            _cell(log.medBookEmployeeName ?? '—'),
            _cell(log.medBookPosition ?? '—'),
            _cell(log.medBookNumber ?? '—'),
            _cell(log.medBookValidUntil != null
                ? _dateFmt.format(log.medBookValidUntil!)
                : '—'),
            _cell('$issued\n$sign'),
            _cell('$returned\n$sign'),
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
      case HaccpLogType.medBookRegistry:
        return _buildMedBookTable(context);
      case HaccpLogType.medExaminations:
        return _buildMedExaminationsTable(context);
      case HaccpLogType.disinfectantAccounting:
        return _buildDisinfectantAccountingTable(context);
      case HaccpLogType.equipmentWashing:
        return _buildEquipmentWashingTable(context);
      case HaccpLogType.generalCleaningSchedule:
        return _buildGeneralCleaningTable(context);
      case HaccpLogType.sieveFilterMagnet:
        return _buildSieveFilterMagnetTable(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMedExaminationsTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(0.7),
        3: FlexColumnWidth(0.6),
        4: FlexColumnWidth(0.8),
        5: FlexColumnWidth(0.7),
        6: FlexColumnWidth(0.7)
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(children: [
          _header('№'),
          _header('Ф. И. О.'),
          _header('Должность'),
          _header('Дата осмотра'),
          _header('Заключение'),
          _header('Решение'),
          _header('Подпись')
        ]),
        TableRow(children: [
          _cell('1'),
          _cell(log.medExamEmployeeName ?? '—'),
          _cell(log.medExamPosition ?? '—'),
          _cell(log.medExamDate != null
              ? _dateFmt.format(log.medExamDate!)
              : '—'),
          _cell(log.medExamConclusion ?? '—'),
          _cell(log.medExamEmployerDecision ?? '—'),
          _cell(creator != null
              ? '${creator!.fullName}${creator!.surname != null ? ' ${creator!.surname}' : ''}'
              : '—'),
        ]),
      ],
    );
  }

  Widget _buildDisinfectantAccountingTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.6),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(0.5),
        3: FlexColumnWidth(0.6),
        4: FlexColumnWidth(0.8)
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(children: [
          _header('Дата'),
          _header('Объект/Дезсредство'),
          _header('Кол-во'),
          _header('Поступление'),
          _header('Ответственный')
        ]),
        TableRow(children: [
          _cell(_dateFmt.format(log.createdAt)),
          _cell(log.disinfObjectName ?? log.disinfAgentName ?? '—'),
          _cell(log.disinfObjectCount != null
              ? log.disinfObjectCount.toString()
              : (log.disinfQuantity != null
                  ? log.disinfQuantity.toString()
                  : '—')),
          _cell(log.disinfReceiptDate != null
              ? _dateFmt.format(log.disinfReceiptDate!)
              : '—'),
          _cell(log.disinfResponsibleName ?? creator?.fullName ?? '—'),
        ]),
      ],
    );
  }

  Widget _buildEquipmentWashingTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.6),
        1: FlexColumnWidth(0.4),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.8),
        5: FlexColumnWidth(0.7)
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(children: [
          _header('Дата'),
          _header('Время'),
          _header('Оборудование'),
          _header('Моющее'),
          _header('Дез. раствор'),
          _header('Контролёр')
        ]),
        TableRow(children: [
          _cell(_dateFmt.format(log.createdAt)),
          _cell(log.washTime ?? '—'),
          _cell(log.washEquipmentName ?? '—'),
          _cell(log.washSolutionName ?? '—'),
          _cell(log.washDisinfectantName ?? '—'),
          _cell(log.washControllerSignature ?? creator?.fullName ?? '—'),
        ]),
      ],
    );
  }

  Widget _buildGeneralCleaningTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.3),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(0.6),
        3: FlexColumnWidth(0.8)
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(children: [
          _header('№'),
          _header('Помещение'),
          _header('Дата'),
          _header('Ответственный')
        ]),
        TableRow(children: [
          _cell('1'),
          _cell(log.genCleanPremises ?? '—'),
          _cell(log.genCleanDate != null
              ? _dateFmt.format(log.genCleanDate!)
              : '—'),
          _cell(log.genCleanResponsible ?? creator?.fullName ?? '—'),
        ]),
      ],
    );
  }

  Widget _buildSieveFilterMagnetTable(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(0.6),
        3: FlexColumnWidth(0.6),
        4: FlexColumnWidth(0.7),
        5: FlexColumnWidth(0.6)
      },
      border: TableBorder.all(color: Colors.grey),
      children: [
        TableRow(children: [
          _header('№ сита/магнита'),
          _header('Наименование'),
          _header('Состояние'),
          _header('Дата очистки'),
          _header('ФИО'),
          _header('Комментарии')
        ]),
        TableRow(children: [
          _cell(log.sieveNo ?? '—'),
          _cell(log.sieveNameLocation ?? '—'),
          _cell(log.sieveCondition ?? '—'),
          _cell(log.sieveCleaningDate != null
              ? _dateFmt.format(log.sieveCleaningDate!)
              : '—'),
          _cell(log.sieveSignature ?? creator?.fullName ?? '—'),
          _cell(log.sieveComments ?? '—'),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final establishmentName =
        context.watch<AccountManagerSupabase>().establishment?.name ?? '—';

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(
            '${loc.t('haccp_entry_view') ?? 'Запись'} — ${(loc.t(log.logType.displayNameKey) ?? log.logType.displayNameRu)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            loc.t('haccp_recommended_sample') ?? 'Рекомендуемый образец',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
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
                Icon(Icons.lock_outline,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.t('haccp_entry_immutable_hint') ??
                        'Только просмотр. Редактирование записей журнала недоступно.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
