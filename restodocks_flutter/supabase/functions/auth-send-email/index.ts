// Send Email Auth Hook — Supabase вызывает вместо SMTP. Отправка через Resend.
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://osglfptwbuqqmqunttha.supabase.co";
// Как в send-registration-email: веб открывает /auth/confirm-click → verifyOTP(token_hash), без «съедания» токена prefetch-ом.
const CONFIRM_CLICK_URL = "https://restodocks.com/auth/confirm-click";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST", "Access-Control-Allow-Headers": "authorization, content-type" } });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 400, headers: { "Content-Type": "application/json" } });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  const hookSecretRaw = Deno.env.get("SEND_EMAIL_HOOK_SECRET");
  if (!apiKey || !hookSecretRaw) {
    console.error("RESEND_API_KEY or SEND_EMAIL_HOOK_SECRET not set");
    return new Response(JSON.stringify({ error: "Hook not configured" }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
  const hookSecret = hookSecretRaw.replace(/^v1,whsec_/i, "");
  const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <noreply@restodocks.com>";

  try {
    const payload = await req.text();
    const headers = Object.fromEntries(req.headers);
    console.log("auth-send-email: received request, content-type:", headers["content-type"]);
    const wh = new Webhook(hookSecret);
    const { user, email_data } = wh.verify(payload, headers) as {
      user: { email: string };
      email_data: { token: string; token_hash: string; redirect_to: string; email_action_type: string; site_url: string };
    };

    const { token_hash, redirect_to, email_action_type } = email_data;
    // Supabase GET /verify ожидает параметр "token" (значение = token_hash). token_hash= не работает.
    const verifyUrl = `${SUPABASE_URL}/auth/v1/verify?token=${encodeURIComponent(token_hash)}&type=${encodeURIComponent(email_action_type)}&redirect_to=${encodeURIComponent(redirect_to)}`;

    const subjectMap: Record<string, string> = {
      signup: "Подтвердите регистрацию — Restodocks",
      magiclink: "Вход по ссылке — Restodocks",
      recovery: "Сброс пароля — Restodocks",
      invite: "Приглашение в Restodocks",
    };
    const subject = subjectMap[email_action_type] ?? "Restodocks";

    const html = `
<p>Здравствуйте!</p>
<p>Нажмите на ссылку для подтверждения:</p>
<p><a href="${confirmClickHref}" style="color:#2754C5;text-decoration:underline">Подтвердить</a></p>
<p>Или скопируйте ссылку в браузер:</p>
<p style="word-break:break-all;font-size:12px;color:#666">${confirmClickHref}</p>
<p>Если вы не регистрировались — проигнорируйте это письмо.</p>
<p>С уважением,<br>Команда Restodocks</p>
    `.trim();

    console.log("auth-send-email: sending to", user.email, "type=", email_action_type);
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [user.email], subject, html }),
    });

    const data = await res.json();
    if (!res.ok) {
      console.error("Resend error:", data);
      return new Response(JSON.stringify({ error: { http_code: res.status, message: data?.message ?? "Resend error" } }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log("auth-send-email: success, id=", data?.id);
    return new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const stack = e instanceof Error ? e.stack : "";
    console.error("auth-send-email ERROR:", msg);
    if (msg.includes("signature") || msg.includes("verify")) {
      console.error("auth-send-email: SEND_EMAIL_HOOK_SECRET в Secrets должен совпадать с секретом в Auth Hooks");
    }
    // "No matching signature" = SEND_EMAIL_HOOK_SECRET не совпадает с секретом в Dashboard Hooks
    return new Response(
      JSON.stringify({ error: { http_code: 500, message: msg } }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }
});
