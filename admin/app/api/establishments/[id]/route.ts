import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

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
