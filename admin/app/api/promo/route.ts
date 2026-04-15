import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'
import { isAllowedPromoGrantType, isSelectablePromoGrantTier } from '@/lib/promo-tiers'

const EMPLOYEE_PACK_OPTIONS = new Set([0, 5, 8, 12, 15])
const BRANCH_PACK_OPTIONS = new Set([0, 1, 3, 5, 10])

export const dynamic = 'force-dynamic'

async function checkAuth(): Promise<boolean> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword) return false
  return verifySessionToken(session, adminPassword)
}

export async function GET() {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)
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
  if (body.activation_duration_days !== undefined && body.activation_duration_days !== null) {
    const n = Number(body.activation_duration_days)
    if (!Number.isInteger(n) || n < 1 || n > 36500) {
      return NextResponse.json(
        { error: 'Invalid activation_duration_days: must be an integer between 1 and 36500' },
        { status: 400 },
      )
    }
  }
  const grantTier = typeof body.grants_subscription_type === 'string'
    ? body.grants_subscription_type.trim().toLowerCase()
    : 'ultra'
  if (!isSelectablePromoGrantTier(grantTier)) {
    return NextResponse.json(
      { error: 'Invalid grants_subscription_type: use pro or ultra' },
      { status: 400 },
    )
  }

  const empPacks =
    body.grants_employee_slot_packs !== undefined && body.grants_employee_slot_packs !== null
      ? Number(body.grants_employee_slot_packs)
      : 0
  const brPacks =
    body.grants_branch_slot_packs !== undefined && body.grants_branch_slot_packs !== null
      ? Number(body.grants_branch_slot_packs)
      : 0
  if (!Number.isInteger(empPacks) || !EMPLOYEE_PACK_OPTIONS.has(empPacks)) {
    return NextResponse.json({ error: 'Invalid grants_employee_slot_packs: allowed 0, 5, 8, 12, 15' }, { status: 400 })
  }
  if (!Number.isInteger(brPacks) || !BRANCH_PACK_OPTIONS.has(brPacks)) {
    return NextResponse.json({ error: 'Invalid grants_branch_slot_packs: allowed 0, 1, 3, 5, 10' }, { status: 400 })
  }
  const additiveOnly =
    body.grants_additive_only === true ||
    body.grants_additive_only === 'true' ||
    body.grants_additive_only === 1

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)
  const { data, error } = await supabase
    .from('promo_codes')
    .insert({
      code: body.code.trim(),
      note: body.note || null,
      starts_at: body.starts_at || null,
      expires_at: body.expires_at || null,
      max_employees: body.max_employees ?? null,
      activation_duration_days: body.activation_duration_days ?? null,
      grants_subscription_type: grantTier,
      grants_employee_slot_packs: empPacks,
      grants_branch_slot_packs: brPacks,
      grants_additive_only: additiveOnly,
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
  const allowed = [
    'code',
    'note',
    'starts_at',
    'expires_at',
    'is_used',
    'used_at',
    'used_by_establishment_id',
    'max_employees',
    'is_disabled',
    'activation_duration_days',
    'grants_subscription_type',
    'grants_employee_slot_packs',
    'grants_branch_slot_packs',
    'grants_additive_only',
  ] as const
  if (updates.grants_subscription_type !== undefined && updates.grants_subscription_type !== null) {
    const g = String(updates.grants_subscription_type).trim().toLowerCase()
    if (!isAllowedPromoGrantType(g)) {
      return NextResponse.json(
        { error: 'Invalid grants_subscription_type: use pro, ultra, or a legacy tier already in the database' },
        { status: 400 },
      )
    }
    updates.grants_subscription_type = g
  }
  if (updates.grants_employee_slot_packs !== undefined && updates.grants_employee_slot_packs !== null) {
    const n = Number(updates.grants_employee_slot_packs)
    if (!Number.isInteger(n) || !EMPLOYEE_PACK_OPTIONS.has(n)) {
      return NextResponse.json({ error: 'Invalid grants_employee_slot_packs: allowed 0, 5, 8, 12, 15' }, { status: 400 })
    }
    updates.grants_employee_slot_packs = n
  }
  if (updates.grants_branch_slot_packs !== undefined && updates.grants_branch_slot_packs !== null) {
    const n = Number(updates.grants_branch_slot_packs)
    if (!Number.isInteger(n) || !BRANCH_PACK_OPTIONS.has(n)) {
      return NextResponse.json({ error: 'Invalid grants_branch_slot_packs: allowed 0, 1, 3, 5, 10' }, { status: 400 })
    }
    updates.grants_branch_slot_packs = n
  }
  if (updates.grants_additive_only !== undefined && updates.grants_additive_only !== null) {
    updates.grants_additive_only = Boolean(updates.grants_additive_only)
  }
  if (updates.activation_duration_days !== undefined && updates.activation_duration_days !== null) {
    const n = Number(updates.activation_duration_days)
    if (!Number.isInteger(n) || n < 1 || n > 36500) {
      return NextResponse.json(
        { error: 'Invalid activation_duration_days: must be an integer between 1 and 36500' },
        { status: 400 },
      )
    }
  }
  const patch = Object.fromEntries(
    Object.entries(updates).filter(([k]) => allowed.includes(k as typeof allowed[number]))
  )
  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)
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
  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)
  const { error } = await supabase
    .from('promo_codes')
    .delete()
    .eq('id', id)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
