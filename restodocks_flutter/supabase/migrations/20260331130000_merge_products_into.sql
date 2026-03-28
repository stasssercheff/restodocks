-- Слияние дубликатов продуктов: перенос ссылок (ТТК, склад, номенклатура) и удаление лишних строк products.

CREATE OR REPLACE FUNCTION merge_products_into(
  p_target UUID,
  p_sources UUID[]
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s UUID;
  n INT := 0;
BEGIN
  IF p_target IS NULL THEN
    RAISE EXCEPTION 'merge_products_into: p_target is null';
  END IF;
  IF p_sources IS NULL OR array_length(p_sources, 1) IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'merged_sources', 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE id = p_target) THEN
    RAISE EXCEPTION 'merge_products_into: target product not found';
  END IF;

  IF p_target = ANY(p_sources) THEN
    RAISE EXCEPTION 'merge_products_into: target must not appear in sources';
  END IF;

  FOREACH s IN ARRAY p_sources LOOP
    IF s IS NULL OR s = p_target THEN CONTINUE; END IF;
    IF NOT EXISTS (SELECT 1 FROM products WHERE id = s) THEN CONTINUE; END IF;

    -- 1. Ингредиенты ТТК
    UPDATE tt_ingredients SET product_id = p_target WHERE product_id = s;

    -- 2. Движения склада: для pos_sale с строкой счёта — схлопываем в существующую строку target
    UPDATE establishment_stock_movements tgt
    SET delta_grams = tgt.delta_grams + src.delta_grams
    FROM establishment_stock_movements src
    WHERE src.product_id = s
      AND src.reason = 'pos_sale'
      AND src.pos_order_line_id IS NOT NULL
      AND tgt.product_id = p_target
      AND tgt.reason = 'pos_sale'
      AND tgt.pos_order_line_id = src.pos_order_line_id
      AND tgt.establishment_id = src.establishment_id;

    DELETE FROM establishment_stock_movements src
    WHERE src.product_id = s
      AND src.pos_order_line_id IS NOT NULL
      AND src.reason = 'pos_sale'
      AND EXISTS (
        SELECT 1 FROM establishment_stock_movements tgt
        WHERE tgt.product_id = p_target
          AND tgt.reason = 'pos_sale'
          AND tgt.pos_order_line_id = src.pos_order_line_id
          AND tgt.establishment_id = src.establishment_id
      );

    UPDATE establishment_stock_movements SET product_id = p_target WHERE product_id = s;

    -- 3. Остатки: суммируем в target
    UPDATE establishment_stock_balances bt
    SET quantity_grams = bt.quantity_grams + bs.quantity_grams,
        updated_at = NOW()
    FROM establishment_stock_balances bs
    WHERE bs.product_id = s
      AND bt.establishment_id = bs.establishment_id
      AND bt.product_id = p_target;

    INSERT INTO establishment_stock_balances (establishment_id, product_id, quantity_grams, updated_at)
    SELECT bs.establishment_id, p_target, bs.quantity_grams, NOW()
    FROM establishment_stock_balances bs
    WHERE bs.product_id = s
      AND NOT EXISTS (
        SELECT 1 FROM establishment_stock_balances bt
        WHERE bt.establishment_id = bs.establishment_id
          AND bt.product_id = p_target
      );

    DELETE FROM establishment_stock_balances WHERE product_id = s;

    -- 4. Номенклатура заведений
    DELETE FROM establishment_products ep
    USING establishment_products tgt
    WHERE ep.product_id = s
      AND tgt.establishment_id = ep.establishment_id
      AND tgt.product_id = p_target;

    UPDATE establishment_products SET product_id = p_target WHERE product_id = s;

    -- 5. История цен
    UPDATE product_price_history SET product_id = p_target WHERE product_id = s;

    -- 6. Алиасы импорта (если таблицы есть в проекте)
    IF to_regclass('public.product_aliases') IS NOT NULL THEN
      DELETE FROM product_aliases a
      WHERE a.product_id = s
        AND EXISTS (
          SELECT 1 FROM product_aliases b
          WHERE b.input_name_normalized = a.input_name_normalized
            AND b.establishment_id IS NOT DISTINCT FROM a.establishment_id
            AND b.product_id = p_target
        );
      UPDATE product_aliases SET product_id = p_target WHERE product_id = s;
    END IF;

    IF to_regclass('public.product_alias_rejections') IS NOT NULL THEN
      DELETE FROM product_alias_rejections a
      WHERE a.product_id = s
        AND EXISTS (
          SELECT 1 FROM product_alias_rejections b
          WHERE b.input_name_normalized = a.input_name_normalized
            AND b.establishment_id IS NOT DISTINCT FROM a.establishment_id
            AND b.product_id = p_target
        );
      UPDATE product_alias_rejections SET product_id = p_target WHERE product_id = s;
    END IF;

    IF to_regclass('public.product_nutrition_links') IS NOT NULL THEN
      DELETE FROM product_nutrition_links x
      WHERE x.product_id = s
        AND EXISTS (SELECT 1 FROM product_nutrition_links t WHERE t.product_id = p_target);
      UPDATE product_nutrition_links SET product_id = p_target WHERE product_id = s;
    END IF;

    DELETE FROM products WHERE id = s;
    n := n + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'merged_sources', n);
END;
$$;

COMMENT ON FUNCTION merge_products_into(UUID, UUID[]) IS
  'Слияние продуктов: p_target остаётся, строки p_sources удаляются после переноса ссылок.';

GRANT EXECUTE ON FUNCTION merge_products_into(UUID, UUID[]) TO anon, authenticated;
