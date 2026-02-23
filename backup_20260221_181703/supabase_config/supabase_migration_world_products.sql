-- Migration to populate products table with comprehensive world products database
-- This will replace all existing products with 3000+ translated products
-- Execute this in Supabase SQL Editor

-- ⚠️  CRITICAL WARNING: This will DELETE all existing products and related data! ⚠️
-- Make sure to backup important TTK and nomenclature data before running this!
-- After this migration, you may need to re-add products to your nomenclature.

-- Step 1: Delete existing data in correct order to respect foreign keys
DELETE FROM tt_ingredients WHERE product_id IS NOT NULL;
DELETE FROM establishment_products;
DELETE FROM translations WHERE entity_type = 'product';
DELETE FROM products;

-- Step 2: Insert new comprehensive products database
-- This includes 3000+ products with nutritional data (KBZU) and translations in 5 languages
-- Generated automatically by generate_world_products.py

-- Products insertion (see products_only.sql for the full INSERT statement)
-- Translations insertion (see translations_only.sql for the full INSERT statement)