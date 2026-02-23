// Edge Function: запрос сброса пароля — отправка письма со ссылкой
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req.headers.get("Origin")) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const appUrl = Deno.env.get("APP_URL")?.trim() || "https://restodocks.app";
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();

  if (!resendKey) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const { email } = (await req.json()) as { email?: string };
    if (!email || typeof email !== "string") {
      return new Response(JSON.stringify({ error: "email required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: employees, error: empErr } = await supabase
      .from("employees")
      .select("id, full_name")
      .ilike("email", email.trim())
      .eq("is_active", true);

    if (empErr || !employees?.length) {
      return new Response(JSON.stringify({ ok: true }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const employee = employees[0];
    const token = crypto.randomUUID() + "-" + crypto.randomUUID().replace(/-/g, "");

    await supabase.from("password_reset_tokens").insert({
      employee_id: employee.id,
      token,
      expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    });

    const resetUrl = `${appUrl}/reset-password?token=${encodeURIComponent(token)}`;

    const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <onboarding@resend.dev>";

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [email.trim()],
        subject: "Восстановление доступа — Restodocks",
        html: `
<p>Здравствуйте!</p>
<p>Вы запросили восстановление доступа к Restodocks.</p>
<p>Перейдите по ссылке для смены пароля (действует 1 час):</p>
<p><a href="${resetUrl}">${resetUrl}</a></p>
<p>Если вы не запрашивали сброс пароля, проигнорируйте это письмо.</p>
<p>С уважением,<br>Команда Restodocks</p>
        `.trim(),
      }),
    });

    if (!emailRes.ok) {
      const errData = await emailRes.json();
      throw new Error(errData?.message || emailRes.statusText);
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
