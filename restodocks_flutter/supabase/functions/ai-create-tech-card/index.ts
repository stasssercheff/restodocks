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
            "Технолог ОП. По запросу — ТТК в JSON. Только {\"cards\":[{...}]}; элемент = одна ТТК. " +
            "Компоненты «своего приготовления» (хлеб, соус и т.п.) — отдельные ПФ (isSemiFinished=true) + в основной ТТК ingredientType='semi_finished'. " +
            "Поля: dishName, technologyText, isSemiFinished, yieldGrams, ingredients[] " +
            "{productName,grossGrams,unit,primaryWastePct,netGrams,cookingLossPct,outputGrams,ingredientType,cookingProcessId}. " +
            "cookingProcessId — ОБЯЗАТЕЛЬНО для каждого ингредиента, одно из значений (латиница): " +
            "boiling,frying,baking,stewing,sous_vide,fermentation,grilling,torch_browning,sauteing,blanching,steaming,canning,cutting. " +
            "Подбери по смыслу (овощи на гриле → grilling, запечь → baking, нарезка сырого → cutting). " +
            "cookingLossPct — оценка % ужарки для этой строки (0–60), согласованная с cookingProcessId. " +
            "Технология: 3–5 коротких шагов. ≥3 ингредиента. Без markdown.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.35,
      maxTokens: 1792,
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
