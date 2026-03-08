// Edge Function: сохранение IP и геолокации при входе (Supabase Auth)
// Вызывается клиентом после успешного signInWithPassword — JWT в Authorization
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

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

  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace(/^Bearer\s+/i, "")?.trim();
  if (!token) {
    return new Response(JSON.stringify({ error: "Authorization required" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  const { data: { user }, error: userError } = await supabase.auth.getUser(token);
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const ip = getClientIp(req);
  const geo = await fetchGeo(ip);
  const now = new Date().toISOString();

  const { error: updateError } = await supabase
    .from("employees")
    .update({
      last_login_ip: ip,
      last_login_country: geo.country ?? null,
      last_login_city: geo.city ?? null,
      last_login_at: now,
    })
    .eq("id", user.id);

  if (updateError) {
    return new Response(JSON.stringify({ error: updateError.message }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const loginLocation = geo.city || geo.country
    ? { city: geo.city ?? null, country: geo.country ?? null }
    : null;

  return new Response(
    JSON.stringify({ ok: true, login_location: loginLocation }),
    { headers: { ...cors, "Content-Type": "application/json" } }
  );
});
