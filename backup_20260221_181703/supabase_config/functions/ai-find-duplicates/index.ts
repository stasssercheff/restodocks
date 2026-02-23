// Supabase Edge Function: поиск дубликатов в списке названий продуктов (ИИ)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

const SYSTEM_PROMPT = `You analyze a list of product names (with their IDs) and find duplicates — similar names that likely refer to the same product.

Examples of duplicates:
- "Лук репчатый" and "Лук репч. (заказ)"
- "Морковь" and "Морковь столовая"
- "Куриная грудка" and "Грудка куриная"

INPUT: Array of {id, name}
OUTPUT: JSON object with "groups" — array of arrays. Each inner array contains IDs of products that are duplicates of each other.
- A product can be in only one group
- Groups must have at least 2 items
- Order groups by relevance (most obvious duplicates first)

Return ONLY valid JSON. No markdown.`;

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

  const hasProvider =
    Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
    Deno.env.get("GEMINI_API_KEY")?.trim() ||
    Deno.env.get("OPENAI_API_KEY");
  if (!hasProvider) {
    return new Response(
      JSON.stringify({ error: "GIGACHAT_AUTH_KEY, GEMINI_API_KEY or OPENAI_API_KEY required" }),
      {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      },
    );
  }

  try {
    const body = (await req.json()) as { products?: Array<{ id: string; name: string }> };
    const products = Array.isArray(body.products)
      ? body.products.filter((p) => p && typeof p.id === "string" && typeof p.name === "string")
      : [];

    if (products.length < 2) {
      return new Response(JSON.stringify({ groups: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const userContent = `Find duplicate groups in:\n${JSON.stringify(products.slice(0, 300), null, 0)}`;

    const content = await chatText({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userContent },
      ],
      temperature: 0.1,
      maxTokens: 4096,
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ groups: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();

    const parsed = JSON.parse(jsonStr) as { groups?: string[][] };
    const groups = Array.isArray(parsed.groups)
      ? parsed.groups.filter((g) => Array.isArray(g) && g.length >= 2)
      : [];

    return new Response(JSON.stringify({ groups }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), groups: [] }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
