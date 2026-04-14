import { NextResponse } from 'next/server'
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
    const { data: rpcData, error } = await supabase.rpc('admin_delete_establishment', {
      p_establishment_id: id,
    })
    if (error) {
      const err = error as {
        message?: string
        details?: string
        hint?: string
        code?: string
      }
      const msg = [err.message, err.details, err.hint].filter(Boolean).join(' — ') || String(error)
      console.error('Admin delete establishment error:', error)
      const hint =
        /function public\.admin_delete_establishment|does not exist|42883/i.test(msg)
          ? ' Выполните миграции Supabase: 20260406234000_admin_delete_establishment_returns_jsonb.sql и зависимости _delete_establishment_cascade.'
          : ''
      return NextResponse.json({ error: msg + hint, code: err.code }, { status: 500 })
    }
    return NextResponse.json({ ok: true, result: rpcData ?? null })
  } catch (e) {
    console.error('Admin delete establishment error:', e)
    const msg =
      e instanceof Error
        ? e.message
        : typeof e === 'object' &&
            e !== null &&
            'message' in e &&
            typeof (e as { message: unknown }).message === 'string'
          ? (e as { message: string }).message
          : 'Delete failed'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}
