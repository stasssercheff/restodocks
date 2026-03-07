import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { verifySessionToken } from '@/lib/session'

function getServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? ''
  return createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY!)
}

async function checkAuth(): Promise<boolean> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = process.env.ADMIN_PASSWORD
  if (!session || !adminPassword) return false
  return verifySessionToken(session, adminPassword)
}

export async function GET() {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from('promo_codes')
    .select('*, establishments:used_by_establishment_id(name)')
    .order('created_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

export async function POST(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json()

  // Server-side validation
  if (!body.code || typeof body.code !== 'string' || body.code.trim().length === 0 || body.code.length > 64) {
    return NextResponse.json({ error: 'Invalid promo code: must be a non-empty string up to 64 characters' }, { status: 400 })
  }
  if (body.note !== undefined && body.note !== null && (typeof body.note !== 'string' || body.note.length > 500)) {
    return NextResponse.json({ error: 'Invalid note: must be a string up to 500 characters' }, { status: 400 })
  }
  if (body.max_employees !== undefined && body.max_employees !== null) {
    const n = Number(body.max_employees)
    if (!Number.isInteger(n) || n < 1 || n > 10000) {
      return NextResponse.json({ error: 'Invalid max_employees: must be an integer between 1 and 10000' }, { status: 400 })
    }
  }
  if (body.starts_at && isNaN(Date.parse(body.starts_at))) {
    return NextResponse.json({ error: 'Invalid starts_at: must be a valid ISO date string' }, { status: 400 })
  }
  if (body.expires_at && isNaN(Date.parse(body.expires_at))) {
    return NextResponse.json({ error: 'Invalid expires_at: must be a valid ISO date string' }, { status: 400 })
  }

  const supabase = getServiceClient()
  const { data, error } = await supabase
    .from('promo_codes')
    .insert({
      code: body.code.trim(),
      note: body.note || null,
      starts_at: body.starts_at || null,
      expires_at: body.expires_at || null,
      max_employees: body.max_employees ?? null,
    })
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data)
}

export async function PATCH(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json()
  const { id, ...updates } = body
  const allowed = ['code', 'note', 'starts_at', 'expires_at', 'is_used', 'used_at', 'used_by_establishment_id', 'max_employees'] as const
  const patch = Object.fromEntries(
    Object.entries(updates).filter(([k]) => allowed.includes(k as typeof allowed[number]))
  )
  const supabase = getServiceClient()
  const { error } = await supabase
    .from('promo_codes')
    .update(patch)
    .eq('id', id)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}

export async function DELETE(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { id } = await req.json()
  const supabase = getServiceClient()
  const { error } = await supabase
    .from('promo_codes')
    .delete()
    .eq('id', id)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
