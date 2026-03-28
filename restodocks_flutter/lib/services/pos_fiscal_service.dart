import '../utils/dev_log.dart';
import 'establishment_fiscal_settings_service.dart';
import 'fiscal_outbox_service.dart';
import 'fiscal_tax_presets_service.dart';

/// Фискализация и связь с ККТ: очередь исходящих операций + пресеты налогов.
/// Подключение реального драйвера ККТ — отдельный этап.
class PosFiscalService {
  PosFiscalService._();
  static final PosFiscalService instance = PosFiscalService._();

  /// Подключена ли облачная/локальная ККТ (драйвер). Пока всегда false.
  bool get isKktDriverConfigured => false;

  Future<int> pendingOutboxCount(String establishmentId) =>
      FiscalOutboxService.instance.countPending(establishmentId);

  /// После закрытия счёта — поставить операцию в очередь до обмена с ККТ.
  Future<void> queueSaleAfterOrderClose({
    required String establishmentId,
    required String orderId,
    required double grandTotal,
    required String currencyCode,
  }) async {
    try {
      await FiscalOutboxService.instance.enqueueSale(
        establishmentId: establishmentId,
        posOrderId: orderId,
        payload: {
          'source': 'pos_hall',
          'grandTotal': grandTotal,
          'currency': currencyCode,
          'queuedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      devLog('PosFiscalService: queued sale outbox order=$orderId');
    } catch (e, st) {
      devLog('PosFiscalService: queueSaleAfterOrderClose $e $st');
    }
  }

  /// Старый вызов из UI — делегирует в очередь.
  Future<void> registerSalePlaceholder({
    required String orderId,
    required double amount,
    String? establishmentId,
    String currencyCode = 'RUB',
  }) async {
    final est = establishmentId;
    if (est == null) {
      devLog('PosFiscalService: registerSalePlaceholder skip (no establishmentId)');
      return;
    }
    await queueSaleAfterOrderClose(
      establishmentId: est,
      orderId: orderId,
      grandTotal: amount,
      currencyCode: currencyCode,
    );
  }

  /// Эффективная ставка НДС/налога для UI (пресет региона ± переопределение заведения).
  Future<double?> effectiveVatPercent(String establishmentId) async {
    await FiscalTaxPresetsService.instance.ensureLoaded();
    final row =
        await EstablishmentFiscalSettingsService.instance.fetch(establishmentId);
    final regionCode = row?.taxRegion ?? 'RU';
    final preset = await FiscalTaxPresetsService.instance.region(regionCode);
    if (row?.vatOverridePercent != null) return row!.vatOverridePercent;
    return preset?.defaultVatPercent;
  }
}
