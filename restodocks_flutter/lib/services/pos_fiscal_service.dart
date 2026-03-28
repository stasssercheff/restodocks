import '../utils/dev_log.dart';

/// Интеграция с ККТ / ОФД — заглушка до подключения оборудования или облачного провайдера.
class PosFiscalService {
  PosFiscalService._();
  static final PosFiscalService instance = PosFiscalService._();

  bool get isConfigured => false;

  /// После успешной фискализации сюда передают данные чека; пока не вызывается.
  Future<void> registerSalePlaceholder({
    required String orderId,
    required double amount,
  }) async {
    devLog('PosFiscalService: registerSalePlaceholder (not configured) $orderId $amount');
  }
}
