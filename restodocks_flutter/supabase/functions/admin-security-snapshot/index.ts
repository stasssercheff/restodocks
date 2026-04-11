// Сводка безопасности для платформенной админки: Cloudflare (опционально) + эвристики.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  enforceRateLimit,
  getAuthenticatedUserEmail,
  resolveCorsHeaders,
} from "../_shared/security.ts";

const CF_GRAPHQL = "https://api.cloudflare.com/client/v4/graphql";

/** Совпадает с `_platformAdminEmails` в app_router.dart; доп. список — secret PLATFORM_ADMIN_EMAILS. */
const DEFAULT_PLATFORM_ADMIN_EMAILS = new Set([
  "stasssercheff@gmail.com",
]);

function platformAdminEmails(): Set<string> {
  const env = (Deno.env.get("PLATFORM_ADMIN_EMAILS") ?? "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return new Set([...DEFAULT_PLATFORM_ADMIN_EMAILS, ...env]);
}

function isPlatformAdmin(email: string | null): boolean {
  if (!email) return false;
  return platformAdminEmails().has(email.toLowerCase().trim());
}

async function cloudflareGraphql(
  token: string,
  query: string,
  variables: Record<string, unknown>,
): Promise<{ data?: unknown; errors?: { message: string }[] }> {
  const res = await fetch(CF_GRAPHQL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });
  const json = (await res.json()) as {
    data?: unknown;
    errors?: { message: string }[];
  };
  return json;
}

type FwEvent = {
  action?: string | null;
  clientIP?: string | null;
  datetime?: string | null;
  clientRequestPath?: string | null;
  clientCountryName?: string | null;
  edgeResponseStatus?: number | null;
  source?: string | null;
};

/** Структура для локализации на клиенте (ключи + параметры). */
type Insight =
  | { kind: "traffic_volume"; severity: "info"; requests24h: number }
  | { kind: "waf_activity"; severity: "warning"; blocks: number; challenges: number }
  | { kind: "ip_noisy"; severity: "warning"; ip: string; events: number }
  | { kind: "probe_path"; severity: "warning"; pathSample: string }
  | { kind: "db_attack_note"; severity: "info" };

function buildInsights(requests24h: number | null, events: FwEvent[]): Insight[] {
  const out: Insight[] = [];

  if (requests24h != null && requests24h > 0) {
    out.push({
      kind: "traffic_volume",
      severity: "info",
      requests24h,
    });
  }

  const blocked = events.filter((e) =>
    /block|deny|drop/i.test(e.action ?? "")
  );
  const challenged = events.filter((e) =>
    /challenge|managed_challenge/i.test(e.action ?? "")
  );
  if (blocked.length > 0 || challenged.length > 0) {
    out.push({
      kind: "waf_activity",
      severity: "warning",
      blocks: blocked.length,
      challenges: challenged.length,
    });
  }

  const byIp = new Map<string, number>();
  for (const e of events) {
    const ip = e.clientIP?.trim();
    if (!ip) continue;
    byIp.set(ip, (byIp.get(ip) ?? 0) + 1);
  }
  for (const [ip, n] of byIp) {
    if (n >= 5) {
      out.push({ kind: "ip_noisy", severity: "warning", ip, events: n });
      break;
    }
  }

  const probePaths =
    /(\.env|wp-login|xmlrpc|phpmyadmin|\.git|union\s+select|\/\.\.\/)/i;
  for (const e of events) {
    const p = e.clientRequestPath ?? "";
    if (probePaths.test(p)) {
      out.push({
        kind: "probe_path",
        severity: "warning",
        pathSample: p.length > 120 ? `${p.slice(0, 120)}…` : p,
      });
      break;
    }
  }

  out.push({ kind: "db_attack_note", severity: "info" });

  return out;
}

