/**
 * Supabase config — values inlined at build time from process.env
 */
export async function getSupabaseConfig(): Promise<{ url: string; serviceRoleKey: string } | null> {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? ''
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? ''
  if (!url || !key) return null
  return { url, serviceRoleKey: key }
}
