# Редирект www → apex в Cloudflare

Пошаговая настройка редиректа `www.restodocks.com` → `restodocks.com`, чтобы устранить ошибку 522 и проблемы с индексацией Google.

---

## Шаг 1. Войти в Cloudflare

1. Откройте браузер и перейдите на [https://dash.cloudflare.com](https://dash.cloudflare.com)
2. Войдите в аккаунт
3. В списке сайтов найдите и нажмите **restodocks.com**

---

## Шаг 2. Перейти в Redirect Rules

1. В левом меню домена выберите **Rules**
2. В подменю откройте вкладку **Redirect Rules**
3. Нажмите кнопку **Create rule** (справа вверху)

---

## Шаг 3. Выбрать тип правила

Появится окно создания правила. Убедитесь, что выбран тип **Redirect Rule** (а не Config Rule или Rate Limiting Rule).

---

## Шаг 4. Заполнить блок «If incoming requests match…»

### 4.1. Имя правила

В поле **Rule name** вверху введите:

```
www to apex
```

### 4.2. Условие (When incoming requests match)

1. В выпадающем списке выберите **Edit expression** (или **Custom filter expression**)
2. Либо выберите простой режим и заполните:
   - **Field:** `Hostname`
   - **Operator:** `equals`
   - **Value:** `www.restodocks.com`

Если используется Custom filter expression, вставьте:

```
(http.host eq "www.restodocks.com")
```

Это условие срабатывает на все запросы к `www.restodocks.com` (любой путь: `/`, `/login`, `/menu` и т.д.).

---

## Шаг 5. Заполнить блок «Then…»

### 5.1. Type

В поле **Type** выберите **Dynamic**.

(Static — для одного фиксированного URL; Dynamic — когда целевой URL зависит от пути и параметров.)

### 5.2. Expression

В поле **Expression** вставьте одно из выражений (оба рабочие):

**Вариант 1 (с path и query):**
```
concat("https://restodocks.com", http.request.uri.path)
```
Query string (параметры после `?`) нужно сохранять отдельно — см. п. 5.4.

**Вариант 2 (рекомендуемый, с сохранением пути и query):**
```
concat("https://restodocks.com", http.request.uri.path, if(http.request.uri.query ne "", concat("?", http.request.uri.query), ""))
```

Это перенаправит:
- `https://www.restodocks.com/` → `https://restodocks.com/`
- `https://www.restodocks.com/login` → `https://restodocks.com/login`
- `https://www.restodocks.com/auth/confirm?token_hash=xxx&type=email` → `https://restodocks.com/auth/confirm?token_hash=xxx&type=email`

### 5.3. Status code

В поле **Status code** выберите **301 — Permanent Redirect**.

### 5.4. Preserve query string

Включите переключатель **Preserve query string** (если он есть). Это сохранит параметры (`?token_hash=...&type=...`) при редиректе — важно для подтверждения email и других ссылок.

Если используете Вариант 2 из п. 5.2, query уже учтён в выражении, но переключатель всё равно лучше включить.

---

## Шаг 6. Сохранить и применить

1. Проверьте, что правило в списке отображается первым или выше других Redirect Rules (приоритет — сверху вниз)
2. Нажмите **Deploy** (или **Save**)

Правило начнёт работать сразу.

---

## Шаг 7. Проверка

Выполните в терминале:

```bash
curl -I https://www.restodocks.com/
```

Ожидаемый результат:

```
HTTP/2 301
location: https://restodocks.com/
```

Далее откройте в браузере `https://www.restodocks.com/` — должна открыться `https://restodocks.com/` без ошибки 522.

---

## Порядок правил (важно)

Cloudflare применяет Redirect Rules сверху вниз. Рекомендуемый порядок:

1. **www to apex** — первым, чтобы `www.restodocks.com` сразу уходил на apex
2. HTTP → HTTPS (если есть отдельное правило)
3. Остальные правила

Чтобы изменить порядок: перетащите правило в списке или нажмите на три точки рядом с правилом → **Move**.

---

## Если что-то не работает

### Редирект не срабатывает

- Убедитесь, что правило **Enabled** (не выключено)
- Проверьте условие: `http.host eq "www.restodocks.com"` — без лишних пробелов, в кавычках
- Очистите кэш браузера или проверьте в режиме инкогнито

### Всё равно 522

522 означает, что Cloudflare не может достучаться до origin. Redirect Rule выполняется **до** обращения к origin, поэтому редирект должен сработать и 522 исчезнуть. Если 522 остаётся:

- Подождите 1–2 минуты после сохранения правила
- Убедитесь, что сохранена именно **Redirect Rule**, а не Page Rule или другой тип

### Потерялись параметры при редиректе (например, подтверждение email)

- Включите **Preserve query string**
- Либо используйте Вариант 2 для Expression (см. п. 5.2)

---

## Итог

| До | После |
|----|-------|
| https://www.restodocks.com/ → 522 | https://www.restodocks.com/ → 301 → https://restodocks.com/ (200) |
| Google видит 5xx на www | www редиректит на apex, 5xx исчезает |
