import { createClient } from "jsr:@supabase/supabase-js@2";

type RateLimitOptions = {
  windowMs: number;
  maxRequests: number;
};

const defaultAllowedOrigins = [
  "https://restodocks.com",
  "https://www.restodocks.com",
  "https://restodocks.pages.dev",
];

function matchesOriginRule(origin: string, rule: string): boolean {
  const normalizedRule = rule.trim().toLowerCase();
  const normalizedOrigin = origin.trim().toLowerCase();
  if (!normalizedRule) return false;
  if (normalizedRule === normalizedOrigin) return true;
  if (normalizedRule.startsWith("*.")) {
    const suffix = normalizedRule.slice(1); // ".example.com"
    return normalizedOrigin.endsWith(suffix);
  }
  return false;
}

export function resolveCorsHeaders(req: Request): Record<string, string> {
  const requestOrigin = req.headers.get("origin");
  const envOrigins = (Deno.env.get("RD_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const allowlist = envOrigins.length > 0 ? envOrigins : defaultAllowedOrigins;

  // Native iOS/Android requests usually have no Origin.
  if (!requestOrigin) {
    return {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    };
  }

  const allowed = allowlist.some((rule) => matchesOriginRule(requestOrigin, rule));
  return {
    "Access-Control-Allow-Origin": allowed ? requestOrigin : "null",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

export function getClientIp(req: Request): string {
  const cfIp = req.headers.get("cf-connecting-ip");
  if (cfIp) return cfIp;
  const realIp = req.headers.get("x-real-ip");
  if (realIp) return realIp;
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return "unknown";
}

type Bucket = { hits: number[] };

declare global {
  // deno-lint-ignore no-var
  var __rdRateBuckets: Map<string, Bucket> | undefined;
}

function getBuckets(): Map<string, Bucket> {
  if (!globalThis.__rdRateBuckets) {
    globalThis.__rdRateBuckets = new Map<string, Bucket>();
  }
  return globalThis.__rdRateBuckets;
}

export function enforceRateLimit(
  req: Request,
  bucketKey: string,
  options: RateLimitOptions,
): boolean {
  const ip = getClientIp(req);
  const now = Date.now();
  const windowStart = now - options.windowMs;
  const key = `${bucketKey}:${ip}`;
  const buckets = getBuckets();
  const bucket = buckets.get(key) ?? { hits: [] };
  bucket.hits = bucket.hits.filter((ts) => ts >= windowStart);
  if (bucket.hits.length >= options.maxRequests) {
    buckets.set(key, bucket);
    return false;
  }
  bucket.hits.push(now);
  buckets.set(key, bucket);
  return true;
}

export function hasValidApiKey(req: Request): boolean {
  const apiKey = req.headers.get("apikey")?.trim();
  if (!apiKey) return false;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (service && apiKey === service) return true;
  return false;
}

export function isServiceRoleRequest(req: Request): boolean {
  const apiKey = req.headers.get("apikey")?.trim();
  if (!apiKey) return false;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  return !!service && apiKey === service;
}

export async function hasValidApiKeyOrUser(req: Request): Promise<boolean> {
  if (hasValidApiKey(req)) return true;

  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return false;
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return false;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  if (!supabaseUrl || !anonKey) return false;

  try {
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await authClient.auth.getUser(token);
    return !error && !!data.user;
  } catch {
    return false;
  }
}

export async function getAuthenticatedUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  if (!supabaseUrl || !anonKey) return null;

  try {
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await authClient.auth.getUser(token);
    if (error || !data.user?.id) return null;
    return data.user.id;
  } catch {
    return null;
  }
}
