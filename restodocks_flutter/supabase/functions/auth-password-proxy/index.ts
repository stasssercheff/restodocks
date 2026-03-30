// Прокси входа: серверный fetch к GoTrue password grant — обход 522/«CORS» в браузере на auth/v1/token.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { corsPreflightHeaders } from "../_shared/cors_light.ts";

// Как authenticate-employee: анти-брут в пределах изолята (не замена лимитов на стороне Auth).
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const rateLimitMap = new Map<string, { count: number; windowStart: number }>();

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(ip, { count: 1, windowStart: now });
    return true;
  }
  entry.count++;
  if (entry.count > RATE_LIMIT_MAX) return false;
  return true;
}

Deno.serve(async (req: Request) => {
  const hBase = corsPreflightHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: hBase });
  }
  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  if (!checkRateLimit(clientIp)) {
    return new Response(
      JSON.stringify({ error: "too_many_requests", message: "Слишком много попыток входа. Подождите 15 минут." }),
      { status: 429, headers: { ...hBase, "Content-Type": "application/json", "Retry-After": "900" } },
    );
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...hBase, "Content-Type": "application/json" },
    });
  }

  let body: { email?: string; password?: string };
  try {
    body = (await req.json()) as { email?: string; password?: string };
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...hBase, "Content-Type": "application/json" },
    });
  }

  const email = typeof body.email === "string" ? body.email.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!email || !password) {
    return new Response(JSON.stringify({ error: "email_and_password_required" }), {
      status: 400,
      headers: { ...hBase, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const tokenUrl = `${supabaseUrl}/auth/v1/token?grant_type=password`;
  const authRes = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
    },
    body: JSON.stringify({ email, password }),
  });

  const text = await authRes.text();
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    return new Response(
      JSON.stringify({ error: "auth_upstream_invalid", detail: text.slice(0, 240) }),
      {
        status: 502,
        headers: { ...hBase, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify(payload), {
    status: authRes.status,
    headers: { ...hBase, "Content-Type": "application/json" },
  });
});
