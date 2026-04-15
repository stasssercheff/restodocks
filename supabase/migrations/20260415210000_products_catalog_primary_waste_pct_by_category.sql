-- Колонка справочного % отхода на продукте (заполняется вручную, из номенклатуры или из глобального обучения по ТТК).
-- Ранее здесь была эвристика по category — отменена: рыба/мясо и отходы слишком разные для одной цифры по категории.
-- См. product_primary_waste_stats + record_product_waste_sample_global.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS primary_waste_pct real;

COMMENT ON COLUMN public.products.primary_waste_pct IS
  'Справочный % отхода при первичной обработке (0–99.9); подсказка в ТТК и вклад в глобальное среднее. Ужарка по способу приготовления — product_cooking_loss_stats.';
