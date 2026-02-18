-- Test RLS policies for establishment_products
-- Run this in Supabase SQL Editor to check current state

-- Check if establishment_products table exists
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'establishment_products';

-- Check RLS status
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'establishment_products';

-- Check existing policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'establishment_products';

-- Test query that should work (if policies are correct)
-- SELECT COUNT(*) FROM establishment_products LIMIT 1;