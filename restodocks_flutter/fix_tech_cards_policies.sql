-- Исправление политик для tech_cards
-- Проблема: политики используют auth.uid(), но приложение работает через employee-based аутентификацию

-- Удаляем старые политики
DROP POLICY IF EXISTS "Users can view tech cards from their establishment" ON tech_cards;
DROP POLICY IF EXISTS "Users can manage tech cards from their establishment" ON tech_cards;

-- Создаем новые политики, которые работают с текущей архитектурой
-- Проверяем доступ через таблицу employees (текущий пользователь = employee в системе)

CREATE POLICY "Employees can view tech cards from their establishment" ON tech_cards
  FOR SELECT USING (
    establishment_id IN (
      SELECT establishment_id FROM employees 
      WHERE id::text = current_setting('app.current_employee_id', true)
      AND is_active = true
    )
  );

CREATE POLICY "Employees can manage tech cards from their establishment" ON tech_cards
  FOR ALL USING (
    establishment_id IN (
      SELECT establishment_id FROM employees 
      WHERE id::text = current_setting('app.current_employee_id', true)
      AND is_active = true
    )
  );

-- Аналогично исправляем политики для tt_ingredients
DROP POLICY IF EXISTS "Users can view ingredients from their establishment" ON tt_ingredients;
DROP POLICY IF EXISTS "Users can manage ingredients from their establishment" ON tt_ingredients;

CREATE POLICY "Employees can view ingredients from their establishment" ON tt_ingredients
  FOR SELECT USING (
    tech_card_id IN (
      SELECT id FROM tech_cards WHERE establishment_id IN (
        SELECT establishment_id FROM employees 
        WHERE id::text = current_setting('app.current_employee_id', true)
        AND is_active = true
      )
    )
  );

CREATE POLICY "Employees can manage ingredients from their establishment" ON tt_ingredients
  FOR ALL USING (
    tech_card_id IN (
      SELECT id FROM tech_cards WHERE establishment_id IN (
        SELECT establishment_id FROM employees 
        WHERE id::text = current_setting('app.current_employee_id', true)
        AND is_active = true
      )
    )
  );
