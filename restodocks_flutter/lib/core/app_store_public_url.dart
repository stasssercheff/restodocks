/// Публичная страница приложения в App Store (кнопка на веб-логине).
/// В Cloudflare Variables / локально: `--dart-define=APP_STORE_PUBLIC_URL=https://apps.apple.com/app/...`
/// Если не задано — открывается поиск по названию (работает без числового id).
const String _kAppStoreUrlFromEnv = String.fromEnvironment(
  'APP_STORE_PUBLIC_URL',
  defaultValue: '',
);

String get appStoreListingUriString {
  final t = _kAppStoreUrlFromEnv.trim();
  if (t.isNotEmpty) return t;
  return 'https://apps.apple.com/search?term=Restodocks';
}
