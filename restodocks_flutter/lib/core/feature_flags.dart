/// Feature flags.
/// Enable via --dart-define=ENABLE_XXX=true at build time.
class FeatureFlags {
  FeatureFlags._();

  /// TТК import from Excel/PDF. Включён.
  static bool get ttkImportEnabled => true;
}
