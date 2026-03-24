-- RLS / IDOR regression test (User_A must not access User_B data)
-- Run in Supabase SQL Editor (staging first), then production.
--
-- Expected result: script finishes with NOTICE lines only.
-- Any "RAISE EXCEPTION" means security regression.

BEGIN;

DO $$
DECLARE
  user_a uuid;
  est_a uuid;
  user_b uuid;
  est_b uuid;
  sample_tc_b uuid;
  sample_ep_b uuid;
  sample_order_b uuid;
  visible_count integer;
  changed_count integer;
BEGIN
  SELECT e.id, e.establishment_id
    INTO user_a, est_a
  FROM employees e
  WHERE e.is_active = true
  LIMIT 1;

  IF user_a IS NULL THEN
    RAISE EXCEPTION 'No active employees found';
  END IF;

  SELECT e.id, e.establishment_id
    INTO user_b, est_b
  FROM employees e
  WHERE e.is_active = true
    AND e.establishment_id <> est_a
  LIMIT 1;

  IF user_b IS NULL THEN
    RAISE EXCEPTION 'Need at least 2 establishments with active employees for cross-tenant test';
  END IF;

  -- Simulate authenticated User_A context.
  PERFORM set_config('request.jwt.claim.sub', user_a::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';

  -- 1) Cross-tenant SELECT must return zero rows (tech_cards)
  SELECT tc.id
    INTO sample_tc_b
  FROM tech_cards tc
  WHERE tc.establishment_id = est_b
  LIMIT 1;

  IF sample_tc_b IS NOT NULL THEN
    SELECT count(*)
      INTO visible_count
    FROM tech_cards
    WHERE id = sample_tc_b;

    IF visible_count > 0 THEN
      RAISE EXCEPTION 'RLS leak: User_A can SELECT User_B tech_card %', sample_tc_b;
    END IF;

    UPDATE tech_cards
    SET updated_at = updated_at
    WHERE id = sample_tc_b;
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    IF changed_count > 0 THEN
      RAISE EXCEPTION 'RLS leak: User_A can UPDATE User_B tech_card %', sample_tc_b;
    END IF;
  END IF;

  -- 2) Cross-tenant SELECT/UPDATE must be blocked (establishment_products)
  SELECT ep.product_id
    INTO sample_ep_b
  FROM establishment_products ep
  WHERE ep.establishment_id = est_b
  LIMIT 1;

  IF sample_ep_b IS NOT NULL THEN
    SELECT count(*)
      INTO visible_count
    FROM establishment_products
    WHERE establishment_id = est_b
      AND product_id = sample_ep_b;

    IF visible_count > 0 THEN
      RAISE EXCEPTION 'RLS leak: User_A can SELECT User_B establishment_products (product_id=%)', sample_ep_b;
    END IF;

    UPDATE establishment_products
    SET price = price
    WHERE establishment_id = est_b
      AND product_id = sample_ep_b;
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    IF changed_count > 0 THEN
      RAISE EXCEPTION 'RLS leak: User_A can UPDATE User_B establishment_products (product_id=%)', sample_ep_b;
    END IF;
  END IF;

  -- 3) Cross-tenant order_documents must not be visible
  SELECT od.id
    INTO sample_order_b
  FROM order_documents od
  WHERE od.establishment_id = est_b
  LIMIT 1;

  IF sample_order_b IS NOT NULL THEN
    SELECT count(*)
      INTO visible_count
    FROM order_documents
    WHERE id = sample_order_b;

    IF visible_count > 0 THEN
      RAISE EXCEPTION 'RLS leak: User_A can SELECT User_B order_document %', sample_order_b;
    END IF;
  END IF;

  RAISE NOTICE 'PASS: User_A (%) cannot access User_B (%) cross-tenant rows', user_a, user_b;
END $$;

ROLLBACK;
