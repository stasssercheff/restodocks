import { NextRequest, NextResponse } from 'next/server'
import { getAdminPassword } from '@/lib/admin-env'
import { createSessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

type AttemptState = {
  failedTimestamps: number[]
  lockUntilMs: number
}

const MAX_FAILED_ATTEMPTS = 5
const ATTEMPT_WINDOW_MS = 10 * 60 * 1000
const LOCKOUT_MS = 15 * 60 * 1000

const attemptBuckets = new Map<string, AttemptState>()

function getClientIp(req: NextRequest): string {
  const cfIp = req.headers.get('cf-connecting-ip')?.trim()
  if (cfIp) return cfIp
  const xff = req.headers.get('x-forwarded-for')?.trim()
  if (xff) return xff.split(',')[0]?.trim() || 'unknown'
  const realIp = req.headers.get('x-real-ip')?.trim()
  if (realIp) return realIp
  return 'unknown'
}

function getAttemptState(ip: string): AttemptState {
  const now = Date.now()
  const state = attemptBuckets.get(ip) ?? { failedTimestamps: [], lockUntilMs: 0 }
  state.failedTimestamps = state.failedTimestamps.filter((ts) => ts >= now - ATTEMPT_WINDOW_MS)
  attemptBuckets.set(ip, state)
  return state
}

function recordFailedAttempt(ip: string): AttemptState {
  const now = Date.now()
  const state = getAttemptState(ip)
  state.failedTimestamps.push(now)
  if (state.failedTimestamps.length >= MAX_FAILED_ATTEMPTS) {
    state.lockUntilMs = now + LOCKOUT_MS
    state.failedTimestamps = []
  }
  attemptBuckets.set(ip, state)
  return state
}

function clearAttemptState(ip: string): void {
  attemptBuckets.delete(ip)
}

export async function POST(req: NextRequest) {
  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }

  const ip = getClientIp(req)
  const attemptState = getAttemptState(ip)
  const now = Date.now()
  if (attemptState.lockUntilMs > now) {
    const retryAfterSec = Math.ceil((attemptState.lockUntilMs - now) / 1000)
    return NextResponse.json(
      { error: 'Too many failed attempts. Try later.' },
      {
        status: 429,
        headers: { 'Retry-After': String(retryAfterSec) },
      },
    )
  }

  const password =
    typeof body === 'object' &&
    body !== null &&
    'password' in body &&
    typeof body.password === 'string'
      ? body.password.trim()
      : ''
  const adminPassword = await getAdminPassword()

  if (!adminPassword || !password || password !== adminPassword) {
    const failedState = recordFailedAttempt(ip)
    const isLockedNow = failedState.lockUntilMs > Date.now()
    console.warn(
      `[admin-auth] failed login ip=${ip} locked=${isLockedNow} attemptsInWindow=${failedState.failedTimestamps.length}`,
    )
    return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
  }

  clearAttemptState(ip)
  const token = await createSessionToken(adminPassword)
  const res = NextResponse.json({ ok: true })
  res.cookies.set('admin_session', token, {
    httpOnly: true,
    secure: process.env.NODE_ENV !== 'development',
    sameSite: 'strict',
    maxAge: 60 * 60 * 24,
    path: '/',
  })
  return res
}

export async function DELETE() {
  const res = NextResponse.json({ ok: true })
  res.cookies.delete('admin_session')
  return res
}
