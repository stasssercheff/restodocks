/// Feature flags. Default: false (safe for prod).
/// Enable via --dart-define=ENABLE_XXX=true at build time.
class FeatureFlags {
  FeatureFlags._();

  /// TТК import from Excel/PDF. Off by default.
  static const bool ttkImportEnabled = bool.fromEnvironment(
    'ENABLE_TTK_IMPORT',
    defaultValue: false,
  );
}
