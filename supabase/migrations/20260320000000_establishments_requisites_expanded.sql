-- Расширенные реквизиты заведения для приказов/документов
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS legal_name TEXT;
COMMENT ON COLUMN establishments.legal_name IS 'Полное юридическое наименование (для приказов/документов)';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS ogrn_ogrnip TEXT;
COMMENT ON COLUMN establishments.ogrn_ogrnip IS 'ОГРН / ОГРНИП';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS kpp TEXT;
COMMENT ON COLUMN establishments.kpp IS 'КПП (только для ООО)';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS bank_rs TEXT;
COMMENT ON COLUMN establishments.bank_rs IS 'Банковские реквизиты: Р/С';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS bank_bik TEXT;
COMMENT ON COLUMN establishments.bank_bik IS 'Банковские реквизиты: БИК';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS bank_name TEXT;
COMMENT ON COLUMN establishments.bank_name IS 'Банковские реквизиты: Банк';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS director_fio TEXT;
COMMENT ON COLUMN establishments.director_fio IS 'ФИО руководителя (для подписей)';

ALTER TABLE establishments ADD COLUMN IF NOT EXISTS director_position TEXT;
COMMENT ON COLUMN establishments.director_position IS 'Должность руководителя (для документов/подстановок)';

