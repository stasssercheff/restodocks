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

    const systemPrompt = `You are an expert food recognition and nutrition analyst for restaurants. Analyze each food product and provide complete information:

1. PRODUCT IDENTIFICATION:
   - normalizedName: Clean, standard name in English (e.g., "carrot", "chicken breast", "strawberry")
   - suggestedCategory: Exact category from: "vegetables", "fruits", "meat", "seafood", "dairy", "grains", "bakery", "pantry", "spices", "beverages", "eggs", "legumes", "nuts", "misc"
   - suggestedUnit: Standard unit - "g" for solids, "ml" for liquids, "pcs" for countable items

2. PRICE ANALYSIS:
   - suggestedPrice: Realistic wholesale USD per kg based on market data. Only suggest if input price seems wrong.

3. NUTRITION DATA per 100g (MANDATORY - use accurate food composition data):
   - suggestedCalories: kcal per 100g (precise value)
   - suggestedProtein: grams per 100g (protein content)
   - suggestedFat: grams per 100g (fat content)
   - suggestedCarbs: grams per 100g (carbohydrate content)

STRICT NUTRITION GUIDELINES:
- Vegetables (carrot, tomato, lettuce): 20-50 kcal, low protein/fat, 5-15g carbs
- Fruits (apple, banana, strawberry): 30-80 kcal, 0.5-1.5g protein, 0.2-0.5g fat, 10-25g carbs
- Meat (chicken, beef, pork): 150-250 kcal, 20-35g protein, 3-15g fat, 0-2g carbs
- Fish/Seafood (salmon, tuna): 120-250 kcal, 18-30g protein, 4-20g fat, 0-1g carbs
- Dairy (milk, cheese, yogurt): 50-400 kcal, 3-35g protein, 1-35g fat, 3-10g carbs
- Grains (rice, pasta, bread): 300-400 kcal, 8-15g protein, 1-5g fat, 70-85g carbs
- Eggs: 155 kcal, 13g protein, 11g fat, 1g carbs

RECOGNITION PATTERNS:
- "куриная грудка" → "chicken breast", meat, 165 kcal, 31g protein
- "морковь" → "carrot", vegetables, 41 kcal, 10g carbs
- "клубника" → "strawberry", fruits, 32 kcal, 8g carbs
- "говядина" → "beef", meat, 250 kcal, 26g protein
- "лосось" → "salmon", seafood, 206 kcal, 22g protein

ALWAYS return complete, accurate nutrition data. Never use null for nutrition values.

Output ONLY valid JSON. No explanations.`;

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
