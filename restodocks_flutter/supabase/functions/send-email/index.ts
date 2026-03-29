import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import {
  enforceRateLimit,
  enforceRateLimitByIdentity,
  getAuthenticatedUserId,
  hasValidApiKeyOrUser,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts"

const MAX_SUBJECT_LEN = 900
const MAX_HTML_LEN = 450_000
const MAX_TO_LEN = 320
/** Вложения: суммарно base64 не больше ~2MB на письмо (заказ PDF). */
const MAX_ATTACHMENT_TOTAL_B64 = 2_800_000

interface EmailRequest {
  to: string
  subject: string
  html: string
  /** Optional: attachments — content as base64 string */
  attachments?: Array<{ filename: string; content: string }>
}

serve(async (req) => {
  const corsHeaders = resolveCorsHeaders(req)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
  if (!(await hasValidApiKeyOrUser(req))) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req)
  // Вызовы с service role (другие Edge Functions, админ) — только общий лимит по IP.
  if (isService) {
    if (!enforceRateLimit(req, "send-email:svc", { windowMs: 60_000, maxRequests: 120 })) {
      return new Response(
        JSON.stringify({ error: 'Too many requests' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  } else {
    const uid = await getAuthenticatedUserId(req)
    if (!uid) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    if (
      !enforceRateLimit(req, "send-email", { windowMs: 60_000, maxRequests: 20 }) ||
      !enforceRateLimitByIdentity(uid, "send-email:user-hour", {
        windowMs: 3_600_000,
        maxRequests: 40,
      })
    ) {
      return new Response(
        JSON.stringify({ error: 'Too many requests' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  }

  try {
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
    const RESEND_FROM = Deno.env.get('RESEND_FROM_EMAIL')?.trim() || 'Restodocks <noreply@restodocks.com>'

    const { to, subject, html, attachments }: EmailRequest = await req.json()

    if (typeof to !== "string" || typeof subject !== "string" || typeof html !== "string") {
      return new Response(
        JSON.stringify({ error: 'Invalid payload' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    const toTrim = to.trim()
    if (!toTrim || toTrim.length > MAX_TO_LEN) {
      return new Response(
        JSON.stringify({ error: 'Invalid recipient' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    if (subject.length > MAX_SUBJECT_LEN || html.length > MAX_HTML_LEN) {
      return new Response(
        JSON.stringify({ error: 'Payload too large' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    let attachB64Total = 0
    if (attachments?.length) {
      for (const a of attachments) {
        const c = a?.content
        if (typeof c === "string") attachB64Total += c.length
      }
      if (attachB64Total > MAX_ATTACHMENT_TOTAL_B64) {
        return new Response(
          JSON.stringify({ error: 'Attachments too large' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    console.log(`send-email: request received attachments=${attachments?.length ?? 0}`)
    if (attachments?.length) {
      attachments.forEach((a, i) => {
        console.log(`  attachment[${i}]: contentLen=${a.content?.length ?? 0}`)
      })
    }

    const payload: Record<string, unknown> = {
      from: RESEND_FROM,
      to: [toTrim],
      subject,
      html,
    }

    if (attachments?.length) {
      // Resend REST API accepts content as base64 string directly
      payload.attachments = attachments.map((a) => ({
        filename: a.filename,
        content: a.content,
      }))
    }

    console.log(`send-email: calling Resend API, from=${RESEND_FROM}, attachments=${attachments?.length ?? 0}`)

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(payload),
    })

    const data = await res.json()
    console.log(`send-email: Resend response status=${res.status}`)
    if (!res.ok) {
      console.error('Resend API error: failed to send email')
      return new Response(
        JSON.stringify({ error: data?.message ?? data?.error ?? String(data) }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ ok: true, data }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )

  } catch (err) {
    console.error('Email function error:', err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
