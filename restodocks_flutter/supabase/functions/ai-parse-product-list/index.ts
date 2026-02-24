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

const SYSTEM_PROMPT = `Ты — парсер списка продуктов для ресторана. ОБЯЗАТЕЛЬНО выполняй ВСЕ пункты.

ИСТОЧНИКИ ДАННЫХ (принимай и обрабатывай ВСЕ):
- Excel, CSV, текст (.txt)
- Apple Numbers (.numbers) — игнорировать XML, пути, мусор. Извлекать только строки с названием продукта и ценой
- Apple Pages (.pages)
- RTF (.rtf) — каждая строка часто имеет формат Название\\tЦена. Извлекать ОБА. Никогда не возвращать строки только с ценой
- Word (.docx), вставленный текст из мессенджеров

КРИТИЧЕСКИ ВАЖНО — ИСПРАВЛЕНИЕ ОПЕЧАТОК:
- Прогоняй каждое название через проверку. Исправляй ВСЕ опечатки
- Примеры: "Авокало"->"Авокадо", "Анчоусм"->"Анчоусы", "АпельсмН"->"Апельсин", "картофан"->"Картофель", "морков"->"Морковь"
- Используй стандартную кулинарную терминологию. Нет названий с опечатками в результате

OUTPUT: JSON array of objects, each with:
- name (string, required): product name, cleaned and normalized
- price (number|null): price per kg or unit if detectable
- unit (string|null): "g", "kg", "ml", "l", "pcs", "portion" or similar

RULES:
- Infer columns by content meaning. Product names can be in any column.
- Extract and normalize product names: fix ALL typos (grammatical and semantic)
- Fix typos: "картофан" -> "Картофель", "помидор" -> "Томат", "лук" -> "Лук репчатый", "Авокало" -> "Авокадо", "Анчоусм" -> "Анчоусы", "АпельсмН" -> "Апельсин"
- Use standard culinary terminology, correct spelling
- Handle various price formats: "50р", "50 руб", "50.5", "50,5"
- Analyze prices: detect currency, validate reasonableness
- Recognize units: кг, г, шт, л, мл, порция, упаковка
- Handle comma as decimal separator (50,5 = 50.5) and dots (50.5 = 50.5)
- Handle spaces in numbers (1 000 = 1000)
- Skip rows without product names (headers, totals, empty rows)
- Return ONLY valid JSON array, no markdown, no extra text.
- Max 500 items. If more rows, take first 500.

EXAMPLES:
- "Картофель 45р кг" -> {"name": "Картофель", "price": 45, "unit": "kg"}
- "Лук репчатый;120;шт" -> {"name": "Лук репчатый", "price": 120, "unit": "pcs"}
- "Помидоры черри 250 руб/кг" -> {"name": "Томат черри", "price": 250, "unit": "kg"}`;

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
    if (!Deno.env.get("AI_PROVIDER") && Deno.env.get("GEMINI_API_KEY")?.trim()) {
      Deno.env.set("AI_PROVIDER", "gemini");
    }
    const body = (await req.json()) as { rows?: string[]; text?: string; source?: string };
    let rows: string[] = [];
    const source = typeof body.source === "string" ? body.source : "";

    if (Array.isArray(body.rows) && body.rows.length > 0) {
      rows = body.rows
        .map((r) => (typeof r === "string" ? r : String(r ?? "")).trim())
        .filter((r) => r.length > 0);
    } else if (typeof body.text === "string" && body.text.trim()) {
      rows = body.text
        .split(/\r?\n/)
        .map((r) => r.trim())
        .filter((r) => r.length > 0);
      if (rows.length === 0) rows = [body.text.trim()];
    }

    if (rows.length === 0) {
      return new Response(JSON.stringify({ items: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const sourceHint = source ? `\n\nИсточник: ${source}. Обработай соответственно.` : "";
    const toSend = rows.slice(0, 500);
    const userContent = `Распарси в список продуктов. Обязательно исправь ВСЕ опечатки в названиях.${sourceHint}\n\nСтрок: ${toSend.length}\n\n${toSend.map((r, i) => `${i + 1}. ${r}`).join("\n")}`;

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
