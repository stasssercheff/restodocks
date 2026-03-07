import { getCloudflareContext } from '@opennextjs/cloudflare'

export async function getAdminPassword(): Promise<string> {
  const p = (process.env.ADMIN_PASSWORD ?? '').trim()
  if (p) return p
  try {
    const { env } = await getCloudflareContext()
    const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } }).ADMIN_CONFIG
    if (kv) {
      const v = await kv.get('admin_password')
      return (v ?? '').trim()
    }
  } catch {
    // ignore
  }
  return ''
}

export async function getSupabaseConfig(): Promise<{ url: string; serviceRoleKey: string } | null> {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? ''
  if (!url || !key) return null
  return { url, serviceRoleKey: key }
}
