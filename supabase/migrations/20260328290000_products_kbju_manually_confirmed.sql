-- Пользователь подтверждает, что КБЖУ в карточке продукта указаны верно (в т.ч. нули),
-- чтобы фоновые сервисы не пытались «дозаполнить» и ТТК не помечала строку как без КБЖУ.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS kbju_manually_confirmed boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.products.kbju_manually_confirmed IS
  'User confirmed nutrition values are intentional (including zeros); skip auto backfill and incomplete-KBJU warnings for this product.';
