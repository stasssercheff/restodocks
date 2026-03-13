// Edge Function: смена пароля из личного кабинета (после проверки старого пароля)
// Пользователь должен быть авторизован. Ввод: старый пароль, новый пароль.
// Создаём токен, отправляем письмо. По ссылке — страница смены пароля (как при забытом пароле).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs@2";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "authorization_required" }), {
      status: 401,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const appUrl = Deno.env.get("APP_URL")?.trim() || "https://restodocks.app";
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();

  if (!resendKey) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as { old_password?: string; new_password?: string };
    const { old_password, new_password } = body;

    if (!old_password || !new_password || typeof old_password !== "string" || typeof new_password !== "string") {
      return new Response(JSON.stringify({ error: "old_password and new_password required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (new_password.length < 6) {
      return new Response(JSON.stringify({ error: "password_min_6_chars" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userErr } = await supabaseUser.auth.getUser();
    if (userErr || !user?.email) {
      return new Response(JSON.stringify({ error: "invalid_session" }), {
        status: 401,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const authUserId = user.id;
    const email = user.email;

    const { data: employees, error: empErr } = await supabaseAdmin
      .from("employees")
      .select("id, email, auth_user_id, password_hash")
      .or(`id.eq.${authUserId},auth_user_id.eq.${authUserId}`)
      .eq("is_active", true);

    if (empErr || !employees?.length) {
      return new Response(JSON.stringify({ error: "employee_not_found" }), {
        status: 404,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const employee = employees[0];
    const empEmail = (employee.email ?? email) as string;

    let oldPasswordValid = false;
    if (employee.auth_user_id) {
      const anonClient = createClient(supabaseUrl, supabaseAnonKey);
      const { error: verifyErr } = await anonClient.auth.signInWithPassword({
        email: empEmail,
        password: old_password,
      });
      oldPasswordValid = !verifyErr;
    } else {
      const ph = employee.password_hash as string | null;
      oldPasswordValid = !!ph && bcrypt.compareSync(old_password, ph);
    }

    if (!oldPasswordValid) {
      return new Response(JSON.stringify({ error: "invalid_old_password" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const token = crypto.randomUUID() + "-" + crypto.randomUUID().replace(/-/g, "");

    await supabaseAdmin.from("password_reset_tokens").insert({
      employee_id: employee.id,
      token,
      expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    });

    const resetUrl = `${appUrl}/reset-password?token=${encodeURIComponent(token)}`;

    const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <noreply@restodocks.com>";

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [empEmail],
        subject: "Подтверждение смены пароля — Restodocks",
        html: `
<p>Здравствуйте!</p>
<p>Вы запросили смену пароля в Restodocks.</p>
<p>Перейдите по ссылке, чтобы подтвердить и установить новый пароль (действует 1 час):</p>
<p><a href="${resetUrl}">${resetUrl}</a></p>
<p>После перехода введите новый пароль и войдите в учётную запись.</p>
<p>Если вы не запрашивали смену пароля, проигнорируйте это письмо.</p>
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
