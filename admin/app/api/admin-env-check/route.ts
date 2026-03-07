import { NextResponse } from 'next/server'
import { getCloudflareContext } from '@opennextjs/cloudflare'

export const dynamic = 'force-dynamic'

/** Debug: which env source has ADMIN_PASSWORD (do not deploy to prod) */
export async function GET() {
  const fromProcess = !!process.env.ADMIN_PASSWORD
  let fromCf = false
  try {
    const { env } = await getCloudflareContext()
    fromCf = !!(env as Record<string, unknown>).ADMIN_PASSWORD
  } catch {
    // ignore
  }
  return NextResponse.json({
    fromProcessEnv: fromProcess,
    fromCloudflareEnv: fromCf,
    hint: fromProcess ? 'process.env works' : fromCf ? 'getCloudflareContext works' : 'neither has ADMIN_PASSWORD',
  })
}
