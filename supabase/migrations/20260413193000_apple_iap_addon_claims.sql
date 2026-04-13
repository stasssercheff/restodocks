-- Apple IAP add-ons: идемпотентное начисление пакетов по transaction_id.
-- Один transaction_id применяется только один раз.

CREATE TABLE IF NOT EXISTS public.apple_iap_addon_claims (
  transaction_id text PRIMARY KEY,
  product_id text NOT NULL,
  owner_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  purchase_date timestamptz NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.apple_iap_addon_claims IS
  'Идемпотентные claims по consumable add-on IAP Apple; один transaction_id начисляется один раз.';

CREATE INDEX IF NOT EXISTS apple_iap_addon_claims_owner_idx
  ON public.apple_iap_addon_claims (owner_id);

CREATE INDEX IF NOT EXISTS apple_iap_addon_claims_establishment_idx
  ON public.apple_iap_addon_claims (establishment_id);

ALTER TABLE public.apple_iap_addon_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.apple_iap_addon_claims FROM PUBLIC;
GRANT ALL ON TABLE public.apple_iap_addon_claims TO service_role;

CREATE OR REPLACE FUNCTION public.apply_apple_iap_addon_claim (
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

  IF v_product = 'restodocks_addon_employee_pack_5' THEN
    PERFORM public.establishment_entitlement_merge_employee_packs(p_establishment_id, 1);
    RETURN true;
  ELSIF v_product = 'restodocks_addon_branch_pack_1' THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(p_owner_id, 1);
    RETURN true;
  END IF;

  DELETE FROM public.apple_iap_addon_claims WHERE transaction_id = v_tx;
  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.apply_apple_iap_addon_claim (text, text, uuid, uuid, timestamptz) IS
  'Идемпотентно применяет add-on IAP по transaction_id и начисляет соответствующий пакет.';

REVOKE ALL ON FUNCTION public.apply_apple_iap_addon_claim (text, text, uuid, uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_apple_iap_addon_claim (text, text, uuid, uuid, timestamptz) TO service_role;
