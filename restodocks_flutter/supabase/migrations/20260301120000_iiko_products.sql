-- iiko products: отдельная номенклатура для инвентаризации из iiko-бланков
-- Не пересекается с основными products / establishment_products

CREATE TABLE IF NOT EXISTS iiko_products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
    code            TEXT,
    name            TEXT NOT NULL,
    unit            TEXT,
    group_name      TEXT,
    sort_order      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Один набор продуктов на заведение (при перезагрузке бланка — полная замена)
CREATE INDEX IF NOT EXISTS iiko_products_establishment_idx ON iiko_products(establishment_id);

-- RLS
ALTER TABLE iiko_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "iiko_products_select" ON iiko_products
    FOR SELECT USING (
        establishment_id IN (
            SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid()
            UNION
            SELECT id FROM establishments WHERE owner_auth_user_id = auth.uid()
        )
    );

CREATE POLICY "iiko_products_insert" ON iiko_products
    FOR INSERT WITH CHECK (
        establishment_id IN (
            SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid()
            UNION
            SELECT id FROM establishments WHERE owner_auth_user_id = auth.uid()
        )
    );

CREATE POLICY "iiko_products_delete" ON iiko_products
    FOR DELETE USING (
        establishment_id IN (
            SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid()
            UNION
            SELECT id FROM establishments WHERE owner_auth_user_id = auth.uid()
        )
    );
