-- Final P0 closeout: remove anonymous table-level invite access and lock nutrition writes.

-- 1) co_owner_invitations: table access for anon removed, invite flow goes via SECURITY DEFINER RPCs.
ALTER TABLE co_owner_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_co_owner_invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

REVOKE SELECT, UPDATE ON TABLE co_owner_invitations FROM anon;

CREATE OR REPLACE FUNCTION public.accept_co_owner_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row co_owner_invitations%ROWTYPE;
BEGIN
  SELECT *
  INTO v_row
  FROM co_owner_invitations
  WHERE invitation_token = p_token
    AND status = 'pending'
    AND (expires_at IS NULL OR expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'accept_co_owner_invitation: invitation not found or expired';
  END IF;

  UPDATE co_owner_invitations
  SET status = 'accepted',
      updated_at = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', 'accepted'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_co_owner_invitation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO anon;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO authenticated;

-- 2) Nutrition layer: no direct writes from anon/authenticated clients.
-- Writes should happen only via trusted backend/service role paths.
ALTER TABLE public.nutrition_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_nutrition_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_research_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "anon_update_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_update_nutrition_profiles" ON public.nutrition_profiles;

DROP POLICY IF EXISTS "anon_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "anon_update_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_update_nutrition_aliases" ON public.nutrition_aliases;

DROP POLICY IF EXISTS "anon_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "anon_update_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_update_product_nutrition_links" ON public.product_nutrition_links;

DROP POLICY IF EXISTS "anon_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "anon_update_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_update_nutrition_research_queue" ON public.nutrition_research_queue;
