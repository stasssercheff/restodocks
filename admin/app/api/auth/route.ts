import { NextRequest, NextResponse } from 'next/server'
import { createSessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  const body = await req.json()
  const password = typeof body?.password === 'string' ? body.password.trim() : ''
  const adminPassword = (process.env.ADMIN_PASSWORD ?? '').trim()

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
