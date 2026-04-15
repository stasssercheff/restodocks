-- Откат эвристики из 20260415210000: обнуляем primary_waste_pct только там,
-- где значение совпадает с тем, что выставила та миграция (по имени/категории).
-- Не трогаем строки, где % уже меняли вручную на другое число.

UPDATE public.products p
SET primary_waste_pct = 0
WHERE abs(
  coalesce(p.primary_waste_pct, 0)::double precision - (
    CASE
      WHEN lower(p.name) LIKE '%полуфабрикат%'
        OR coalesce(p.names::text, '') ilike '%полуфабрикат%'
        THEN 0::double precision
      WHEN lower(p.name) LIKE '%фарш%'
        OR coalesce(p.names::text, '') ilike '%фарш%'
        OR coalesce(p.names::text, '') ilike '%ground%'
        THEN 2::double precision
      WHEN p.category = 'meat' THEN 10::double precision
      WHEN p.category = 'seafood' THEN 14::double precision
      WHEN p.category = 'vegetables' THEN 18::double precision
      WHEN p.category = 'fruits' THEN 12::double precision
      WHEN p.category = 'legumes' THEN 3::double precision
      WHEN p.category = 'grains' THEN 0::double precision
      WHEN p.category = 'dairy' THEN 0::double precision
      WHEN p.category = 'eggs' THEN 12::double precision
      WHEN p.category = 'bakery' THEN 0::double precision
      WHEN p.category = 'beverages' THEN 0::double precision
      WHEN p.category = 'oils' THEN 0::double precision
      WHEN p.category = 'spices' THEN 0::double precision
      WHEN p.category = 'nuts' THEN 5::double precision
      WHEN p.category = 'pantry' THEN 3::double precision
      WHEN p.category = 'misc' THEN 5::double precision
      ELSE 0::double precision
    END
  )
) < 0.0001;
