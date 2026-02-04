// Supabase Edge Function: распознавание продукта по вводу (нормализация, категория, единица)
import "jsr:@supabase/functions-js/edge_runtime.d.ts";

const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

const CATEGORIES = "vegetables, fruits, meat, seafood, dairy, grains, bakery, pantry, spices, beverages, eggs, legumes, nuts, misc";
const UNITS = "g, kg, pcs, l, ml, portion";

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
    const { userInput } = (await req.json()) as { userInput?: string };
    if (!userInput || typeof userInput !== "string") {
      return new Response(JSON.stringify({ error: "userInput required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const systemPrompt = `You are a product name normalizer for a restaurant. Given raw user input (product name, possibly with typos or colloquial), output JSON:
- normalizedName: string, clean standard name (e.g. "помидор черри" -> "Томат черри")
- suggestedCategory: one of: ${CATEGORIES}
- suggestedUnit: one of: ${UNITS}
- suggestedWastePct: number 0-100, typical primary waste percentage when cleaning/peeling (e.g. carrots ~15, onions ~10, meat ~5, fish ~30). Use null if unsure.
Output only valid JSON. No markdown.`;

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
          { role: "user", content: userInput.trim() },
        ],
        temperature: 0.3,
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
      return new Response(JSON.stringify({ normalizedName: userInput.trim(), suggestedCategory: null, suggestedUnit: null, suggestedWastePct: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const parsed = JSON.parse(content) as Record<string, unknown>;
    const waste = parsed.suggestedWastePct;
    return new Response(JSON.stringify({
      normalizedName: typeof parsed.normalizedName === "string" ? parsed.normalizedName : userInput.trim(),
      suggestedCategory: typeof parsed.suggestedCategory === "string" ? parsed.suggestedCategory : null,
      suggestedUnit: typeof parsed.suggestedUnit === "string" ? parsed.suggestedUnit : null,
      suggestedWastePct: typeof waste === "number" && waste >= 0 && waste <= 100 ? waste : null,
    }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
