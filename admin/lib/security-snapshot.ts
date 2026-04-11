/** Сводка безопасности (Cloudflare GraphQL + эвристики) — общая логика для API route. */

const CF_GRAPHQL = 'https://api.cloudflare.com/client/v4/graphql'

export type FwEvent = {
  action?: string | null
  clientIP?: string | null
  datetime?: string | null
  clientRequestPath?: string | null
  clientCountryName?: string | null
  edgeResponseStatus?: number | null
  source?: string | null
}

export type Insight =
  | { kind: 'traffic_volume'; severity: 'info'; requests24h: number }
  | { kind: 'waf_activity'; severity: 'warning'; blocks: number; challenges: number }
  | { kind: 'ip_noisy'; severity: 'warning'; ip: string; events: number }
  | { kind: 'probe_path'; severity: 'warning'; pathSample: string }
  | { kind: 'db_attack_note'; severity: 'info' }

export type SecuritySnapshotPayload = {
  ok: boolean
  generatedAt: string
  cloudflare: {
    configured: boolean
    requests24hApprox: number | null
    firewallEvents: FwEvent[]
    graphqlErrors: string[] | null
  }
  insights: Insight[]
  links: {
    cloudflareSecurity: string
    cloudflareWaf: string
    supabaseLogs: string
    supabaseAuth: string
  }
  hint: string | null
}

async function cloudflareGraphql(
  token: string,
  query: string,
  variables: Record<string, unknown>,
): Promise<{ data?: unknown; errors?: { message: string }[] }> {
  const res = await fetch(CF_GRAPHQL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query, variables }),
  })
  return (await res.json()) as { data?: unknown; errors?: { message: string }[] }
}

export function buildInsights(requests24h: number | null, events: FwEvent[]): Insight[] {
  const out: Insight[] = []

  if (requests24h != null && requests24h > 0) {
    out.push({
      kind: 'traffic_volume',
      severity: 'info',
      requests24h,
    })
  }

  const blocked = events.filter(e => /block|deny|drop/i.test(e.action ?? ''))
  const challenged = events.filter(e => /challenge|managed_challenge/i.test(e.action ?? ''))
  if (blocked.length > 0 || challenged.length > 0) {
    out.push({
      kind: 'waf_activity',
      severity: 'warning',
      blocks: blocked.length,
      challenges: challenged.length,
    })
  }

  const byIp = new Map<string, number>()
  for (const e of events) {
    const ip = e.clientIP?.trim()
    if (!ip) continue
    byIp.set(ip, (byIp.get(ip) ?? 0) + 1)
  }
  for (const [ip, n] of byIp) {
    if (n >= 5) {
      out.push({ kind: 'ip_noisy', severity: 'warning', ip, events: n })
      break
    }
  }

  const probePaths = /(\.env|wp-login|xmlrpc|phpmyadmin|\.git|union\s+select|\/\.\.\/)/i
  for (const e of events) {
    const p = e.clientRequestPath ?? ''
    if (probePaths.test(p)) {
      out.push({
        kind: 'probe_path',
        severity: 'warning',
        pathSample: p.length > 120 ? `${p.slice(0, 120)}…` : p,
      })
      break
    }
  }

  out.push({ kind: 'db_attack_note', severity: 'info' })
  return out
}

function supabaseProjectRefFromUrl(supabaseUrl: string): string | null {
  const m = /^https:\/\/([a-z0-9-]+)\.supabase\.co\/?$/i.exec(supabaseUrl.trim())
  return m ? m[1] : null
}

