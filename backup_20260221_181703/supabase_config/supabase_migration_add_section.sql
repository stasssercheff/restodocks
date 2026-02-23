-- Add section field to tech_cards table
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS section TEXT;

-- Add index for section queries
CREATE INDEX IF NOT EXISTS idx_tech_cards_section ON tech_cards(section);

-- Add RLS policy for section field
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to see section field
CREATE POLICY "Users can view tech_cards section" ON tech_cards
FOR SELECT USING (
  establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
);

-- Policy to allow users to update section
CREATE POLICY "Users can update tech_cards section" ON tech_cards
FOR UPDATE USING (
  establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
);