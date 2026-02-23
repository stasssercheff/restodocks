// Supabase Edge Function: батч-исправление названий продуктов (опечатки, сленг)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

const SYSTEM_PROMPT = `You are a product name normalizer for a restaurant. Given a list of product names (possibly with typos, slang, abbreviations), return corrected standard names.

RULES:
- Fix typos: "картофан" -> "Картофель", "лук репка" -> "Лук репчатый"
- Expand abbreviations: "лук репч." -> "Лук репчатый"
- Remove extra words like "(заказ)", "кг" if redundant
- Keep the first letter capitalized for each significant word
- Output language: same as input (if Russian -> Russian, etc.)
- Return ONLY a JSON array of strings in the SAME ORDER as input. One string per input name.
- If a name is already correct, return it unchanged.`;

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
    const body = (await req.json()) as { names?: string[] };
    const names = Array.isArray(body.names)
      ? body.names.filter((n) => typeof n === "string" && n.trim()).slice(0, 200)
      : [];

    if (names.length === 0) {
      return new Response(JSON.stringify({ normalized: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const userContent = `Normalize these ${names.length} product names:\n${names.map((n, i) => `${i + 1}. ${n}`).join("\n")}`;

    const content = await chatText({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userContent },
      ],
      temperature: 0.2,
      maxTokens: 4096,
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ normalized: names }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();

    const parsed = JSON.parse(jsonStr);
    const arr = Array.isArray(parsed) ? parsed : parsed.normalized ?? [];
    const normalized = names.map((n, i) => {
      const v = arr[i];
      return typeof v === "string" && v.trim() ? v.trim() : n;
    });

    return new Response(JSON.stringify({ normalized }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
