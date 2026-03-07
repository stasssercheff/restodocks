import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

export async function GET() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { data: establishments, error } = await supabase
    .from('establishments')
    .select('id, name, address, created_at, default_currency, owner_id, registration_ip, registration_country, registration_city')
    .order('created_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Для каждого заведения считаем сотрудников и находим владельца
  const ids = establishments.map(e => e.id)

  const { data: employees } = await supabase
    .from('employees')
    .select('id, full_name, email, roles, establishment_id')
    .in('establishment_id', ids)

  const result = establishments.map(est => {
    const estEmployees = employees?.filter(e => e.establishment_id === est.id) ?? []
    const owner = estEmployees.find(e => e.roles?.includes('owner'))
    return {
      ...est,
      employee_count: estEmployees.length,
      owner_name: owner?.full_name ?? '—',
      owner_email: owner?.email ?? '—',
    }
  })

  return NextResponse.json(result)
}
