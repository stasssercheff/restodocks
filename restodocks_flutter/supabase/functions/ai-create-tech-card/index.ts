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
    const body = (await req.json()) as {
      prompt?: string;
      establishmentId?: string;
      department?: string;
      locale?: string;
      checkOnly?: boolean;
    };
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    const establishmentId = typeof body.establishmentId === "string" ? body.establishmentId.trim() : "";
    const checkOnly = body.checkOnly === true;
    const department =
      typeof body.department === "string" && body.department.trim().toLowerCase() === "bar"
        ? "bar"
        : "kitchen";
    const rawLocale = typeof body.locale === "string" ? body.locale.trim().toLowerCase() : "";
    const localeTag = rawLocale.length >= 2 ? rawLocale.slice(0, 2) : "en";
    if (!checkOnly && !prompt) {
      return new Response(JSON.stringify({ error: "prompt required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (establishmentId) {
      const { checkAndIncrementAiTtkUsage, getAiTtkUsageStatus } = await import("../_shared/ai_ttk_limit.ts");
      const status = checkOnly
        ? await getAiTtkUsageStatus(establishmentId, department)
        : await checkAndIncrementAiTtkUsage(establishmentId, department);
      const { allowed, reason, count, limit } = status;
      if (!allowed) {
        return new Response(
          JSON.stringify({
            error: reason ?? "ai_limit_exceeded",
            reason: reason ?? "ai_limit_exceeded",
            limit,
            used: count,
            remaining: Math.max(0, limit - count),
            allowed: false,
          }),
          { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
      if (checkOnly) {
        return new Response(
          JSON.stringify({
            allowed: true,
            limit,
            used: count,
            remaining: Math.max(0, limit - count),
          }),
          { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
    }

    const langRule =
      localeTag === "ru"
        ? "All natural-language fields (dishName, each productName, technologyText) MUST be in Russian. Do not mix in English except internationally common product names if unavoidable."
        : localeTag === "en"
        ? "All natural-language fields (dishName, each productName, technologyText) MUST be in English. Do not mix in Russian or other languages."
        : `All natural-language fields (dishName, each productName, technologyText) MUST be written in the primary language for UI locale "${localeTag}". Avoid mixing languages.`;
    const departmentRule =
      department === "bar"
        ? "Department is BAR. Choose category and cookingProcessId strictly by drink type and ingredient role. Category rules: cappuccino/latte/espresso/raf/tea/cocoa -> hot_drinks (never alcoholic_cocktails); cocktail with spirits -> alcoholic_cocktails; non-alcoholic mixed drinks/lemonades -> non_alcoholic_drinks; neat spirits/wine/beer -> drinks_pure. Process rules per ingredient: espresso coffee -> espresso_extraction; milk for cappuccino/latte -> steaming; cocktail assembly in shaker -> shaking; stirred cocktail in mixing glass -> stirring; build in serving glass -> building; blender drinks -> blending; boiling water/syrup -> boiling; simple slicing/garnish -> cutting."
        : "Department is KITCHEN. Avoid bar-only drink classification unless explicitly a beverage card.";

    const content = await chatText({
      messages: [
        {
          role: "system",
          content:
            "You are a head technologist. Return ONLY JSON as {\"cards\":[{...}]}; each array element is one tech card. " +
            "In-house prepped components (bread, sauces, etc.) are separate semi-finished items (isSemiFinished=true) and referenced in the main card with ingredientType='semi_finished'. " +
            "Fields: dishName, technologyText, isSemiFinished, yieldGrams, ingredients[] " +
            "{productName,grossGrams,unit,primaryWastePct,netGrams,cookingLossPct,outputGrams,ingredientType,cookingProcessId}. " +
            "cookingProcessId is REQUIRED for every ingredient, one of these Latin ids: " +
            "boiling,frying,baking,stewing,sous_vide,fermentation,grilling,torch_browning,sauteing,blanching,steaming,canning,cutting,shaking,stirring,building,blending,espresso_extraction. " +
            "Pick by meaning (grilled vegetables → grilling, bake → baking, raw cut → cutting). " +
            "cookingLossPct — estimated shrinkage % for that line (0–60), consistent with cookingProcessId. " +
            "technologyText: 3–5 short steps. At least 3 ingredients. No markdown. " +
            langRule +
            " " +
            departmentRule,
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
