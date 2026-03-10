// Supabase Edge Function: распознавание ТТК из PDF
// Извлекает текст через unpdf, парсит через ИИ
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { extractText, getDocumentProxy } from "npm:unpdf@0.4.1";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const PDF_SYSTEM_PROMPT = `You are a tech card (recipe/semi-finished product) parser. The input is raw text extracted from a PDF (e.g. Shama.Book, iiko, other ТТК formats).

Typical structure:
- Header: "Технологическая карта № XXXX от DD.MM.YYYY" or similar
- Dish/ПФ name: next line after header or in "Наименование" column
- Table: № | Наименование сырья и п/ф | Нетто/Брутто | Расход на 1 | Расход на 10 | Выход
- Ingredient rows: number, product name, gross g, net g, etc.
- "Выход на 1 порцию: X г", "Выход на 10 порций: X г"
- "Информация о пищевой ценности: Белки; Жиры; Углеводы; Калорийность"
- Technology block: "Технологический процесс изготовления..."

How to split cards: each PDF page may have one tech card, or multiple. Look for new "Технологическая карта №" or new dish name to start a new card.

For each ingredient, set ingredientType: "product" if purchased (сырьё, смесь, мука, масло — e.g. "смесь РИКО"); "semi_finished" if ПФ (крем, бисквит собственного производства).

Extract: dishName, isSemiFinished (true if "ПФ" in name), ingredients (productName, grossGrams, netGrams, primaryWastePct, cookingLossPct, ingredientType; unit default "g"), technologyText.

Return ONLY valid JSON, no markdown:
{ "cards": [ { "dishName": string, "technologyText": string | null, "isSemiFinished": boolean | null, "ingredients": [ { "productName": string, "grossGrams": number | null, "netGrams": number | null, "primaryWastePct": number | null, "cookingMethod": string | null, "cookingLossPct": number | null, "unit": string | null, "ingredientType": "product" | "semi_finished" | null } ] }, ... ] }

Return ALL cards found. If no cards, return { "cards": [] }.`;

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

  try {
    const body = (await req.json()) as { pdfBase64?: string };
    const pdfBase64 = body.pdfBase64;
    if (!pdfBase64 || typeof pdfBase64 !== "string") {
      return new Response(JSON.stringify({ error: "pdfBase64 required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const hasProvider = Deno.env.get("GROQ_API_KEY")?.trim() ||
      Deno.env.get("GEMINI_API_KEY")?.trim() ||
      Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
      Deno.env.get("OPENAI_API_KEY");
    if (!hasProvider) {
      return new Response(JSON.stringify({ error: "AI provider key required" }), {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // Decode base64 to Uint8Array
    const binary = atob(pdfBase64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    // Extract text
    let text: string;
    try {
      const pdf = await getDocumentProxy(bytes);
      const result = await extractText(pdf, { mergePages: true });
      text = result.text ?? "";
    } catch (e) {
      return new Response(JSON.stringify({ error: `PDF extraction failed: ${e}` }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!text.trim()) {
      return new Response(JSON.stringify({ cards: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const content = await chatText({
      messages: [
        { role: "system", content: PDF_SYSTEM_PROMPT },
        { role: "user", content: `PDF extracted text:\n\n${text}` },
      ],
      maxTokens: 16384,
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ cards: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let parsed: { cards?: unknown[] };
    try {
      const cleaned = content.replace(/^```\w*\n?|\n?```$/g, "").trim();
      parsed = JSON.parse(cleaned) as { cards?: unknown[] };
    } catch {
      return new Response(JSON.stringify({ cards: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const cards = Array.isArray(parsed.cards) ? parsed.cards : [];
    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const ingredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => {
            const it = String(i.ingredientType ?? "").toLowerCase();
            const ingredientType = (it === "product" || it === "semi_finished") ? it : undefined;
            return {
              productName: String(i.productName ?? ""),
              grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
              netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
              unit: i.unit != null ? String(i.unit) : undefined,
              cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
              primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
              cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
              ingredientType,
            };
          })
        : [];
      return {
        dishName: c.dishName != null ? String(c.dishName) : null,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
      };
    });

    return new Response(JSON.stringify({ cards: normalized }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
