import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  record: any
  schema: string
  old_record: any | null
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const payload: WebhookPayload = await req.json()
    const { record } = payload

    // Check if this is a new user confirmation (email_confirmed_at was set)
    if (payload.type === 'UPDATE' &&
        payload.table === 'users' &&
        payload.schema === 'auth' &&
        record.email_confirmed_at &&
        !payload.old_record?.email_confirmed_at) {

      const userId = record.id
      const userEmail = record.email

      // Get employee data
      const { data: employee, error: empError } = await supabaseClient
        .from('employees')
        .select(`
          *,
          establishments (
            name,
            pin_code
          )
        `)
        .eq('id', userId)
        .single()

      if (empError || !employee) {
        console.log('Employee not found for user:', userId)
        return new Response(JSON.stringify({ error: 'Employee not found' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      const establishment = employee.establishments
      const isOwner = employee.roles?.includes('owner')

      // Prepare welcome email
      let subject: string
      let htmlContent: string

      if (isOwner && establishment) {
        // Owner welcome email
        subject = `Регистрация компании в системе Restodocks`
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2>Здравствуйте!</h2>
            <p>Регистрация вашего заведения <strong>${establishment.name}</strong> успешно завершена.</p>
            <p>Для доступа сотрудников к системе используйте уникальный идентификатор:</p>
            <p><strong>PIN-код компании: ${establishment.pin_code}</strong></p>
            <p><strong>Ваш логин:</strong> ${userEmail}</p>
            <p><strong>Ваш пароль:</strong> [Указанный при регистрации]</p>
            <p><em>Инструкция: Передайте данный код персоналу. Им потребуется ввести его один раз при регистрации в приложении для синхронизации с базой данных вашего заведения.</em></p>
            <br>
            <p>С уважением,<br>Команда Restodocks</p>
          </div>
        `
      } else if (establishment) {
        // Employee welcome email
        subject = `Доступ к корпоративному пространству ${establishment.name}`
        htmlContent = `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2>Здравствуйте!</h2>
            <p>Ваша учетная запись успешно привязана к системе управления заведением <strong>${establishment.name}</strong>.</p>
            <p><strong>Ваш логин:</strong> ${userEmail}</p>
            <p><strong>Ваш пароль:</strong> [Указанный при регистрации]</p>
            <br>
            <p>С уважением,<br>Команда Restodocks</p>
          </div>
        `
      } else {
        console.log('No establishment found for employee:', employee.id)
        return new Response(JSON.stringify({ error: 'No establishment found' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      // Send welcome email
      const { error: emailError } = await supabaseClient.functions.invoke('send-email', {
        body: {
          to: userEmail,
          subject: subject,
          html: htmlContent
        }
      })

      if (emailError) {
        console.error('Failed to send welcome email:', emailError)
        return new Response(JSON.stringify({ error: 'Failed to send email' }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      console.log('Welcome email sent to:', userEmail)
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Webhook error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})