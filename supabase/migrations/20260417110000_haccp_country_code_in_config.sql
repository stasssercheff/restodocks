ALTER TABLE public.establishment_haccp_config
ADD COLUMN IF NOT EXISTS haccp_country_code text;

UPDATE public.establishment_haccp_config
SET haccp_country_code = upper(trim(haccp_country_code))
WHERE haccp_country_code IS NOT NULL;

ALTER TABLE public.establishment_haccp_config
DROP CONSTRAINT IF EXISTS establishment_haccp_config_haccp_country_code_check;

ALTER TABLE public.establishment_haccp_config
ADD CONSTRAINT establishment_haccp_config_haccp_country_code_check
CHECK (
  haccp_country_code IS NULL
  OR haccp_country_code IN ('RU', 'US', 'ES', 'FR', 'GB', 'TR', 'IT', 'DE')
);

COMMENT ON COLUMN public.establishment_haccp_config.haccp_country_code
IS 'Нормативный профиль HACCP по стране (RU, US, ES, FR, GB, TR, IT, DE)';
