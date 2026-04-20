# Cloudflare Admin — необходимые секреты

## GitHub Actions (Repository Secrets)

| Секрет | Описание |
|--------|----------|
| `ADMIN_PASSWORD` | Пароль для входа — сохраняется в KV при каждом деплое |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key из Supabase → Settings → API |
| `SUPABASE_URL` | Уже есть (используется как NEXT_PUBLIC_SUPABASE_URL) |
| `RESEND_API_KEY` | (Опционально) Resend API для вкладки «Рассылка»; при деплое также пишется в KV `resend_api_key` |
| `RESEND_FROM_EMAIL` | (Опционально) От кого, например `Restodocks <info@restodocks.com>`; KV `resend_from_email` |

## Как хранится пароль

Пароль берётся из **Cloudflare KV** (namespace `ADMIN_CONFIG`). При каждом деплое workflow записывает `ADMIN_PASSWORD` из GitHub Secret в KV. KV bindings работают надёжно в Workers.

## Ручная установка пароля (если деплой не записал)

```bash
cd admin
printf '%s' 'твой_пароль' > /tmp/admin_pw
npx wrangler kv key put --namespace-id=3f9acc45fa9e41a585e0d9be3e34ab02 "admin_password" --path=/tmp/admin_pw --remote
rm /tmp/admin_pw
```

GitHub Secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_PASSWORD`; для рассылки опционально `RESEND_API_KEY`, `RESEND_FROM_EMAIL`.

---
