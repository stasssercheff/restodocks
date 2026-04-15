// Edge Function: письма при регистрации (владелец / сотрудник)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  hasValidApiKeyOrUser,
  resolveCorsHeaders,
} from "../_shared/security.ts";

function normalizeBaseUrl(raw: string): string {
  return raw.replace(/\/+$/, "");
}

/** Как Flutter [isPublicAppHost] + origin из APP_URL — ссылки в письме не уводят на чужой хост. */
function isAllowedAppOrigin(origin: string): boolean {
  let host: string;
  try {
    host = new URL(origin).hostname.toLowerCase();
  } catch {
    return false;
  }
  if (host === "restodocks.com" || host === "www.restodocks.com") return true;
  if (host === "restodocks.ru" || host === "www.restodocks.ru") return true;
  if (host.endsWith(".restodocks.com")) return true;
  if (host.endsWith(".restodocks.ru")) return true;
  if (
    host === "restodocks.pages.dev" ||
    host === "www.restodocks.pages.dev" ||
    host.endsWith(".restodocks.pages.dev")
  ) {
    return true;
  }
  if (host.endsWith(".pages.dev") && host.includes("restodocks")) return true;
  if (host === "localhost" || host.startsWith("127.0.0.1")) return true;
  const envUrl = Deno.env.get("APP_URL")?.trim();
  if (envUrl) {
    try {
      if (new URL(envUrl).origin === origin) return true;
    } catch (_) {}
  }
  return false;
}

/** База для ссылок в письме: тело запроса appBaseUrl (iOS/anon без Origin), иначе Origin, APP_URL, прод. */
function resolveAppBaseUrl(req: Request, body?: { appBaseUrl?: string }): string {
  const raw = body?.appBaseUrl?.trim();
  if (raw) {
    try {
      const o = new URL(raw).origin;
      if (isAllowedAppOrigin(o)) return o;
    } catch (_) {}
  }
  const origin = req.headers.get("origin")?.trim();
  if (origin) {
    try {
      const o = new URL(origin).origin;
      if (isAllowedAppOrigin(o)) return o;
    } catch (_) {}
  }
  const envUrl = Deno.env.get("APP_URL")?.trim();
  if (envUrl && (envUrl.startsWith("https://") || envUrl.startsWith("http://"))) {
    return normalizeBaseUrl(envUrl);
  }
  return "https://restodocks.com";
}

/** Resend POST /emails возвращает `{ data: { id } }`; старые ответы могли отдавать `id` наверху. */
function resendMessageId(json: unknown): string | undefined {
  if (json && typeof json === "object") {
    const o = json as Record<string, unknown>;
    const inner = o["data"];
    if (inner && typeof inner === "object") {
      const id = (inner as Record<string, unknown>)["id"];
      if (typeof id === "string" && id.length > 0) return id;
    }
    const top = o["id"];
    if (typeof top === "string" && top.length > 0) return top;
  }
  return undefined;
}

function extractTokenHashFromActionLink(actionLink: string): { token_hash: string; type: string } | null {
  try {
    const u = new URL(actionLink);
    const token = u.searchParams.get("token");
    const type = u.searchParams.get("type") || "magiclink";
    if (token && (type === "signup" || type === "magiclink")) return { token_hash: token, type };
  } catch (_) {}
  return null;
}

/**
 * Смок/watchdog: адреса *@invalid.restodocks не вызывают Resend (см. scripts/watch_edge_status_spikes.sh).
 * События смотрите в Supabase → Edge Functions → Logs, поиск по `send_registration_email_noop`.
 */
function isResendNoopRecipient(raw: string): boolean {
  const t = raw.trim().toLowerCase();
  const at = t.lastIndexOf("@");
  if (at < 1) return false;
  return t.slice(at + 1) === "invalid.restodocks";
}

