// Supabase Edge Function: батч-исправление названий продуктов (опечатки, сленг)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const SYSTEM_PROMPT = `Ты — нормализатор названий продуктов для ресторана. Исправляй ВСЕ опечатки. Результат должен соответствовать стандартным названиям из базы продуктов.

КРИТИЧЕСКИ ВАЖНО: В итоге не должно быть названий с опечатками. Прогоняй каждое название через проверку.

RULES:
- Fix typos: "картофан" -> "Картофель", "помидор" -> "Томат", "лук репка" -> "Лук репчатый", "морков" -> "Морковь"
- Fix common misspellings: "Авокало" -> "Авокадо", "Анчоусм" -> "Анчоусы", "АпельсмН" -> "Апельсин"
- Handle colloquial names: "болгарка" -> "Перец сладкий", "батат" -> "Сладкий картофель", "зелень" -> "Зелень свежая"
- Expand abbreviations: "л. репч." -> "Лук репчатый", "пом." -> "Помидоры", "карт." -> "Картофель"
- Remove extra words: "(заказ)", "кг", "шт", "упаковка", "пачка" if redundant
- Handle quantity indicators: "1кг картофель" -> "Картофель", "5шт лук" -> "Лук"
- Keep proper capitalization for product names
- Use standard Russian restaurant terminology
- Output language: same as input (Russian -> Russian)
- Return ONLY a JSON array of strings in the SAME ORDER as input. One string per input name.
- If a name is already correct, return it unchanged.

EXAMPLES:
- "картофан" -> "Картофель"
- "помидор черри" -> "Томат черри"
- "лук репка" -> "Лук репчатый"
- "морков свежая" -> "Морковь свежая"
- "болгарка красная" -> "Перец сладкий красный"
- "батат" -> "Сладкий картофель"
- "зелень укроп" -> "Укроп свежий"`;

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
    Deno.env.get("GROQ_API_KEY")?.trim() ||
    Deno.env.get("GEMINI_API_KEY")?.trim() ||
    Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
    Deno.env.get("OPENAI_API_KEY");
  if (!hasProvider) {
    return new Response(
      JSON.stringify({ error: "GROQ_API_KEY, GEMINI_API_KEY, GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }),
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
      context: "product",
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
