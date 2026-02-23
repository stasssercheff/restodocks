-- Fix section column and RLS policies for tech_cards table
-- Execute this in Supabase SQL Editor

-- Add section column if it doesn't exist
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS section TEXT;

-- Add index for section queries
CREATE INDEX IF NOT EXISTS idx_tech_cards_section ON tech_cards(section);

-- Remove conflicting RLS policies if they exist
DROP POLICY IF EXISTS "Users can view tech_cards section" ON tech_cards;
DROP POLICY IF EXISTS "Users can update tech_cards section" ON tech_cards;

-- Note: RLS policies for tech_cards are already defined in supabase_policies.sql
-- No need to redefine them here, as they already cover all operations