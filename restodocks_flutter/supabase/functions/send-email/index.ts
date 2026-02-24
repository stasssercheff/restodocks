import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { Resend } from "npm:resend@2.0.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface EmailRequest {
  to: string
  subject: string
  html: string
  /** Optional: attachments as base64. Resend expects content as base64 string or buffer. */
  attachments?: Array<{ filename: string; content: string }>
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const resend = new Resend(Deno.env.get('RESEND_API_KEY'))

    const { to, subject, html, attachments }: EmailRequest = await req.json()

    const payload: {
      from: string
      to: string[]
      subject: string
      html: string
      attachments?: Array<{ filename: string; content: string }>
    } = {
      from: Deno.env.get('RESEND_FROM_EMAIL')?.trim() || 'Restodocks <noreply@restodocks.com>',
      to: [to],
      subject: subject,
      html: html,
    }
    if (attachments?.length) {
      payload.attachments = attachments.map((a) => ({ filename: a.filename, content: a.content }))
    }

    const { data, error } = await resend.emails.send(payload)

    if (error) {
      console.error('Resend error:', error)
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log('Email sent successfully:', data)
    return new Response(JSON.stringify({ success: true, data }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Email function error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})