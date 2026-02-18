-- TEMPORARY: Disable RLS to test if screen works
-- Execute this in Supabase SQL Editor to temporarily disable RLS
-- WARNING: This removes security! Re-enable after testing!

-- Disable RLS temporarily for testing
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- Test query
SELECT COUNT(*) FROM establishment_products;

-- After testing, re-enable with:
-- ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;