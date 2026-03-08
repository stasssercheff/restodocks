# Продукты: переводы и КБЖУ

## 1. Переводы продуктов (ru, en, es)

База продуктов `products` хранит названия в колонке `names` (JSONB):
```json
{"ru": "Молоко", "en": "Milk", "es": "Leche"}
```

### Языки в системе
- **ru** — русский
- **en** — английский  
- **es** — испанский

### Скрипты
- **upload_missing_products.py** — при добавлении новых продуктов пишет `names: {ru, en, es}`. Словарь `EN_ES` — испанские переводы; fallback на `en`, если нет перевода.
- **restodocks_flutter/scripts/batch_translate_products_to_spanish.py** — добавляет `es` уже существующим продуктам (ru/en без es) через Edge Function `auto-translate-product`.

### Запуск добавления ES к существующим продуктам
```bash
export SUPABASE_URL=https://YOUR_PROJECT.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=...
cd restodocks_flutter && python3 scripts/batch_translate_products_to_spanish.py
```

---

## 2. КБЖУ из открытых источников

Колонки в `products`: `calories`, `protein`, `fat`, `carbs` (per 100g).

**Источник**: [Open Food Facts](https://world.openfoodfacts.org/) — бесплатный API, без ключа.

### Скрипт `scripts/fetch_kbju_openfoodfacts.py`
- Ищет продукт по имени (en или ru)
- Берёт nutriments: `energy-kcal_100g`, `proteins_100g`, `fat_100g`, `carbohydrates_100g`
- Обновляет только строки, где КБЖУ пустые (или по флагу — перезаписывать)
- Лимит запросов: ~100/мин

### Запуск
```bash
pip install requests  # если нет
python3 scripts/fetch_kbju_openfoodfacts.py [SERVICE_ROLE_KEY]
```

### Важно
- **КБЖУ только в БД** — в интерфейсе нигде не отображается (колонки `calories`, `protein`, `fat`, `carbs` в `products` не выводятся в UI).
- Если Open Food Facts не находит продукт — поле остаётся NULL.
