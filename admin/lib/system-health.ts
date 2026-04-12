/**
 * Сводка «состояние / нагрузка»: проверки доступности Supabase и снимок HTTP к зоне Cloudflare.
 */

import { supabaseProjectRefFromUrl } from '@/lib/security-snapshot'

const CF_GRAPHQL = 'https://api.cloudflare.com/client/v4/graphql'

const LATENCY_WARN_MS = 1200
const CF_REQUESTS_INFO_PER_DAY = 5_000_000

export type ProbeResult = {
  ok: boolean
  latencyMs: number
  status?: number
  detail?: string
}

export type SystemHealthPayload = {
  ok: boolean
  generatedAt: string
  supabaseUrlHost: string | null
  supabaseProjectRef: string | null
  authHealth: ProbeResult | null
  restSmoke: ProbeResult | null
  restRowEstimate: number | null
  cloudflare: {
    configured: boolean
    requests24hApprox: number | null
    graphqlError: string | null
  }
  hints: string[]
  links: {
    supabaseProject: string
    supabaseAdvisor: string
    cloudflareAnalytics: string
    cloudflareWorkersOverview: string
  }
}

function trimUrl(url: string): string {
  return url.replace(/\/+$/, '')
}

async function probeAuthHealth(supabaseUrl: string, apiKey: string): Promise<ProbeResult> {
  const t0 = Date.now()
  try {
    // Без apikey многие проекты отвечают 401 — тот же ключ, что для PostgREST (service_role).
    const res = await fetch(`${trimUrl(supabaseUrl)}/auth/v1/health`, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        apikey: apiKey,
        Authorization: `Bearer ${apiKey}`,
      },
      cache: 'no-store',
    })
    const latencyMs = Date.now() - t0
    return {
      ok: res.ok,
      latencyMs,
      status: res.status,
      detail: res.ok ? undefined : `HTTP ${res.status}`,
    }
  } catch (e) {
    return {
      ok: false,
      latencyMs: Date.now() - t0,
      detail: e instanceof Error ? e.message : 'fetch failed',
    }
  }
}

/** HEAD к PostgREST: проверяет API + БД без тела ответа. */
async function probeRestHead(
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<{ probe: ProbeResult; rowEstimate: number | null }> {
  const t0 = Date.now()
  try {
    const res = await fetch(`${trimUrl(supabaseUrl)}/rest/v1/establishments?select=id`, {
      method: 'HEAD',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: 'count=exact',
      },
      cache: 'no-store',
    })
    const latencyMs = Date.now() - t0
    let rowEstimate: number | null = null
    const cr = res.headers.get('content-range')
    if (cr) {
      const m = /\/(\d+)\s*$/.exec(cr)
      if (m) rowEstimate = parseInt(m[1], 10)
    }
    return {
      probe: {
        ok: res.ok,
        latencyMs,
        status: res.status,
        detail: res.ok ? undefined : `HTTP ${res.status}`,
      },
      rowEstimate,
    }
  } catch (e) {
    return {
      probe: {
        ok: false,
        latencyMs: Date.now() - t0,
        detail: e instanceof Error ? e.message : 'fetch failed',
      },
      rowEstimate: null,
    }
  }
}

async function fetchCfRequests24h(token: string, zoneTag: string): Promise<{ total: number | null; error: string | null }> {
  const end = new Date()
  const start = new Date(end.getTime() - 24 * 60 * 60 * 1000)
  const query = `
    query ($zoneTag: string, $start: Time, $end: Time) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          httpRequests1hGroups(
            limit: 10000
            filter: { datetime_geq: $start, datetime_lt: $end }
          ) {
            sum { requests }
          }
        }
      }
    }
  `
  const res = await fetch(CF_GRAPHQL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      query,
      variables: { zoneTag, start: start.toISOString(), end: end.toISOString() },
    }),
  })
  const json = (await res.json()) as {
    errors?: { message: string }[]
    data?: {
      viewer?: {
        zones?: { httpRequests1hGroups?: { sum?: { requests?: number } }[] }[]
      }
    }
  }
  if (json.errors?.length) {
    return { total: null, error: json.errors[0]?.message ?? 'GraphQL error' }
  }
  const groups = json.data?.viewer?.zones?.[0]?.httpRequests1hGroups
  if (!groups) return { total: null, error: null }
  let total = 0
  for (const g of groups) {
    total += g.sum?.requests ?? 0
  }
  return { total, error: null }
}

