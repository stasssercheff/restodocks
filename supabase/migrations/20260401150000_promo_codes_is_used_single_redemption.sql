-- Админка и клиент ожидают: промокод «использован», если есть хотя бы одно погашение.
-- Раньше триггер ставил is_used только при COUNT(*) >= 2 (два заведения), из‑за чего
-- одноразовое использование отображалось как «Свободен». Срок действия (expires_at)
-- не отменяет факт погашения — is_used берётся только из promo_code_redemptions.

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_sync_promo_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_pc bigint;
BEGIN
  v_pc := COALESCE(NEW.promo_code_id, OLD.promo_code_id);
  UPDATE public.promo_codes pc
  SET
    is_used = (
      EXISTS (
        SELECT 1
        FROM public.promo_code_redemptions r
        WHERE r.promo_code_id = pc.id
      )
    ),
    used_at = (
      SELECT MIN(r.redeemed_at)
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    used_by_establishment_id = (
      SELECT r.establishment_id
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
      ORDER BY r.redeemed_at ASC
      LIMIT 1
    )
  WHERE pc.id = v_pc;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Пересчитать строки, уже в БД (редкий legacy: только колонки promo_codes без строки в redemptions)
UPDATE public.promo_codes pc
SET
  is_used = (
    EXISTS (
      SELECT 1
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    )
    OR (pc.used_by_establishment_id IS NOT NULL)
  ),
  used_at = COALESCE(
    (
      SELECT MIN(r.redeemed_at)
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    pc.used_at
  ),
  used_by_establishment_id = COALESCE(
    (
      SELECT r.establishment_id
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
      ORDER BY r.redeemed_at ASC
      LIMIT 1
    ),
    pc.used_by_establishment_id
  );
