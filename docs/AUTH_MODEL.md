# Модель авторизации Restodocks

## Единый источник правды

**auth.uid()** = ID пользователя в Supabase Auth (`auth.users.id`).  
Это идентификатор вошедшего пользователя. Все RLS-политики должны опираться на него.

## Связь Auth ↔ Employee

| auth.users        | employees                         |
|-------------------|-----------------------------------|
| id (auth.uid())   | auth_user_id — ссылка на auth     |
| email, password   | full_name, department, roles...   |

- **employees.id** — внутренний PK сотрудника (UUID), используется в FK (created_by_employee_id и т.п.).
- **employees.auth_user_id** — привязка к Supabase Auth. Для входа по email/паролю: `auth_user_id = auth.uid()`.

## Правило для RLS

**Всегда** использовать:

```sql
auth_user_id = auth.uid()
-- или
establishment_id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
```

**Никогда** не использовать:

```sql
employees.id = auth.uid()  -- неверно: id ≠ auth user id
```

## Текущие политики

- **anon** — для неавторизованных (часть таблиц)
- **authenticated** — для авторизованных (auth_order_documents_*, auth_inventory_documents_*, auth_schedule_*, auth_order_list_* и т.д.)

Политики, опирающиеся на `employees.id = auth.uid()`, считаются ошибочными и удаляются миграцией `20260225170000_unify_rls_auth_user_id.sql`.
