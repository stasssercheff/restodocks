import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Feature flags.
/// Prod (IS_BETA=false): кнопка импорта ТТК всегда. Beta: по --dart-define=ENABLE_TTK_IMPORT=true.
class FeatureFlags {
  FeatureFlags._();

  /// Маркер беты. По умолчанию считаем, что это **prod**, если флаг не задан явно.
  static bool get isBeta => const bool.fromEnvironment('IS_BETA', defaultValue: false);

  /// Основной прод-домен (не Preview на Pages). На нём POS выключен даже если в сборке ошибочно передан IS_BETA=true.
  static bool get _isProdMarketingHost {
    if (!kIsWeb) return false;
    final h = Uri.base.host.toLowerCase();
    return h == 'restodocks.com' || h == 'www.restodocks.com';
  }

  /// Опасные/временные инструменты для тестов (например, удаление всех ТТК).
  /// Включать только в Beta: `--dart-define=IS_BETA=true --dart-define=ENABLE_BETA_TOOLS=true`
  static bool get betaToolsEnabled =>
      isBeta && (const String.fromEnvironment('ENABLE_BETA_TOOLS', defaultValue: 'false') == 'true');

  /// ТТК import from Excel/PDF. В проде всегда включено (IS_BETA=false), в Beta — по ENABLE_TTK_IMPORT.
  /// Не путать с POS: импорт ТТК на restodocks.com должен оставаться доступен при IS_BETA=false.
  static bool get ttkImportEnabled {
    if (!isBeta) return true; // прод — кнопка всегда
    return const String.fromEnvironment('ENABLE_TTK_IMPORT', defaultValue: 'false') == 'true';
  }

  /// POS / склад POS / закупка POS / зал (столы, касса, заказы подразделений, KDS), а также плитка «Склад» → `/inventory`.
  /// Включается только в Beta (`IS_BETA=true`) и не на основном домене **restodocks.com**.
  static bool get posModuleEnabled => isBeta && !_isProdMarketingHost;

  /// Экран «Журнал ошибок»: только в beta, не на основном прод-домене **restodocks.com**
  /// (даже если в сборке ошибочно передан `IS_BETA=true`), и не в нативном iOS (IPA).
  /// В веб-бете (например Pages) остаётся для отладки.
  static bool get showSystemErrorsJournal =>
      isBeta &&
      !_isProdMarketingHost &&
      (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);
}
