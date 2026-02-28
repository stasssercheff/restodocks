import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { Resend } from "npm:resend@4.0.0"

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

  try {
    const resend = new Resend(Deno.env.get('RESEND_API_KEY'))

    const { to, subject, html, attachments }: EmailRequest = await req.json()

    console.log(`send-email: to=${to} subject="${subject}" attachments=${attachments?.length ?? 0}`)
    if (attachments?.length) {
      attachments.forEach((a, i) => {
        console.log(`  attachment[${i}]: filename=${a.filename} contentLen=${a.content?.length ?? 0}`)
      })
    }

    // Pass base64 content directly — Resend SDK accepts base64 string as attachment content
    const resolvedAttachments = attachments?.length
      ? attachments.map((a) => ({
          filename: a.filename,
          content: a.content, // base64 string, accepted by Resend
        }))
      : undefined

    const payload = {
      from: Deno.env.get('RESEND_FROM_EMAIL')?.trim() || 'Restodocks <noreply@restodocks.com>',
      to: [to],
      subject,
      html,
      ...(resolvedAttachments ? { attachments: resolvedAttachments } : {}),
    }

    console.log(`send-email: sending payload, from=${payload.from}, attachments=${resolvedAttachments?.length ?? 0}`)

    const { data, error } = await resend.emails.send(payload)

    if (error) {
      console.error('Resend error:', JSON.stringify(error))
      return new Response(JSON.stringify({ error: (error as { message?: string }).message ?? String(error) }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    console.log('Email sent successfully, id:', (data as { id?: string })?.id)
    return new Response(JSON.stringify({ ok: true, data }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('Email function error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})