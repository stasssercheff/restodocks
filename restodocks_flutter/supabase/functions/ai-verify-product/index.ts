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

    const systemPrompt = `You are a product data verifier for a restaurant. For each product you receive:
1. normalizedName: correct/standard name (fix typos, unify spelling). Return null if the name is already correct.
2. suggestedCategory: appropriate category like "meat", "dairy", "vegetables", "fruits", "spices", "bakery", "beverages", etc. Return null if unknown.
3. suggestedUnit: appropriate unit like "kg", "g", "l", "ml", "pcs", "pack". Return "g" for most food items.
4. suggestedPrice: typical wholesale price per kg in USD (number). Return only if we need to suggest a price (e.g. when current price is missing or clearly wrong). Use null if unknown.
5. suggestedCalories, suggestedProtein, suggestedFat, suggestedCarbs: per 100g. Suggest only if missing or if current values look wrong (e.g. calories 0 for meat, or unrealistic). Use null for unknown.
Output ONLY valid JSON with keys: normalizedName, suggestedCategory, suggestedUnit, suggestedPrice, suggestedCalories, suggestedProtein, suggestedFat, suggestedCarbs. No markdown. Use null for any value you are not suggesting.`;

    const current = [];
    if (body.currentPrice != null) current.push(`price per kg: ${body.currentPrice}`);
    if (body.currentCalories != null) current.push(`calories: ${body.currentCalories}`);
    if (body.currentProtein != null) current.push(`protein: ${body.currentProtein}`);
    if (body.currentFat != null) current.push(`fat: ${body.currentFat}`);
    if (body.currentCarbs != null) current.push(`carbs: ${body.currentCarbs}`);
    const userContent = current.length > 0
      ? `Product: "${productName}". Current: ${current.join(", ")}. Verify and suggest corrections or fill missing (category, unit, price in USD per kg, nutrition per 100g).`
      : `Product: "${productName}". Suggest normalized name, category, unit, typical price per kg (USD), and nutrition per 100g.`;

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
