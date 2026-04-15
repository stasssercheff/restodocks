/// Общие `dart-define` для клиента Supabase и прямых HTTP-вызовов Edge Functions.
/// Один источник — чтобы iOS/Web не расходились с прод-сайтом при кастомном `SUPABASE_URL`.
const String kSupabaseUrlFromEnvironment = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://osglfptwbuqqmqunttha.supabase.co',
);
const String kSupabaseAnonKeyFromEnvironment = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'sb_publishable_VLi05Njkuzk_SBkLB_8j0A_00jr73Im',
);

/// Базовый URL веб-приложения для ссылок из писем (подтверждение копирования заведения и т.д.).
const String kPublicAppOriginFromEnvironment = String.fromEnvironment(
  'PUBLIC_APP_ORIGIN',
  defaultValue: 'https://restodocks.com',
);
