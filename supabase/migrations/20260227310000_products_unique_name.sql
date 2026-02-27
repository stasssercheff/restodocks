-- Добавляем уникальный индекс на lower(trim(name)) чтобы предотвратить
-- создание дублирующихся продуктов на уровне базы данных.
-- Сравнение без учёта регистра и пробелов по краям.

CREATE UNIQUE INDEX IF NOT EXISTS products_name_unique_lower
    ON products (lower(trim(name)));
