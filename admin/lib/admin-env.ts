import { getCloudflareContext } from '@opennextjs/cloudflare'

type WorkerEnv = {
  ADMIN_PASSWORD?: string
  SUPABASE_SERVICE_ROLE_KEY?: string
  SUPABASE_URL?: string
  NEXT_PUBLIC_SUPABASE_URL?: string
  NEXT_PUBLIC_SUPABASE_ANON_KEY?: string
}

async function getEnv(): Promise<WorkerEnv> {
  try {
    const { env } = await getCloudflareContext()
    return env as WorkerEnv
  } catch {
    return {
      ADMIN_PASSWORD: process.env.ADMIN_PASSWORD,
      SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
      SUPABASE_URL: process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    }
  }
}

export async function getAdminPassword(): Promise<string | undefined> {
  const env = await getEnv()
  return env.ADMIN_PASSWORD
}

export async function getSupabaseConfig(): Promise<{ url: string; serviceRoleKey: string } | null> {
  const env = await getEnv()
  const url = env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  const key = env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY ?? ''
  if (!url || !key) return null
  return { url, serviceRoleKey: key }
}