Deno.serve(async (req: Request) => {
  const corsHeaders = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!enforceRateLimit(req, "admin-security-snapshot", {
    windowMs: 60_000,
    maxRequests: 20,
  })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const email = await getAuthenticatedUserEmail(req);
  if (!isPlatformAdmin(email)) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const generatedAt = new Date().toISOString();
  const cfToken = Deno.env.get("CLOUDFLARE_API_TOKEN")?.trim();
  const zoneTag = Deno.env.get("CLOUDFLARE_ZONE_ID")?.trim();
  const accountId = Deno.env.get("CLOUDFLARE_ACCOUNT_ID")?.trim();

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  let supabaseProjectRef: string | null = null;
  const m = /^https:\/\/([a-z0-9-]+)\.supabase\.co\/?$/i.exec(supabaseUrl);
  if (m) supabaseProjectRef = m[1];

  if (!cfToken || !zoneTag) {
    return new Response(
      JSON.stringify({
        ok: true,
        generatedAt,
        cloudflare: {
          configured: false,
          requests24hApprox: null,
          firewallEvents: [],
          graphqlErrors: null,
        },
        insights: buildInsights(null, []),
        links: {
          cloudflareSecurity: accountId
            ? `https://dash.cloudflare.com/${accountId}/${zoneTag ?? ""}/security/analytics`
            : "https://dash.cloudflare.com/",
          cloudflareWaf: accountId && zoneTag
            ? `https://dash.cloudflare.com/${accountId}/${zoneTag}/security/waf`
            : "https://dash.cloudflare.com/",
          supabaseLogs: supabaseProjectRef
            ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/logs/explorer`
            : "https://supabase.com/dashboard",
          supabaseAuth: supabaseProjectRef
            ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/auth/users`
            : "https://supabase.com/dashboard",
        },
        hint:
          "Задайте в Secrets Edge Functions: CLOUDFLARE_API_TOKEN (Analytics + Firewall Read) и CLOUDFLARE_ZONE_ID — появятся счётчик запросов и выборка событий WAF.",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const end = new Date();
  const start = new Date(end.getTime() - 24 * 60 * 60 * 1000);
  const startIso = start.toISOString();
  const endIso = end.toISOString();

  const qRequests = `
    query ($zoneTag: string, $start: Time, $end: Time) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          httpRequests1hGroups(
            limit: 10000
            filter: { datetime_geq: $start, datetime_lt: $end }
          ) {
            sum {
              requests
            }
          }
        }
      }
    }
  `;

  const qFw = `
    query ($zoneTag: string, $start: Time, $end: Time) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          firewallEventsAdaptive(
            filter: { datetime_geq: $start, datetime_lt: $end }
            limit: 40
            orderBy: [datetime_DESC]
          ) {
            action
            clientIP
            datetime
            clientRequestPath
            clientCountryName
            edgeResponseStatus
            source
          }
        }
      }
    }
  `;

  const vars = { zoneTag, start: startIso, end: endIso };

  const [r1, r2] = await Promise.all([
    cloudflareGraphql(cfToken, qRequests, vars),
    cloudflareGraphql(cfToken, qFw, vars),
  ]);

  const gqlErrors = [
    ...(r1.errors?.map((e) => e.message) ?? []),
    ...(r2.errors?.map((e) => e.message) ?? []),
  ];

  let requests24hApprox: number | null = null;
  const zones1 = (r1.data as {
    viewer?: { zones?: { httpRequests1hGroups?: { sum?: { requests?: number } }[] }[] };
  })?.viewer?.zones;
  if (zones1?.[0]?.httpRequests1hGroups) {
    let total = 0;
    for (const g of zones1[0].httpRequests1hGroups ?? []) {
      total += g.sum?.requests ?? 0;
    }
    requests24hApprox = total;
  }

  let firewallEvents: FwEvent[] = [];
  const zones2 = (r2.data as {
    viewer?: {
      zones?: {
        firewallEventsAdaptive?: FwEvent[];
      }[];
    };
  })?.viewer?.zones;
  if (zones2?.[0]?.firewallEventsAdaptive) {
    firewallEvents = zones2[0].firewallEventsAdaptive;
  }

  const insights = buildInsights(requests24hApprox, firewallEvents);

  return new Response(
    JSON.stringify({
      ok: true,
      generatedAt,
      cloudflare: {
        configured: true,
        requests24hApprox,
        firewallEvents,
        graphqlErrors: gqlErrors.length ? gqlErrors : null,
      },
      insights,
      links: {
        cloudflareSecurity: accountId
          ? `https://dash.cloudflare.com/${accountId}/${zoneTag}/security/analytics`
          : "https://dash.cloudflare.com/",
        cloudflareWaf: accountId
          ? `https://dash.cloudflare.com/${accountId}/${zoneTag}/security/waf`
          : "https://dash.cloudflare.com/",
        supabaseLogs: supabaseProjectRef
          ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/logs/explorer`
          : "https://supabase.com/dashboard",
        supabaseAuth: supabaseProjectRef
          ? `https://supabase.com/dashboard/project/${supabaseProjectRef}/auth/users`
          : "https://supabase.com/dashboard",
      },
      hint: gqlErrors.length
        ? `Часть запросов к Cloudflare GraphQL недоступна на текущем тарифе или токену не хватает прав: ${gqlErrors[0]}`
        : null,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