export async function buildSystemHealthReport(params: {
  supabaseUrl: string
  serviceRoleKey: string
  cfToken: string | undefined
  zoneTag: string | undefined
  accountId: string | undefined
}): Promise<SystemHealthPayload> {
  const { supabaseUrl, serviceRoleKey, cfToken, zoneTag, accountId } = params
  const generatedAt = new Date().toISOString()
  const ref = supabaseProjectRefFromUrl(supabaseUrl)
  const host = (() => {
    try {
      return new URL(supabaseUrl).host
    } catch {
      return null
    }
  })()

  const [authHealth, restPack] = await Promise.all([
    probeAuthHealth(supabaseUrl, serviceRoleKey),
    probeRestHead(supabaseUrl, serviceRoleKey),
  ])

  const hints: string[] = []

  if (authHealth.latencyMs >= LATENCY_WARN_MS || !authHealth.ok) {
    hints.push(
      !authHealth.ok
        ? 'Auth (GoTrue) недоступен или вернул ошибку — проверьте проект Supabase и статус региона.'
        : `Задержка ответа Auth ${authHealth.latencyMs} мс — при повторении откройте Reports → Database в Supabase (нагрузка или сеть).`,
    )
  }
  if (restPack.probe.latencyMs >= LATENCY_WARN_MS || !restPack.probe.ok) {
    hints.push(
      !restPack.probe.ok
        ? 'PostgREST/таблица establishments недоступны — миграции, RLS или ключ service_role.'
        : `Задержка API БД ${restPack.probe.latencyMs} мс — возможна нагрузка на Postgres или «холодный» старт.`,
    )
  }

  const token = cfToken?.trim()
  const zone = zoneTag?.trim()
  const acc = accountId?.trim()

  let requests24h: number | null = null
  let graphqlError: string | null = null
  if (token && zone) {
    const cf = await fetchCfRequests24h(token, zone)
    requests24h = cf.total
    graphqlError = cf.error
    if (graphqlError) {
      hints.push(`Cloudflare GraphQL: ${graphqlError}`)
    }
    if (requests24h != null && requests24h > CF_REQUESTS_INFO_PER_DAY) {
      hints.push(
        `За сутки к зоне ~${requests24h.toLocaleString('ru-RU')} HTTP-запросов — необычно много для малого трафика; проверьте ботов и кэш.`,
      )
    }
  } else {
    hints.push(
      'Для графика трафика задайте CLOUDFLARE_API_TOKEN и CLOUDFLARE_ZONE_ID в секретах Worker (как на вкладке «Безопасность»).',
    )
  }

  const cfConfigured = Boolean(token && zone)

  const linksBase = {
    supabaseProject: ref ? `https://supabase.com/dashboard/project/${ref}` : 'https://supabase.com/dashboard',
    supabaseAdvisor: ref ? `https://supabase.com/dashboard/project/${ref}/advisors/recommendations` : 'https://supabase.com/dashboard',
    cloudflareAnalytics:
      acc && zone ? `https://dash.cloudflare.com/${acc}/${zone}/analytics/traffic` : 'https://dash.cloudflare.com/',
    cloudflareWorkersOverview: acc ? `https://dash.cloudflare.com/${acc}/workers-and-pages` : 'https://dash.cloudflare.com/',
  }

  const overallOk = authHealth.ok && restPack.probe.ok

  return {
    ok: overallOk,
    generatedAt,
    supabaseUrlHost: host,
    supabaseProjectRef: ref,
    authHealth,
    restSmoke: restPack.probe,
    restRowEstimate: restPack.rowEstimate,
    cloudflare: {
      configured: cfConfigured,
      requests24hApprox: requests24h,
      graphqlError,
    },
    hints,
    links: linksBase,
  }
}

export { LATENCY_WARN_MS, CF_REQUESTS_INFO_PER_DAY }
