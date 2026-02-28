-- Исправление: в живой БД колонка filled_by_employee_id имеет NOT NULL,
-- но приложение пишет submitted_by_employee_id.
-- Решение: копируем значение submitted_by_employee_id в filled_by_employee_id
-- и снимаем NOT NULL с filled_by_employee_id.

-- 1. Снимаем NOT NULL с filled_by_employee_id (если колонка существует)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'checklist_submissions'
      AND column_name = 'filled_by_employee_id'
  ) THEN
    ALTER TABLE checklist_submissions
      ALTER COLUMN filled_by_employee_id DROP NOT NULL;

    -- 2. Синхронизируем: заполняем filled_by_employee_id из submitted_by_employee_id
    --    для строк, где filled_by_employee_id ещё null
    UPDATE checklist_submissions
    SET filled_by_employee_id = submitted_by_employee_id
    WHERE filled_by_employee_id IS NULL
      AND submitted_by_employee_id IS NOT NULL;
  END IF;
END$$;
