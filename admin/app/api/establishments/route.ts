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

  const selectBase =
    'id, name, address, created_at, default_currency, owner_id, parent_establishment_id, registration_ip, registration_country, registration_city'

  let { data: establishments, error } = await supabase
    .from('establishments')
    .select(`${selectBase}, max_additional_establishments_override`)
    .order('created_at', { ascending: false })

  // Пока миграция не применена на БД, колонки нет — читаем без неё (лимит доп. в UI будет «платформа»).
  if (
    error &&
    /max_additional_establishments_override|does not exist/i.test(error.message)
  ) {
    const retry = await supabase
      .from('establishments')
      .select(selectBase)
      .order('created_at', { ascending: false })
    establishments =
      retry.data?.map(row => ({
        ...row,
        max_additional_establishments_override: null,
      })) ?? null
    error = retry.error
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

  const list = (establishments ?? []) as EstablishmentRow[]
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

  const { data: employees } = await supabase
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
      }
    }

    // Если владелец не найден по самому филиалу, пробуем найти его у root parent.
    const rootId = getRootParentId(estId)
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
    }
  })

  return NextResponse.json(result)
}
