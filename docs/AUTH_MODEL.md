# Модель авторизации Restodocks

## Единый источник правды

**auth.uid()** = ID пользователя в Supabase Auth (`auth.users.id`).  
Все входят только по учётной записи (email/пароль).

## employees.id = auth.users.id

- **employees.id** = `auth.users.id` — единый идентификатор. При создании сотрудника передаём `id = auth.uid()`.
- Колонка `auth_user_id` удалена.
- FK `employees.id REFERENCES auth.users(id)` — при удалении пользователя в Auth удаляется запись сотрудника.

## Правило для RLS

**Всегда** использовать:

```sql
id = auth.uid()
-- или
establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
```

## Текущие политики

- **anon** — для регистрации (establishments, employees)
- **authenticated** — для авторизованных (auth_select_employees с `id = auth.uid()`, auth_order_documents_*, и т.д.)
