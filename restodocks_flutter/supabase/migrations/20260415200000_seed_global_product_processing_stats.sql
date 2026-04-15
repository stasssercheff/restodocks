-- Начальное заполнение глобальных показателей: % ужарки (дефолты способов × все продукты),
-- % отхода (колонка products + агрегат по ТТК), усиление КБЖУ на products из nutrition_profiles где пусто.
-- При появлении нового продукта в каталоге — те же дефолты % ужарки (триггер).

-- Дефолтные % ужарки по способу (синхрон с CookingProcess.defaultProcesses во Flutter).
CREATE OR REPLACE FUNCTION public._default_cooking_loss_rows()
RETURNS TABLE (process_id text, loss_pct double precision)
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  VALUES
    ('boiling'::text, 25.0::double precision),
    ('frying', 15.0),
    ('baking', 20.0),
    ('stewing', 30.0),
    ('sous_vide', 5.0),
    ('fermentation', 10.0),
    ('grilling', 25.0),
    ('torch_browning', 2.0),
    ('sauteing', 15.0),
    ('blanching', 10.0),
    ('steaming', 8.0),
    ('canning', 5.0),
    ('cutting', 0.0);
$$;

REVOKE ALL ON FUNCTION public._default_cooking_loss_rows() FROM PUBLIC;

-- 1) Базовые строки: каждый продукт × каждый способ (только где строки ещё нет).
INSERT INTO public.product_cooking_loss_stats (
  product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
)
SELECT p.id, d.process_id, d.loss_pct, 1, now()
FROM public.products p
CROSS JOIN public._default_cooking_loss_rows() AS d(process_id, loss_pct)
ON CONFLICT (product_id, cooking_process_id) DO NOTHING;

-- 2) Ужарка: агрегат по сохранённым строкам ТТК (нетто → выход + способ), слияние со средним в таблице.
WITH per_row AS (
  SELECT
    ti.product_id,
    lower(trim(ti.cooking_process_id::text)) AS proc_id,
    CASE
      WHEN ti.cooking_loss_pct_override IS NOT NULL THEN
        greatest(0::double precision, least(99.9::double precision, ti.cooking_loss_pct_override::double precision))
      WHEN ti.net_weight > 0 AND ti.output_weight IS NOT NULL AND ti.output_weight >= 0 THEN
        greatest(
          0::double precision,
          least(
            99.9::double precision,
            (1.0 - ti.output_weight::double precision / nullif(ti.net_weight::double precision, 0)) * 100.0
          )
        )
      ELSE NULL
    END AS loss_pct
  FROM public.tt_ingredients ti
  WHERE ti.product_id IS NOT NULL
    AND ti.source_tech_card_id IS NULL
    AND ti.gross_weight > 0
    AND ti.cooking_process_id IS NOT NULL
    AND length(trim(ti.cooking_process_id::text)) > 0
    AND lower(trim(ti.cooking_process_id::text)) <> 'custom'
),
agg AS (
  SELECT
    product_id,
    proc_id AS cooking_process_id,
    avg(loss_pct)::double precision AS avg_loss_pct,
    count(*)::integer AS sample_count
  FROM per_row
  WHERE loss_pct IS NOT NULL
  GROUP BY product_id, proc_id
)
INSERT INTO public.product_cooking_loss_stats (
  product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
)
SELECT a.product_id, a.cooking_process_id, a.avg_loss_pct, a.sample_count, now()
FROM agg a
ON CONFLICT (product_id, cooking_process_id) DO UPDATE SET
  avg_loss_pct = (
    public.product_cooking_loss_stats.avg_loss_pct * public.product_cooking_loss_stats.sample_count::double precision
    + excluded.avg_loss_pct * excluded.sample_count::double precision
  ) / nullif(
    public.product_cooking_loss_stats.sample_count + excluded.sample_count,
    0
  )::double precision,
  sample_count = public.product_cooking_loss_stats.sample_count + excluded.sample_count,
  updated_at = now();

