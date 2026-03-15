# Перевод на вьетнамский (vi)

Скрипты перевода UI (`generate_vietnamese_translations.py`, `translate_localizable_deepl.py`):
- создают бэкап `localizable.json.bak.YYYYMMDD_HHMMSS` перед изменением;
- слияние: новые переводы перезаписывают существующие, уже имеющиеся ключи сохраняются.

## 1. Интерфейс (localizable.json)

### Вариант A: через DeepL

```bash
cd restodocks_flutter
python3 scripts/translate_localizable_deepl.py
```

(Требует SUPABASE_URL и SUPABASE_ANON_KEY в env или в lib/main.dart)

### Вариант B: через Google Translate (без Supabase)

```bash
pip install deep-translator
cd restodocks_flutter
python3 scripts/generate_vietnamese_translations.py
```

## 2. Продукты (номенклатура)

### Важно: деплой Edge Function

Перед пакетным переводом продуктов нужно задеплоить Edge Function:

```bash
cd restodocks_flutter
supabase functions deploy auto-translate-product
```

Убедитесь, что в Supabase Dashboard → Project Settings → Edge Functions задан секрет `DEEPL_API_KEY`.

### Пакетный перевод

```bash
cd restodocks_flutter
python3 scripts/batch_translate_products_to_spanish.py
```

Скрипт переводит на все языки (ru, en, es, tr, vi) через DeepL. **Без `--max-batches`** обрабатываются все продукты.

Если вьетнамский не появился — попробуйте принудительно:
```bash
python3 scripts/batch_translate_products_to_spanish.py --force-vi
```

### Автоперевод при смене языка

При выборе вьетнамского в настройках приложение фоново переводит продукты, у которых нет имени на vi.
