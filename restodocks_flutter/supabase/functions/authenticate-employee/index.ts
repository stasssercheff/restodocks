// Edge Function: legacy-аутентификация сотрудника по email + password_hash (BCrypt)
// Проверка пароля происходит на сервере — клиент никогда не видит password_hash
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// bcrypt только по dynamic import — иначе холодный старт тянет тяжёлый модуль до OPTIONS/раннего кода.
type BcryptJs = { compare(s: string, hash: string): Promise<boolean>; hash(s: string, r: number): Promise<string> };
let _bcrypt: BcryptJs | null = null;
async function bcryptMod(): Promise<BcryptJs> {
  if (!_bcrypt) _bcrypt = (await import("npm:bcryptjs@2")).default as BcryptJs;
  return _bcrypt;
}
async function bcryptCompare(plain: string, hash: string): Promise<boolean> {
  return (await bcryptMod()).compare(plain, hash);
}
async function bcryptHash(plain: string, rounds: number): Promise<string> {
  return (await bcryptMod()).hash(plain, rounds);
}

/// Узкий поиск auth user по email (listUsers(1000) долго и даёт EarlyDrop при таймаутах клиента).
async function findAuthUserIdByEmail(
  supabaseUrl: string,
  serviceKey: string,
  supabase: ReturnType<typeof createClient>,
  emailLower: string,
): Promise<string | null> {
  try {
    const u = new URL(`${supabaseUrl}/auth/v1/admin/users`);
    u.searchParams.set("email", emailLower);
    const res = await fetch(u.toString(), {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });
    if (res.ok) {
      const j = await res.json() as { users?: Array<{ id?: string; email?: string }> };
      const users = j?.users;
      if (Array.isArray(users)) {
        const hit = users.find((x) => x.email?.toLowerCase() === emailLower);
        if (hit?.id) return String(hit.id);
      }
    }
  } catch (e) {
    console.warn("[authenticate-employee] admin users email fetch:", e);
  }
  const { data: listData } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 });
  const existingUser = listData?.users?.find((u) => u.email?.toLowerCase() === emailLower);
  return existingUser?.id ? String(existingUser.id) : null;
}

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
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
  const cors = corsHeaders(req.headers.get("Origin"));
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

    console.log(`[authenticate-employee] Attempt for email=${email ?? "(empty)"}, establishment_id=${establishmentId ?? "(none)"}`);

    if (!email || !password) {
      return new Response(
        JSON.stringify({ error: "email and password are required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // Ищем сотрудников по email (limit 5 — один email редко в >5 заведениях)
    let query = supabase
      .from("employees")
      .select("id, auth_user_id, email, full_name, surname, roles, establishment_id, department, section, is_active, password_hash, preferred_language, data_access_enabled, can_edit_own_schedule")
      .ilike("email", email)
      .eq("is_active", true)
      .limit(5);

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
      console.log("[authenticate-employee] No active employees found for email");
      return new Response(
        JSON.stringify({ error: "invalid_credentials" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    console.log(`[authenticate-employee] Found ${employees.length} employee(s), checking password`);

    // Перебираем — может быть несколько заведений с одним email
    for (const emp of employees) {
      // Пароль только в Auth: для сотрудников с auth_user_id не проверяем password_hash
      if (emp.auth_user_id) {
        console.log(`[authenticate-employee] Employee ${emp.id} has auth_user_id — use Supabase Auth`);
        continue;
      }

      const hash = emp.password_hash as string | null;
      if (!hash) {
        console.log(`[authenticate-employee] Employee ${emp.id} has no password_hash, skipping`);
        continue;
      }

      let passwordMatch = false;

      if (hash.startsWith("$2a$") || hash.startsWith("$2b$")) {
        // BCrypt
        passwordMatch = await bcryptCompare(password, hash);
      } else {
        // Legacy plaintext password — hash it immediately and deny login
        // (forces the user to reset their password via the reset flow)
        console.warn(`[authenticate-employee] Employee ${emp.id} still has plaintext password_hash — forcing reset`);
        const newHash = await bcryptHash(hash, 10);
        await supabase
          .from("employees")
          .update({ password_hash: newHash })
          .eq("id", emp.id);
        // Do NOT match: user must reset password
        passwordMatch = false;
      }

      if (!passwordMatch) {
        console.log(`[authenticate-employee] Password mismatch for employee ${emp.id}`);
        continue;
      }

      console.log(`[authenticate-employee] Password OK for employee ${emp.id}, fetching establishment`);

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

      // Связка с Supabase Auth: все сотрудники должны иметь auth_user_id. Без него не возвращаем success.
      let authUserLinked = false;
      if (!emp.auth_user_id) {
        let linkedAuthUserId: string | null = null;

        // 1. Пробуем создать нового пользователя
        try {
          const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
            email: emp.email,
            password,
            email_confirm: true,
          });
          if (!createErr && newUser?.user?.id) {
            linkedAuthUserId = newUser.user.id;
            console.log(`[authenticate-employee] Created auth user ${linkedAuthUserId} for employee ${emp.id}`);
          } else {
            const errMsg = createErr?.message ?? "";
            const isAlreadyExists = /already|exists|registered|duplicate/i.test(errMsg);
            if (isAlreadyExists) {
              // 2. Пользователь уже есть в Auth — ищем и привязываем (без listUsers(1000))
              const emailLower = (emp.email as string)?.toLowerCase() ?? "";
              const existingId = await findAuthUserIdByEmail(
                supabaseUrl,
                supabaseServiceKey,
                supabase,
                emailLower,
              );
              if (existingId) {
                linkedAuthUserId = existingId;
                const { error: pwdErr } = await supabase.auth.admin.updateUserById(linkedAuthUserId, {
                  password,
                });
                if (pwdErr) {
                  console.warn("[authenticate-employee] updateUserById (password) failed:", pwdErr.message);
                } else {
                  console.log(`[authenticate-employee] Linked existing auth user ${linkedAuthUserId} for employee ${emp.id}`);
                }
              }
            } else {
              console.warn("[authenticate-employee] createUser failed:", errMsg);
            }
          }
        } catch (authErr) {
          console.warn("[authenticate-employee] Auth user creation error:", authErr);
        }

        if (linkedAuthUserId) {
          const { error: updateErr } = await supabase
            .from("employees")
            .update({ auth_user_id: linkedAuthUserId })
            .eq("id", emp.id);
          if (!updateErr) {
            authUserLinked = true;
          } else {
            console.error("[authenticate-employee] Failed to update auth_user_id:", updateErr.message);
          }
        }

        if (!authUserLinked) {
          console.error("[authenticate-employee] Cannot link auth user for employee", emp.id, "- refusing login");
          return new Response(
            JSON.stringify({
              error: "auth_link_required",
              message: "Требуется привязка к Supabase Auth. Обратитесь к администратору или сбросьте пароль.",
            }),
            { status: 503, headers: { ...cors, "Content-Type": "application/json" } }
          );
        }
      } else {
        authUserLinked = true; // уже привязан
      }

      // Возвращаем данные БЕЗ password_hash
      const { password_hash: _omit, ...employeeWithoutHash } = emp;
      const payload: Record<string, unknown> = {
        employee: employeeWithoutHash,
        establishment: estData,
      };
      if (authUserLinked) payload.authUserCreated = true; // клиент вызовет signInWithPassword

      return new Response(
        JSON.stringify(payload),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    console.log("[authenticate-employee] No matching password for any employee");
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
