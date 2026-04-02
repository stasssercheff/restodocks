/**
 * Возвращает URL обучающего видео: для российских IP — Supabase Storage (сокращаем трафик),
 * для остальных — YouTube.
 *
 * GET ?id=goZ20v6DV2s  (YouTube video ID)
 * Response: { url: "https://..." }
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

const BUCKET = "training_videos";
const SIGNED_URL_EXPIRES_SEC = 3600; // 1 час

// YouTube ID -> fallback YouTube URL (для не-RU или если файла нет в Storage)
const YOUTUBE_MAP: Record<string, string> = {
  goZ20v6DV2s: "https://youtu.be/goZ20v6DV2s",
  "ggc8es-ivJc": "https://youtu.be/ggc8es-ivJc",
  MixDi9UC2kg: "https://youtu.be/MixDi9UC2kg",
  "JjMe-Tb04ZM": "https://youtu.be/JjMe-Tb04ZM",
  "e5DJHk_pSbE": "https://youtu.be/e5DJHk_pSbE",
  bGVJtSdpid0: "https://youtu.be/bGVJtSdpid0",
  nkk9BpyIkuQ: "https://youtu.be/nkk9BpyIkuQ",
  rFXg9gJ5qUw: "https://youtu.be/rFXg9gJ5qUw",
  "tJvjUcNRnsc": "https://youtu.be/tJvjUcNRnsc",
  "VFSGL0Zj7fc": "https://youtu.be/VFSGL0Zj7fc",   // Инвентаризации IIKO слияние_1
  "WQruFDlDQ": "https://youtu.be/WQruFDlDQ",       // Инвентаризации IIKO слияние_2
  sF26hjgdjO8: "https://youtu.be/sF26hjgdjO8",
  zgH9ITDHU4U: "https://youtu.be/zgH9ITDHU4U",
  ZICdajkAbNY: "https://youtu.be/ZICdajkAbNY",
  tO4ihTk8bDM: "https://youtu.be/tO4ihTk8bDM",
  p9I1rsNgXpU: "https://youtu.be/p9I1rsNgXpU",
  "po5_brrXdVw": "https://youtu.be/po5_brrXdVw",
  "66Q9iUyuqso": "https://youtu.be/66Q9iUyuqso",
  tYsFlIll954: "https://youtu.be/tYsFlIll954",
};

function getClientIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  const realIp = req.headers.get("x-real-ip");
  if (realIp) return realIp;
  return null;
}

async function getCountryCode(ip: string): Promise<string | null> {
  if (!ip || ip === "127.0.0.1" || ip.startsWith("::1") || ip === "::ffff:127.0.0.1") {
    return "RU"; // локальная разработка — считаем RU
  }
  try {
    const res = await fetch(`http://ip-api.com/json/${ip}?fields=countryCode`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { countryCode?: string };
    return data.countryCode ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const cors = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { ...cors, "Content-Type": "application/json" } });
  }
  const uid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !uid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
  }
  if (!enforceRateLimit(req, "get-training-video-url", { windowMs: 60_000, maxRequests: 60 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), { status: 429, headers: { ...cors, "Content-Type": "application/json" } });
  }

  try {
    const url = new URL(req.url);
    const id = url.searchParams.get("id")?.trim();
    if (!id) {
      return new Response(JSON.stringify({ error: "Missing id" }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }

    const youtubeUrl = YOUTUBE_MAP[id];
    if (!youtubeUrl) {
      return new Response(JSON.stringify({ error: "Unknown video id" }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }

    const ip = getClientIp(req);
    const country = ip ? await getCountryCode(ip) : null;

    if (country === "RU") {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (supabaseUrl && serviceKey) {
        const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
        const path = `${id}.mp4`;
        const { data: signed, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, SIGNED_URL_EXPIRES_SEC);
        if (!error && signed?.signedUrl) {
          return new Response(JSON.stringify({ url: signed.signedUrl }), { status: 200, headers: { ...cors, "Content-Type": "application/json" } });
        }
      }
    }

    return new Response(JSON.stringify({ url: youtubeUrl }), { status: 200, headers: { ...cors, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("get-training-video-url:", err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
