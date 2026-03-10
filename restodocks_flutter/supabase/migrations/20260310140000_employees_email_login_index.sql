-- Индекс для authenticate-employee: быстрый поиск по email при is_active=true
CREATE INDEX IF NOT EXISTS idx_employees_email_active
  ON employees (email)
  WHERE is_active = true;
