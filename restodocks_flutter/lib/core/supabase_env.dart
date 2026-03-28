/// Общие `dart-define` для клиента Supabase и прямых HTTP-вызовов Edge Functions.
/// Один источник — чтобы iOS/Web не расходились с прод-сайтом при кастомном `SUPABASE_URL`.
const String kSupabaseUrlFromEnvironment = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://osglfptwbuqqmqunttha.supabase.co',
);
const String kSupabaseAnonKeyFromEnvironment = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE',
);