export async function handleRequest(req: Request): Promise<Response> {
  const cors = resolveCorsHeaders(req);
  const reqApikey = req.headers.get("apikey")?.trim() ?? "";
  const reqAuth = req.headers.get("authorization")?.trim() ??
    req.headers.get("Authorization")?.trim() ??
    "";
  const authPrefix = reqAuth.split(" ")[0] ?? "";
  const authTokenPreview = reqAuth.includes(" ")
    ? (reqAuth.split(" ")[1] ?? "").slice(0, 16)
    : reqAuth.slice(0, 16);
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let body: {
    type: "owner" | "employee" | "co_owner" | "registration_confirmed" | "confirmation_only";
    to: string;
    companyName?: string;
    email?: string;
    fullName?: string;
    registeredAtLocal?: string;
    pinCode?: string;
    password?: string;
    language?: string;
    appBaseUrl?: string;
  };
  try {
    body = (await req.json()) as typeof body;
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  // Смок/мониторинг: не требуем auth для invalid.restodocks, чтобы не флапал 401.
  if (body?.to && isResendNoopRecipient(body.to)) {
    return new Response(JSON.stringify({ ok: true, noop: true }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  if (!(await hasValidApiKeyOrUser(req))) {
    console.log(JSON.stringify({
      event: "send_registration_email_unauthorized",
      apikey_prefix: reqApikey.slice(0, 16),
      authorization_scheme: authPrefix,
      authorization_token_prefix: authTokenPreview,
      has_origin: !!req.headers.get("origin"),
    }));
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

  try {
    const { type, to, companyName, email, fullName, pinCode, password } = body;
    const lang = normalizeLanguage(body.language);
    const appBaseUrl = resolveAppBaseUrl(req, body);
    console.log(JSON.stringify({
      event: "send_registration_email_request",
      type: type ?? null,
      to_domain: (to?.split("@")[1] ?? "").toLowerCase(),
      language: lang,
      has_password: !!password,
      apikey_prefix: reqApikey.slice(0, 16),
      authorization_scheme: authPrefix,
    }));

    if (to && isResendNoopRecipient(to)) {
      console.log(
        JSON.stringify({
          event: "send_registration_email_noop",
          message:
            "Resend skipped (test domain invalid.restodocks). See scripts/watch_edge_status_spikes.sh",
          type: type ?? null,
        }),
      );
      return new Response(JSON.stringify({ ok: true, noop: true }), {
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
    const redirectUrl = `${appBaseUrl}/auth/confirm?lang=${encodeURIComponent(lang)}`;
    const confirmClickUrl = `${appBaseUrl}/auth/confirm-click`;

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
            options: { redirectTo: redirectUrl },
          });
          if (!r1.error && r1.data?.properties?.action_link) link = r1.data.properties.action_link;
        }
        if (!link) {
          const r2 = await supabase.auth.admin.generateLink({
            type: "magiclink",
            email: to.trim(),
            options: { redirectTo: redirectUrl },
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
          ? `${confirmClickUrl}?token_hash=${encodeURIComponent(extracted.token_hash)}&type=${encodeURIComponent(extracted.type)}&lang=${encodeURIComponent(lang)}`
          : `${confirmClickUrl}?r=${btoa(link).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}&lang=${encodeURIComponent(lang)}`;
        const copy = i18nCopy(lang);
        const subject = copy.confirmSubject;
        const greeting = fullName?.trim()
          ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!`
          : copy.greeting;
        const html = `
<p>${greeting}</p>
<p>${copy.confirmIntro}</p>
<p><a href="${escapeHtml(wrappedHref)}" style="color:#2754C5;text-decoration:none">${copy.confirmCta}</a></p>
<p>${copy.regards}<br>Restodocks</p>
        `.trim();
        const text = `${greeting}\n\n${copy.confirmIntro}\n\n${copy.regards}\nRestodocks`;
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
        const payload = await res.json();
        if (!res.ok) {
          console.log(JSON.stringify({
            event: "send_registration_email_resend_error",
            type: "confirmation_only",
            status: res.status,
            message: payload?.message ?? null,
          }));
          return new Response(JSON.stringify({ error: payload?.message || res.statusText }), {
            status: res.status,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        const msgId = resendMessageId(payload);
        if (!msgId) {
          return new Response(JSON.stringify({ error: "Resend OK but no message id in response" }), {
            status: 502,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        return new Response(JSON.stringify({ id: msgId, ok: true }), {
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
      const copy = i18nCopy(lang);
      const subject = copy.confirmedSubject;
      const companyText = companyName
        ? (lang === "ru"
            ? ` в заведении <strong>${escapeHtml(companyName)}</strong>`
            : ` <strong>${escapeHtml(companyName)}</strong>`)
        : "";
      const html = `
<p>${copy.greeting}</p>
<p>${copy.confirmedIntro}${companyText}.</p>
<p>${copy.confirmedSigninHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ from, to: [to], subject, html }),
      });

      const payload = await res.json();
      if (!res.ok) {
        console.log(JSON.stringify({
          event: "send_registration_email_resend_error",
          type: "registration_confirmed",
          status: res.status,
          message: payload?.message ?? null,
        }));
        return new Response(JSON.stringify({ error: payload?.message || res.statusText }), {
          status: res.status,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const msgId = resendMessageId(payload);
      if (!msgId) {
        return new Response(JSON.stringify({ error: "Resend OK but no message id in response" }), {
          status: 502,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ id: msgId, ok: true }), {
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
        const copy = i18nCopy(lang);
        const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
        subject = copy.ownerSubject;
        html = `
<p>${greeting}</p>
<p>${copy.welcomeLead}</p>
<p>${copy.ownerRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong> ${copy.ownerRegisteredSuffix}</p>
<p>${copy.ownerIdentifierHint}</p>
<p><strong>${copy.companyPinLabel}: ${escapeHtml(pinCode || "")}</strong></p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p><strong>${copy.instructionLabel}:</strong><br>${copy.ownerInstruction}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();
      } else {
        const copy = i18nCopy(lang);
        const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
        subject = copy.ownerSubject;
        html = `
<p>${greeting}</p>
<p>${copy.welcomeLead}</p>
<p>${copy.ownerRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong> ${copy.ownerRegisteredSuffix}</p>
<p>${copy.ownerIdentifierHint}</p>
<p><strong>${copy.companyPinLabel}: ${escapeHtml(pinCode || "")}</strong></p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();
      }
    } else if (type === "co_owner") {
      const copy = i18nCopy(lang);
      const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
      subject = copy.coOwnerSubject;
      html = `
<p>${greeting}</p>
<p>${copy.welcomeLead}</p>
<p>${copy.coOwnerRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong> ${copy.coOwnerRegisteredSuffix}</p>
<p>${copy.ownerIdentifierHint}</p>
<p><strong>${copy.companyPinLabel}: ${escapeHtml(pinCode || "")}</strong></p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p><strong>${copy.instructionLabel}:</strong><br>${copy.coOwnerInstruction}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();
    } else {
      if (lang === "ru") {
        const copy = i18nCopy(lang);
        const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
        subject = `${copy.employeeSubjectPrefix} ${escapeHtml(companyName)}`;
        html = `
<p>${greeting}</p>
<p>${copy.employeeRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong>.</p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();
      } else {
        const copy = i18nCopy(lang);
        const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
        subject = `${copy.employeeSubjectPrefix} ${escapeHtml(companyName)}`;
        html = `
<p>${greeting}</p>
<p>${copy.employeeRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong>.</p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
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

    const payload = await res.json();

    if (!res.ok) {
      console.log(JSON.stringify({
        event: "send_registration_email_resend_error",
        type: type ?? null,
        status: res.status,
        message: payload?.message ?? null,
      }));
      return new Response(JSON.stringify({ error: payload?.message || res.statusText }), {
        status: res.status,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const msgId = resendMessageId(payload);
    if (!msgId) {
      return new Response(JSON.stringify({ error: "Resend OK but no message id in response" }), {
        status: 502,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ id: msgId, ok: true }), {
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

function normalizeLanguage(input?: string): "ru" | "en" | "es" | "it" | "tr" | "vi" {
  const v = (input ?? "").trim().toLowerCase();
  if (v === "ru" || v === "en" || v === "es" || v === "it" || v === "tr" || v === "vi") return v;
  return "en";
}

type MailLanguage = "ru" | "en" | "es" | "it" | "tr" | "vi";
type MailCopy = {
  greeting: string;
  greetingNamePrefix: string;
  regards: string;
  confirmSubject: string;
  confirmIntro: string;
  confirmCta: string;
  confirmedSubject: string;
  confirmedIntro: string;
  confirmedSigninHint: string;
  ownerSubject: string;
  ownerRegisteredPrefix: string;
  ownerRegisteredSuffix: string;
  ownerIdentifierHint: string;
  companyPinLabel: string;
  yourLoginLabel: string;
  passwordHint: string;
  instructionLabel: string;
  ownerInstruction: string;
  coOwnerSubject: string;
  coOwnerRegisteredPrefix: string;
  coOwnerRegisteredSuffix: string;
  coOwnerInstruction: string;
  employeeSubjectPrefix: string;
  employeeRegisteredPrefix: string;
  spamHint: string;
  registrationTimeLabel: string;
  /** Одна строка после приветствия: «добро пожаловать» + контекст письма с PIN/логином */
  welcomeLead: string;
};

function i18nCopy(lang: MailLanguage): MailCopy {
  switch (lang) {
    case "ru":
      return {
        greeting: "Здравствуйте!",
        greetingNamePrefix: "Здравствуйте",
        regards: "С уважением,",
        confirmSubject: "Restodocks: завершите регистрацию",
        confirmIntro: "Завершите регистрацию в Restodocks — перейдите по ссылке:",
        confirmCta: "Завершить регистрацию",
        confirmedSubject: "Регистрация подтверждена — Restodocks",
        confirmedIntro: "Ваша регистрация",
        confirmedSigninHint: "Теперь вы можете войти в систему Restodocks, используя указанный при регистрации email и пароль.",
        ownerSubject: "Регистрация компании в системе Restodocks",
        ownerRegisteredPrefix: "Регистрация вашего заведения",
        ownerRegisteredSuffix: "успешно завершена.",
        ownerIdentifierHint: "Для доступа сотрудников к системе используйте уникальный идентификатор:",
        companyPinLabel: "PIN-код компании",
        yourLoginLabel: "Ваш логин",
        passwordHint: "Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в системе.",
        instructionLabel: "Инструкция",
        ownerInstruction: "Передайте PIN-код персоналу. Им потребуется ввести его один раз при регистрации в системе для синхронизации с базой данных вашего заведения.",
        coOwnerSubject: "Регистрация доп. собственника в системе Restodocks",
        coOwnerRegisteredPrefix: "Регистрация дополнительного собственника в заведении",
        coOwnerRegisteredSuffix: "успешно завершена.",
        coOwnerInstruction: "Используйте PIN-код заведения при работе команды. Для входа в систему используйте email и пароль, указанные при регистрации.",
        employeeSubjectPrefix: "Доступ к корпоративному пространству",
        employeeRegisteredPrefix: "Ваша учетная запись успешно привязана к системе управления заведением",
        spamHint:
          "Вторым письмом (чуть позже) может прийти ссылка для подтверждения email — проверьте «Спам» и вкладку «Промоакции». Если письма с PIN не было — смотрите логи Edge send-registration-email в Supabase.",
        registrationTimeLabel: "Время регистрации",
        welcomeLead:
          "<strong>Добро пожаловать в Restodocks!</strong> Ниже — данные заведения: PIN для персонала и ваш логин (email) для входа.",
      };
    case "es":
      return {
        greeting: "Hola!",
        greetingNamePrefix: "Hola",
        regards: "Saludos,",
        confirmSubject: "Restodocks: complete su registro",
        confirmIntro: "Complete su registro en Restodocks con este enlace:",
        confirmCta: "Completar registro",
        confirmedSubject: "Registro confirmado — Restodocks",
        confirmedIntro: "Su registro en",
        confirmedSigninHint: "Ahora puede iniciar sesión en Restodocks con su correo y contraseña.",
        ownerSubject: "Registro de empresa en Restodocks",
        ownerRegisteredPrefix: "Su establecimiento",
        ownerRegisteredSuffix: "se ha registrado correctamente.",
        ownerIdentifierHint: "Use este identificador para su personal:",
        companyPinLabel: "PIN de la empresa",
        yourLoginLabel: "Su acceso",
        passwordHint: "Use la contraseña que indicó al registrarse. Si es necesario, restablézcala en el sistema.",
        instructionLabel: "Instrucción",
        ownerInstruction: "Comparta el PIN con el personal. Lo necesitarán una vez al registrarse en el sistema.",
        coOwnerSubject: "Registro de copropietario en Restodocks",
        coOwnerRegisteredPrefix: "Su acceso de copropietario para",
        coOwnerRegisteredSuffix: "ha sido activado.",
        coOwnerInstruction: "Comparta el PIN del establecimiento con su equipo. Para iniciar sesión use su correo y contraseña.",
        employeeSubjectPrefix: "Acceso al espacio de",
        employeeRegisteredPrefix: "Su cuenta se vinculó correctamente a",
        spamHint: "También llegará un correo de confirmación. Revise Spam si no aparece.",
        registrationTimeLabel: "Hora de registro",
        welcomeLead:
          "<strong>¡Bienvenido a Restodocks!</strong> A continuación: PIN del establecimiento y su acceso (email) para iniciar sesión.",
      };
    case "it":
      return {
        greeting: "Ciao!",
        greetingNamePrefix: "Ciao",
        regards: "Cordiali saluti,",
        confirmSubject: "Restodocks: completa la registrazione",
        confirmIntro: "Completa la registrazione a Restodocks con questo link:",
        confirmCta: "Completa registrazione",
        confirmedSubject: "Registrazione confermata — Restodocks",
        confirmedIntro: "La tua registrazione per",
        confirmedSigninHint: "Ora puoi accedere a Restodocks con email e password.",
        ownerSubject: "Registrazione azienda in Restodocks",
        ownerRegisteredPrefix: "La tua struttura",
        ownerRegisteredSuffix: "è stata registrata con successo.",
        ownerIdentifierHint: "Usa questo identificatore per il personale:",
        companyPinLabel: "PIN aziendale",
        yourLoginLabel: "Il tuo login",
        passwordHint: "Usa la password scelta in registrazione. Se necessario, reimpostala nel sistema.",
        instructionLabel: "Istruzioni",
        ownerInstruction: "Condividi il PIN con il personale: servirà una sola volta alla registrazione nel sistema.",
        coOwnerSubject: "Registrazione co-proprietario in Restodocks",
        coOwnerRegisteredPrefix: "Il tuo accesso come co-proprietario a",
        coOwnerRegisteredSuffix: "è stato attivato.",
        coOwnerInstruction: "Condividi il PIN della struttura con il team. Per accedere usa email e password.",
        employeeSubjectPrefix: "Accesso allo spazio di",
        employeeRegisteredPrefix: "Il tuo account è stato collegato a",
        spamHint: "Arriverà anche un'email di conferma. Controlla Spam se necessario.",
        registrationTimeLabel: "Orario registrazione",
        welcomeLead:
          "<strong>Benvenuto in Restodocks!</strong> Di seguito: PIN della struttura e il tuo login (email) per l'accesso.",
      };
    case "tr":
      return {
        greeting: "Merhaba!",
        greetingNamePrefix: "Merhaba",
        regards: "Saygılarımızla,",
        confirmSubject: "Restodocks: kaydınızı tamamlayın",
        confirmIntro: "Restodocks kaydınızı şu bağlantı ile tamamlayın:",
        confirmCta: "Kaydı tamamla",
        confirmedSubject: "Kayıt onaylandı — Restodocks",
        confirmedIntro: "Şu işletme için kaydınız onaylandı:",
        confirmedSigninHint: "Artık Restodocks'a e-posta ve şifrenizle giriş yapabilirsiniz.",
        ownerSubject: "Restodocks işletme kaydı",
        ownerRegisteredPrefix: "İşletmeniz",
        ownerRegisteredSuffix: "başarıyla kaydedildi.",
        ownerIdentifierHint: "Personel için bu tanımlayıcıyı kullanın:",
        companyPinLabel: "Şirket PIN",
        yourLoginLabel: "Girişiniz",
        passwordHint: "Kayıtta belirlediğiniz şifreyi kullanın. Gerekirse sistemde sıfırlayın.",
        instructionLabel: "Talimat",
        ownerInstruction: "PIN'i personele iletin. Sistemde ilk kayıtta bir kez gerekir.",
        coOwnerSubject: "Restodocks ortak sahip kaydı",
        coOwnerRegisteredPrefix: "Şu işletme için ortak sahip erişiminiz",
        coOwnerRegisteredSuffix: "etkinleştirildi.",
        coOwnerInstruction: "İşletme PIN kodunu ekiple paylaşın. Giriş için e-posta ve şifrenizi kullanın.",
        employeeSubjectPrefix: "Çalışma alanına erişim:",
        employeeRegisteredPrefix: "Hesabınız şu işletmeye bağlandı:",
        spamHint: "Ayrıca onay bağlantısı e-postası gelir. Gerekirse Spam'i kontrol edin.",
        registrationTimeLabel: "Kayıt zamanı",
        welcomeLead:
          "<strong>Restodocks'a hoş geldiniz!</strong> Aşağıda: işletme PIN'i ve giriş için e-postanız.",
      };
    case "vi":
      return {
        greeting: "Xin chào!",
        greetingNamePrefix: "Xin chào",
        regards: "Trân trọng,",
        confirmSubject: "Restodocks: hoàn tất đăng ký",
        confirmIntro: "Vui lòng hoàn tất đăng ký Restodocks bằng liên kết này:",
        confirmCta: "Hoàn tất đăng ký",
        confirmedSubject: "Đăng ký đã xác nhận — Restodocks",
        confirmedIntro: "Đăng ký của bạn cho",
        confirmedSigninHint: "Bây giờ bạn có thể đăng nhập Restodocks bằng email và mật khẩu.",
        ownerSubject: "Đăng ký cơ sở trong Restodocks",
        ownerRegisteredPrefix: "Cơ sở của bạn",
        ownerRegisteredSuffix: "đã được đăng ký thành công.",
        ownerIdentifierHint: "Vui lòng dùng mã định danh này cho nhân viên:",
        companyPinLabel: "PIN cơ sở",
        yourLoginLabel: "Đăng nhập của bạn",
        passwordHint: "Dùng mật khẩu đã đặt khi đăng ký. Nếu cần, đặt lại trong hệ thống.",
        instructionLabel: "Hướng dẫn",
        ownerInstruction: "Chia sẻ PIN cho nhân viên. Họ chỉ cần nhập một lần khi đăng ký trong hệ thống.",
        coOwnerSubject: "Đăng ký đồng sở hữu trong Restodocks",
        coOwnerRegisteredPrefix: "Quyền truy cập đồng sở hữu của bạn cho",
        coOwnerRegisteredSuffix: "đã được kích hoạt.",
        coOwnerInstruction: "Chia sẻ mã PIN cơ sở với đội ngũ. Đăng nhập bằng email và mật khẩu đã đăng ký.",
        employeeSubjectPrefix: "Quyền truy cập không gian của",
        employeeRegisteredPrefix: "Tài khoản của bạn đã được liên kết với",
        spamHint: "Một email xác nhận riêng sẽ được gửi. Hãy kiểm tra Spam nếu cần.",
        registrationTimeLabel: "Thời gian đăng ký",
        welcomeLead:
          "<strong>Chào mừng đến Restodocks!</strong> Bên dưới: PIN cơ sở và email đăng nhập của bạn.",
      };
    case "en":
    default:
      return {
        greeting: "Hello!",
        greetingNamePrefix: "Hello",
        regards: "Best regards,",
        confirmSubject: "Restodocks: complete your registration",
        confirmIntro: "Please complete your Restodocks registration using this link:",
        confirmCta: "Complete registration",
        confirmedSubject: "Registration confirmed — Restodocks",
        confirmedIntro: "Your registration for",
        confirmedSigninHint: "You can now sign in to Restodocks using your email and password.",
        ownerSubject: "Company registration in Restodocks",
        ownerRegisteredPrefix: "Your establishment",
        ownerRegisteredSuffix: "has been successfully registered.",
        ownerIdentifierHint: "Please use this identifier for your staff:",
        companyPinLabel: "Company PIN",
        yourLoginLabel: "Your login",
        passwordHint: "Please use the password you entered during registration. If needed, reset it in Restodocks (sign-in / recovery).",
        instructionLabel: "Instruction",
        ownerInstruction: "Share the PIN with your staff. They will need it once when registering in the system.",
        coOwnerSubject: "Co-owner registration in Restodocks",
        coOwnerRegisteredPrefix: "Your co-owner access for",
        coOwnerRegisteredSuffix: "has been activated.",
        coOwnerInstruction: "Share the establishment PIN with your team. Sign in using your email and password.",
        employeeSubjectPrefix: "Access to",
        employeeRegisteredPrefix: "Your account has been linked to",
        spamHint: "A separate email with the confirmation link may follow shortly — please check Spam. If the PIN email is missing, check Edge logs for send-registration-email.",
        registrationTimeLabel: "Registration time",
        welcomeLead:
          "<strong>Welcome to Restodocks!</strong> Below: your establishment PIN and login (email) for sign-in.",
      };
  }
}
