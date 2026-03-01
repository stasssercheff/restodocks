import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface EmailRequest {
  to: string
  subject: string
  html: string
  /** Optional: attachments — content as base64 string */
  attachments?: Array<{ filename: string; content: string }>
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Require the Supabase anon key (or service role) — blocks unauthenticated external callers
  const expectedKey = Deno.env.get('SUPABASE_ANON_KEY')
  const providedKey = req.headers.get('apikey') || req.headers.get('Authorization')?.replace('Bearer ', '')
  if (!expectedKey || providedKey !== expectedKey) {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!serviceKey || providedKey !== serviceKey) {
      return new Response(
        JSON.stringify({ error: 'Forbidden' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
  }

  try {
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
    const RESEND_FROM = Deno.env.get('RESEND_FROM_EMAIL')?.trim() || 'Restodocks <noreply@restodocks.com>'

    const { to, subject, html, attachments }: EmailRequest = await req.json()

    console.log(`send-email: to=${to} subject="${subject}" attachments=${attachments?.length ?? 0}`)
    if (attachments?.length) {
      attachments.forEach((a, i) => {
        console.log(`  attachment[${i}]: filename=${a.filename} contentLen=${a.content?.length ?? 0}`)
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
    console.log(`send-email: Resend response status=${res.status} data=${JSON.stringify(data)}`)

    if (!res.ok) {
      console.error('Resend API error:', JSON.stringify(data))
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
