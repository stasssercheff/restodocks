-- Усреднённый % ужарки по связке заведение + продукт + способ приготовления (обучение из ТТК: ИИ и пользователь).

CREATE TABLE IF NOT EXISTS public.establishment_product_cooking_loss_stats (
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  cooking_process_id text NOT NULL,
  avg_loss_pct double precision NOT NULL,
  sample_count integer NOT NULL DEFAULT 0 CHECK (sample_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (establishment_id, product_id, cooking_process_id)
);

CREATE INDEX IF NOT EXISTS establishment_product_cooking_loss_stats_product_idx
  ON public.establishment_product_cooking_loss_stats (product_id);

ALTER TABLE public.establishment_product_cooking_loss_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "epcls_select_auth" ON public.establishment_product_cooking_loss_stats;
CREATE POLICY "epcls_select_auth" ON public.establishment_product_cooking_loss_stats
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT e.establishment_id FROM public.employees e
      WHERE (e.id = auth.uid() OR e.auth_user_id = auth.uid()) AND e.is_active = true
    )
    OR establishment_id IN (
      SELECT est.id FROM public.establishments est
      WHERE est.owner_id IN (
        SELECT id FROM public.employees e2
        WHERE e2.id = auth.uid() OR e2.auth_user_id = auth.uid()
      )
    )
  );

COMMENT ON TABLE public.establishment_product_cooking_loss_stats IS
  'Скользящее среднее % ужарки по продукту и способу приготовления в рамках заведения (обучение).';

CREATE OR REPLACE FUNCTION public._can_access_establishment_for_epcls(p_establishment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    WHERE (e.id = auth.uid() OR e.auth_user_id = auth.uid())
      AND e.establishment_id = p_establishment_id
      AND e.is_active = true
  )
  OR EXISTS (
    SELECT 1 FROM public.establishments est
    WHERE est.id = p_establishment_id
      AND est.owner_id IN (
        SELECT id FROM public.employees e2
        WHERE e2.id = auth.uid() OR e2.auth_user_id = auth.uid()
      )
  );
$$;

REVOKE ALL ON FUNCTION public._can_access_establishment_for_epcls(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.record_product_cooking_loss_sample(
  p_establishment_id uuid,
  p_product_id uuid,
  p_cooking_process_id text,
  p_loss_pct double precision,
  p_source text DEFAULT 'user'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proc text;
  v_loss double precision;
  v_src text;
BEGIN
  IF NOT public._can_access_establishment_for_epcls(p_establishment_id) THEN
    RAISE EXCEPTION 'record_product_cooking_loss_sample: forbidden';
  END IF;
  v_proc := lower(trim(p_cooking_process_id));
  IF v_proc IS NULL OR v_proc = '' OR v_proc = 'custom' THEN
    RETURN;
  END IF;
  v_loss := greatest(0::double precision, least(99.9::double precision, p_loss_pct));
  v_src := lower(trim(coalesce(p_source, 'user')));
  IF v_src NOT IN ('user', 'ai') THEN
    v_src := 'user';
  END IF;

  INSERT INTO public.establishment_product_cooking_loss_stats AS s (
    establishment_id, product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
  )
  VALUES (p_establishment_id, p_product_id, v_proc, v_loss, 1, now())
  ON CONFLICT (establishment_id, product_id, cooking_process_id)
  DO UPDATE SET
    avg_loss_pct = (s.avg_loss_pct * s.sample_count + excluded.avg_loss_pct)
      / (s.sample_count + excluded.sample_count),
    sample_count = s.sample_count + excluded.sample_count,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_cooking_loss_sample(uuid, uuid, text, double precision, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_cooking_loss_sample(uuid, uuid, text, double precision, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_suggested_cooking_loss_pct(
  p_establishment_id uuid,
  p_product_id uuid,
  p_cooking_process_id text
) RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proc text;
  v_out double precision;
BEGIN
  IF NOT public._can_access_establishment_for_epcls(p_establishment_id) THEN
    RETURN NULL;
  END IF;
  v_proc := lower(trim(p_cooking_process_id));
  IF v_proc IS NULL OR v_proc = '' OR v_proc = 'custom' THEN
    RETURN NULL;
  END IF;
  SELECT s.avg_loss_pct INTO v_out
  FROM public.establishment_product_cooking_loss_stats s
  WHERE s.establishment_id = p_establishment_id
    AND s.product_id = p_product_id
    AND s.cooking_process_id = v_proc
    AND s.sample_count > 0
  LIMIT 1;
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.get_suggested_cooking_loss_pct(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_suggested_cooking_loss_pct(uuid, uuid, text) TO authenticated;
