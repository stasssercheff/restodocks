import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

function skipGeo(ip: string): boolean {
  if (!ip || ip === 'unknown') return true
  if (ip === '127.0.0.1') return true
  if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true
  return false
}

async function fetchGeoFromIpinfo(ip: string): Promise<{ country?: string; city?: string }> {
  const res = await fetch(`https://ipinfo.io/${encodeURIComponent(ip)}`, {
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) return {}
  const data = (await res.json()) as { country?: string; city?: string; bogon?: boolean }
  if (data.bogon) return {}
  return { country: data.country, city: data.city }
}

async function fetchGeoFromIpApiCo(ip: string): Promise<{ country?: string; city?: string }> {
  const res = await fetch(`https://ipapi.co/${encodeURIComponent(ip)}/json/`, {
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) return {}
  const data = (await res.json()) as { country_name?: string; city?: string; error?: boolean }
  if (data.error) return {}
  return {
    country: data.country_name,
    city: data.city,
  }
}

async function fetchGeo(ip: string): Promise<{ country?: string; city?: string }> {
  try {
    const a = await fetchGeoFromIpinfo(ip)
    if (a.country || a.city) return a
  } catch {
    // try fallback
  }
  try {
    return await fetchGeoFromIpApiCo(ip)
  } catch {
    return {}
  }
}

export async function POST() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { data: establishments, error: fetchError } = await supabase
    .from('establishments')
    .select('id, name, registration_ip')
    .not('registration_ip', 'is', null)

  if (fetchError) return NextResponse.json({ error: fetchError.message }, { status: 500 })
  const list = establishments ?? []

  let updated = 0
  const errors: string[] = []

  for (const est of list) {
    const ip = est.registration_ip
    if (!ip || skipGeo(ip)) continue

    const geo = await fetchGeo(ip)
    if (!geo.country && !geo.city) continue

    const { error: updateError } = await supabase
      .from('establishments')
      .update({
        registration_country: geo.country ?? null,
        registration_city: geo.city ?? null,
      })
      .eq('id', est.id)

    if (updateError) {
      errors.push(`${est.name}: ${updateError.message}`)
    } else {
      updated++
    }

    // Небольшая задержка, чтобы не упереться в лимит ipinfo.io
    await new Promise((r) => setTimeout(r, 200))
  }

  return NextResponse.json({ updated, total: list.length, errors })
}
