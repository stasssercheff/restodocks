import { NextRequest, NextResponse } from 'next/server'
import { getCloudflareContext } from '@opennextjs/cloudflare'
import { createSessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

async function getAdminPassword(): Promise<string> {
  const p = (process.env.ADMIN_PASSWORD ?? '').trim()
  if (p) return p
  try {
    const { env } = await getCloudflareContext()
    const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } }).ADMIN_CONFIG
    if (kv) {
      const v = await kv.get('admin_password')
      return (v ?? '').trim()
    }
  } catch {
    // ignore
  }
  return ''
}

export async function POST(req: NextRequest) {
  const body = await req.json()
  const password = typeof body?.password === 'string' ? body.password.trim() : ''
  const adminPassword = await getAdminPassword()

  if (!adminPassword || !password || password !== adminPassword) {
    return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
  }

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
