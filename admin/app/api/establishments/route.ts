import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'
import {
  hasEffectivePro,
  subscriptionGroupKey,
  summarizeSubscriptionForAdmin,
  type PromoRedemptionRow,
} from '@/lib/subscription-admin'

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

  const selectCore =
    'id, name, address, created_at, default_currency, owner_id, parent_establishment_id, registration_ip, registration_country, registration_city'

  /** Пока на БД не все миграции — перебираем селекты от полного к минимальному. */
  const selectVariants: string[] = [
    `${selectCore}, subscription_type, pro_paid_until, pro_trial_ends_at`,
    `${selectCore}, subscription_type, pro_trial_ends_at`,
    `${selectCore}, subscription_type`,
    selectCore,
  ]

  function isMissingColumnError(message: string) {
    return /does not exist|column .+ does not exist/i.test(message)
  }

  function normalizeEstablishmentRow(row: Record<string, unknown>) {
    return {
      ...row,
      subscription_type: (row.subscription_type as string | null | undefined) ?? null,
      pro_paid_until: (row.pro_paid_until as string | null | undefined) ?? null,
      pro_trial_ends_at: (row.pro_trial_ends_at as string | null | undefined) ?? null,
    }
  }

  let establishments: ReturnType<typeof normalizeEstablishmentRow>[] | null = null
  let error: { message: string } | null = null

  for (const sel of selectVariants) {
    const res = await supabase.from('establishments').select(sel).order('created_at', { ascending: false })
    if (!res.error) {
      establishments = (res.data ?? []).map(r =>
        normalizeEstablishmentRow(r as unknown as Record<string, unknown>),
      )
      error = null
      break
    }
    error = res.error
    if (!isMissingColumnError(res.error.message)) break
  }

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  type EstablishmentRow = {
    id: string
    parent_establishment_id: string | null
    owner_id: string | null
    // Остальные поля не нужны для расчётов, но оставляем тип как неизвестный.
    [key: string]: unknown
  }
  type EmployeeRow = {
    id?: string | null
    full_name?: string | null
    email?: string | null
    roles?: string[] | null
    establishment_id: string
  }

  const list = (establishments ?? []) as unknown as EstablishmentRow[]
  const mainCountByOwner = new Map<string, number>()
  for (const est of list) {
    const ownerId = est.owner_id ?? ''
    if (!ownerId || est.parent_establishment_id) continue
    mainCountByOwner.set(ownerId, (mainCountByOwner.get(ownerId) ?? 0) + 1)
  }

  // Для каждого заведения считаем сотрудников и находим владельца.
  // Для филиалов: если в employees по самому филиалу владелец не найден,
  // показываем владельца основного (root parent establishment).
  const ids = list.map(e => e.id)

  const promoByEstId = new Map<string, PromoRedemptionRow>()
  if (ids.length > 0) {
    const { data: redemptionRows } = await supabase
      .from('promo_code_redemptions')
      .select(
        'establishment_id, redeemed_at, promo_codes(code, activation_duration_days, expires_at)',
      )
      .in('establishment_id', ids)

    for (const raw of redemptionRows ?? []) {
      const r = raw as unknown as {
        establishment_id: string
        redeemed_at?: string | null
        promo_codes:
          | {
              code: string
              activation_duration_days?: number | null
              expires_at?: string | null
            }
          | {
              code: string
              activation_duration_days?: number | null
              expires_at?: string | null
            }[]
          | null
      }
      const nested = r.promo_codes
      const pc = Array.isArray(nested) ? nested[0] : nested
      const code = pc?.code
      if (!code || promoByEstId.has(r.establishment_id)) continue
      promoByEstId.set(r.establishment_id, {
        code,
        redeemed_at: r.redeemed_at ?? null,
        activation_duration_days: pc?.activation_duration_days ?? null,
        expires_at: pc?.expires_at ?? null,
      })
    }
  }

  // Пустой .in() у PostgREST даёт ошибку запроса — при 0 заведений список сотрудников пустой.
  const { data: employees } =
    ids.length === 0
      ? { data: [] as Record<string, unknown>[] | null }
      : await supabase
          .from('employees')
          .select('id, full_name, email, roles, establishment_id')
          .in('establishment_id', ids)

  const employeesByEstId = new Map<string, EmployeeRow[]>()
  for (const emp of (employees ?? []) as EmployeeRow[]) {
    const key = emp.establishment_id
    const arr = employeesByEstId.get(key) ?? []
    arr.push(emp)
    employeesByEstId.set(key, arr)
  }

  const parentById = new Map<string, string | null | undefined>()
  for (const est of list) {
    parentById.set(est.id, est.parent_establishment_id)
  }
  const childrenByParent = new Map<string, string[]>()
  for (const est of list) {
    const parentId = est.parent_establishment_id
    if (!parentId) continue
    const arr = childrenByParent.get(parentId) ?? []
    arr.push(est.id)
    childrenByParent.set(parentId, arr)
  }

  function getRootParentId(startId: string): string {
    // parent_establishment_id может указывать на main (NULL/empty) напрямую.
    // Если дерево глубже — поднимаемся пока можем.
    let cur: string | null | undefined = startId
    // Защита от циклов: максимум 10 шагов.
    for (let i = 0; i < 10; i++) {
      if (!cur) break
      const parent = parentById.get(cur)
      if (!parent) return cur
      cur = parent
    }
    return startId
  }

  function collectDescendants(rootId: string): string[] {
    const out: string[] = []
    const stack = [...(childrenByParent.get(rootId) ?? [])]
    const seen = new Set<string>()
    while (stack.length > 0) {
      const cur = stack.pop()!
      if (seen.has(cur)) continue
      seen.add(cur)
      out.push(cur)
      const next = childrenByParent.get(cur) ?? []
      for (const n of next) stack.push(n)
    }
    return out
  }

  const result = list.map(est => {
    const estId = est.id
    const rootId = getRootParentId(estId)
    // Для филиалов показываем источник подписки по корневому заведению владельца,
    // если у самого филиала нет своей строки promo_code_redemptions.
    const promo = promoByEstId.get(estId) ?? promoByEstId.get(rootId)
    const subFields = {
      subscription_type: est.subscription_type as string | null | undefined,
      pro_paid_until: est.pro_paid_until as string | null | undefined,
      pro_trial_ends_at: est.pro_trial_ends_at as string | null | undefined,
    }
    const createdAt = est.created_at as string | null | undefined
    const subscription_summary = summarizeSubscriptionForAdmin(subFields, promo, Date.now(), createdAt)
    const effective_pro = hasEffectivePro(subFields, promo)
    const subscription_group = subscriptionGroupKey(subFields, promo, Date.now(), createdAt)

    const isMain = !est.parent_establishment_id
    const scopeIds = isMain ? [estId, ...collectDescendants(estId)] : [estId]
    const estEmployees = scopeIds.flatMap(id => employeesByEstId.get(id) ?? [])
    const owner = estEmployees.find(e => e.roles?.includes('owner'))

    if (owner) {
      const ownerId = est.owner_id ?? ''
      const ownerMainCount = ownerId ? (mainCountByOwner.get(ownerId) ?? 0) : 0
      const establishment_type = est.parent_establishment_id
        ? 'branch'
        : ownerMainCount > 1
          ? 'separate'
          : 'main'
      return {
        ...est,
        employee_count: estEmployees.length,
        owner_name: owner?.full_name ?? '—',
        owner_email: owner?.email ?? '—',
        establishment_type,
        subscription_summary,
        effective_pro,
        subscription_group,
      }
    }

    // Если владелец не найден по самому филиалу, пробуем найти его у root parent.
    const rootEmployees = employeesByEstId.get(rootId) ?? []
    const rootOwner = rootEmployees.find(e => e.roles?.includes('owner'))

    const ownerId = est.owner_id ?? ''
    const ownerMainCount = ownerId ? (mainCountByOwner.get(ownerId) ?? 0) : 0
    const establishment_type = est.parent_establishment_id
      ? 'branch'
      : ownerMainCount > 1
        ? 'separate'
        : 'main'
    return {
      ...est,
      employee_count: estEmployees.length,
      owner_name: rootOwner?.full_name ?? '—',
      owner_email: rootOwner?.email ?? '—',
      establishment_type,
      subscription_summary,
      effective_pro,
      subscription_group,
    }
  })

  return NextResponse.json(result)
}
