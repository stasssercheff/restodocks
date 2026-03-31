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
  const supabase = createClient(config.url, config.serviceRoleKey)
  return { ok: true, supabase }
}

/** Лимит доп. заведений на заведение (null = сброс к глобальной настройке) */
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response

  const { id } = await params
  if (!id) return NextResponse.json({ error: 'Establishment ID required' }, { status: 400 })

  let body: { max_additional_establishments_override?: number | null }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const raw = body.max_additional_establishments_override
  if (raw === undefined) {
    return NextResponse.json({ error: 'max_additional_establishments_override required (number or null)' }, { status: 400 })
  }
  if (raw !== null) {
    const num = Number(raw)
    if (!Number.isInteger(num) || num < 0 || num > 999) {
      return NextResponse.json({ error: 'max_additional_establishments_override must be null or 0–999' }, { status: 400 })
    }
  }

  const { data, error } = await auth.supabase
    .from('establishments')
    .update({
      max_additional_establishments_override: raw,
      updated_at: new Date().toISOString(),
    })
    .eq('id', id)
    .select('id, max_additional_establishments_override')
    .single()

  if (error) {
    console.error('Admin PATCH establishment override error:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
  return NextResponse.json(data)
}

export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const { id } = await params
  if (!id) return NextResponse.json({ error: 'Establishment ID required' }, { status: 400 })

  try {
    const { error } = await supabase.rpc('_delete_establishment_cascade', { p_establishment_id: id })
    if (error) throw error
    return NextResponse.json({ ok: true })
  } catch (e) {
    console.error('Admin delete establishment error:', e)
    return NextResponse.json(
      { error: e instanceof Error ? e.message : 'Delete failed' },
      { status: 500 }
    )
  }
}
