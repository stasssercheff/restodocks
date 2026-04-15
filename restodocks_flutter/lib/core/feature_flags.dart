import 'package:flutter/foundation.dart' show kIsWeb;
import 'subscription_entitlements.dart';

/// Feature flags.
/// Prod (IS_BETA=false): кнопка импорта ТТК всегда. Beta: по --dart-define=ENABLE_TTK_IMPORT=true.
class FeatureFlags {
  FeatureFlags._();

  /// Маркер беты. По умолчанию считаем, что это **prod**, если флаг не задан явно.
  static bool get isBeta => const bool.fromEnvironment('IS_BETA', defaultValue: false);

  /// Основной прод-домен: скрываем POS на витрине (не смешивать с beta-хостами).
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

  /// Web: бета/превью без `--dart-define=IS_BETA=true` (часто Cloudflare Pages).
  /// Прод-витрина restodocks.com — POS не включаем по хосту (только через IS_BETA при необходимости).
  static bool get _posModuleEnabledWebNonProdHost {
    if (!kIsWeb) return false;
    try {
      final h = Uri.base.host.toLowerCase();
      if (h == 'localhost' || h == '127.0.0.1') return true;
      if (h == 'restodocks.pages.dev' || h == 'www.restodocks.pages.dev') {
        return true;
      }
      if (h.endsWith('.restodocks.pages.dev')) return true;
      if (h == 'restodocks.vercel.app') return true;
      if (h.contains('staging') && h.contains('restodocks')) return true;
    } catch (_) {}
    return false;
  }

  /// POS: зал (столы, касса), заказы подразделений, KDS, склад POS, закупка POS, сводный склад, «Продажи».
  /// Бланк инвентаризации (`/inventory`) — отдельно, доступен и в проде.
  ///
  /// Явно: `--dart-define=ENABLE_POS=true` (если бета на своём домене без шаблона ниже).
  static bool get _posModuleEnabledFromDefine =>
      const String.fromEnvironment('ENABLE_POS', defaultValue: 'false') == 'true';

  /// Временно выключить весь POS UI (зал, столы, касса, KDS, склад/закупка POS, заказы подразделений, продажи POS).
  /// Для бэты можно передать `--dart-define=HIDE_POS_MODULE=true` (см. `cloudflare-build.sh` / deploy-cloudflare-beta).
  /// Обычная инвентаризация `/inventory` не относится к POS и не скрывается.
  static bool get _hidePosModule =>
      const String.fromEnvironment('HIDE_POS_MODULE', defaultValue: 'false') == 'true';

  /// Включается если: `IS_BETA=true`, или `ENABLE_POS=true`, или открыт известный не-прод веб-хост (Cloudflare Pages и т.д.).
  ///
  /// На **restodocks.com** / **www.restodocks.com** пункты POS в меню **никогда** не показываем — даже если в сборке
  /// ошибочно переданы `IS_BETA` / `ENABLE_POS` (витрина и основной прод без POS в навигации).
  /// Beta / превью / localhost — по правилам ниже.
  static bool get posModuleEnabled {
    if (_hidePosModule) return false;
    if (_isProdMarketingHost) return false;
    return isBeta || _posModuleEnabledFromDefine || _posModuleEnabledWebNonProdHost;
  }

  /// POS в UI: только когда модуль включён для окружения и тарифный доступ Ultra-уровня
  /// (включая активный trial 72 часа).
  static bool posEnabledForSubscription(SubscriptionEntitlements entitlements) {
    return posModuleEnabled && entitlements.hasUltraLevelFeatures;
  }
}
