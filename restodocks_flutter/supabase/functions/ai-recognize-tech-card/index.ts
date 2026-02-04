// Supabase Edge Function: распознавание ТТК по фото карточки (OpenAI Vision)
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
    const body = (await req.json()) as { imageBase64?: string; rows?: string[][] };
    const imageBase64 = body.imageBase64;
    const rows = body.rows;

    if (imageBase64 && typeof imageBase64 === "string") {
      const imageUrl = imageBase64.startsWith("data:") ? imageBase64 : `data:image/jpeg;base64,${imageBase64}`;
      const systemPrompt = `You are a tech card (recipe card) parser. The app table has EXACT columns in this order:
1) Dish name | 2) Product/ingredient name | 3) Gross (g) | 4) Waste % | 5) Net (g) | 6) Cooking method | 7) Cooking loss % | 8) Output | 9) Price per kg | 10) Cost | 11) Technology
Extract from the image so each value goes into the correct column. Return ONLY valid JSON, no markdown.

Schema:
- dishName: string (column 1 - name of dish or semi-finished)
- technologyText: string (column 11 - full technology text)
- isSemiFinished: boolean (true = semi-finished, false = finished dish)
- ingredients: array of objects, one per ingredient row. Each object:
  - productName: string (column 2)
  - grossGrams: number (column 3, in grams)
  - primaryWastePct: number (column 4, 0-100, percent waste)
  - netGrams: number (column 5, in grams)
  - cookingMethod: string (column 6, e.g. "Жарка", "Варка")
  - cookingLossPct: number (column 7, 0-100, percent cooking loss/shrinkage, optional)
  - unit: string (e.g. "g", "kg", "pcs", "шт")

If a number is missing in the image use null. Use exact numbers from the image.`;

      const res = await fetch(OPENAI_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o",
          messages: [
            { role: "system", content: systemPrompt },
            {
              role: "user",
              content: [
                { type: "text", text: "Extract the tech card data from this image." },
                { type: "image_url", image_url: { url: imageUrl } },
              ],
            },
          ],
          max_tokens: 2048,
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
        return new Response(JSON.stringify({ error: "Empty response", dishName: null, technologyText: null, ingredients: [] }), {
          status: 200,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }

      const parsed = JSON.parse(content) as Record<string, unknown>;
      const ingredients = Array.isArray(parsed.ingredients)
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
        ingredients,
        isSemiFinished: typeof parsed.isSemiFinished === "boolean" ? parsed.isSemiFinished : undefined,
      }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (rows && Array.isArray(rows)) {
      const systemPrompt = `You are a tech card parser. The app table columns are: 1=Dish name, 2=Product, 3=Gross (g), 4=Waste %, 5=Net (g), 6=Cooking method, 7=Cooking loss %, 8=Output, 9=Price/kg, 10=Cost, 11=Technology.
Given table rows (each row = array of cell strings), map each cell to the correct field. Return ONLY valid JSON:
- dishName, technologyText, isSemiFinished
- ingredients: array of { productName, grossGrams?, primaryWastePct?, netGrams?, cookingMethod?, cookingLossPct?, unit? }
No markdown.`;

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
            { role: "user", content: `Table:\n${JSON.stringify(rows)}` },
          ],
          max_tokens: 2048,
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
        return new Response(JSON.stringify({ dishName: null, technologyText: null, ingredients: [], isSemiFinished: undefined }), {
          status: 200,
          headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
        });
      }

      const parsed = JSON.parse(content) as Record<string, unknown>;
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

    return new Response(JSON.stringify({ error: "imageBase64 or rows required" }), {
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
