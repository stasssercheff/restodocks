-- Настройки налоговой зоны заведения и очередь исходящих фискальных операций (ККТ/ОФД позже).
CREATE TABLE IF NOT EXISTS establishment_fiscal_settings (
  establishment_id UUID PRIMARY KEY REFERENCES establishments(id) ON DELETE CASCADE,
  tax_region TEXT NOT NULL DEFAULT 'RU',
  price_tax_mode TEXT NOT NULL DEFAULT 'tax_included'
    CHECK (price_tax_mode IN ('tax_included', 'tax_excluded')),
  vat_override_percent NUMERIC(6, 2)
    CHECK (vat_override_percent IS NULL OR (vat_override_percent >= 0 AND vat_override_percent <= 100)),
  fiscal_section_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE establishment_fiscal_settings IS 'Переопределения налоговой логики заведения; пресеты страны — в приложении (world_tax_presets.json).';
COMMENT ON COLUMN establishment_fiscal_settings.tax_region IS 'Ключ региона из пресетов: RU, AE, KZ, DE, US, RS, ...';
COMMENT ON COLUMN establishment_fiscal_settings.price_tax_mode IS 'Цена в меню: с НДС (tax_included) или без (tax_excluded, напр. США).';
COMMENT ON COLUMN establishment_fiscal_settings.vat_override_percent IS 'Процент НДС/налога вместо дефолта пресета; NULL = из пресета.';

ALTER TABLE establishment_fiscal_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_establishment_fiscal_settings_all" ON establishment_fiscal_settings;
CREATE POLICY "anon_establishment_fiscal_settings_all" ON establishment_fiscal_settings
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_establishment_fiscal_settings_all" ON establishment_fiscal_settings;
CREATE POLICY "auth_establishment_fiscal_settings_all" ON establishment_fiscal_settings
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS fiscal_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  pos_order_id UUID REFERENCES pos_orders(id) ON DELETE SET NULL,
  operation TEXT NOT NULL CHECK (operation IN ('sale', 'refund', 'correction')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'synced', 'failed', 'skipped')),
  client_request_id UUID NOT NULL UNIQUE,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_outbox_establishment ON fiscal_outbox(establishment_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_outbox_status ON fiscal_outbox(establishment_id, status)
  WHERE status = 'pending';

COMMENT ON TABLE fiscal_outbox IS 'Очередь фискальных операций до обмена с ККТ/облаком; client_request_id — идемпотентность.';

ALTER TABLE fiscal_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_fiscal_outbox_all" ON fiscal_outbox;
CREATE POLICY "anon_fiscal_outbox_all" ON fiscal_outbox
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_fiscal_outbox_all" ON fiscal_outbox;
CREATE POLICY "auth_fiscal_outbox_all" ON fiscal_outbox
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Тег для будущей маркировки / налогов по категории блюда (опционально).
ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS fiscal_system_tag TEXT;

COMMENT ON COLUMN tech_cards.fiscal_system_tag IS 'Системный тег номенклатуры: SYS_FOOD, SYS_ALCO_HARD, ... (см. world_tax_presets.json).';
