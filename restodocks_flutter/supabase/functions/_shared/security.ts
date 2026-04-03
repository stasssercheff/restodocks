import { createClient } from "jsr:@supabase/supabase-js@2";

type RateLimitOptions = {
  windowMs: number;
  maxRequests: number;
};

const defaultAllowedOrigins = [
  "https://restodocks.com",
  "https://www.restodocks.com",
  "https://www.restodocks.ru",
  "https://restodocks.ru",
  "https://restodocks.pages.dev",
  "*.restodocks.pages.dev",
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

function mergedAllowedOrigins(): string[] {
  const env = (Deno.env.get("RD_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const seen = new Set<string>();
  const out: string[] = [];
  for (const r of [...defaultAllowedOrigins, ...env]) {
    const k = r.trim().toLowerCase();
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push(r.trim());
  }
  return out;
}

export function isAllowedOrigin(req: Request): boolean {
  const requestOrigin = req.headers.get("origin");
  if (!requestOrigin) return true;
  const allowlist = mergedAllowedOrigins();
  return allowlist.some((rule) => matchesOriginRule(requestOrigin, rule));
}

export function resolveCorsHeaders(req: Request): Record<string, string> {
  const requestOrigin = req.headers.get("origin");
  const allowlist = mergedAllowedOrigins();

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

/** Лимит по произвольному ключу (без IP) — например user id из JWT. */
export function enforceRateLimitByIdentity(
  identityKey: string,
  bucketSuffix: string,
  options: RateLimitOptions,
): boolean {
  const now = Date.now();
  const windowStart = now - options.windowMs;
  const key = `${bucketSuffix}:id:${identityKey}`;
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

/** RFC 7235: схема Bearer без учёта регистра; токен — остаток после первого пробела. */
function parseBearerToken(header: string | null | undefined): string | null {
  const h = header?.trim();
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : null;
}

export function hasValidApiKey(req: Request): boolean {
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const anon = Deno.env.get("SUPABASE_ANON_KEY")?.trim();

  const apiKey = req.headers.get("apikey")?.trim();
  if (apiKey) {
    if (service && apiKey === service) return true;
    // Стандартный клиент Supabase шлёт публичный anon key в apikey (не JWT пользователя).
    if (anon && apiKey === anon) return true;
  }

  // Только Authorization: Bearer <anon> (редко, но без дубля apikey в заголовке).
  const bearerOnly = parseBearerToken(
    req.headers.get("authorization") ?? req.headers.get("Authorization"),
  );
  if (anon && bearerOnly === anon) return true;

  return false;
}

export function isServiceRoleRequest(req: Request): boolean {
  const apiKey = req.headers.get("apikey")?.trim();
  if (!apiKey) return false;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  return !!service && apiKey === service;
}

/** Некоторые вызовы functions.invoke передают service JWT только в Authorization. */
export function isServiceRoleBearer(req: Request): boolean {
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!service) return false;
  const token = parseBearerToken(
    req.headers.get("authorization") ?? req.headers.get("Authorization"),
  );
  return !!token && token === service;
}

export async function hasValidApiKeyOrUser(req: Request): Promise<boolean> {
  if (hasValidApiKey(req)) return true;
  if (isServiceRoleBearer(req)) return true;

  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const token = parseBearerToken(
    req.headers.get("authorization") ?? req.headers.get("Authorization"),
  );
  if (!token) return false;
  if (anonKey && token === anonKey) return true;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
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
  const token = parseBearerToken(
    req.headers.get("authorization") ?? req.headers.get("Authorization"),
  );
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
