import { getCloudflareContext } from '@opennextjs/cloudflare'

/// Пароль админки: секрет Worker `ADMIN_PASSWORD` (Dashboard) → KV `admin_password` (деплой из GitHub) → `process.env` (локальный dev).
/// Раньше сначала шли в `process.env` — на Workers у OpenNext он часто пуст, и брался KV с другим значением, хотя в Dashboard уже задан верный пароль.
export async function getAdminPassword(): Promise<string> {
  try {
    const { env } = await getCloudflareContext()
    const e = env as Record<string, unknown>
    const bound = e.ADMIN_PASSWORD
    if (typeof bound === 'string' && bound.trim()) {
      return bound.trim()
    }
    const kv = e.ADMIN_CONFIG as
      | { get: (k: string) => Promise<string | null> }
      | undefined
    if (kv) {
      const v = await kv.get('admin_password')
      const fromKv = (v ?? '').trim()
      if (fromKv) return fromKv
    }
  } catch {
    // не Cloudflare (next dev) — ниже process.env
  }
  return (process.env.ADMIN_PASSWORD ?? '').trim()
}

export async function getSupabaseConfig(): Promise<{ url: string; serviceRoleKey: string } | null> {
  let url = (process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').trim()
  let key = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim()
  if (!url || !key) {
    try {
      const { env } = await getCloudflareContext()
      const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } })
        .ADMIN_CONFIG
      if (kv) {
        url = ((await kv.get('supabase_url')) ?? url).trim()
        key = ((await kv.get('supabase_service_role_key')) ?? key).trim()
      }
    } catch {
      // ignore
    }
  }
  if (!url || !key) return null
  return { url, serviceRoleKey: key }
}

const DEFAULT_RESEND_FROM = 'Restodocks <info@restodocks.com>'

/** Ключ Resend и адрес отправителя для рассылки из админки (process.env, KV, Cloudflare bindings). */
export async function getResendConfig(): Promise<{ apiKey: string; fromEmail: string } | null> {
  let apiKey = (process.env.RESEND_API_KEY ?? '').trim()
  let fromEmail = (process.env.RESEND_FROM_EMAIL ?? '').trim() || DEFAULT_RESEND_FROM

  try {
    const { env } = await getCloudflareContext()
    const e = env as Record<string, unknown>
    const boundKey = e.RESEND_API_KEY
    if (typeof boundKey === 'string' && boundKey.trim()) apiKey = boundKey.trim()
    const boundFrom = e.RESEND_FROM_EMAIL
    if (typeof boundFrom === 'string' && boundFrom.trim()) fromEmail = boundFrom.trim()
  } catch {
    /* не Cloudflare */
  }

  if (!apiKey) {
    try {
      const { env } = await getCloudflareContext()
      const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } }).ADMIN_CONFIG
      if (kv) {
        const v = await kv.get('resend_api_key')
        if (v?.trim()) apiKey = v.trim()
        const fe = await kv.get('resend_from_email')
        if (fe?.trim()) fromEmail = fe.trim()
      }
    } catch {
      /* ignore */
    }
  }

  if (!apiKey) return null
  if (!fromEmail) fromEmail = DEFAULT_RESEND_FROM
  return { apiKey, fromEmail }
}
