import type { SupabaseClient } from '@supabase/supabase-js'
import { isAllowedPromoGrantType, safeTierString } from '@/lib/promo-tiers'

export type BroadcastUserKind = 'owners' | 'line' | 'all'
export type BroadcastSubscriptionMode =
  | 'all'
  | 'with_any_subscription'
  | 'with_specific_subscriptions'
  | 'without_subscription'

export type BroadcastFilters = {
  userKind: BroadcastUserKind
  subscriptionMode: BroadcastSubscriptionMode
  subscriptionTypes: string[]
  registeredFrom: string | null
  registeredTo: string | null
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

/** Подтверждённый email в Auth + активная запись сотрудника; для «собственники» — роль owner. */
export async function collectBroadcastRecipients(
  supabase: SupabaseClient,
  filters: BroadcastFilters,
): Promise<string[]> {
  const fromDate = parseDateStart(filters.registeredFrom)
  const toDate = parseDateEnd(filters.registeredTo)
  const normalizedSpecificTiers = new Set(
    filters.subscriptionTypes
      .map((x) => safeTierString(x))
      .filter((x) => x.length > 0 && isAllowedPromoGrantType(x)),
  )

  const emailByAuthId = new Map<string, string>()
  const createdAtByAuthId = new Map<string, Date>()
  let page = 1
  const perPage = 1000
  for (;;) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage })
    if (error) throw error
    const users = data?.users ?? []
    for (const u of users) {
      if (!u.email_confirmed_at || !u.email?.trim()) continue
      const created = parseDate(u.created_at ?? null)
      if (fromDate && (!created || created < fromDate)) continue
      if (toDate && (!created || created > toDate)) continue
      if (created) createdAtByAuthId.set(u.id, created)
      if (u.email_confirmed_at && u.email?.trim()) {
        emailByAuthId.set(u.id, u.email.trim().toLowerCase())
      }
    }
    if (users.length < perPage) break
    page += 1
  }

  const confirmedIds = [...emailByAuthId.keys()]
  if (confirmedIds.length === 0) return []

  const collected = new Set<string>()
  const establishmentIds = new Set<string>()
  const filteredEmployees: Array<{ id: string; email: string | null; establishment_id: string; roles: string[] }> = []
  const idChunkSize = 200

  for (const ids of chunk(confirmedIds, idChunkSize)) {
    const { data: rows, error: e2 } = await supabase
      .from('employees')
      .select('id, email, roles, establishment_id')
      .in('id', ids)
      .eq('is_active', true)
      .not('email', 'is', null)
    if (e2) throw e2

    for (const row of rows ?? []) {
      const roles = (row.roles as string[] | null) ?? []
      const isOwner = roles.includes('owner')
      if (filters.userKind === 'owners' && !isOwner) continue
      if (filters.userKind === 'line' && isOwner) continue
      const estId = String(row.establishment_id ?? '').trim()
      if (!estId) continue
      filteredEmployees.push({
        id: String(row.id),
        email: (row.email as string | null) ?? null,
        establishment_id: estId,
        roles,
      })
      establishmentIds.add(estId)
    }
  }

  const tierByEstId = new Map<string, string>()
  const estIds = [...establishmentIds]
  for (const ids of chunk(estIds, 200)) {
    const { data: estRows, error: estErr } = await supabase
      .from('establishments')
      .select('id, subscription_type')
      .in('id', ids)
    if (estErr) throw estErr
    for (const est of estRows ?? []) {
      tierByEstId.set(String(est.id), safeTierString(est.subscription_type))
    }
  }

  for (const row of filteredEmployees) {
    // Safety: only users we already filtered from auth list.
    if (!emailByAuthId.has(row.id)) continue
    if (!createdAtByAuthId.has(row.id)) continue
    const tier = tierByEstId.get(row.establishment_id) ?? 'free'
    if (!matchesSubscriptionFilter(tier, filters.subscriptionMode, normalizedSpecificTiers)) continue

    const authEmail = emailByAuthId.get(row.id)
    const em = (authEmail ?? String(row.email ?? '').trim()).toLowerCase()
    if (em) collected.add(em)
  }

  return [...collected].sort()
}

function parseDate(iso: string | null): Date | null {
  if (!iso) return null
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? null : d
}

function parseDateStart(raw: string | null): Date | null {
  if (!raw) return null
  const d = new Date(`${raw}T00:00:00.000Z`)
  return Number.isNaN(d.getTime()) ? null : d
}

function parseDateEnd(raw: string | null): Date | null {
  if (!raw) return null
  const d = new Date(`${raw}T23:59:59.999Z`)
  return Number.isNaN(d.getTime()) ? null : d
}

function matchesSubscriptionFilter(
  tierRaw: string,
  mode: BroadcastSubscriptionMode,
  specificTiers: Set<string>,
): boolean {
  const tier = safeTierString(tierRaw)
  const paid = isAllowedPromoGrantType(tier)
  if (mode === 'all') return true
  if (mode === 'without_subscription') return !paid
  if (mode === 'with_any_subscription') return paid
  if (mode === 'with_specific_subscriptions') {
    if (!paid) return false
    if (specificTiers.size === 0) return false
    return specificTiers.has(tier)
  }
  return true
}

export function plainTextToEmailHtml(text: string): string {
  const esc = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
  const body = esc.replace(/\r\n/g, '\n').split('\n').join('<br/>')
  return `<!DOCTYPE html><html><body style="font-family:system-ui,sans-serif;font-size:15px;line-height:1.5;color:#111;">${body}</body></html>`
}

const RESEND_BATCH_MAX = 100

export async function sendBroadcastViaResend(options: {
  apiKey: string
  from: string
  subject: string
  textBody: string
  htmlBody: string
  recipients: string[]
}): Promise<{ sent: number; failed: number; errors: string[] }> {
  const { apiKey, from, subject, textBody, htmlBody, recipients } = options
  const errors: string[] = []
  let sent = 0
  let failed = 0

  for (let i = 0; i < recipients.length; i += RESEND_BATCH_MAX) {
    const batch = recipients.slice(i, i + RESEND_BATCH_MAX)
    const payload = batch.map(to => ({
      from,
      to: [to],
      subject,
      html: htmlBody,
      text: textBody,
    }))

    const res = await fetch('https://api.resend.com/emails/batch', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })

    const json = (await res.json().catch(() => ({}))) as { message?: string; name?: string }
    if (!res.ok) {
      failed += batch.length
      const msg =
        typeof json?.message === 'string'
          ? json.message
          : `Resend batch HTTP ${res.status}`
      errors.push(msg)
      continue
    }
    sent += batch.length
  }

  return { sent, failed, errors }
}
