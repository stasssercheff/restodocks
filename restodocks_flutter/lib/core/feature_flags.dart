/// Feature flags.
/// Prod (IS_BETA=false): кнопка импорта ТТК всегда. Beta: по --dart-define=ENABLE_TTK_IMPORT=true.
class FeatureFlags {
  FeatureFlags._();

  /// ТТК import from Excel/PDF. В проде всегда включено (IS_BETA=false), в Beta — по ENABLE_TTK_IMPORT.
  static bool get ttkImportEnabled {
    const isBeta = bool.fromEnvironment('IS_BETA', defaultValue: true);
    if (!isBeta) return true; // прод — кнопка всегда
    return const String.fromEnvironment('ENABLE_TTK_IMPORT', defaultValue: 'false') == 'true';
  }
}
