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

async function hasTable(supabase: SupabaseClient, table: string): Promise<boolean> {
  const { error } = await supabase.from(table).select('id').limit(1)
  if (!error) return true
  const msg = `${error.message ?? ''} ${error.details ?? ''}`.toLowerCase()
  if (msg.includes('could not find the table') || msg.includes('relation') && msg.includes('does not exist')) {
    return false
  }
  return true
}

export async function POST(req: NextRequest) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const body = await req.json().catch(() => null)
  const accountLogin = (body?.account_login ?? '').toString().trim().toLowerCase()
  const supportOperatorLogin = (body?.support_operator_login ?? 'admin').toString().trim()
  const appOrigin = (body?.app_origin ?? '').toString().trim().replace(/\/+$/, '')
  if (!accountLogin) {
    return NextResponse.json({ error: 'Account login is required' }, { status: 400 })
  }

  const { data: emp, error: empErr } = await supabase
    .from('employees')
    .select('id, email, full_name, roles, is_active, establishment_id')
    .eq('email', accountLogin)
    .eq('is_active', true)
    .maybeSingle()
  if (empErr) return NextResponse.json({ error: empErr.message }, { status: 500 })
  if (!emp) {
    return NextResponse.json({ error: 'Логин не найден' }, { status: 404 })
  }

  const establishmentId = (emp as { establishment_id?: string | null }).establishment_id?.toString().trim() ?? ''
  if (!establishmentId) {
    return NextResponse.json({ error: 'Для логина не найдено заведение' }, { status: 404 })
  }
  const { data: est, error: estErr } = await supabase
    .from('establishments')
    .select('id, name, pin_code, support_access_enabled')
    .eq('id', establishmentId)
    .maybeSingle()
  if (estErr) return NextResponse.json({ error: estErr.message }, { status: 500 })
  if (!est) return NextResponse.json({ error: 'Заведение не найдено' }, { status: 404 })
  if (est.support_access_enabled !== true) {
    return NextResponse.json({ error: 'Владелец отключил доступ техподдержки' }, { status: 403 })
  }

  const pinForAudit = (est.pin_code ?? '').toString().trim().toUpperCase()
  if (!pinForAudit) {
    return NextResponse.json({ error: 'PIN компании не задан у пользователя' }, { status: 403 })
  }

  const hasAudit = await hasTable(supabase, 'support_access_audit_log')
  const hasEvents = await hasTable(supabase, 'support_access_event_log')
  if (!hasAudit || !hasEvents) {
    return NextResponse.json(
      { error: 'Не применены миграции журнала техподдержки в Supabase (support_access_audit_log / support_access_event_log).' },
      { status: 500 },
    )
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
    pin_code: pinForAudit,
  })
  if (insErr) return NextResponse.json({ error: insErr.message }, { status: 500 })

  const { error: evErr } = await supabase.from('support_access_event_log').insert({
    establishment_id: est.id,
    event_type: 'support_login',
    support_operator_login: supportOperatorLogin,
    account_login: accountLogin,
  })
  if (evErr) return NextResponse.json({ error: evErr.message }, { status: 500 })

  const redirectTo = appOrigin
    ? `${appOrigin}/auth/confirm`
    : 'https://restodocks-beta.pages.dev/auth/confirm'
  const { data: linkData, error: linkErr } = await supabase.auth.admin.generateLink({
    type: 'magiclink',
    email: accountLogin,
    options: { redirectTo },
  })
  if (linkErr) return NextResponse.json({ error: linkErr.message }, { status: 500 })
  const actionLink = linkData?.properties?.action_link
  if (!actionLink) {
    return NextResponse.json({ error: 'Не удалось сгенерировать ссылку входа' }, { status: 500 })
  }

  return NextResponse.json({
    ok: true,
    establishment: est,
    account: emp,
    action_link: actionLink,
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

  const { error: evErr } = await supabase.from('support_access_event_log').insert({
    establishment_id: establishmentId,
    event_type: 'support_logout',
  })
  if (evErr) return NextResponse.json({ error: evErr.message }, { status: 500 })

  return NextResponse.json({ ok: true })
}

export async function GET(req: NextRequest) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const establishmentId = req.nextUrl.searchParams.get('establishment_id')?.trim() ?? ''
  if (!establishmentId) return NextResponse.json({ error: 'establishment_id is required' }, { status: 400 })

  const { data, error } = await supabase
    .from('support_access_event_log')
    .select('id, event_type, support_operator_login, account_login, created_at')
    .eq('establishment_id', establishmentId)
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data ?? [])
}
