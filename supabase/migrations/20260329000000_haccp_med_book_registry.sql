-- Журнал учёта личных медицинских книжек: новый тип + колонки в haccp_quality_logs

DO $$ BEGIN
  ALTER TYPE haccp_log_type ADD VALUE 'med_book_registry';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS med_book_employee_name TEXT,
  ADD COLUMN IF NOT EXISTS med_book_position TEXT,
  ADD COLUMN IF NOT EXISTS med_book_number TEXT,
  ADD COLUMN IF NOT EXISTS med_book_valid_until DATE,
  ADD COLUMN IF NOT EXISTS med_book_issued_at DATE,
  ADD COLUMN IF NOT EXISTS med_book_returned_at DATE;

COMMENT ON COLUMN haccp_quality_logs.med_book_employee_name IS 'ФИО работника (журнал учёта медкнижек)';
COMMENT ON COLUMN haccp_quality_logs.med_book_position IS 'Должность';
COMMENT ON COLUMN haccp_quality_logs.med_book_number IS 'Номер медицинской книжки';
COMMENT ON COLUMN haccp_quality_logs.med_book_valid_until IS 'Срок действия медкнижки';
COMMENT ON COLUMN haccp_quality_logs.med_book_issued_at IS 'Дата получения медкнижки (расписка)';
COMMENT ON COLUMN haccp_quality_logs.med_book_returned_at IS 'Дата возврата медкнижки (расписка)';
