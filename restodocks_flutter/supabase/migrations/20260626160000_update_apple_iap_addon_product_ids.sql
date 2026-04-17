-- Apple IAP: switch addon product_id mapping to current App Store Connect IDs.
-- Old restodocks_* addon IDs are no longer accepted.

CREATE OR REPLACE FUNCTION public.apply_apple_iap_addon_claim(
  p_transaction_id text,
  p_product_id text,
  p_owner_id uuid,
  p_establishment_id uuid,
  p_purchase_date timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx text := trim(COALESCE(p_transaction_id, ''));
  v_product text := trim(COALESCE(p_product_id, ''));
  v_inserted integer := 0;
BEGIN
  IF v_tx = '' OR v_product = '' OR p_owner_id IS NULL OR p_establishment_id IS NULL THEN
    RETURN false;
  END IF;

  INSERT INTO public.apple_iap_addon_claims (
    transaction_id,
    product_id,
    owner_id,
    establishment_id,
    purchase_date,
    applied_at
  )
  VALUES (
    v_tx,
    v_product,
    p_owner_id,
    p_establishment_id,
    p_purchase_date,
    now()
  )
  ON CONFLICT (transaction_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN false;
  END IF;

  -- Employee add-ons are sold as slot bundles:
  -- 5/10/15/20 extra employees => 1/2/3/4 packs.
  IF v_product = '5_extra_employee_monthly' THEN
    PERFORM public.establishment_entitlement_merge_employee_packs(p_establishment_id, 1);
    RETURN true;
  ELSIF v_product = '10_extra_employee_monthly' THEN
    PERFORM public.establishment_entitlement_merge_employee_packs(p_establishment_id, 2);
    RETURN true;
  ELSIF v_product = '15_extra_employee_monthly' THEN
    PERFORM public.establishment_entitlement_merge_employee_packs(p_establishment_id, 3);
    RETURN true;
  ELSIF v_product = '20_extra_employee_monthly' THEN
    PERFORM public.establishment_entitlement_merge_employee_packs(p_establishment_id, 4);
    RETURN true;
  END IF;

  -- Establishment add-ons are branch slot packs.
  IF v_product = '1_extra_establishment_monthly' THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(p_owner_id, 1);
    RETURN true;
  ELSIF v_product = '3_extra_establishment_monthly' THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(p_owner_id, 3);
    RETURN true;
  ELSIF v_product = '5_extra_establishment_monthly' THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(p_owner_id, 5);
    RETURN true;
  ELSIF v_product = '10_extra_establishment_monthly' THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(p_owner_id, 10);
    RETURN true;
  END IF;

  -- Unknown product: rollback idempotency record for this tx.
  DELETE FROM public.apple_iap_addon_claims WHERE transaction_id = v_tx;
  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.apply_apple_iap_addon_claim(text, text, uuid, uuid, timestamptz) IS
  'Idempotent Apple IAP addon claim using current Product IDs (extra employees/establishments).';
