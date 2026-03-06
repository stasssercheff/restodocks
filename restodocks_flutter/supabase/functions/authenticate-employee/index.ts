// Edge Function: legacy-аутентификация сотрудника по email + password_hash (BCrypt)
// Проверка пароля происходит на сервере — клиент никогда не видит password_hash
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs@2";

const ALLOWED_ORIGINS = [
  "https://restodocks.com",
  "https://www.restodocks.com",
  "https://restodocks.vercel.app",
  "https://restodocks.netlify.app",
  "https://restodocks.pages.dev",
  "http://localhost",
  "http://127.0.0.1",
];
const ALLOWED_SUFFIXES = [".pages.dev", ".netlify.app", ".vercel.app"];

function getCorsHeaders(origin: string | null): Record<string, string> {
  const base: Record<string, string> = {
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
  if (origin && isOriginAllowed(origin)) {
    base["Access-Control-Allow-Origin"] = origin;
  }
  return base;
}

function isOriginAllowed(origin: string | null): boolean {
  if (!origin || typeof origin !== "string") return false;
  try {
    const url = new URL(origin);
    const host = url.hostname.toLowerCase();
    if (ALLOWED_ORIGINS.includes(origin) || ALLOWED_ORIGINS.includes(`${url.protocol}//${host}`)) return true;
    if (host === "localhost" || host === "127.0.0.1") return true;
    return ALLOWED_SUFFIXES.some((s) => host.endsWith(s));
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Simple in-memory rate limiter: max 10 attempts per IP per 15 minutes
// (Deno isolate is short-lived, but this stops rapid bursts within one isolate)
// ---------------------------------------------------------------------------
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
  const cors = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  // Rate limiting by IP
  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  if (!checkRateLimit(clientIp)) {
    return new Response(
      JSON.stringify({ error: "Too many requests. Please try again later." }),
      { status: 429, headers: { ...cors, "Content-Type": "application/json", "Retry-After": "900" } }
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
    );
  }

  // service_role клиент — нужен для чтения password_hash (RLS bypassed на сервере)
  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  try {
    const body = (await req.json()) as {
      email?: string;
      password?: string;
      establishment_id?: string; // опционально — для входа в рамках одного заведения
    };

    const email = body.email?.trim().toLowerCase();
    const password = body.password?.trim();
    const establishmentId = body.establishment_id?.trim();

    if (!email || !password) {
      return new Response(
        JSON.stringify({ error: "email and password are required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // Ищем сотрудников по email
    let query = supabase
      .from("employees")
      .select("id, email, full_name, surname, roles, establishment_id, department, section, is_active, password_hash, preferred_language, data_access_enabled, can_edit_own_schedule, created_at")
      .ilike("email", email)
      .eq("is_active", true);

    if (establishmentId) {
      query = query.eq("establishment_id", establishmentId);
    }

    const { data: employees, error: empError } = await query;

    if (empError) {
      console.error("[authenticate-employee] DB error:", empError.message);
      return new Response(
        JSON.stringify({ error: "Database error" }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    if (!employees || employees.length === 0) {
      // Одинаковый ответ независимо от причины — не раскрываем существование email
      return new Response(
        JSON.stringify({ error: "invalid_credentials" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // Перебираем — может быть несколько заведений с одним email
    for (const emp of employees) {
      const hash = emp.password_hash as string | null;
      if (!hash) continue;

      let passwordMatch = false;

      if (hash.startsWith("$2a$") || hash.startsWith("$2b$")) {
        // BCrypt
        passwordMatch = await bcrypt.compare(password, hash);
      } else {
        // Legacy plaintext password — hash it immediately and deny login
        // (forces the user to reset their password via the reset flow)
        console.warn(`[authenticate-employee] Employee ${emp.id} still has plaintext password_hash — forcing reset`);
        const newHash = await bcrypt.hash(hash, 10);
        await supabase
          .from("employees")
          .update({ password_hash: newHash })
          .eq("id", emp.id);
        // Do NOT match: user must reset password
        passwordMatch = false;
      }

      if (!passwordMatch) continue;

      // Нашли — загружаем заведение
      const { data: estData, error: estError } = await supabase
        .from("establishments")
        .select("*")
        .eq("id", emp.establishment_id)
        .limit(1)
        .single();

      if (estError || !estData) {
        console.error("[authenticate-employee] Establishment not found for employee:", emp.id);
        continue;
      }

      // Возвращаем данные БЕЗ password_hash
      const { password_hash: _omit, ...employeeWithoutHash } = emp;
      return new Response(
        JSON.stringify({
          employee: employeeWithoutHash,
          establishment: estData,
        }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // Ни один пароль не подошёл
    return new Response(
      JSON.stringify({ error: "invalid_credentials" }),
      { status: 401, headers: { ...cors, "Content-Type": "application/json" } }
    );

  } catch (e) {
    console.error("[authenticate-employee] Unexpected error:", e);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
    );
  }
});
