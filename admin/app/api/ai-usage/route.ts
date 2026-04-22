import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

async function checkAuth(): Promise<boolean> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword) return false
  return verifySessionToken(session, adminPassword)
}

function parseDays(raw: string | null): number {
  const n = Number(raw ?? '30')
  if (!Number.isFinite(n)) return 30
  return Math.max(1, Math.min(180, Math.floor(n)))
}

function parseLimit(raw: string | null): number {
  const n = Number(raw ?? '500')
  if (!Number.isFinite(n)) return 500
  return Math.max(50, Math.min(5000, Math.floor(n)))
}

type UsageRow = {
  created_at: string
  provider: string
  model: string | null
  context: string | null
  function_name: string | null
  input_tokens: number | null
  output_tokens: number | null
  total_tokens: number | null
  estimated_cost_usd: number | null
  status: string | null
}

export async function GET(req: NextRequest) {
  if (!await checkAuth()) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { searchParams } = new URL(req.url)
  const days = parseDays(searchParams.get('days'))
  const provider = (searchParams.get('provider') ?? '').trim().toLowerCase()
  const limit = parseLimit(searchParams.get('limit'))

  const fromIso = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString()
  let query = supabase
    .from('ai_usage_logs')
    .select('created_at,provider,model,context,function_name,input_tokens,output_tokens,total_tokens,estimated_cost_usd,status')
    .gte('created_at', fromIso)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (provider) query = query.eq('provider', provider)

  const { data, error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const rows = (data ?? []) as UsageRow[]
  const summary = {
    requests: 0,
    successRequests: 0,
    failedRequests: 0,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    estimatedCostUsd: 0,
  }
  const byProvider = new Map<string, { requests: number; totalTokens: number; estimatedCostUsd: number }>()
  const byContext = new Map<string, { requests: number; totalTokens: number; estimatedCostUsd: number }>()
  const byDay = new Map<string, { requests: number; totalTokens: number; estimatedCostUsd: number }>()

  for (const row of rows) {
    const input = Number(row.input_tokens ?? 0)
    const output = Number(row.output_tokens ?? 0)
    const total = Number(row.total_tokens ?? input + output)
    const cost = Number(row.estimated_cost_usd ?? 0)
    const status = (row.status ?? 'ok').toLowerCase()
    const providerKey = (row.provider || 'unknown').toLowerCase()
    const contextKey = (row.context || 'unknown').toLowerCase()
    const dayKey = (row.created_at || '').slice(0, 10)

    summary.requests += 1
    if (status === 'ok') summary.successRequests += 1
    else summary.failedRequests += 1
    summary.inputTokens += input
    summary.outputTokens += output
    summary.totalTokens += total
    summary.estimatedCostUsd += cost

    const prov = byProvider.get(providerKey) ?? { requests: 0, totalTokens: 0, estimatedCostUsd: 0 }
    prov.requests += 1
    prov.totalTokens += total
    prov.estimatedCostUsd += cost
    byProvider.set(providerKey, prov)

    const ctx = byContext.get(contextKey) ?? { requests: 0, totalTokens: 0, estimatedCostUsd: 0 }
    ctx.requests += 1
    ctx.totalTokens += total
    ctx.estimatedCostUsd += cost
    byContext.set(contextKey, ctx)

    if (dayKey) {
      const day = byDay.get(dayKey) ?? { requests: 0, totalTokens: 0, estimatedCostUsd: 0 }
      day.requests += 1
      day.totalTokens += total
      day.estimatedCostUsd += cost
      byDay.set(dayKey, day)
    }
  }

  return NextResponse.json({
    meta: { days, provider: provider || null, fromIso, sampleSize: rows.length, limit },
    summary: {
      ...summary,
      estimatedCostUsd: Number(summary.estimatedCostUsd.toFixed(6)),
    },
    byProvider: Array.from(byProvider.entries())
      .map(([name, v]) => ({ provider: name, ...v, estimatedCostUsd: Number(v.estimatedCostUsd.toFixed(6)) }))
      .sort((a, b) => b.estimatedCostUsd - a.estimatedCostUsd),
    byContext: Array.from(byContext.entries())
      .map(([name, v]) => ({ context: name, ...v, estimatedCostUsd: Number(v.estimatedCostUsd.toFixed(6)) }))
      .sort((a, b) => b.estimatedCostUsd - a.estimatedCostUsd),
    byDay: Array.from(byDay.entries())
      .map(([date, v]) => ({ date, ...v, estimatedCostUsd: Number(v.estimatedCostUsd.toFixed(6)) }))
      .sort((a, b) => a.date.localeCompare(b.date)),
    recent: rows.slice(0, 200),
  })
}
