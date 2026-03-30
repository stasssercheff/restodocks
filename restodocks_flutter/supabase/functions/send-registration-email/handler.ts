// Edge Function: письма при регистрации (владелец / сотрудник)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  hasValidApiKeyOrUser,
  isAllowedOrigin,
  resolveCorsHeaders,
} from "../_shared/security.ts";

const REDIRECT_URL = "https://restodocks.com/auth/confirm";
const CONFIRM_CLICK_URL = "https://restodocks.com/auth/confirm-click";

function extractTokenHashFromActionLink(actionLink: string): { token_hash: string; type: string } | null {
  try {
    const u = new URL(actionLink);
    const token = u.searchParams.get("token");
    const type = u.searchParams.get("type") || "magiclink";
    if (token && (type === "signup" || type === "magiclink")) return { token_hash: token, type };
  } catch (_) {}
  return null;
}

export async function handleRequest(req: Request): Promise<Response> {
  const cors = resolveCorsHeaders(req);
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!(await hasValidApiKeyOrUser(req)) && !isAllowedOrigin(req)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "send-registration-email", { windowMs: 60_000, maxRequests: 12 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <noreply@restodocks.com>";

  try {
    const body = (await req.json()) as {
      type: "owner" | "employee" | "registration_confirmed" | "confirmation_only";
      to: string;
      companyName?: string;
      email?: string;
      pinCode?: string;
      password?: string;
      language?: string;
    };

    const { type, to, companyName, email, pinCode, password } = body;
    const lang = normalizeLanguage(body.language);

    if (type === "confirmation_only" && to) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!supabaseUrl || !serviceKey) {
        return new Response(JSON.stringify({ error: "Service not configured" }), {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      try {
        const supabase = createClient(supabaseUrl, serviceKey);
        let link: string | null = null;
        if (password && typeof password === "string" && password.length > 0) {
          const r1 = await supabase.auth.admin.generateLink({
            type: "signup",
            email: to.trim(),
            password,
            options: { redirectTo: REDIRECT_URL },
          });
          if (!r1.error && r1.data?.properties?.action_link) link = r1.data.properties.action_link;
        }
        if (!link) {
          const r2 = await supabase.auth.admin.generateLink({
            type: "magiclink",
            email: to.trim(),
            options: { redirectTo: REDIRECT_URL },
          });
          if (!r2.error && r2.data?.properties?.action_link) link = r2.data.properties.action_link;
        }
        if (!link) {
          return new Response(JSON.stringify({ error: "Could not generate confirmation link" }), {
            status: 400,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        const extracted = extractTokenHashFromActionLink(link);
        const wrappedHref = extracted
          ? `${CONFIRM_CLICK_URL}?token_hash=${encodeURIComponent(extracted.token_hash)}&type=${encodeURIComponent(extracted.type)}`
          : `${CONFIRM_CLICK_URL}?r=${btoa(link).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`;
        const isRu = lang === "ru";
        const subject = isRu ? "Restodocks: завершите регистрацию" : "Restodocks: complete your registration";
        const html = isRu
          ? `
<p>Здравствуйте!</p>
<p>Завершите регистрацию в Restodocks — перейдите по ссылке:</p>
<p><a href="${escapeHtml(wrappedHref)}" style="color:#2754C5;text-decoration:none">Завершить регистрацию</a></p>
<p>С уважением,<br>Restodocks</p>
        `.trim()
          : `
<p>Hello!</p>
<p>Please complete your Restodocks registration using this link:</p>
<p><a href="${escapeHtml(wrappedHref)}" style="color:#2754C5;text-decoration:none">Complete registration</a></p>
<p>Best regards,<br>Restodocks</p>
        `.trim();
        const text = isRu
          ? "Здравствуйте!\n\nЗавершите регистрацию в Restodocks — откройте письмо в браузере и нажмите ссылку.\n\nС уважением,\nRestodocks"
          : "Hello!\n\nPlease complete your Restodocks registration by opening this link in your browser.\n\nBest regards,\nRestodocks";
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from,
            to: [to.trim()],
            subject,
            html,
            text,
          }),
        });
        const data = await res.json();
        if (!res.ok) {
          return new Response(JSON.stringify({ error: data?.message || res.statusText }), {
            status: res.status,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        return new Response(JSON.stringify({ id: data?.id, ok: true }), {
          headers: { ...cors, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: String(e) }), {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
    }

    if (type === "registration_confirmed") {
      if (!to) {
        return new Response(JSON.stringify({ error: "to required" }), {
          status: 400,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const isRu = lang === "ru";
      const subject = isRu ? "Регистрация подтверждена — Restodocks" : "Registration confirmed — Restodocks";
      const companyText = companyName
        ? (isRu ? ` в заведении <strong>${escapeHtml(companyName)}</strong>` : ` for <strong>${escapeHtml(companyName)}</strong>`)
        : "";
      const html = isRu
        ? `
<p>Здравствуйте!</p>
<p>Ваша регистрация${companyText} успешно подтверждена.</p>
<p>Теперь вы можете войти в приложение Restodocks, используя указанный при регистрации email и пароль.</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim()
        : `
<p>Hello!</p>
<p>Your registration${companyText} has been confirmed.</p>
<p>You can now sign in to Restodocks using your email and password.</p>
<p>Best regards,<br>Restodocks team</p>
      `.trim();

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ from, to: [to], subject, html }),
      });

      const data = await res.json();
      if (!res.ok) {
        return new Response(JSON.stringify({ error: data?.message || res.statusText }), {
          status: res.status,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ id: data?.id, ok: true }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (!type || !to || !companyName || !email) {
      return new Response(JSON.stringify({ error: "type, to, companyName, email required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    let subject: string;
    let html: string;

    if (type === "owner") {
      if (lang === "ru") {
        subject = "Регистрация компании в системе Restodocks";
        html = `
<p>Здравствуйте!</p>
<p>Регистрация вашего заведения <strong>${escapeHtml(companyName)}</strong> успешно завершена.</p>
<p>Для доступа сотрудников к системе используйте уникальный идентификатор:</p>
<p><strong>PIN-код компании: ${escapeHtml(pinCode || "")}</strong></p>
<p>Ваш логин: <strong>${escapeHtml(email)}</strong></p>
<p>Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в приложении.</p>
<p><strong>Инструкция:</strong><br>Передайте PIN-код персоналу. Им потребуется ввести его один раз при регистрации в приложении для синхронизации с базой данных вашего заведения.</p>
<p style="color:#666;font-size:14px">Отдельно придёт письмо со ссылкой для подтверждения email. Если не увидите его — проверьте папку «Спам».</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim();
      } else {
        subject = "Company registration in Restodocks";
        html = `
<p>Hello!</p>
<p>Your establishment <strong>${escapeHtml(companyName)}</strong> has been successfully registered.</p>
<p>Please use this identifier for your staff:</p>
<p><strong>Company PIN: ${escapeHtml(pinCode || "")}</strong></p>
<p>Your login: <strong>${escapeHtml(email)}</strong></p>
<p>Please use the password you entered during registration. If needed, reset it in the app.</p>
<p style="color:#666;font-size:14px">A separate email with confirmation link is sent by auth provider. Please check Spam if needed.</p>
<p>Best regards,<br>Restodocks team</p>
      `.trim();
      }
    } else {
      if (lang === "ru") {
        subject = `Доступ к корпоративному пространству ${escapeHtml(companyName)}`;
        html = `
<p>Здравствуйте!</p>
<p>Ваша учетная запись успешно привязана к системе управления заведением <strong>${escapeHtml(companyName)}</strong>.</p>
<p>Ваш логин: <strong>${escapeHtml(email)}</strong></p>
<p>Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в приложении.</p>
<p style="color:#666;font-size:14px">Отдельно придёт письмо со ссылкой для подтверждения email. Если не увидите его — проверьте папку «Спам».</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim();
      } else {
        subject = `Access to ${escapeHtml(companyName)} workspace`;
        html = `
<p>Hello!</p>
<p>Your account has been linked to <strong>${escapeHtml(companyName)}</strong>.</p>
<p>Your login: <strong>${escapeHtml(email)}</strong></p>
<p>Please use the password you entered during registration. If needed, reset it in the app.</p>
<p style="color:#666;font-size:14px">A separate email with confirmation link is sent by auth provider. Please check Spam if needed.</p>
<p>Best regards,<br>Restodocks team</p>
      `.trim();
      }
    }

    const text = html
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, "")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/\n{3,}/g, "\n\n")
      .trim();
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from, to: [to], subject, html, text }),
    });

    const data = await res.json();

    if (!res.ok) {
      return new Response(JSON.stringify({ error: data?.message || res.statusText }), {
        status: res.status,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ id: data?.id, ok: true }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function normalizeLanguage(input?: string): "ru" | "en" {
  const v = (input ?? "").trim().toLowerCase();
  return v === "ru" ? "ru" : "en";
}
