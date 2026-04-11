import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'
import { buildSecuritySnapshot } from '@/lib/security-snapshot'

export const dynamic = 'force-dynamic'

function envTrim(name: string): string | undefined {
  const v = process.env[name]?.trim()
  return v || undefined
}

export async function GET() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const config = await getSupabaseConfig()
  const supabaseUrl = config?.url ?? ''

  const payload = await buildSecuritySnapshot({
    supabaseUrl,
    cfToken: envTrim('CLOUDFLARE_API_TOKEN'),
    zoneTag: envTrim('CLOUDFLARE_ZONE_ID'),
    accountId: envTrim('CLOUDFLARE_ACCOUNT_ID'),
  })

  return NextResponse.json(payload)
}
