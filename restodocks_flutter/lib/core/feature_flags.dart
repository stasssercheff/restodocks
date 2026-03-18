/// Feature flags.
/// Prod (IS_BETA=false): кнопка импорта ТТК всегда. Beta: по --dart-define=ENABLE_TTK_IMPORT=true.
class FeatureFlags {
  FeatureFlags._();

  /// Маркер беты. По умолчанию считаем, что это **prod**, если флаг не задан явно.
  static bool get isBeta => const bool.fromEnvironment('IS_BETA', defaultValue: false);

  /// Опасные/временные инструменты для тестов (например, удаление всех ТТК).
  /// Включать только в Beta: `--dart-define=IS_BETA=true --dart-define=ENABLE_BETA_TOOLS=true`
  static bool get betaToolsEnabled =>
      isBeta && (const String.fromEnvironment('ENABLE_BETA_TOOLS', defaultValue: 'false') == 'true');

  /// ТТК import from Excel/PDF. В проде всегда включено (IS_BETA=false), в Beta — по ENABLE_TTK_IMPORT.
  static bool get ttkImportEnabled {
    if (!isBeta) return true; // прод — кнопка всегда
    return const String.fromEnvironment('ENABLE_TTK_IMPORT', defaultValue: 'false') == 'true';
  }
}
