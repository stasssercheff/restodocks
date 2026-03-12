/// Feature flags.
/// Enable via --dart-define=ENABLE_TTK_IMPORT=true at build time.
class FeatureFlags {
  FeatureFlags._();

  /// ТТК import from Excel/PDF. По умолчанию выключен, включается в Beta через ENABLE_TTK_IMPORT=true.
  static bool get ttkImportEnabled =>
      const String.fromEnvironment('ENABLE_TTK_IMPORT', defaultValue: 'false') == 'true';
}
