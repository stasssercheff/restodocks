/**
 * CORS без зависимостей (jsr supabase-js и т.д.).
 * Нужен для index.ts: OPTIONS отвечает до dynamic import(handler), иначе preflight даёт 503 BOOT_ERROR.
 */
const defaultRules = [
  "https://restodocks.com",
  "https://www.restodocks.com",
  "https://restodocks.pages.dev",
  "*.restodocks.pages.dev",
];

function matchesRule(origin: string, rule: string): boolean {
  const r = rule.trim().toLowerCase();
  const o = origin.trim().toLowerCase();
  if (!r) return false;
  if (r === o) return true;
  if (r.startsWith("*.")) {
    const suffix = r.slice(1);
    return o.endsWith(suffix);
  }
  return false;
}

export function corsPreflightHeaders(req: Request): Record<string, string> {
  const requestOrigin = req.headers.get("origin");
  const envRules = (Deno.env.get("RD_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const rules = envRules.length > 0 ? envRules : defaultRules;

  if (!requestOrigin) {
    return {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    };
  }

  const allowed = rules.some((rule) => matchesRule(requestOrigin, rule));
  return {
    "Access-Control-Allow-Origin": allowed ? requestOrigin : "null",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}
