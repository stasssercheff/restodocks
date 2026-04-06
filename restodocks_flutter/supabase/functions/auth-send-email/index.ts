// Send Email Auth Hook — Supabase вызывает вместо SMTP. Отправка через Resend.
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://osglfptwbuqqmqunttha.supabase.co";
const DEFAULT_SITE_ORIGIN = "https://restodocks.com";

type Lang = "ru" | "en" | "es" | "it" | "tr" | "vi";

function normalizeLanguage(input?: string): Lang {
  const v = (input ?? "").trim().toLowerCase();
  if (v === "ru" || v === "en" || v === "es" || v === "it" || v === "tr" || v === "vi") return v;
  return "en";
}

/** Origin кнопки «Подтвердить»: тот же, что в redirect_to при signUp (бэта/прод/iOS через PUBLIC_APP_ORIGIN). */
function originForConfirmClick(redirectTo: string, siteUrl?: string): string {
  for (const raw of [redirectTo, siteUrl]) {
    if (!raw) continue;
    try {
      return new URL(raw).origin;
    } catch (_) {}
  }
  return DEFAULT_SITE_ORIGIN;
}

function languageForConfirmEmail(redirectTo: string | undefined, metadataLang: Lang): Lang {
  if (!redirectTo) return metadataLang;
  try {
    const u = new URL(redirectTo);
    if (u.searchParams.has("lang")) {
      return normalizeLanguage(u.searchParams.get("lang") ?? undefined);
    }
  } catch (_) {}
  return metadataLang;
}

function copy(lang: Lang) {
  switch (lang) {
    case "ru":
      return {
        greeting: "Здравствуйте!",
        actionLine: "Чтобы завершить регистрацию в Restodocks, нажмите на ссылку:",
        cta: "Подтвердить email",
        fallback: "Если кнопка не открывается, скопируйте ссылку в браузер:",
        ignore: "Если вы не регистрировались — проигнорируйте это письмо.",
        regards: "С уважением,\nКоманда Restodocks",
        subjects: {
          signup: "Подтвердите регистрацию — Restodocks",
          magiclink: "Вход по ссылке — Restodocks",
          recovery: "Сброс пароля — Restodocks",
          invite: "Приглашение в Restodocks",
        } as Record<string, string>,
      };
    default:
      return {
        greeting: "Hello!",
        actionLine: "Please complete your Restodocks registration using this link:",
        cta: "Confirm email",
        fallback: "If the button does not open, copy this link in your browser:",
        ignore: "If you did not request this, please ignore this email.",
        regards: "Best regards,\nRestodocks team",
        subjects: {
          signup: "Confirm registration — Restodocks",
          magiclink: "Sign in link — Restodocks",
          recovery: "Password reset — Restodocks",
          invite: "Invitation to Restodocks",
        } as Record<string, string>,
      };
  }
}

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
      user: { email: string; user_metadata?: Record<string, unknown> };
      email_data: { token: string; token_hash: string; redirect_to: string; email_action_type: string; site_url: string };
    };

    const { token_hash, redirect_to, email_action_type } = email_data;
    const actionType = (email_action_type ?? "").trim().toLowerCase();
    // Регистрация: письмо со ссылкой уже шлёт send-registration-email (confirmation_only) из приложения.
    // Иначе три письма: Hook + «данные» + Edge-подтверждение.
    if (actionType === "signup") {
      console.log(
        "auth-send-email: skip Resend for signup (send-registration-email confirmation_only)",
      );
      return new Response(JSON.stringify({}), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Supabase GET /verify ожидает параметр "token" (значение = token_hash). token_hash= не работает.
    const verifyUrl = `${SUPABASE_URL}/auth/v1/verify?token=${encodeURIComponent(token_hash)}&type=${encodeURIComponent(email_action_type)}&redirect_to=${encodeURIComponent(redirect_to)}`;

    const metadataLang = normalizeLanguage(user.user_metadata?.["interface_language"]?.toString());
    const lang = languageForConfirmEmail(redirect_to, metadataLang);
    const clickOrigin = originForConfirmClick(redirect_to, email_data.site_url);
    const confirmClickBase = `${clickOrigin}/auth/confirm-click`;

    const confirmClickHref =
      actionType === "magiclink"
        ? `${confirmClickBase}?token_hash=${encodeURIComponent(token_hash)}&type=${encodeURIComponent(email_action_type)}&lang=${encodeURIComponent(lang)}`
        : verifyUrl;
    const i18n = copy(lang);
    const subject = i18n.subjects[email_action_type] ?? "Restodocks";

    const html = `
<p>${i18n.greeting}</p>
<p>${i18n.actionLine}</p>
<p><a href="${confirmClickHref}" style="color:#2754C5;text-decoration:underline">${i18n.cta}</a></p>
<p>${i18n.fallback}</p>
<p style="word-break:break-all;font-size:12px;color:#666">${confirmClickHref}</p>
<p>${i18n.ignore}</p>
<p>${i18n.regards.replace("\n", "<br>")}</p>
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
