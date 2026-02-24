-- Настройка подтверждения email и webhook для приветственных писем

-- 1. Включить подтверждение email в Authentication > Providers > Email
--    В Supabase Dashboard: Authentication -> Providers -> Email -> Enable "Confirm Email"

-- 2. Настроить SMTP провайдер (например, Resend, SendGrid)
--    В Supabase Dashboard: Authentication -> SMTP Settings

-- 3. Создать webhook для отслеживания подтверждения email
--    Этот webhook срабатывает при обновлении auth.users

INSERT INTO supabase_functions.http_request_queue (
  method,
  url,
  headers,
  body,
  timeout_ms
) VALUES (
  'POST',
  CONCAT(current_setting('app.supabase_url'), '/functions/v1/send-welcome-email'),
  jsonb_build_object(
    'Authorization', CONCAT('Bearer ', current_setting('app.service_role_key')),
    'Content-Type', 'application/json'
  ),
  NULL,
  5000
);

-- Создаем webhook через pg_net для отправки POST запроса к Edge Function
-- при подтверждении email пользователя

CREATE OR REPLACE FUNCTION handle_email_confirmation()
RETURNS TRIGGER AS $$
BEGIN
  -- Отправляем запрос к Edge Function только если email был подтвержден
  IF NEW.email_confirmed_at IS NOT NULL AND OLD.email_confirmed_at IS NULL THEN
    PERFORM
      net.http_post(
        url := CONCAT(current_setting('app.supabase_url'), '/functions/v1/send-welcome-email'),
        headers := jsonb_build_object(
          'Authorization', CONCAT('Bearer ', current_setting('app.service_role_key')),
          'Content-Type', 'application/json'
        ),
        body := jsonb_build_object(
          'type', TG_OP,
          'table', TG_TABLE_NAME,
          'record', row_to_json(NEW),
          'schema', TG_TABLE_SCHEMA,
          'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
        )
      );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Создаем триггер на таблице auth.users
-- (если он не существует)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'on_email_confirmation'
    AND tgrelid = 'auth.users'::regclass
  ) THEN
    CREATE TRIGGER on_email_confirmation
      AFTER UPDATE ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION handle_email_confirmation();
  END IF;
END $$;

-- Инструкции по настройке:
-- 1. В Supabase Dashboard перейдите в Authentication -> Providers -> Email
-- 2. Включите "Confirm Email"
-- 3. Настройте SMTP в Authentication -> SMTP Settings
-- 4. Добавьте переменные окружения:
--    - RESEND_API_KEY (для отправки email через Resend)
-- 5. Разверните Edge Functions:
--    supabase functions deploy send-email
--    supabase functions deploy send-welcome-email