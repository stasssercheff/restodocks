-- Способ «mixing» (смешивание) в дефолтах % ужарки (0%), синхрон с CookingProcess.defaultProcesses во Flutter.

CREATE OR REPLACE FUNCTION public._default_cooking_loss_rows()
RETURNS TABLE (process_id text, loss_pct double precision)
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  VALUES
    ('mixing'::text, 0.0::double precision),
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

INSERT INTO public.product_cooking_loss_stats (
  product_id, cooking_process_id, avg_loss_pct, sample_count, updated_at
)
SELECT p.id, 'mixing'::text, 0.0::double precision, 1, now()
FROM public.products p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.product_cooking_loss_stats s
  WHERE s.product_id = p.id AND s.cooking_process_id = 'mixing'
);
