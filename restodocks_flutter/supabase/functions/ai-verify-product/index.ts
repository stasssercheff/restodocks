// Supabase Edge Function: верификация продукта для сверки по списку (цена, КБЖУ, название)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

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

  const hasProvider = Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("OPENAI_API_KEY");
  if (!hasProvider) {
    return new Response(JSON.stringify({ error: "GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as {
      productName?: string;
      currentPrice?: number;
      currentCalories?: number;
      currentProtein?: number;
      currentFat?: number;
      currentCarbs?: number;
    };
    const productName = body.productName?.trim();
    if (!productName) {
      return new Response(JSON.stringify({ error: "productName required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const systemPrompt = `You are a nutrition expert for a restaurant database. For each food product:

1. normalizedName: Standard English name (e.g., "carrot", "strawberry"). Return null if already correct.

2. suggestedCategory: One of: "vegetables", "fruits", "meat", "seafood", "dairy", "grains", "bakery", "pantry", "spices", "beverages", "eggs", "legumes", "nuts", "misc"

3. suggestedUnit: "g" for most foods, "ml" for liquids, "pcs" for eggs/items counted

4. suggestedPrice: Wholesale USD per kg (realistic market prices). Only if missing/wrong.

5. NUTRITION per 100g (REQUIRED - use real food data):
   - suggestedCalories: kcal per 100g
   - suggestedProtein: grams per 100g
   - suggestedFat: grams per 100g  
   - suggestedCarbs: grams per 100g

REAL EXAMPLES:
- Carrot: calories: 41, protein: 0.9, fat: 0.2, carbs: 10
- Strawberry: calories: 32, protein: 0.7, fat: 0.3, carbs: 8
- Chicken breast: calories: 165, protein: 31, fat: 3.6, carbs: 0
- Salmon: calories: 206, protein: 22, fat: 12, carbs: 0

ALWAYS provide accurate nutrition data per 100g. Use null only if completely unknown.

Output ONLY valid JSON with all keys. No markdown.`;

    const current = [];
    if (body.currentPrice != null) current.push(`price per kg: ${body.currentPrice}`);
    if (body.currentCalories != null) current.push(`calories per 100g: ${body.currentCalories}`);
    if (body.currentProtein != null) current.push(`protein per 100g: ${body.currentProtein}`);
    if (body.currentFat != null) current.push(`fat per 100g: ${body.currentFat}`);
    if (body.currentCarbs != null) current.push(`carbs per 100g: ${body.currentCarbs}`);

    const userContent = current.length > 0
      ? `Food product: "${productName}". Current data: ${current.join(", ")}. Provide complete nutrition data per 100g (calories, protein, fat, carbs) and verify/correct other fields.`
      : `Food product: "${productName}". Provide: standard name, category, unit, wholesale USD/kg price, and ACCURATE nutrition per 100g (calories, protein, fat, carbs).`;

    const content = await chatText({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userContent },
      ],
      temperature: 0.2,
    });
    if (!content?.trim()) {
      return new Response(JSON.stringify({
        normalizedName: null,
        suggestedCategory: null,
        suggestedUnit: null,
        suggestedPrice: null,
        suggestedCalories: null,
        suggestedProtein: null,
        suggestedFat: null,
        suggestedCarbs: null,
      }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
    const parsed = JSON.parse(content) as Record<string, unknown>;
    const num = (v: unknown): number | null =>
      typeof v === "number" && !Number.isNaN(v) ? v : (v != null ? Number(v) : null);
    const str = (v: unknown): string | null =>
      typeof v === "string" && v.trim() !== "" ? v.trim() : null;
    return new Response(JSON.stringify({
      normalizedName: typeof parsed.normalizedName === "string" && parsed.normalizedName.trim() !== ""
        ? parsed.normalizedName.trim()
        : null,
      suggestedCategory: str(parsed.suggestedCategory),
      suggestedUnit: str(parsed.suggestedUnit),
      suggestedPrice: num(parsed.suggestedPrice),
      suggestedCalories: num(parsed.suggestedCalories),
      suggestedProtein: num(parsed.suggestedProtein),
      suggestedFat: num(parsed.suggestedFat),
      suggestedCarbs: num(parsed.suggestedCarbs),
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
