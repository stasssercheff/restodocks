import { getCloudflareContext } from '@opennextjs/cloudflare'

/**
 * Gets ADMIN_PASSWORD from Cloudflare Worker env (production) or process.env (local dev).
 * On Cloudflare, process.env may not have runtime secrets; getCloudflareContext().env does.
 */
export async function getAdminPassword(): Promise<string | undefined> {
  try {
    const { env } = await getCloudflareContext()
    return (env as { ADMIN_PASSWORD?: string }).ADMIN_PASSWORD
  } catch {
    return process.env.ADMIN_PASSWORD
  }
}
