# restodocks.com — фикс логина при Cloudflare Proxy

## Проблема
- restodocks.com (Proxied) — логин ломается
- restodocks-2u8.pages.dev — работает
- Без proxy — нет доступа из других стран

## Решение (по шагам)

### 1. Configuration Rule: Bypass Cache для restodocks.com
Cloudflare → restodocks.com → **Rules** → **Configuration Rules** → **Create rule**

| Поле | Значение |
|------|----------|
| Rule name | `Bypass cache restodocks.com` |
| When | **Hostname** equals `restodocks.com` |
| Then | **Cache Level** → **Bypass** |

**Deploy** → **Save and Deploy**

### 2. Purge Everything
**Caching** → **Configuration** → **Purge Everything**

### 3. Проверка
Войти на https://restodocks.com — логин должен работать.

---

### Если не помогло: Development Mode (диагностика)
Overview → **Development Mode** → включить.  
Проверить логин. Если заработало — проблема в кеше/оптимизациях Cloudflare.  
Development Mode выключить через 3 часа (авто-выключение).

### Если нужен Pro
Rocket Loader и Auto Minify на Free могут быть скрыты. На Pro их можно отключить.  
Либо: тариф Workers Paid ($5/мес) — Worker для обхода.
