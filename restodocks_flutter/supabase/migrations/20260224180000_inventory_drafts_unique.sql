-- Уникальный индекс для upsert по establishment_id (тихое автосохранение черновиков)
CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_drafts_establishment_unique
  ON inventory_drafts(establishment_id);
