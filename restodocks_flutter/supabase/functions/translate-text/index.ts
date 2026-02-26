// Supabase Edge Function: перевод текста через Google Cloud Translation API v2
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GOOGLE_TRANSLATE_URL = "https://translation.googleapis.com/language/translate/v2";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req.headers.get("Origin")) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  const apiKey = Deno.env.get("GOOGLE_TRANSLATE_API_KEY")?.trim();
  if (!apiKey) {
    return new Response(
      JSON.stringify({ error: "GOOGLE_TRANSLATE_API_KEY not set in Supabase secrets" }),
      {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      }
    );
  }

  try {
    const body = (await req.json()) as { text?: string; from?: string; to?: string };
    const { text, from, to } = body;
    if (!text || typeof text !== "string" || !to || typeof to !== "string") {
      return new Response(
        JSON.stringify({ error: "text and to (target language) are required" }),
        {
          status: 400,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        }
      );
    }

    const trimmed = text.trim();
    if (!trimmed) {
      return new Response(JSON.stringify({ translatedText: "" }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const payload: Record<string, unknown> = {
      q: [trimmed],
      target: to,
      format: "text",
    };
    if (from && typeof from === "string" && from.trim()) {
      payload.source = from.trim();
    }

    const url = `${GOOGLE_TRANSLATE_URL}?key=${encodeURIComponent(apiKey)}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("[translate-text] Google API error:", res.status, errText);
      return new Response(
        JSON.stringify({
          error: `Google Translate API: ${res.status}`,
          details: res.status === 403 ? "Check API key and enable Cloud Translation API" : errText.slice(0, 200),
        }),
        {
          status: 502,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        }
      );
    }

    const data = (await res.json()) as { data?: { translations?: Array<{ translatedText?: string }> } };
    const translated = data?.data?.translations?.[0]?.translatedText?.trim();
    if (!translated) {
      return new Response(
        JSON.stringify({ error: "Empty translation from Google" }),
        {
          status: 502,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({ translatedText: translated }),
      {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      }
    );
  } catch (e) {
    console.error("[translate-text]", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
