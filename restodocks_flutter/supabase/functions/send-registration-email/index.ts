// Edge Function: письма при регистрации (владелец / сотрудник)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

  // Require the Supabase anon key (or service role) — blocks unauthenticated external callers
  const expectedAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const expectedServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const providedKey = req.headers.get("apikey") || req.headers.get("Authorization")?.replace("Bearer ", "");
  if (providedKey !== expectedAnonKey && providedKey !== expectedServiceKey) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
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

  const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <noreply@restodocks.com>";

  try {
    const body = (await req.json()) as {
      type: "owner" | "employee" | "registration_confirmed";
      to: string;
      companyName?: string;
      email?: string;
      pinCode?: string;
    };

    const { type, to, companyName, email, pinCode } = body;

    // Письмо о завершении регистрации (после подтверждения email)
    if (type === "registration_confirmed") {
      if (!to) {
        return new Response(JSON.stringify({ error: "to required" }), {
          status: 400,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }
      const subject = "Регистрация подтверждена — Restodocks";
      const companyText = companyName ? ` в заведении <strong>${escapeHtml(companyName)}</strong>` : "";
      const html = `
<p>Здравствуйте!</p>
<p>Ваша регистрация${companyText} успешно подтверждена.</p>
<p>Теперь вы можете войти в приложение Restodocks, используя указанный при регистрации email и пароль.</p>
<p>С уважением,<br>Команда Restodocks</p>
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
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ id: data?.id, ok: true }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!type || !to || !companyName || !email) {
      return new Response(JSON.stringify({ error: "type, to, companyName, email required" }), {
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
<p>Ваш логин: <strong>${escapeHtml(email)}</strong></p>
<p>Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в приложении.</p>
<p><strong>Инструкция:</strong><br>Передайте PIN-код персоналу. Им потребуется ввести его один раз при регистрации в приложении для синхронизации с базой данных вашего заведения.</p>
<p>С уважением,<br>Команда Restodocks</p>
      `.trim();
    } else {
      subject = `Доступ к корпоративному пространству ${escapeHtml(companyName)}`;
      html = `
<p>Здравствуйте!</p>
<p>Ваша учетная запись успешно привязана к системе управления заведением <strong>${escapeHtml(companyName)}</strong>.</p>
<p>Ваш логин: <strong>${escapeHtml(email)}</strong></p>
<p>Для входа используйте пароль, который вы указали при регистрации. Если вы забыли пароль — воспользуйтесь функцией восстановления в приложении.</p>
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
