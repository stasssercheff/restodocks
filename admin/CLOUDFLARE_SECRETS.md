# Cloudflare Admin — необходимые секреты

Для работы админки на Cloudflare Workers нужны секреты.

## GitHub Actions (Repository Secrets)

Добавь в **Settings → Secrets and variables → Actions**:

| Секрет | Описание |
|--------|----------|
| `ADMIN_PASSWORD` | Пароль для входа в админку |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key из Supabase → Settings → API |
| `SUPABASE_URL` | Уже есть (используется как NEXT_PUBLIC_SUPABASE_URL) |

## Cloudflare Dashboard (альтернатива)

Можно задать вручную: **Workers & Pages** → restodocks-admin → **Settings** → **Variables and Secrets**:

- `ADMIN_PASSWORD` (Secret)
- `SUPABASE_SERVICE_ROLE_KEY` (Secret)
- `SUPABASE_URL` (Secret или Variable)

Важно: **не включать Encrypt** при сохранении — иначе значение может не совпадать с ожидаемым.
