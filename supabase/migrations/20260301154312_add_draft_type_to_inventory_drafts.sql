-- Добавить поддержку нескольких типов черновиков инвентаризации (standard и iiko_inventory)
-- Раньше было UNIQUE(establishment_id) → теперь UNIQUE(establishment_id, draft_type)
-- Это позволяет хранить одновременно стандартный черновик и iiko-черновик без конфликтов.

-- 1. Добавить колонку draft_type
ALTER TABLE public.inventory_drafts
  ADD COLUMN IF NOT EXISTS draft_type TEXT NOT NULL DEFAULT 'standard';

-- 2. Обновить существующие строки: если draft_data содержит _type = 'iiko_inventory' — помечаем
UPDATE public.inventory_drafts
  SET draft_type = 'iiko_inventory'
  WHERE draft_data->>'_type' = 'iiko_inventory';

-- 3. Удалить старый UNIQUE(establishment_id) constraint
ALTER TABLE public.inventory_drafts
  DROP CONSTRAINT IF EXISTS inventory_drafts_establishment_id_key;

-- 4. Добавить новый UNIQUE(establishment_id, draft_type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'inventory_drafts_estid_type_key'
  ) THEN
    ALTER TABLE public.inventory_drafts
      ADD CONSTRAINT inventory_drafts_estid_type_key
      UNIQUE(establishment_id, draft_type);
  END IF;
END$$;
