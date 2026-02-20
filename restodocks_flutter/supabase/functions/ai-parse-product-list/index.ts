// Supabase Edge Function: всеядный парсинг списка продуктов из строк (файл или текст)
// ИИ самостоятельно определяет колонки: Название, Цена, Ед. изм. по смыслу содержимого
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

const SYSTEM_PROMPT = `You are a product list parser for a restaurant. Given raw rows (from Excel, CSV, or pasted text from messengers/notes), extract product items.

INPUT: Array of raw text rows. Each row can be:
- Tab/coma/semicolon-separated columns
- Inline text like "картофель 50р кг" or "лук репка - 120 - шт"
- Mixed formats

OUTPUT: JSON array of objects, each with:
- name (string, required): product name, cleaned
- price (number|null): price per kg or unit if detectable
- unit (string|null): "g", "kg", "ml", "l", "pcs" or similar

RULES:
- Infer columns by content meaning. Names can be in any column.
- Ignore formatting errors, use raw values.
- Handle comma as decimal separator (50,5 = 50.5).
- Handle spaces in numbers (1 000 = 1000).
- Return ONLY valid JSON array, no markdown, no extra text.
- If a row has no product name, skip it.
- Max 500 items. If more rows, take first 500.`;

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
    const body = (await req.json()) as { rows?: string[]; text?: string };
    let rows: string[] = [];

    if (Array.isArray(body.rows) && body.rows.length > 0) {
      rows = body.rows
        .map((r) => (typeof r === "string" ? r : String(r ?? "")).trim())
        .filter((r) => r.length > 0);
    } else if (typeof body.text === "string" && body.text.trim()) {
      rows = body.text
        .split(/\r?\n/)
        .map((r) => r.trim())
        .filter((r) => r.length > 0);
    }

    if (rows.length === 0) {
      return new Response(JSON.stringify({ items: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // Limit to avoid token overflow
    const toSend = rows.slice(0, 500);
    const userContent = `Parse these ${toSend.length} rows into product list:\n\n${toSend.map((r, i) => `${i + 1}. ${r}`).join("\n")}`;

    const content = await chatText({
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userContent },
      ],
      temperature: 0.2,
      maxTokens: 8192,
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ items: [], error: "Empty AI response" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();

    const parsed = JSON.parse(jsonStr);
    const arr = Array.isArray(parsed) ? parsed : parsed.items ?? parsed.data ?? [];
    const items = arr
      .filter((o: unknown) => o && typeof o === "object")
      .map((o: Record<string, unknown>) => ({
        name: typeof o.name === "string" ? o.name.trim() : String(o.name ?? "").trim(),
        price: typeof o.price === "number" && !Number.isNaN(o.price) ? o.price : (o.price != null ? Number(o.price) : null),
        unit: typeof o.unit === "string" && o.unit.trim() ? o.unit.trim() : null,
      }))
      .filter((o: { name: string }) => o.name.length > 0);

    return new Response(JSON.stringify({ items }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), items: [] }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
