// Supabase Edge Function: распознавание ТТК по фото или таблице (Excel, текст).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText, chatWithVision } from "../_shared/ai_provider.ts";

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

  try {
    const body = (await req.json()) as { imageBase64?: string; rows?: string[][] };
    const imageBase64 = body.imageBase64;
    const rows = body.rows;

    const hasTextProvider = Deno.env.get("DEEPSEEK_API_KEY")?.trim() || Deno.env.get("GROQ_API_KEY")?.trim() || Deno.env.get("GEMINI_API_KEY")?.trim() || Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("OPENAI_API_KEY")?.trim();

    const normalizeJson = (content: string): string => {
      let c = content.trim();
      c = c.replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```$/i, "").trim();
      const s = c.indexOf("{");
      const e = c.lastIndexOf("}");
      if (s >= 0 && e > s) return c.slice(s, e + 1);
      return c;
    };

    if (imageBase64 && typeof imageBase64 === "string") {
      if (!hasTextProvider) {
        return new Response(JSON.stringify({ error: "AI_PROVIDER_MISSING", message: "Set DEEPSEEK_API_KEY, GROQ_API_KEY or OPENAI_API_KEY for photo OCR." }), {
          status: 500,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }
      const imageUrl = imageBase64.startsWith("data:")
        ? imageBase64
        : `data:image/jpeg;base64,${imageBase64}`;
      const systemPrompt = `You parse ONE Russian tech card image (ТТК).
Return ONLY strict JSON:
{
  "dishName": string|null,
  "technologyText": string|null,
  "isSemiFinished": boolean|null,
  "ingredients": [
    {
      "productName": string,
      "grossGrams": number|null,
      "primaryWastePct": number|null,
      "netGrams": number|null,
      "cookingMethod": string|null,
      "cookingLossPct": number|null,
      "unit": string|null
    }
  ]
}
Rules:
- Extract ingredients from recipe table.
- Ignore section numbering and prose headers.
- Convert decimal commas to dot in numbers.
- unit for gram entries: "g".
- If unknown value, use null.`;
      const content = await chatWithVision({
        messages: [
          { role: "system", content: systemPrompt },
          {
            role: "user",
            content: [
              { type: "text", text: "Extract one tech card from this photo. Return JSON only." },
              { type: "image_url", image_url: { url: imageUrl } },
            ],
          },
        ],
        maxTokens: 2048,
      });
      const parsed = JSON.parse(normalizeJson(content)) as Record<string, unknown>;
      const ingredientsFromImage = Array.isArray(parsed.ingredients)
        ? (parsed.ingredients as Record<string, unknown>[]).map((i) => ({
            productName: String(i.productName ?? ""),
            grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
            netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
            unit: i.unit != null ? String(i.unit) : undefined,
            cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
            primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
            cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
          })).filter((x) => x.productName.trim().length > 0)
        : [];
      return new Response(JSON.stringify({
        dishName: parsed.dishName != null ? String(parsed.dishName) : null,
        technologyText: parsed.technologyText != null ? String(parsed.technologyText) : null,
        ingredients: ingredientsFromImage,
        isSemiFinished: typeof parsed.isSemiFinished === "boolean" ? parsed.isSemiFinished : undefined,
      }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (rows && Array.isArray(rows)) {
      if (!hasTextProvider) {
        return new Response(JSON.stringify({ error: "DEEPSEEK_API_KEY, GROQ_API_KEY, GEMINI_API_KEY, GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }), {
          status: 500,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }
      const systemPrompt = `You are a tech card parser. The app table columns are: 1=Dish name, 2=Product, 3=Gross (g), 4=Waste %, 5=Net (g), 6=Cooking method, 7=Cooking loss %, 8=Output, 9=Price/kg, 10=Cost, 11=Technology.
Given table rows (each row = array of cell strings), map each cell to the correct field. Return ONLY valid JSON:
- dishName, technologyText, isSemiFinished
- ingredients: array of { productName, grossGrams?, primaryWastePct?, netGrams?, cookingMethod?, cookingLossPct?, unit? }
No markdown.`;

      const content = await chatText({
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `Table:\n${JSON.stringify(rows)}` },
        ],
        maxTokens: 2048,
        context: "ttk_parse",
      });

      if (!content?.trim()) {
        return new Response(JSON.stringify({ dishName: null, technologyText: null, ingredients: [], isSemiFinished: undefined }), {
          status: 200,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }

      const parsed = JSON.parse(normalizeJson(content)) as Record<string, unknown>;
      const ingredientsFromRows = Array.isArray(parsed.ingredients)
        ? (parsed.ingredients as Record<string, unknown>[]).map((i) => ({
            productName: String(i.productName ?? ""),
            grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
            netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
            unit: i.unit != null ? String(i.unit) : undefined,
            cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
            primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
            cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
          }))
        : [];

      return new Response(JSON.stringify({
        dishName: parsed.dishName != null ? String(parsed.dishName) : null,
        technologyText: parsed.technologyText != null ? String(parsed.technologyText) : null,
        ingredients: ingredientsFromRows,
        isSemiFinished: typeof parsed.isSemiFinished === "boolean" ? parsed.isSemiFinished : undefined,
      }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "rows required (Excel file). Photo upload is disabled." }), {
      status: 400,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
