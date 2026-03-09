# Cloudflare: HTTP→HTTPS редирект и устранение 5xx для индексации Google

Если в Google Search Console «Ошибка сервера (5xx)» на `http://www.restodocks.com/`, нужно настроить:
1. Редирект HTTP → HTTPS (301)
2. Режим Always Use HTTPS
3. Правила для www и apex

---

## Шаг 1. SSL/TLS режим

1. Откройте [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Выберите домен **restodocks.com**
3. В левом меню: **SSL/TLS**
4. Вкладка **Overview**
5. **SSL/TLS encryption mode** → выберите **Full** или **Full (strict)**
   - Full: Cloudflare шифрует трафик к origin
   - Full (strict): то же + проверка сертификата origin
6. Нажмите **Save** (если меняли)

---

## Шаг 2. Always Use HTTPS

1. В том же домене **restodocks.com** в Cloudflare
2. **SSL/TLS** → вкладка **Edge Certificates**
3. Найдите переключатель **Always Use HTTPS**
4. Включите его (ON)
5. В результате: `http://www.restodocks.com` → `https://www.restodocks.com` (301)

**Если Always Use HTTPS включён** — Шаг 3 можно пропустить. Этого достаточно для редиректа HTTP → HTTPS. Проверьте через `curl -I http://www.restodocks.com/` — должен быть 301 и Location: https://...

---

## Шаг 3. Redirect Rules (только если Always Use HTTPS не помог)

Если после Шага 2 всё ещё 5xx — добавьте явное правило.

**Где искать:** Rules → Overview → Create rule → Redirect Rule

---

### Блок «If incoming requests match…»

Используйте **Wildcard pattern** (не Custom filter expression — он может выдавать ошибки разбора).

1. Выберите **Wildcard pattern**.
2. В поле **Request URL** вставьте:
   ```
   http://www.restodocks.com/*
   ```
   Это ловит все HTTP-запросы на www. Для apex добавьте отдельное правило: `http://restodocks.com/*`.

---

### Блок «Then…» (для Wildcard pattern)

1. **Type** — выберите **Static**.
2. **URL** (Target URL) — вставьте:
   ```
   https://www.restodocks.com/${1}
   ```
   `${1}` — захваченный путь из `*` (например, `login` или пусто для `/`).
3. **Status code** — **301**.
4. **Preserve query string** — **обязательно включите** (иначе теряются `token_hash` и `type` в ссылках подтверждения email).
5. Нажмите **Deploy**.

---

## Шаг 4. Apex (restodocks.com) → www.restodocks.com

Если `restodocks.com` (без www) ведёт на `www.restodocks.com`. Обычно это уже настроено через Namecheap (Redirect Domain). Если нужно задать в Cloudflare:

1. **Rules** → **Create rule** → **Redirect Rule** (см. Шаг 3)
2. **Rule name:** `Apex to WWW`
3. **When:**
   - Field: **Hostname**
   - Operator: **equals**
   - Value: `restodocks.com`
4. **Then:**
   - Type: **Dynamic**
   - Expression: `concat("https://www.restodocks.com", http.request.uri.path)`
   - Status code: **301**
   - **Preserve query string: включить** (иначе ломается подтверждение email)

---

## Шаг 5. Google Search Console

1. [Search Console](https://search.google.com/search-console)
2. Убедитесь, что есть свойство **https://www.restodocks.com** (URL prefix)
3. **Settings** (шестерёнка) → **Change of address**
4. Если используете www как основной — выберите `https://www.restodocks.com`
5. В **Sitemaps** можно добавить `https://www.restodocks.com/sitemap.xml` (если sitemap есть)

---

## Проверка

- `http://www.restodocks.com/` → должен редиректить на `https://www.restodocks.com/` (301)
- `http://restodocks.com/` → `https://www.restodocks.com/` (301)
- `https://restodocks.com/` → `https://www.restodocks.com/` (301, если настроено apex→www)
- `https://www.restodocks.com/` → открывается без ошибок (200)

Проверить:
```bash
curl -I http://www.restodocks.com/
# Ожидается: HTTP/1.1 301 ... Location: https://www.restodocks.com/
```

---

## Порядок правил

Cloudflare применяет правила сверху вниз. Рекомендуемый порядок:
1. HTTP → HTTPS (Always Use HTTPS или Redirect Rule)
2. Apex → www (если нужен)
3. Остальные правила
