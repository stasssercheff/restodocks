import { NextRequest, NextResponse } from 'next/server'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

async function requireAdmin(): Promise<
  | { ok: true; supabase: SupabaseClient }
  | { ok: false; response: NextResponse }
> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return { ok: false, response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  }
  const config = await getSupabaseConfig()
  if (!config) {
    return { ok: false, response: NextResponse.json({ error: 'Supabase not configured' }, { status: 500 }) }
  }
  return { ok: true, supabase: createClient(config.url, config.serviceRoleKey) }
}

export async function POST(req: NextRequest) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const body = await req.json().catch(() => null)
  const pinCode = (body?.pin_code ?? '').toString().trim().toUpperCase()
  const accountLogin = (body?.account_login ?? '').toString().trim().toLowerCase()
  const supportOperatorLogin = (body?.support_operator_login ?? 'admin').toString().trim()
  if (!pinCode || !accountLogin) {
    return NextResponse.json({ error: 'PIN and account login are required' }, { status: 400 })
  }

  const { data: est, error: estErr } = await supabase
    .from('establishments')
    .select('id, name, pin_code, support_access_enabled')
    .eq('pin_code', pinCode)
    .maybeSingle()
  if (estErr) return NextResponse.json({ error: estErr.message }, { status: 500 })
  if (!est) return NextResponse.json({ error: 'Заведение по PIN не найдено' }, { status: 404 })
  if (est.support_access_enabled !== true) {
    return NextResponse.json({ error: 'Владелец отключил доступ техподдержки' }, { status: 403 })
  }

  const { data: emp, error: empErr } = await supabase
    .from('employees')
    .select('id, email, full_name, roles, is_active')
    .eq('establishment_id', est.id)
    .eq('email', accountLogin)
    .eq('is_active', true)
    .maybeSingle()
  if (empErr) return NextResponse.json({ error: empErr.message }, { status: 500 })
  if (!emp) {
    return NextResponse.json({ error: 'Логин не найден в этом заведении' }, { status: 404 })
  }

  const { data: activeRows, error: activeErr } = await supabase
    .from('support_access_audit_log')
    .select('id')
    .eq('establishment_id', est.id)
    .is('ended_at', null)
    .limit(1)
  if (activeErr) return NextResponse.json({ error: activeErr.message }, { status: 500 })
  if ((activeRows ?? []).length > 0) {
    return NextResponse.json({ error: 'Сеанс техподдержки уже активен для этого заведения' }, { status: 409 })
  }

  const { error: insErr } = await supabase.from('support_access_audit_log').insert({
    establishment_id: est.id,
    support_operator_login: supportOperatorLogin,
    account_login: accountLogin,
    pin_code: pinCode,
  })
  if (insErr) return NextResponse.json({ error: insErr.message }, { status: 500 })

  return NextResponse.json({
    ok: true,
    establishment: est,
    account: emp,
  })
}

export async function PATCH(req: NextRequest) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const body = await req.json().catch(() => null)
  const establishmentId = (body?.establishment_id ?? '').toString().trim()
  if (!establishmentId) {
    return NextResponse.json({ error: 'establishment_id is required' }, { status: 400 })
  }

  const { data: activeRows, error: activeErr } = await supabase
    .from('support_access_audit_log')
    .select('id')
    .eq('establishment_id', establishmentId)
    .is('ended_at', null)
    .order('started_at', { ascending: false })
    .limit(1)
  if (activeErr) return NextResponse.json({ error: activeErr.message }, { status: 500 })
  const active = (activeRows ?? [])[0]
  if (!active) {
    return NextResponse.json({ error: 'Активный сеанс не найден' }, { status: 404 })
  }

  const now = new Date().toISOString()
  const { error: updErr } = await supabase
    .from('support_access_audit_log')
    .update({ ended_at: now, updated_at: now })
    .eq('id', active.id)
  if (updErr) return NextResponse.json({ error: updErr.message }, { status: 500 })

  return NextResponse.json({ ok: true })
}

export async function GET(req: NextRequest) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const establishmentId = req.nextUrl.searchParams.get('establishment_id')?.trim() ?? ''
  if (!establishmentId) return NextResponse.json({ error: 'establishment_id is required' }, { status: 400 })

  const { data, error } = await supabase
    .from('support_access_audit_log')
    .select('id, support_operator_login, account_login, started_at, ended_at')
    .eq('establishment_id', establishmentId)
    .order('started_at', { ascending: false })
    .limit(100)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data ?? [])
}
