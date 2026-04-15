-- Системные (глобальные) усреднённые показатели по продуктам: % ужарки по способу приготовления и % отхода (брутто→нетто).
-- Источник данных — все заведения; агрегаты общие для каталога (аналогично слою КБЖУ).

CREATE TABLE IF NOT EXISTS public.product_cooking_loss_stats (
  product_id uuid NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  cooking_process_id text NOT NULL,
  avg_loss_pct double precision NOT NULL,
  sample_count integer NOT NULL DEFAULT 0 CHECK (sample_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (product_id, cooking_process_id)
);

CREATE INDEX IF NOT EXISTS product_cooking_loss_stats_process_idx
  ON public.product_cooking_loss_stats (cooking_process_id);

ALTER TABLE public.product_cooking_loss_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_cooking_loss_stats_select_auth" ON public.product_cooking_loss_stats;
CREATE POLICY "product_cooking_loss_stats_select_auth" ON public.product_cooking_loss_stats
  FOR SELECT TO authenticated
  USING (true);

COMMENT ON TABLE public.product_cooking_loss_stats IS
  'Глобальное скользящее среднее % ужарки по product_id и способу приготовления (обучение по всем заведениям).';

CREATE TABLE IF NOT EXISTS public.product_primary_waste_stats (
  product_id uuid NOT NULL PRIMARY KEY REFERENCES public.products (id) ON DELETE CASCADE,
  avg_waste_pct double precision NOT NULL,
  sample_count integer NOT NULL DEFAULT 0 CHECK (sample_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS product_primary_waste_stats_updated_idx
  ON public.product_primary_waste_stats (updated_at DESC);

ALTER TABLE public.product_primary_waste_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_primary_waste_stats_select_auth" ON public.product_primary_waste_stats;
CREATE POLICY "product_primary_waste_stats_select_auth" ON public.product_primary_waste_stats
  FOR SELECT TO authenticated
  USING (true);

COMMENT ON TABLE public.product_primary_waste_stats IS
  'Глобальное скользящее среднее % отхода (первичная обработка) по product_id (обучение по всем заведениям).';

-- Перенос накопленных данных из заведений в глобальные строки (взвешенное среднее), если таблица заведений уже есть.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'establishment_product_cooking_loss_stats'
  ) THEN
    INSERT INTO public.product_cooking_loss_stats (product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at)
    SELECT
      s.product_id,
      s.cooking_process_id,
      (SUM(s.avg_loss_pct * s.sample_count::double precision) / NULLIF(SUM(s.sample_count), 0))::double precision,
      SUM(s.sample_count)::integer,
      now()
    FROM public.establishment_product_cooking_loss_stats s
    WHERE s.sample_count > 0
    GROUP BY s.product_id, s.cooking_process_id
    ON CONFLICT (product_id, cooking_process_id) DO UPDATE SET
      avg_loss_pct = excluded.avg_loss_pct,
      sample_count = excluded.sample_count,
      updated_at = excluded.updated_at;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.record_product_cooking_loss_sample_global(
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
    RAISE EXCEPTION 'record_product_cooking_loss_sample_global: forbidden';
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

  INSERT INTO public.product_cooking_loss_stats AS s (
    product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
  )
  VALUES (p_product_id, v_proc, v_loss, 1, now())
  ON CONFLICT (product_id, cooking_process_id)
  DO UPDATE SET
    avg_loss_pct = (s.avg_loss_pct * s.sample_count + excluded.avg_loss_pct)
      / (s.sample_count + excluded.sample_count),
    sample_count = s.sample_count + excluded.sample_count,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_cooking_loss_sample_global(uuid, uuid, text, double precision, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_cooking_loss_sample_global(uuid, uuid, text, double precision, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_suggested_cooking_loss_pct_global(
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
  v_proc := lower(trim(p_cooking_process_id));
  IF v_proc IS NULL OR v_proc = '' OR v_proc = 'custom' THEN
    RETURN NULL;
  END IF;
  SELECT s.avg_loss_pct INTO v_out
  FROM public.product_cooking_loss_stats s
  WHERE s.product_id = p_product_id
    AND s.cooking_process_id = v_proc
    AND s.sample_count > 0
  LIMIT 1;
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.get_suggested_cooking_loss_pct_global(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_suggested_cooking_loss_pct_global(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_product_waste_sample_global(
  p_establishment_id uuid,
  p_product_id uuid,
  p_waste_pct double precision,
  p_source text DEFAULT 'user'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_waste double precision;
  v_src text;
BEGIN
  IF NOT public._can_access_establishment_for_epcls(p_establishment_id) THEN
    RAISE EXCEPTION 'record_product_waste_sample_global: forbidden';
  END IF;
  v_waste := greatest(0::double precision, least(99.9::double precision, p_waste_pct));
  v_src := lower(trim(coalesce(p_source, 'user')));
  IF v_src NOT IN ('user', 'ai') THEN
    v_src := 'user';
  END IF;

  INSERT INTO public.product_primary_waste_stats AS s (
    product_id, avg_waste_pct, sample_count, updated_at
  )
  VALUES (p_product_id, v_waste, 1, now())
  ON CONFLICT (product_id)
  DO UPDATE SET
    avg_waste_pct = (s.avg_waste_pct * s.sample_count + excluded.avg_waste_pct)
      / (s.sample_count + excluded.sample_count),
    sample_count = s.sample_count + excluded.sample_count,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_waste_sample_global(uuid, uuid, double precision, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_waste_sample_global(uuid, uuid, double precision, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_suggested_product_waste_pct_global(
  p_product_id uuid
) RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_out double precision;
BEGIN
  SELECT s.avg_waste_pct INTO v_out
  FROM public.product_primary_waste_stats s
  WHERE s.product_id = p_product_id
    AND s.sample_count > 0
  LIMIT 1;
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.get_suggested_product_waste_pct_global(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_suggested_product_waste_pct_global(uuid) TO authenticated;
