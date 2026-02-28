-- Добавляем колонки target_quantity и target_unit к пунктам чеклиста (ПФ с количеством).
ALTER TABLE checklist_items
  ADD COLUMN IF NOT EXISTS target_quantity numeric(10, 3),
  ADD COLUMN IF NOT EXISTS target_unit    text;
