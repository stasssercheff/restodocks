// Edge Function: прокси к Open Food Facts. Обход CORS и 504 в DevTools.
// Клиент вызывает нас вместо прямого запроса к world.openfoodfacts.org.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const OFF_BASE = "https://world.openfoodfacts.org";
const TIMEOUT_MS = 8000;

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(origin) });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const q = url.searchParams.get("q")?.trim();
  if (!q || q.length > 200) {
    return new Response(
      JSON.stringify({ error: "Query parameter q required (max 200 chars)" }),
      { status: 400, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } },
    );
  }

  const offUrl = `${OFF_BASE}/cgi/search.pl?search_terms=${encodeURIComponent(q)}&search_simple=1&action=process&json=1&page_size=15`;

  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    const res = await fetch(offUrl, { signal: ctrl.signal });
    clearTimeout(timer);

    if (!res.ok) {
      return new Response(
        JSON.stringify({ products: [] }),
        { status: 200, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } },
      );
    }
    const json = await res.json();
    return new Response(JSON.stringify(json), {
      status: 200,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  } catch (e) {
    if ((e as Error).name === "AbortError") {
      return new Response(
        JSON.stringify({ products: [], _timeout: true }),
        { status: 200, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } },
      );
    }
    return new Response(
      JSON.stringify({ products: [] }),
      { status: 200, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } },
    );
  }
});
