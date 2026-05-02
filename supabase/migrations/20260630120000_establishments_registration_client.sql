-- Откуда прошла регистрация заведения: нативное приложение / веб с телефона / веб с ПК.
-- Значения задаёт клиент (Flutter) при вызове register-metadata.
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS registration_client TEXT;

COMMENT ON COLUMN public.establishments.registration_client IS
  'Клиент при регистрации: ios_app | android_app | web_mobile | web_desktop | native_other (заполняет Edge register-metadata)';
