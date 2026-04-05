-- IAP: одна подписка Apple (original_transaction_id) → один владелец (auth.users.id);
-- Pro выставляется на все заведения с establishments.owner_id = owner_id.
-- Безопасно при уже owner-scoped таблице (только комментарий / индекс при необходимости).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'apple_iap_subscription_claims'
      AND column_name = 'establishment_id'
  ) THEN
    ALTER TABLE public.apple_iap_subscription_claims
      ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES auth.users (id) ON DELETE CASCADE;

    UPDATE public.apple_iap_subscription_claims c
    SET owner_id = e.owner_id
    FROM public.establishments e
    WHERE e.id = c.establishment_id
      AND c.owner_id IS NULL;

    DELETE FROM public.apple_iap_subscription_claims WHERE owner_id IS NULL;

    DELETE FROM public.apple_iap_subscription_claims c
    WHERE c.ctid <> (
      SELECT min(c2.ctid)
      FROM public.apple_iap_subscription_claims c2
      WHERE c2.owner_id = c.owner_id
    );

    ALTER TABLE public.apple_iap_subscription_claims
      ALTER COLUMN owner_id SET NOT NULL;

    ALTER TABLE public.apple_iap_subscription_claims
      DROP CONSTRAINT IF EXISTS apple_iap_subscription_claims_establishment_unique;

    DROP INDEX IF EXISTS apple_iap_subscription_claims_establishment_id_idx;

    ALTER TABLE public.apple_iap_subscription_claims
      DROP COLUMN establishment_id;
  END IF;
END $$;

ALTER TABLE public.apple_iap_subscription_claims
  DROP CONSTRAINT IF EXISTS apple_iap_subscription_claims_owner_unique;

ALTER TABLE public.apple_iap_subscription_claims
  ADD CONSTRAINT apple_iap_subscription_claims_owner_unique UNIQUE (owner_id);

CREATE INDEX IF NOT EXISTS apple_iap_subscription_claims_owner_id_idx
  ON public.apple_iap_subscription_claims (owner_id);

COMMENT ON TABLE public.apple_iap_subscription_claims IS
  'Привязка auto-renewable IAP Apple к владельцу (owner_id): один original_transaction_id — одна цепочка; Pro на всех заведениях этого owner_id.';
