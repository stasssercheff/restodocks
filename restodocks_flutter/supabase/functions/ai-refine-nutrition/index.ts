// Supabase Edge Function: КБЖУ по названию продукта (fallback к Open Food Facts)
import "jsr:@supabase/functions-js/edge_runtime.d.ts";

const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
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

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "OPENAI_API_KEY not set" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const { productName, existing } = (await req.json()) as {
      productName?: string;
      existing?: { calories?: number; protein?: number; fat?: number; carbs?: number };
    };
    if (!productName || typeof productName !== "string") {
      return new Response(JSON.stringify({ error: "productName required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const systemPrompt = `You are a nutrition expert. For the given food product name, provide approximate nutrition per 100g. Output JSON only:
- calories: number (kcal)
- protein: number (grams)
- fat: number (grams)
- carbs: number (grams)
Use reasonable values for common foods. If uncertain, use null for that field. No markdown.`;

    const userContent = existing
      ? `Product: "${productName}". Existing data: ${JSON.stringify(existing)}. Refine or confirm values per 100g (output full JSON).`
      : `Product: "${productName}". Give nutrition per 100g.`;

    const res = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
        ],
        temperature: 0.2,
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      return new Response(JSON.stringify({ error: `OpenAI: ${res.status} ${err}` }), {
        status: 502,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const data = await res.json() as { choices?: { message?: { content?: string } }[] };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (!content) {
      return new Response(JSON.stringify({ calories: null, protein: null, fat: null, carbs: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const parsed = JSON.parse(content) as Record<string, unknown>;
    const calories = typeof parsed.calories === "number" ? parsed.calories : (parsed.calories != null ? Number(parsed.calories) : null);
    const protein = typeof parsed.protein === "number" ? parsed.protein : (parsed.protein != null ? Number(parsed.protein) : null);
    const fat = typeof parsed.fat === "number" ? parsed.fat : (parsed.fat != null ? Number(parsed.fat) : null);
    const carbs = typeof parsed.carbs === "number" ? parsed.carbs : (parsed.carbs != null ? Number(parsed.carbs) : null);

    return new Response(JSON.stringify({ calories, protein, fat, carbs }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