-- 3) Отход: из карточки продукта (если колонка есть).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'primary_waste_pct'
  ) THEN
    INSERT INTO public.product_primary_waste_stats (
      product_id, avg_waste_pct, sample_count, updated_at
    )
    SELECT p.id,
      greatest(0::double precision, least(99.9::double precision, p.primary_waste_pct::double precision)),
      1,
      now()
    FROM public.products p
    WHERE p.primary_waste_pct IS NOT NULL AND p.primary_waste_pct > 0
    ON CONFLICT (product_id) DO NOTHING;
  END IF;
END $$;

-- 4) Отход: агрегат по ТТК, слияние.
WITH agg AS (
  SELECT
    ti.product_id,
    avg(greatest(0::double precision, least(99.9::double precision, ti.primary_waste_pct::double precision)))::double precision AS avg_waste_pct,
    count(*)::integer AS sample_count
  FROM public.tt_ingredients ti
  WHERE ti.product_id IS NOT NULL
    AND ti.source_tech_card_id IS NULL
    AND ti.gross_weight > 0
    AND ti.primary_waste_pct IS NOT NULL
    AND ti.primary_waste_pct > 0
  GROUP BY ti.product_id
)
INSERT INTO public.product_primary_waste_stats (
  product_id, avg_waste_pct, sample_count, updated_at
)
SELECT a.product_id, a.avg_waste_pct, a.sample_count, now()
FROM agg a
ON CONFLICT (product_id) DO UPDATE SET
  avg_waste_pct = (
    public.product_primary_waste_stats.avg_waste_pct * public.product_primary_waste_stats.sample_count::double precision
    + excluded.avg_waste_pct * excluded.sample_count::double precision
  ) / nullif(
    public.product_primary_waste_stats.sample_count + excluded.sample_count,
    0
  )::double precision,
  sample_count = public.product_primary_waste_stats.sample_count + excluded.sample_count,
  updated_at = now();

-- 5) КБЖУ на products: только заполнение NULL из привязанного nutrition_profile (не перетирать уже заданное).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'product_nutrition_links'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'nutrition_profiles'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'calories'
  ) THEN
    UPDATE public.products p SET
      calories = COALESCE(p.calories, np.calories),
      protein = COALESCE(p.protein, np.protein),
      fat = COALESCE(p.fat, np.fat),
      carbs = COALESCE(p.carbs, np.carbs)
    FROM public.product_nutrition_links pnl
    INNER JOIN public.nutrition_profiles np ON np.id = pnl.nutrition_profile_id
    WHERE pnl.product_id = p.id
      AND (
        NOT EXISTS (
          SELECT 1 FROM information_schema.columns c
          WHERE c.table_schema = 'public' AND c.table_name = 'products' AND c.column_name = 'kbju_manually_confirmed'
        )
        OR COALESCE(p.kbju_manually_confirmed, false) = false
      )
      AND (
        p.calories IS NULL OR p.protein IS NULL OR p.fat IS NULL OR p.carbs IS NULL
      )
      AND (
        np.calories IS NOT NULL OR np.protein IS NOT NULL OR np.fat IS NOT NULL OR np.carbs IS NOT NULL
      );
  END IF;
END $$;

COMMENT ON FUNCTION public._default_cooking_loss_rows() IS
  'Справочник дефолтных % ужарки по cooking_process_id (как в приложении); для сидов и триггера новых продуктов.';

-- 6) Новые продукты в каталоге: сразу строки % ужарки по всем способам (пользовательские сохранения потом усреднят RPC).
CREATE OR REPLACE FUNCTION public.seed_product_cooking_loss_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.product_cooking_loss_stats (
    product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
  )
  SELECT NEW.id, d.process_id, d.loss_pct, 1, now()
  FROM public._default_cooking_loss_rows() AS d(process_id, loss_pct)
  ON CONFLICT (product_id, cooking_process_id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_product_cooking_loss_defaults() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_products_seed_cooking_loss_defaults ON public.products;
CREATE TRIGGER trg_products_seed_cooking_loss_defaults
  AFTER INSERT ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_product_cooking_loss_defaults();

COMMENT ON TRIGGER trg_products_seed_cooking_loss_defaults ON public.products IS
  'Добавление в product_cooking_loss_stats дефолтных % ужарки по всем способам при появлении нового product_id.';
