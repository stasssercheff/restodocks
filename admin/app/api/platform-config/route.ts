import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

async function checkAuth(): Promise<boolean> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword) return false
  return verifySessionToken(session, adminPassword)
}

export async function GET() {
  if (!(await checkAuth())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { data, error } = await supabase
    .from('platform_config')
    .select('key, value')
    .in('key', ['max_establishments_per_owner'])

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const maxEstablishments = data?.find(r => r.key === 'max_establishments_per_owner')
  const value = maxEstablishments?.value
  const num = typeof value === 'number' ? value : (typeof value === 'string' ? parseInt(value, 10) : 5)
  return NextResponse.json({ max_establishments_per_owner: isNaN(num) ? 5 : Math.max(0, num) })
}

export async function PATCH(req: NextRequest) {
  if (!(await checkAuth())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json()
  const max = body.max_establishments_per_owner
  if (max === undefined || max === null) {
    return NextResponse.json({ error: 'max_establishments_per_owner required' }, { status: 400 })
  }
  const num = Number(max)
  if (!Number.isInteger(num) || num < 0 || num > 999) {
    return NextResponse.json({ error: 'max_establishments_per_owner must be 0–999' }, { status: 400 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { error } = await supabase
    .from('platform_config')
    .upsert(
      { key: 'max_establishments_per_owner', value: num, updated_at: new Date().toISOString() },
      { onConflict: 'key' }
    )

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true, max_establishments_per_owner: num })
}
