// Edge Function: письма при регистрации (владелец / сотрудник)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <onboarding@resend.dev>";

  try {
    const body = (await req.json()) as {
      type: "owner" | "employee";
      to: string;
      companyName: string;
      email: string;
      password: string;
      pinCode?: string;
    };

    const { type, to, companyName, email, password, pinCode } = body;

    if (!type || !to || !companyName || !email || !password) {
      return new Response(JSON.stringify({ error: "type, to, companyName, email, password required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let subject: string;
    let html: string;

    if (type === "owner") {
      subject = "Регистрация компании в системе Restodocks";
      html = `
<p>Здравствуйте!</p>
<p>Регистрация вашего заведения <strong>${escapeHtml(companyName)}</strong> успешно завершена.</p>
<p>Для доступа сотрудников к системе используйте уникальный идентификатор:</p>
<p><strong>PIN-код компании: ${escapeHtml(pinCode || "")}</strong></p>
<p>Ваш логин — ${escapeHtml(email)}<br>Ваш пароль — ${escapeHtml(password)}</p>
<p><strong>Инструкция:</strong><br>Передайте данный код персоналу. Им потребуется ввести его один раз при регистрации в приложении для синхронизации с базой данных вашего заведения.</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim();
    } else {
      subject = `Доступ к корпоративному пространству ${escapeHtml(companyName)}`;
      html = `
<p>Здравствуйте!</p>
<p>Ваша учетная запись успешно привязана к системе управления заведением <strong>${escapeHtml(companyName)}</strong>.</p>
<p>Ваш логин — ${escapeHtml(email)}<br>Ваш пароль — ${escapeHtml(password)}</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim();
    }

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
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ id: data?.id, ok: true }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
