-- Удаление дублирующихся продуктов (одинаковое название).
-- Стратегия: для каждой группы дублей оставляем продукт, который уже есть
-- в establishment_products (если есть). Если в nomenclature нет ни одного —
-- оставляем строку с наименьшим id (наиболее ранний, обычно из справочника).
-- Все ссылки из establishment_products и product_price_history переводим
-- на оставшийся продукт, затем удаляем дубли.

BEGIN;

-- 1. Таблица: для каждого (lower(name)) определяем "победителя"
--    Приоритет: продукт, уже стоящий в establishment_products > min(id)
CREATE TEMP TABLE _dedup_winners AS
SELECT DISTINCT ON (lower(trim(p.name)))
    p.id      AS winner_id,
    lower(trim(p.name)) AS name_key
FROM products p
ORDER BY
    lower(trim(p.name)),
    -- предпочитаем тех, кто есть в номенклатуре
    (EXISTS (SELECT 1 FROM establishment_products ep WHERE ep.product_id = p.id)) DESC,
    -- среди них — наименьший id (первый добавленный)
    p.id;

-- 2. Таблица: все дубли → winner_id (исключая самого победителя)
CREATE TEMP TABLE _dedup_victims AS
SELECT p.id AS victim_id, w.winner_id
FROM products p
JOIN _dedup_winners w ON lower(trim(p.name)) = w.name_key
WHERE p.id <> w.winner_id;

-- 3. Перенаправляем establishment_products: дубли → победитель
--    Используем upsert чтобы не создать конфликт по (establishment_id, product_id)
UPDATE establishment_products ep
SET product_id = v.winner_id
FROM _dedup_victims v
WHERE ep.product_id = v.victim_id
  -- не трогаем если у победителя уже есть запись для этого establishment
  AND NOT EXISTS (
      SELECT 1 FROM establishment_products ep2
      WHERE ep2.product_id = v.winner_id
        AND ep2.establishment_id = ep.establishment_id
  );

-- Удаляем дублирующиеся записи establishment_products (у тех жертв,
-- для которых победитель уже был в номенклатуре — строки не переехали выше)
DELETE FROM establishment_products ep
USING _dedup_victims v
WHERE ep.product_id = v.victim_id;

-- 4. Перенаправляем product_price_history (если таблица существует)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'product_price_history') THEN
    UPDATE product_price_history pph
    SET product_id = v.winner_id
    FROM _dedup_victims v
    WHERE pph.product_id = v.victim_id;
  END IF;
END$$;

-- 5. Обнуляем ссылки supplier_ids в продуктах (JSONB) — не критично, пропускаем.

-- 6. Удаляем сами дубли из products
DELETE FROM products
WHERE id IN (SELECT victim_id FROM _dedup_victims);

-- Итог
DO $$
DECLARE
  deleted_count INT;
  remaining_count INT;
BEGIN
  SELECT COUNT(*) INTO deleted_count FROM _dedup_victims;
  SELECT COUNT(*) INTO remaining_count FROM products;
  RAISE NOTICE 'Deleted % duplicate products. Remaining: %', deleted_count, remaining_count;
END$$;

DROP TABLE _dedup_winners;
DROP TABLE _dedup_victims;

COMMIT;
