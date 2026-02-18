-- Check if RLS policies are properly set up for establishment_products
-- Run this in Supabase SQL Editor to diagnose the issue

-- 1. Check if table exists and RLS is enabled
SELECT
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'establishment_products';

-- 2. Check existing policies
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'establishment_products';

-- 3. Test a simple query (should work if policies are correct)
-- This should return 0 rows if table is empty, or actual count if data exists
SELECT COUNT(*) as establishment_products_count FROM establishment_products;

-- 4. Check if user is authenticated (run this while logged in)
-- This should return the current user's ID
SELECT auth.uid() as current_user_id;

-- 5. Check establishments for current user
SELECT id, name, owner_id FROM establishments
WHERE owner_id::text = auth.uid()::text;