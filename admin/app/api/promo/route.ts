import { NextRequest, NextResponse } from 'next/server'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'
import { isAllowedPromoGrantType, isSelectablePromoGrantTier } from '@/lib/promo-tiers'

const EMPLOYEE_PACK_OPTIONS = new Set([0, 5, 8, 12, 15])
const BRANCH_PACK_OPTIONS = new Set([0, 1, 3, 5, 10])

type RedemptionDetail = {
  establishment_id: string
  establishment_name: string | null
  owner_email: string | null
  owner_name: string | null
  redeemed_at: string | null
}

/** Погашения по promo_code_id с именем заведения и владельцем (email поднимается по цепочке филиал → головное). */
async function redemptionDetailsByPromoId(
  supabase: SupabaseClient,
  promoIds: number[],
): Promise<Map<number, RedemptionDetail[]>> {
  const out = new Map<number, RedemptionDetail[]>()
  if (promoIds.length === 0) return out

  const { data: rawRed, error: redErr } = await supabase
    .from('promo_code_redemptions')
    .select('promo_code_id, establishment_id, redeemed_at')
    .in('promo_code_id', promoIds)

  if (redErr) throw new Error(redErr.message)
  const rrows = rawRed ?? []
  if (rrows.length === 0) return out

  const seedEst = new Set<string>()
  for (const r of rrows) {
    const eid = (r as { establishment_id: string }).establishment_id
    if (eid) seedEst.add(eid)
  }

  const estMeta = new Map<string, { name: string | null; parent: string | null }>()
  const seen = new Set<string>()
  let frontier = [...seedEst]
  for (let depth = 0; depth < 24 && frontier.length > 0; depth++) {
    const batch = frontier.filter(id => !seen.has(id))
    if (batch.length === 0) break
    for (const id of batch) seen.add(id)
    const { data: chunk, error: estErr } = await supabase
      .from('establishments')
      .select('id, name, parent_establishment_id')
      .in('id', batch)
    if (estErr) throw new Error(estErr.message)
    const next = new Set<string>()
    for (const row of chunk ?? []) {
      const id = (row as { id: string }).id
      const name = (row as { name: string | null }).name ?? null
      const parent = (row as { parent_establishment_id: string | null }).parent_establishment_id ?? null
      estMeta.set(id, { name, parent })
      if (parent && !seen.has(parent)) next.add(parent)
    }
    frontier = [...next]
  }

  const allEstIds = [...estMeta.keys()]
  const { data: emRows, error: emErr } =
    allEstIds.length === 0
      ? { data: [] as Record<string, unknown>[], error: null }
      : await supabase
          .from('employees')
          .select('establishment_id, email, full_name, roles')
          .in('establishment_id', allEstIds)

  if (emErr) throw new Error(emErr.message)

  type Emp = { establishment_id: string; email: string | null; full_name: string | null; roles: string[] | null }
  const byEst = new Map<string, Emp[]>()
  for (const e of emRows ?? []) {
    const x = e as Emp
    const arr = byEst.get(x.establishment_id) ?? []
    arr.push(x)
    byEst.set(x.establishment_id, arr)
  }

  function resolveOwner(estId: string): { email: string | null; name: string | null } {
    let cur: string | null = estId
    for (let i = 0; i < 14 && cur; i++) {
      const emps = byEst.get(cur) ?? []
      const owner = emps.find(emp => Array.isArray(emp.roles) && emp.roles.includes('owner'))
      if (owner && (owner.email || owner.full_name)) {
        return { email: owner.email ?? null, name: owner.full_name ?? null }
      }
      cur = estMeta.get(cur)?.parent ?? null
    }
    return { email: null, name: null }
  }

  for (const r of rrows) {
    const eid = (r as { establishment_id: string }).establishment_id
    if (!eid) continue
    const pid = (r as { promo_code_id: number }).promo_code_id
    const redeemedAt = (r as { redeemed_at: string | null }).redeemed_at ?? null
    const name = estMeta.get(eid)?.name ?? null
    const own = resolveOwner(eid)
    const list = out.get(pid) ?? []
    list.push({
      establishment_id: eid,
      establishment_name: name,
      owner_email: own.email,
      owner_name: own.name,
      redeemed_at: redeemedAt,
    })
    out.set(pid, list)
  }

  for (const [, list] of out) {
    list.sort((a, b) => {
      const ta = a.redeemed_at ? new Date(a.redeemed_at).getTime() : 0
      const tb = b.redeemed_at ? new Date(b.redeemed_at).getTime() : 0
      return tb - ta
    })
  }

  return out
}

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
  // Не используем вложенный promo_code_redemptions(count): в PostgREST/версии клиента
  // агрегат в embed часто даёт ошибку → 500 в админке.
  const { data: raw, error } = await supabase
    .from('promo_codes')
    .select('*, establishments:used_by_establishment_id(name)')
    .order('created_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const rows = raw ?? []
  const promoIds = rows.map(r => (r as { id: number }).id).filter(id => id != null)
  const countByPromoId = new Map<number, number>()
  if (promoIds.length > 0) {
    const { data: rrows, error: rerr } = await supabase
      .from('promo_code_redemptions')
      .select('promo_code_id')
      .in('promo_code_id', promoIds)
    if (rerr) return NextResponse.json({ error: rerr.message }, { status: 500 })
    for (const row of rrows ?? []) {
      const pid = (row as { promo_code_id: number }).promo_code_id
      countByPromoId.set(pid, (countByPromoId.get(pid) ?? 0) + 1)
    }
  }

  let detailsByPromo: Map<number, RedemptionDetail[]>
  try {
    detailsByPromo = await redemptionDetailsByPromoId(supabase, promoIds)
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'redemption details failed'
    return NextResponse.json({ error: msg }, { status: 500 })
  }

  const data = rows.map(row => {
    const id = (row as { id: number }).id
    return {
      ...(row as Record<string, unknown>),
      redemption_count: countByPromoId.get(id) ?? 0,
      redemption_details: detailsByPromo.get(id) ?? [],
    }
  })
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
  if (body.max_redemptions !== undefined && body.max_redemptions !== null) {
    const n = Number(body.max_redemptions)
    if (!Number.isInteger(n) || n < 1 || n > 100000) {
      return NextResponse.json(
        { error: 'Invalid max_redemptions: must be an integer between 1 and 100000' },
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
      max_redemptions:
        body.max_redemptions !== undefined && body.max_redemptions !== null
          ? Number(body.max_redemptions)
          : 1,
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
    'max_redemptions',
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
  if (updates.max_redemptions !== undefined && updates.max_redemptions !== null) {
    const n = Number(updates.max_redemptions)
    if (!Number.isInteger(n) || n < 1 || n > 100000) {
      return NextResponse.json(
        { error: 'Invalid max_redemptions: must be an integer between 1 and 100000' },
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
