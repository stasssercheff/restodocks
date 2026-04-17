import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../haccp/haccp_country_profile.dart';
import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../models/tech_card.dart';
import '../services/services.dart';
import '../utils/haccp_stored_field_localizer.dart';
import '../utils/employee_display_utils.dart';
import '../utils/translit_utils.dart';
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
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
    final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
    String empName;
    if (subjectNameSnapshot != null && subjectNameSnapshot!.trim().isNotEmpty) {
      empName = translit
          ? cyrillicToLatin(subjectNameSnapshot!.trim())
          : subjectNameSnapshot!.trim();
    } else if (parsed.employeeNameSnapshot != null &&
        parsed.employeeNameSnapshot!.trim().isNotEmpty) {
      final s = parsed.employeeNameSnapshot!.trim();
      empName = translit ? cyrillicToLatin(s) : s;
    } else if (employee != null) {
      empName = employeeDisplayName(employee!, translit: translit);
    } else {
      empName = '—';
    }
    final position = (subjectPositionSnapshot != null &&
            subjectPositionSnapshot!.trim().isNotEmpty)
        ? loc.formatStoredHealthPosition(subjectPositionSnapshot)
        : loc.healthHygienePositionLabel(
            storedPosition: parsed.positionOverride,
            employee: employee,
          );
    final creatorName = creator != null
        ? employeeDisplayName(creator!, translit: translit)
        : '—';
    final y = loc.t('haccp_bool_yes');
    final n = loc.t('haccp_bool_no');
    final sign1 =
        log.status2Ok == true ? y : (log.status2Ok == false ? n : '—');
    final sign2 = log.statusOk == true ? y : (log.statusOk == false ? n : '—');
    final result = log.statusOk == true
        ? loc.t('haccp_status_admitted')
        : (log.statusOk == false ? loc.t('haccp_status_suspended') : '—');
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
            _header(loc.t('haccp_tbl_pp_no')),
            _header(loc.t('haccp_tbl_date')),
            _header(loc.t('haccp_tbl_employee_fio_long')),
            _header(loc.t('haccp_tbl_position')),
            _header(loc.t('haccp_tbl_sign_family_infect')),
            _header(loc.t('haccp_tbl_sign_skin_resp')),
            _header(loc.t('haccp_tbl_exam_outcome')),
            _header(loc.t('haccp_tbl_med_worker_sign')),
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
    final loc = context.watch<LocalizationService>();
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
            _header(loc.t('haccp_tbl_room_name_prod')),
            _header(loc.t('haccp_tbl_fridge_equipment_name')),
            _header(loc.t('haccp_tbl_temp_celsius')),
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
    final loc = context.watch<LocalizationService>();
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
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
              '${loc.t('haccp_tbl_warehouse_room_prefix')} ${log.equipment}',
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
                _header(loc.t('haccp_tbl_serial_short')),
                _header(loc.t('haccp_tbl_date')),
                _header(loc.t('haccp_tbl_temp_c_label')),
                _header(loc.t('haccp_tbl_rel_humidity_pct')),
                _header(loc.t('haccp_tbl_responsible_sign')),
              ],
            ),
            TableRow(
              children: [
                _cell('1'),
                _cell(DateFormat('dd.MM.yyyy').format(log.createdAt)),
                _cell(temp, color: tempAlert ? Colors.red : null),
                _cell(hum, color: humAlert ? Colors.red : null),
                _cell(employee != null
                    ? employeeDisplayName(employee!, translit: translit)
                    : '—'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Приложение 4: Журнал бракеража готовой пищевой продукции.
  Widget _buildFinishedProductBrakerageTable(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final products = context.read<ProductStoreSupabase>();
    final techSvc = context.read<TechCardServiceSupabase>();
    final lang = loc.currentLanguageCode;
    final matched = HaccpStoredFieldLocalizer.matchProduct(
        products.allProducts, log.productName);
    return FutureBuilder<TechCard?>(
      future: log.techCardId != null
          ? techSvc.getTechCardById(log.techCardId!)
          : Future<TechCard?>.value(null),
      builder: (context, snap) {
        final dish = HaccpStoredFieldLocalizer.displayBrakerageDishName(
          productName: log.productName,
          techCard: snap.data,
          matchedProduct: matched,
          languageCode: lang,
          loc: loc,
        );
        final result =
            HaccpStoredFieldLocalizer.localizeFreeText(log.result, loc);
        final approval = HaccpStoredFieldLocalizer.localizeApprovalSnapshot(
            log.approvalToSell, loc);
        final weighing =
            HaccpStoredFieldLocalizer.localizeFreeText(log.weighingResult, loc);
        final note = HaccpStoredFieldLocalizer.localizeFreeText(log.note, loc);
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
                _header(loc.t('haccp_tbl_dish_made_at')),
                _header(loc.t('haccp_tbl_brakerage_removed_at')),
                _header(loc.t('haccp_tbl_dish_name_ready')),
                _header(loc.t('haccp_tbl_organo_result')),
                _header(loc.t('haccp_tbl_sale_allowed')),
                _header(loc.t('haccp_tbl_brakerage_commission_sigs')),
                _header(loc.t('haccp_tbl_portion_weighing')),
                _header(loc.t('haccp_tbl_note')),
              ],
            ),
            TableRow(
              children: [
                _cell(_dateTimeFmt.format(log.createdAt)),
                _cell(log.timeBrakerage ?? '—'),
                _cell(dish),
                _cell(result),
                _cell(approval),
                _cell(log.commissionSignatures ?? '—'),
                _cell(weighing),
                _cell(note),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Приложение 5: Журнал бракеража скоропортящейся пищевой продукции.
  Widget _buildIncomingRawBrakerageTable(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final products = context.read<ProductStoreSupabase>();
    final lang = loc.currentLanguageCode;
    final matched = HaccpStoredFieldLocalizer.matchProduct(
        products.allProducts, log.productName);
    final productLabel = HaccpStoredFieldLocalizer.displayIncomingProductName(
      productName: log.productName,
      matchedProduct: matched,
      languageCode: lang,
      loc: loc,
    );
    final result = HaccpStoredFieldLocalizer.localizeFreeText(log.result, loc);
    final note = HaccpStoredFieldLocalizer.localizeFreeText(log.note, loc);
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
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
            _header(loc.t('haccp_tbl_received_at')),
            _header(loc.t('haccp_tbl_name')),
            _header(loc.t('haccp_tbl_packaging')),
            _header(loc.t('haccp_tbl_manufacturer')),
            _header(loc.t('haccp_tbl_qty_short')),
            _header(loc.t('haccp_tbl_doc_no')),
            _header(loc.t('haccp_tbl_organo_short')),
            _header(loc.t('haccp_tbl_storage_shelf')),
            _header(loc.t('haccp_tbl_sale_date')),
            _header(loc.t('haccp_tbl_signature')),
            _header(loc.t('haccp_tbl_note_short')),
          ],
        ),
        TableRow(
          children: [
            _cell(_dateTimeFmt.format(log.createdAt)),
            _cell(productLabel),
            _cell(log.packaging ?? '—'),
            _cell(log.manufacturerSupplier ?? '—'),
            _cell(log.quantityKg != null
                ? log.quantityKg!.toStringAsFixed(2)
                : '—'),
            _cell(log.documentNumber ?? '—'),
            _cell(result),
            _cell(log.storageConditions ?? '—'),
            _cell(dateSoldStr),
            _cell(employee != null
                ? employeeDisplayName(employee!, translit: translit)
                : '—'),
            _cell(note),
          ],
        ),
      ],
    );
  }

  Widget _buildFryingOilTable(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
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
            _header(loc.t('haccp_tbl_date')),
            _header(loc.t('haccp_tbl_time_start')),
            _header(loc.t('haccp_tbl_fat_type')),
            _header(loc.t('haccp_tbl_score_start')),
            _header(loc.t('haccp_tbl_equipment')),
            _header(loc.t('haccp_tbl_product_type')),
            _header(loc.t('haccp_tbl_time_end')),
            _header(loc.t('haccp_tbl_score_end')),
            _header(loc.t('haccp_tbl_carry_kg')),
            _header(loc.t('haccp_tbl_utilized_kg')),
            _header(loc.t('haccp_tbl_controller')),
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
            _cell(log.commissionSignatures ??
                (employee != null
                    ? employeeDisplayName(employee!, translit: translit)
                    : '—')),
          ],
        ),
      ],
    );
  }

  Widget _buildMedBookTable(BuildContext context) {
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
    final loc = context.watch<LocalizationService>();
    final sign = creator != null
        ? employeeDisplayName(creator!, translit: translit)
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
            _header(loc.t('haccp_tbl_serial_short')),
            _header(loc.t('haccp_tbl_fio_full')),
            _header(loc.t('haccp_tbl_position')),
            _header(loc.t('haccp_tbl_med_book_no')),
            _header(loc.t('haccp_tbl_med_book_valid')),
            _header(loc.t('haccp_tbl_med_book_receipt')),
            _header(loc.t('haccp_tbl_med_book_return')),
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
    final loc = context.watch<LocalizationService>();
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
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
          _header(loc.t('haccp_tbl_serial_short')),
          _header(loc.t('haccp_tbl_med_exam_fio')),
          _header(loc.t('haccp_tbl_position')),
          _header(loc.t('haccp_tbl_exam_date')),
          _header(loc.t('haccp_tbl_conclusion')),
          _header(loc.t('haccp_tbl_decision')),
          _header(loc.t('haccp_tbl_signature'))
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
              ? employeeDisplayName(creator!, translit: translit)
              : '—'),
        ]),
      ],
    );
  }

  Widget _buildDisinfectantAccountingTable(BuildContext context) {
    final loc = context.watch<LocalizationService>();
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
          _header(loc.t('haccp_tbl_date')),
          _header(loc.t('haccp_tbl_object_agent')),
          _header(loc.t('haccp_tbl_qty_short')),
          _header(loc.t('haccp_tbl_receipt')),
          _header(loc.t('haccp_tbl_responsible'))
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
    final loc = context.watch<LocalizationService>();
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
          _header(loc.t('haccp_tbl_date')),
          _header(loc.t('haccp_tbl_time')),
          _header(loc.t('haccp_tbl_equipment')),
          _header(loc.t('haccp_tbl_wash_solution')),
          _header(loc.t('haccp_tbl_disinfect_solution')),
          _header(loc.t('haccp_tbl_controller'))
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
    final loc = context.watch<LocalizationService>();
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
          _header(loc.t('haccp_tbl_serial_short')),
          _header(loc.t('haccp_tbl_room')),
          _header(loc.t('haccp_tbl_date')),
          _header(loc.t('haccp_tbl_responsible'))
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
    final loc = context.watch<LocalizationService>();
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
          _header(loc.t('haccp_tbl_sieve_magnet_no')),
          _header(loc.t('haccp_tbl_name')),
          _header(loc.t('haccp_tbl_condition')),
          _header(loc.t('haccp_tbl_cleaning_date')),
          _header(loc.t('haccp_tbl_med_exam_fio')),
          _header(loc.t('haccp_tbl_comments'))
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
    final acc = context.watch<AccountManagerSupabase>();
    final config = context.watch<HaccpConfigService>();
    final est = acc.establishment;
    final establishmentName = est?.name ?? '—';
    final countryCode =
        est != null ? config.resolveCountryCodeForEstablishment(est) : 'RU';

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
            HaccpCountryProfiles.recommendedSampleLabel(countryCode),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            HaccpCountryProfiles.journalLegalLine(countryCode, log.logType),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 2),
          Text(
            HaccpCountryProfiles.legalFrameworkLabel(
              countryCode,
              loc.currentLanguageCode,
            ),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
