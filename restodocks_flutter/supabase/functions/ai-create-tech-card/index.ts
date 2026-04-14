import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

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
    const body = (await req.json()) as { prompt?: string; establishmentId?: string };
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    const establishmentId = typeof body.establishmentId === "string" ? body.establishmentId.trim() : "";
    if (!prompt) {
      return new Response(JSON.stringify({ error: "prompt required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (establishmentId) {
      const { checkAndIncrementAiTtkUsage } = await import("../_shared/ai_ttk_limit.ts");
      const { allowed, reason } = await checkAndIncrementAiTtkUsage(establishmentId);
      if (!allowed) {
        return new Response(
          JSON.stringify({ error: reason ?? "ai_limit_exceeded", reason: reason ?? "ai_limit_exceeded" }),
          { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
    }

    const content = await chatText({
      messages: [
        {
          role: "system",
          content:
            "Ты технолог общественного питания. По запросу пользователя сгенерируй ТТК в JSON. " +
            "Верни только JSON вида: {\"cards\":[{...}]}, где каждый элемент массива — одна ТТК. " +
            "Если пользователь явно просит компоненты собственного производства (например, домашний хлеб, вяленые томаты собственного производства, соус собственного производства), " +
            "создай ОТДЕЛЬНЫЕ ТТК-ПФ для этих компонентов (isSemiFinished=true), а в основной ТТК добавь их как ingredientType='semi_finished'. " +
            "Для каждой ТТК поля: dishName:string, technologyText:string, isSemiFinished:boolean, " +
            "ingredients:[{productName:string,grossGrams:number,unit:string,primaryWastePct:number,netGrams:number,cookingLossPct:number,outputGrams:number,ingredientType:string}], yieldGrams:number. " +
            "Технология: 3–6 коротких предложений по шагам (без воды). Ингредиентов минимум 3. Без markdown.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.35,
      maxTokens: 3072,
      context: "ttk_create",
    });

    if (!content || !content.trim()) {
      return new Response(JSON.stringify({ error: "ai_empty_response", reason: "ai_empty_response" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();
    const parsed = JSON.parse(jsonStr) as Record<string, unknown>;
    const cardsRaw = parsed["cards"];
    const cards = Array.isArray(cardsRaw)
      ? cardsRaw
      : [parsed];

    return new Response(JSON.stringify({ cards }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `ai_error: ${e}`, reason: "ai_error" }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
