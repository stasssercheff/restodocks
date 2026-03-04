# Настройка бета-деплоя (staging → Vercel)

## 1. Включить GitHub Actions

1. Откройте репозиторий: https://github.com/stasssercheff/restodocks
2. **Settings** → **Actions** → **General**
3. В блоке **Actions permissions** выберите **Allow all actions and reusable workflows**
4. Сохраните (**Save**)

## 2. Добавить Secrets

**Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Добавьте 3 секрета:

| Имя | Откуда взять |
|-----|--------------|
| `STAGING_SUPABASE_URL` | Supabase Dashboard → Project Settings → API → Project URL |
| `STAGING_SUPABASE_ANON_KEY` | Supabase Dashboard → Project Settings → API → anon public |
| `VERCEL_TOKEN` | Vercel → Account Settings → Tokens → Create Token (scope: Full Account). **Никогда не коммитить в код** — иначе Vercel автоматически отзовёт токен. |

## 3. Связать Vercel-проект (если нужно)

1. https://vercel.com/dashboard
2. Проект для беты (prj_rSIA3SgwSDWTL0pfYVJTCiGVFAke)
3. Settings → Git — можно оставить отключённым, т.к. деплой идёт через CLI

## 4. Проверка

1. **Actions** → вкладка **Actions**
2. После push в `staging` запускается **Build and Deploy to Vercel (Demo/Beta)**
3. Если падает — смотрите логи, на каком шаге ошибка

## Миграции Supabase (демо)

**Важно:** без миграций пункты чеклиста, дата/время и название могут не сохраняться.

Если чеклисты не сохраняются (0 пунктов, нет даты, пустое название) или ошибки вида `Could not find the 'X' column` — примените миграции к staging Supabase:

**Вариант 1.** Через CLI: `cd restodocks_flutter && supabase db push`

**Вариант 2.** Вручную: Supabase Dashboard → **SQL Editor** → выполните:

```sql
-- 1. assigned_department для фильтрации чеклистов
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';

-- 2. Колонки для deadline и scheduled_for
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;

-- 3. Колонки для пунктов чеклиста (ПФ с количеством)
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL;
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_quantity numeric(10, 3);
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_unit text;

-- 4. RPC для сохранения дат (обходит schema cache PostgREST)
CREATE OR REPLACE FUNCTION public.update_checklist_dates(
  p_checklist_id uuid,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE checklists
  SET updated_at = now(), deadline_at = p_deadline_at, scheduled_for_at = p_scheduled_for_at
  WHERE id = p_checklist_id;
$$;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO authenticated;

-- 5. Сообщения между сотрудниками
CREATE TABLE IF NOT EXISTS employee_direct_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CHECK (sender_employee_id != recipient_employee_id)
);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_sender ON employee_direct_messages(sender_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_recipient ON employee_direct_messages(recipient_employee_id);
ALTER TABLE employee_direct_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_employee_messages_select" ON employee_direct_messages FOR SELECT TO authenticated USING (sender_employee_id = auth.uid() OR recipient_employee_id = auth.uid());
CREATE POLICY "auth_employee_messages_insert" ON employee_direct_messages FOR INSERT TO authenticated WITH CHECK (sender_employee_id = auth.uid() AND recipient_employee_id != auth.uid() AND recipient_employee_id IN (SELECT id FROM employees e WHERE e.establishment_id = (SELECT establishment_id FROM employees WHERE id = auth.uid())));
```

**После миграций:** Supabase Dashboard → **Settings** → **General** → **Restart project** — обновит schema cache PostgREST (иначе возможны PGRST204 и пустые данные).

## Если Vercel отозвал токен

Vercel отзывает токены при обнаружении в публичном коде/логах. Создайте новый токен в Vercel → Account Settings → Tokens и обновите `VERCEL_TOKEN` в GitHub Secrets.

## Ручной запуск

Actions → **Build and Deploy to Vercel (Demo/Beta)** → **Run workflow** → **Run workflow**