export async function buildSecuritySnapshot(params: {
  supabaseUrl: string
  cfToken: string | undefined
  zoneTag: string | undefined
  accountId: string | undefined
}): Promise<SecuritySnapshotPayload> {
  const { supabaseUrl, cfToken, zoneTag, accountId } = params
  const generatedAt = new Date().toISOString()
  const supabaseProjectRef = supabaseProjectRefFromUrl(supabaseUrl)

  const baseLinks = (z: string | undefined, acc: string | undefined) => ({
    cloudflareSecurity:
      acc && z
        ? `https://dash.cloudflare.com/${acc}/${z}/security/analytics`
        : 'https://dash.cloudflare.com/',
    cloudflareWaf:
      acc && z ? `https://dash.cloudflare.com/${acc}/${z}/security/waf` : 'https://dash.cloudflare.com/',
    supabaseLogs: supabaseProjectRef
      ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/logs/explorer`
      : 'https://supabase.com/dashboard',
    supabaseAuth: supabaseProjectRef
      ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/auth/users`
      : 'https://supabase.com/dashboard',
  })

  const token = cfToken?.trim()
  const zone = zoneTag?.trim()
  const acc = accountId?.trim()

  if (!token || !zone) {
    return {
      ok: true,
      generatedAt,
      cloudflare: {
        configured: false,
        requests24hApprox: null,
        firewallEvents: [],
        graphqlErrors: null,
      },
      insights: buildInsights(null, []),
      links: baseLinks(zone, acc),
      hint:
        'Задайте в переменных окружения Worker (Secrets): CLOUDFLARE_API_TOKEN (Analytics + Firewall Read) и CLOUDFLARE_ZONE_ID — появятся счётчик запросов и события WAF.',
    }
  }

  const end = new Date()
  const start = new Date(end.getTime() - 24 * 60 * 60 * 1000)
  const startIso = start.toISOString()
  const endIso = end.toISOString()

  const qRequests = `
    query ($zoneTag: string, $start: Time, $end: Time) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          httpRequests1hGroups(
            limit: 10000
            filter: { datetime_geq: $start, datetime_lt: $end }
          ) {
            sum {
              requests
            }
          }
        }
      }
    }
  `

  const qFw = `
    query ($zoneTag: string, $start: Time, $end: Time) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          firewallEventsAdaptive(
            filter: { datetime_geq: $start, datetime_lt: $end }
            limit: 40
            orderBy: [datetime_DESC]
          ) {
            action
            clientIP
            datetime
            clientRequestPath
            clientCountryName
            edgeResponseStatus
            source
          }
        }
      }
    }
  `

  const vars = { zoneTag: zone, start: startIso, end: endIso }

  const [r1, r2] = await Promise.all([
    cloudflareGraphql(token, qRequests, vars),
    cloudflareGraphql(token, qFw, vars),
  ])

  const gqlErrors = [...(r1.errors?.map(e => e.message) ?? []), ...(r2.errors?.map(e => e.message) ?? [])]

  let requests24hApprox: number | null = null
  const zones1 = (
    r1.data as {
      viewer?: {
        zones?: { httpRequests1hGroups?: { sum?: { requests?: number } }[] }[]
      }
    }
  )?.viewer?.zones
  if (zones1?.[0]?.httpRequests1hGroups) {
    let total = 0
    for (const g of zones1[0].httpRequests1hGroups ?? []) {
      total += g.sum?.requests ?? 0
    }
    requests24hApprox = total
  }

  let firewallEvents: FwEvent[] = []
  const zones2 = (
    r2.data as {
      viewer?: { zones?: { firewallEventsAdaptive?: FwEvent[] }[] }
    }
  )?.viewer?.zones
  if (zones2?.[0]?.firewallEventsAdaptive) {
    firewallEvents = zones2[0].firewallEventsAdaptive
  }

  const insights = buildInsights(requests24hApprox, firewallEvents)

  return {
    ok: true,
    generatedAt,
    cloudflare: {
      configured: true,
      requests24hApprox,
      firewallEvents,
      graphqlErrors: gqlErrors.length ? gqlErrors : null,
    },
    insights,
    links: baseLinks(zone, acc),
    hint: gqlErrors.length
      ? `Часть запросов к Cloudflare GraphQL недоступна или токену не хватает прав: ${gqlErrors[0]}`
      : null,
  }
}
