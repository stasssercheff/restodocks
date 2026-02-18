-- TEMPORARY: Disable RLS to test if the issue is with RLS policies
-- This will temporarily remove security to test the connection

-- Disable RLS temporarily
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- Test query
SELECT COUNT(*) FROM establishment_products;

-- AFTER TESTING: Re-enable RLS
-- ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;