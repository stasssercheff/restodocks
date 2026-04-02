// Edge Function: письма при регистрации (владелец / сотрудник)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  hasValidApiKeyOrUser,
  resolveCorsHeaders,
} from "../_shared/security.ts";

function resolveAppBaseUrl(req: Request): string {
  const origin = req.headers.get("origin")?.trim();
  if (origin && /^https:\/\/([a-z0-9-]+\.)*restodocks\.pages\.dev$/i.test(origin)) {
    return origin;
  }
  if (origin && /^https:\/\/(www\.)?restodocks\.com$/i.test(origin)) {
    return origin;
  }
  const envUrl = Deno.env.get("APP_URL")?.trim();
  if (envUrl && (envUrl.startsWith("https://") || envUrl.startsWith("http://"))) {
    return envUrl.replace(/\/+$/, "");
  }
  return "https://restodocks.com";
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

export async function handleRequest(req: Request): Promise<Response> {
  const cors = resolveCorsHeaders(req);
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!(await hasValidApiKeyOrUser(req))) {
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
      fullName?: string;
      registeredAtLocal?: string;
      pinCode?: string;
      password?: string;
      language?: string;
    };

    const { type, to, companyName, email, fullName, pinCode, password } = body;
    const lang = normalizeLanguage(body.language);
    const appBaseUrl = resolveAppBaseUrl(req);
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
        const html = `
<p>${copy.greeting}</p>
<p>${copy.confirmIntro}</p>
<p><a href="${escapeHtml(wrappedHref)}" style="color:#2754C5;text-decoration:none">${copy.confirmCta}</a></p>
<p>${copy.regards}<br>Restodocks</p>
        `.trim();
        const text = `${copy.greeting}\n\n${copy.confirmIntro}\n\n${copy.regards}\nRestodocks`;
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
        const copy = i18nCopy(lang);
        const greeting = fullName?.trim() ? `${copy.greetingNamePrefix}, ${escapeHtml(fullName.trim())}!` : copy.greeting;
        subject = copy.ownerSubject;
        html = `
<p>${greeting}</p>
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
<p>${copy.ownerRegisteredPrefix} <strong>${escapeHtml(companyName)}</strong> ${copy.ownerRegisteredSuffix}</p>
<p>${copy.ownerIdentifierHint}</p>
<p><strong>${copy.companyPinLabel}: ${escapeHtml(pinCode || "")}</strong></p>
<p>${copy.yourLoginLabel}: <strong>${escapeHtml(email)}</strong></p>
<p>${copy.passwordHint}</p>
<p style="color:#666;font-size:14px">${copy.spamHint}</p>
<p>${copy.regards}<br>Restodocks</p>
      `.trim();
      }
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
  employeeSubjectPrefix: string;
  employeeRegisteredPrefix: string;
  spamHint: string;
  registrationTimeLabel: string;
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
        confirmedSigninHint: "Теперь вы можете войти в приложение Restodocks, используя указанный при регистрации email и пароль.",
        ownerSubject: "Регистрация компании в системе Restodocks",
        ownerRegisteredPrefix: "Регистрация вашего заведения",
        ownerRegisteredSuffix: "успешно завершена.",
        ownerIdentifierHint: "Для доступа сотрудников к системе используйте уникальный идентификатор:",
        companyPinLabel: "PIN-код компании",
        yourLoginLabel: "Ваш логин",
        passwordHint: "Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в приложении.",
        instructionLabel: "Инструкция",
        ownerInstruction: "Передайте PIN-код персоналу. Им потребуется ввести его один раз при регистрации в приложении для синхронизации с базой данных вашего заведения.",
        employeeSubjectPrefix: "Доступ к корпоративному пространству",
        employeeRegisteredPrefix: "Ваша учетная запись успешно привязана к системе управления заведением",
        spamHint: "Отдельно придёт письмо со ссылкой для подтверждения email. Если не увидите его — проверьте папку «Спам».",
        registrationTimeLabel: "Время регистрации",
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
        passwordHint: "Use la contraseña que indicó al registrarse. Si es necesario, restablézcala en la app.",
        instructionLabel: "Instrucción",
        ownerInstruction: "Comparta el PIN con el personal. Lo necesitarán una vez al registrarse en la app.",
        employeeSubjectPrefix: "Acceso al espacio de",
        employeeRegisteredPrefix: "Su cuenta se vinculó correctamente a",
        spamHint: "También llegará un correo de confirmación. Revise Spam si no aparece.",
        registrationTimeLabel: "Hora de registro",
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
        passwordHint: "Usa la password scelta in registrazione. Se necessario, reimpostala nell'app.",
        instructionLabel: "Istruzioni",
        ownerInstruction: "Condividi il PIN con il personale: servirà una sola volta in registrazione.",
        employeeSubjectPrefix: "Accesso allo spazio di",
        employeeRegisteredPrefix: "Il tuo account è stato collegato a",
        spamHint: "Arriverà anche un'email di conferma. Controlla Spam se necessario.",
        registrationTimeLabel: "Orario registrazione",
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
        passwordHint: "Kayıtta belirlediğiniz şifreyi kullanın. Gerekirse uygulamadan sıfırlayın.",
        instructionLabel: "Talimat",
        ownerInstruction: "PIN'i personele iletin. Uygulamada ilk kayıtta bir kez gerekir.",
        employeeSubjectPrefix: "Çalışma alanına erişim:",
        employeeRegisteredPrefix: "Hesabınız şu işletmeye bağlandı:",
        spamHint: "Ayrıca onay bağlantısı e-postası gelir. Gerekirse Spam'i kontrol edin.",
        registrationTimeLabel: "Kayıt zamanı",
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
        passwordHint: "Dùng mật khẩu đã đặt khi đăng ký. Nếu cần, đặt lại trong ứng dụng.",
        instructionLabel: "Hướng dẫn",
        ownerInstruction: "Chia sẻ PIN cho nhân viên. Họ chỉ cần nhập một lần khi đăng ký.",
        employeeSubjectPrefix: "Quyền truy cập không gian của",
        employeeRegisteredPrefix: "Tài khoản của bạn đã được liên kết với",
        spamHint: "Một email xác nhận riêng sẽ được gửi. Hãy kiểm tra Spam nếu cần.",
        registrationTimeLabel: "Thời gian đăng ký",
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
        passwordHint: "Please use the password you entered during registration. If needed, reset it in the app.",
        instructionLabel: "Instruction",
        ownerInstruction: "Share the PIN with your staff. They will need it once during registration in the app.",
        employeeSubjectPrefix: "Access to",
        employeeRegisteredPrefix: "Your account has been linked to",
        spamHint: "A separate email with confirmation link is sent by auth provider. Please check Spam if needed.",
        registrationTimeLabel: "Registration time",
      };
  }
}
