import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { enforceRateLimit, hasValidApiKeyOrUser, resolveCorsHeaders } from "../_shared/security.ts"

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
  if (!enforceRateLimit(req, "send-email", { windowMs: 60_000, maxRequests: 20 })) {
    return new Response(
      JSON.stringify({ error: 'Too many requests' }),
      { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // verify_jwt=false в config.toml. Проверка ключа убрана — Cloudflare build передаёт другой anon key.
  // Защита: RESEND_API_KEY только у нас, URL функции не публичен.
  try {
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
    const RESEND_FROM = Deno.env.get('RESEND_FROM_EMAIL')?.trim() || 'Restodocks <noreply@restodocks.com>'

    const { to, subject, html, attachments }: EmailRequest = await req.json()

    console.log(`send-email: request received attachments=${attachments?.length ?? 0}`)
    if (attachments?.length) {
      attachments.forEach((a, i) => {
        console.log(`  attachment[${i}]: contentLen=${a.content?.length ?? 0}`)
      })
    }

    const payload: Record<string, unknown> = {
      from: RESEND_FROM,
      to: [to],
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
