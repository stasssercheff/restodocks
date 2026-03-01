import { NextRequest, NextResponse } from 'next/server'

async function createSessionToken(secret: string): Promise<string> {
  const encoder = new TextEncoder()
  const keyData = encoder.encode(secret)
  const expiresAt = Date.now() + 24 * 60 * 60 * 1000
  const payload = `admin:${expiresAt}`
  const key = await crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(payload))
  const sigHex = Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('')
  return `${payload}.${sigHex}`
}

export async function verifySessionToken(token: string, secret: string): Promise<boolean> {
  try {
    const lastDot = token.lastIndexOf('.')
    if (lastDot === -1) return false
    const payload = token.slice(0, lastDot)
    const sigHex = token.slice(lastDot + 1)
    const parts = payload.split(':')
    if (parts.length !== 2 || parts[0] !== 'admin') return false
    const expiresAt = parseInt(parts[1], 10)
    if (isNaN(expiresAt) || Date.now() > expiresAt) return false
    const encoder = new TextEncoder()
    const keyData = encoder.encode(secret)
    const key = await crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
    const sigBytes = new Uint8Array(sigHex.match(/.{2}/g)!.map(h => parseInt(h, 16)))
    return await crypto.subtle.verify('HMAC', key, sigBytes, encoder.encode(payload))
  } catch {
    return false
  }
}

export async function POST(req: NextRequest) {
  const { password } = await req.json()
  const adminPassword = process.env.ADMIN_PASSWORD

  if (!adminPassword || password !== adminPassword) {
    return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
  }

  const token = await createSessionToken(adminPassword)
  const res = NextResponse.json({ ok: true })
  res.cookies.set('admin_session', token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
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
