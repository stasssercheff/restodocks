import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getResendConfig, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'
import {
  collectBroadcastRecipients,
  plainTextToEmailHtml,
  sendBroadcastViaResend,
  type BroadcastFilters,
  type BroadcastSubscriptionMode,
  type BroadcastUserKind,
} from '@/lib/broadcast'

export const dynamic = 'force-dynamic'

async function checkAuth(): Promise<boolean> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword) return false
  return verifySessionToken(session, adminPassword)
}

function parseUserKind(raw: string | null): BroadcastUserKind | null {
  if (raw === 'owners' || raw === 'all' || raw === 'line') return raw
  return null
}

function parseSubscriptionMode(raw: string | null): BroadcastSubscriptionMode | null {
  if (
    raw === 'all' ||
    raw === 'with_any_subscription' ||
    raw === 'with_specific_subscriptions' ||
    raw === 'without_subscription'
  ) {
    return raw
  }
  return null
}

function parseDateYmd(raw: string | null): string | null {
  if (!raw) return null
  return /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : null
}

function parseFiltersFromQuery(req: NextRequest): BroadcastFilters | null {
  const userKind = parseUserKind(req.nextUrl.searchParams.get('userKind'))
  const subscriptionMode = parseSubscriptionMode(req.nextUrl.searchParams.get('subscriptionMode'))
  const registeredFrom = parseDateYmd(req.nextUrl.searchParams.get('registeredFrom'))
  const registeredTo = parseDateYmd(req.nextUrl.searchParams.get('registeredTo'))
  const rawTypes = req.nextUrl.searchParams.get('subscriptionTypes')
  const subscriptionTypes = rawTypes
    ? rawTypes
        .split(',')
        .map((x) => x.trim().toLowerCase())
        .filter(Boolean)
    : []

  if (!userKind || !subscriptionMode) return null
  if (req.nextUrl.searchParams.get('registeredFrom') && !registeredFrom) return null
  if (req.nextUrl.searchParams.get('registeredTo') && !registeredTo) return null
  return { userKind, subscriptionMode, subscriptionTypes, registeredFrom, registeredTo }
}

function parseFiltersFromBody(body: unknown): BroadcastFilters | null {
  if (typeof body !== 'object' || body === null) return null
  const b = body as Record<string, unknown>
  const userKind = parseUserKind(typeof b.userKind === 'string' ? b.userKind : null)
  const subscriptionMode = parseSubscriptionMode(
    typeof b.subscriptionMode === 'string' ? b.subscriptionMode : null,
  )
  const registeredFrom = parseDateYmd(typeof b.registeredFrom === 'string' ? b.registeredFrom : null)
  const registeredTo = parseDateYmd(typeof b.registeredTo === 'string' ? b.registeredTo : null)
  const rawTypes = Array.isArray(b.subscriptionTypes)
    ? b.subscriptionTypes
    : typeof b.subscriptionTypes === 'string'
      ? b.subscriptionTypes.split(',')
      : []
  const subscriptionTypes = rawTypes.map((x) => String(x).trim().toLowerCase()).filter(Boolean)

  if (!userKind || !subscriptionMode) return null
  if (b.registeredFrom != null && !registeredFrom) return null
  if (b.registeredTo != null && !registeredTo) return null
  return { userKind, subscriptionMode, subscriptionTypes, registeredFrom, registeredTo }
}

export async function GET(req: NextRequest) {
  if (!(await checkAuth())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const filters = parseFiltersFromQuery(req)
  if (!filters) {
    return NextResponse.json(
      { error: 'Invalid filters: userKind, subscriptionMode, subscriptionTypes?, registeredFrom?, registeredTo?' },
      { status: 400 },
    )
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  try {
    const emails = await collectBroadcastRecipients(supabase, filters)
    return NextResponse.json({ count: emails.length })
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Failed to list recipients'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  if (!(await checkAuth())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const resend = await getResendConfig()
  if (!resend) {
    return NextResponse.json(
      { error: 'RESEND_API_KEY не задан (локально .env, GitHub Secret, KV resend_api_key)' },
      { status: 500 },
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const filters = parseFiltersFromBody(body)
  if (!filters) {
    return NextResponse.json(
      { error: 'Invalid filters in body: userKind, subscriptionMode, subscriptionTypes?, registeredFrom?, registeredTo?' },
      { status: 400 },
    )
  }

  const subject =
    typeof body === 'object' && body !== null && 'subject' in body
      ? String((body as { subject?: unknown }).subject ?? '').trim()
      : ''
  if (subject.length < 1 || subject.length > 200) {
    return NextResponse.json({ error: 'Тема: от 1 до 200 символов' }, { status: 400 })
  }

  const textBody =
    typeof body === 'object' && body !== null && 'body' in body
      ? String((body as { body?: unknown }).body ?? '')
      : ''
  const trimmedBody = textBody.trim()
  if (trimmedBody.length < 1 || trimmedBody.length > 50_000) {
    return NextResponse.json({ error: 'Текст письма: от 1 до 50000 символов' }, { status: 400 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  let emails: string[]
  try {
    emails = await collectBroadcastRecipients(supabase, filters)
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Failed to list recipients'
    return NextResponse.json({ error: msg }, { status: 500 })
  }

  if (emails.length === 0) {
    return NextResponse.json({ sent: 0, failed: 0, message: 'Нет получателей по выбранным условиям' })
  }

  const htmlBody = plainTextToEmailHtml(trimmedBody)

  const result = await sendBroadcastViaResend({
    apiKey: resend.apiKey,
    from: resend.fromEmail,
    subject,
    textBody: trimmedBody,
    htmlBody,
    recipients: emails,
  })

  return NextResponse.json({
    sent: result.sent,
    failed: result.failed,
    recipientCount: emails.length,
    errors: result.errors.length ? result.errors : undefined,
    from: resend.fromEmail,
  })
}
