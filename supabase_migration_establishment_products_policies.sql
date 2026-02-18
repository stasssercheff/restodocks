-- Add RLS policies for establishment_products table
-- This fixes the 400 error when loading nomenclature

-- First, drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view establishment products from their establishment" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products from their establishment" ON establishment_products;

-- Enable RLS for establishment_products (if not already enabled)
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Allow users to view establishment products from their own establishments
CREATE POLICY "Users can view establishment products from their establishment" ON establishment_products
  FOR SELECT USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

-- Allow users to manage establishment products from their own establishments
CREATE POLICY "Users can manage establishment products from their establishment" ON establishment_products
  FOR ALL USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );