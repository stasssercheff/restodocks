// Edge Function: сохранение IP и геолокации при регистрации заведения
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  hasValidApiKeyOrUser,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

const ORPHAN_ESTABLISHMENT_MAX_AGE_MS = 2 * 60 * 60 * 1000;

function getClientIp(req: Request): string {
  const cfIp = req.headers.get("cf-connecting-ip");
  if (cfIp) return cfIp;
  const realIp = req.headers.get("x-real-ip");
  if (realIp) return realIp;
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return "unknown";
}

interface GeoResponse {
  ip?: string;
  city?: string;
  region?: string;
  country?: string;
  loc?: string;
}

async function fetchGeo(ip: string): Promise<{ country?: string; city?: string }> {
  if (ip === "unknown" || ip === "127.0.0.1" || ip.startsWith("192.168.") || ip.startsWith("10.")) {
    return {};
  }
  try {
    const res = await fetch(`https://ipinfo.io/${encodeURIComponent(ip)}`, {
      headers: { Accept: "application/json" },
    });
    if (!res.ok) return {};
    const data = (await res.json()) as GeoResponse;
    return { country: data.country, city: data.city };
  } catch {
    return {};
  }
}

export async function handleRequest(req: Request): Promise<Response> {
  const cors = resolveCorsHeaders(req);
  try {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  // В pre-auth сценарии (первичная регистрация) запрос может прийти без валидного
  // JWT/api key из текущего рантайма после ротации ключей. Не режем 401 на входе:
  // ниже всё равно есть строгая проверка доступа к establishment (owner/employee
  // или "сиротский" establishment в коротком окне времени).
  await hasValidApiKeyOrUser(req);
  const userId = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req);
  if (!enforceRateLimit(req, "register-metadata", { windowMs: 60_000, maxRequests: 20 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Server misconfigured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const ALLOWED_CLIENTS = new Set([
      "ios_app",
      "android_app",
      "web_mobile",
      "web_desktop",
      "native_other",
    ]);

    const body = (await req.json()) as {
      establishment_id?: string;
      registration_client?: string;
    };
    const establishmentId = body?.establishment_id;
    if (!establishmentId || typeof establishmentId !== "string") {
      return new Response(JSON.stringify({ error: "establishment_id required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    let allowed = false;

    if (isService) {
      allowed = true;
    } else if (userId) {
      // userId — auth.users.id; у employees первичный ключ id ≠ auth, связь через auth_user_id.
      const { data: allowedEmployee } = await supabase
        .from("employees")
        .select("id")
        .eq("auth_user_id", userId)
        .eq("establishment_id", establishmentId)
        .maybeSingle();
      if (allowedEmployee?.id) {
        allowed = true;
      } else {
        const { data: allowedOwner } = await supabase
          .from("establishments")
          .select("id")
          .eq("id", establishmentId)
          .eq("owner_id", userId)
          .maybeSingle();
        if (allowedOwner?.id) allowed = true;
      }
    }

    if (!allowed) {
      const { data: est, error: estErr } = await supabase
        .from("establishments")
        .select("id, owner_id, created_at")
        .eq("id", establishmentId)
        .maybeSingle();
      if (estErr || !est) {
        return new Response(JSON.stringify({ error: "Establishment not found" }), {
          status: 404,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      if (est.owner_id != null && String(est.owner_id).length > 0) {
        return new Response(JSON.stringify({ error: "Forbidden for establishment" }), {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const created = new Date(est.created_at as string);
      if (Number.isNaN(created.getTime()) || Date.now() - created.getTime() > ORPHAN_ESTABLISHMENT_MAX_AGE_MS) {
        return new Response(JSON.stringify({ error: "Forbidden for establishment" }), {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      allowed = true;
    }

    if (!allowed) {
      return new Response(JSON.stringify({ error: "Authenticated user required" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const ip = getClientIp(req);
    const geo = await fetchGeo(ip);

    const rawClient = typeof body?.registration_client === "string"
      ? body.registration_client.trim().toLowerCase()
      : "";
    const registration_client = ALLOWED_CLIENTS.has(rawClient) ? rawClient : null;

    const { error } = await supabase
      .from("establishments")
      .update({
        registration_ip: ip,
        registration_country: geo.country ?? null,
        registration_city: geo.city ?? null,
        ...(registration_client ? { registration_client } : {}),
      })
      .eq("id", establishmentId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: true, ip, country: geo.country, city: geo.city }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
}
