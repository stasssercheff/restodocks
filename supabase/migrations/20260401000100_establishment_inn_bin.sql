-- Реквизиты заведения для бланка соглашения с сотрудником
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS inn_bin TEXT;
COMMENT ON COLUMN establishments.inn_bin IS 'ИНН или БИН для реквизитов (РФ/СНГ)';
