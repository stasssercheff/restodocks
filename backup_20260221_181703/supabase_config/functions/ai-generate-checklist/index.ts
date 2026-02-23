// Supabase Edge Function: генерация чеклиста по запросу (GigaChat или OpenAI)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText, getProvider } from "../_shared/ai_provider.ts";

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

  const hasProvider = Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("GEMINI_API_KEY")?.trim() || Deno.env.get("OPENAI_API_KEY");
  if (!hasProvider) {
    return new Response(JSON.stringify({ error: "GIGACHAT_AUTH_KEY, GEMINI_API_KEY or OPENAI_API_KEY required" }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    console.log("[ai-generate-checklist] Request received");
    const body = (await req.json()) as { prompt?: string; context?: Record<string, unknown> };
    const { prompt, context } = body;
    if (!prompt || typeof prompt !== "string") {
      return new Response(JSON.stringify({ error: "prompt required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const SYSTEM_PROMPT = `You are a restaurant checklist generator. You output widget configurations, NOT plain text lists. The result is a JSON object that defines interactive rows bound to the establishment's database.

## Data sources (within establishment)

- **Items** (nomenclature): products for selection — use source "Items". Reference by UUID if provided.
- **Recipes** (ТТК/ПФ): dishes and semi-finished products — use source "Recipes". Reference by UUID if provided.

## Widget types (row types)

| type     | description                    | fields                            |
|----------|--------------------------------|-----------------------------------|
| Selection| Dropdown search by Items/Recipes| "source": "Items" or "Recipes"    |
| Number   | Numeric input (weight, qty, °C) | "label": string (e.g. "Количество")|
| Status   | Checkbox (boolean)             | "label": string (task name)        |
| Scale    | Rating 1–5                     | "label": string (e.g. "Вкус")      |

## Output logic

Return a JSON object:
\`\`\`json
{
  "name": "Checklist title",
  "items": [ array of widget objects ]
}
\`\`\`

Examples:

1. **Write-off / списание / закупка** (20–50 empty rows by default, 20 if not specified):
   [{"type":"Selection","source":"Items"}, {"type":"Number","label":"Количество"}, {"type":"Selection","source":"Items"}, {"type":"Number","label":"Количество"}, ...]

2. **Бракераж** (quality control):
   [{"type":"Selection","source":"Recipes"}, {"type":"Scale","label":"Вкус"}, {"type":"Status","label":"Вид"}, ...]

3. **Чек-листы** (cleaning, prep, etc.):
   [{"type":"Status","label":"Мытьё пола"}, {"type":"Status","label":"Протирка столов"}, ...]

## Rules

- Volume: For "списание" / "закупка" / "write-off" — generate 20–50 interactive row pairs (Selection+Number), default 20.
- Each object in "items" = one row.
- For Selection: always include "source": "Items" or "Recipes".
- For Number, Status, Scale: include "label" with a short name.
- Output ONLY valid JSON, no markdown, no extra text.`;

    let contextBlock = "";
    if (context && typeof context === "object") {
      const parts: string[] = ["## Establishment context (use only these when relevant):"];
      const items = context.items as Array<{ id?: string; name: string }> | undefined;
      if (Array.isArray(items) && items.length > 0) {
        const preview = items.slice(0, 100).map((x) => (x.id ? `${x.name} (${x.id})` : x.name)).join(", ");
        parts.push(`Items (nomenclature): ${preview}${items.length > 100 ? "..." : ""}`);
      }
      const recipes = context.recipes as Array<{ id?: string; name: string }> | undefined;
      if (Array.isArray(recipes) && recipes.length > 0) {
        const preview = recipes.slice(0, 60).map((x) => (x.id ? `${x.name} (${x.id})` : x.name)).join(", ");
        parts.push(`Recipes (ТТК/ПФ): ${preview}${recipes.length > 60 ? "..." : ""}`);
      }
      const employees = context.employees as string[] | undefined;
      if (Array.isArray(employees) && employees.length > 0) {
        parts.push(`Employees: ${employees.join(", ")}`);
      }
      const schedule = context.scheduleSummary as string | undefined;
      if (typeof schedule === "string" && schedule) {
        parts.push(`Schedule: ${schedule}`);
      }
      if (parts.length > 1) {
        contextBlock = "\n\n" + parts.join("\n");
      }
    }

    const systemPrompt = SYSTEM_PROMPT + contextBlock;

    // Gemini быстрее из ap-northeast-1; GigaChat может быть недоступен
    if (!Deno.env.get("AI_PROVIDER") && Deno.env.get("GEMINI_API_KEY")?.trim()) {
      Deno.env.set("AI_PROVIDER", "gemini");
    }
    console.log("[ai-generate-checklist] Calling AI, provider:", getProvider());
    const content = await chatText({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: prompt },
      ],
      temperature: 0.5,
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ error: "Empty AI response" }), {
        status: 502,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();

    const parsed = JSON.parse(jsonStr) as { name?: string; items?: unknown[] };
    const name = typeof parsed.name === "string" ? parsed.name : "Checklist";
    const rawItems = Array.isArray(parsed.items) ? parsed.items : [];

    const itemTitles: string[] = [];
    const itemWidgets: Record<string, unknown>[] = [];

    // New format: items are widget config objects
    const first = rawItems[0];
    if (first && typeof first === "object" && !Array.isArray(first) && ("type" in (first as object))) {
      for (const row of rawItems) {
        if (row && typeof row === "object" && !Array.isArray(row)) {
          const obj = row as Record<string, unknown>;
          itemWidgets.push(obj);
          const t = obj.type as string | undefined;
          const label = obj.label as string | undefined;
          const source = obj.source as string | undefined;
          if (label) itemTitles.push(label);
          else if (t === "Selection" && source) itemTitles.push(`Выбор: ${source}`);
          else if (t) itemTitles.push(t);
          else itemTitles.push("—");
        }
      }
    } else {
      // Legacy format: items are strings
      for (const row of rawItems) {
        if (typeof row === "string") itemTitles.push(row);
      }
    }

    if (itemTitles.length === 0 && content?.trim()) {
      // AI returned something but we couldn't parse items — try fallback 1
      try {
        const fallbackContent = await chatText({
          messages: [
            { role: "system", content: "Return JSON only: {\"name\": string, \"items\": [\"task1\",\"task2\",...]}. Short task names. No markdown." },
            { role: "user", content: `Checklist: ${prompt}` },
          ],
          temperature: 0.5,
        });
        if (fallbackContent?.trim()) {
          let fs = fallbackContent.trim();
          const cb = fs.match(/```(?:json)?\s*([\s\S]*?)```/);
          if (cb) fs = cb[1].trim();
          const p = JSON.parse(fs) as { name?: string; items?: unknown[] };
          const n = typeof p.name === "string" ? p.name : "Checklist";
          const its = Array.isArray(p.items) ? p.items.filter((x): x is string => typeof x === "string") : [];
          if (its.length > 0) {
            return new Response(JSON.stringify({ name: n, itemTitles: its }), {
              headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
            });
          }
        }
      } catch (_) {}
    }

    // Если после fallback всё ещё пусто — второй fallback с ещё более простым промптом
    if (itemTitles.length === 0) {
      try {
        const fallbackContent = await chatText({
          messages: [
            { role: "system", content: "You return JSON only. {\"name\": string, \"items\": string[]}. No markdown." },
            { role: "user", content: `${prompt}\n\nGenerate a checklist. Return JSON: {"name":"Checklist title","items":["item1","item2","item3",...]}. Items = short task names. Output ONLY valid JSON.` },
          ],
          temperature: 0.5,
        });
        if (fallbackContent?.trim()) {
          let fs = fallbackContent.trim();
          const cb = fs.match(/```(?:json)?\s*([\s\S]*?)```/);
          if (cb) fs = cb[1].trim();
          const p = JSON.parse(fs) as { name?: string; items?: unknown[] };
          const n = typeof p.name === "string" ? p.name : "Checklist";
          const its = Array.isArray(p.items) ? p.items.filter((x): x is string => typeof x === "string") : [];
          if (its.length > 0) {
            return new Response(JSON.stringify({ name: n, itemTitles: its }), {
              headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
            });
          }
        }
      } catch (_) {}
    }

    // Если всё ещё пусто — возвращаем ошибку вместо пустого результата
    if (itemTitles.length === 0) {
      return new Response(JSON.stringify({ error: "AI returned no valid checklist items" }), {
        status: 502,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        name,
        itemTitles,
        itemWidgets: itemWidgets.length > 0 ? itemWidgets : undefined,
      }),
      {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
    } catch (e) {
      // Fallback: retry with simpler prompt if structured parse failed
      try {
        const fallbackPrompt = `Generate a checklist. Return JSON: {"name":"Checklist title","items":["item1","item2",...]}. Items = short task names. Output ONLY valid JSON.`;
        const fallbackContent = await chatText({
          messages: [
            { role: "system", content: "You return JSON only. {\"name\": string, \"items\": string[]}. No markdown." },
            { role: "user", content: `${prompt}\n\n${fallbackPrompt}` },
          ],
          temperature: 0.5,
        });
        if (fallbackContent?.trim()) {
          let fs = fallbackContent.trim();
          const cb = fs.match(/```(?:json)?\s*([\s\S]*?)```/);
          if (cb) fs = cb[1].trim();
          const p = JSON.parse(fs) as { name?: string; items?: unknown[] };
          const n = typeof p.name === "string" ? p.name : "Checklist";
          const its = Array.isArray(p.items) ? p.items.filter((x): x is string => typeof x === "string") : [];
          if (its.length > 0) {
            return new Response(JSON.stringify({ name: n, itemTitles: its }), {
              headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
            });
          }
        }
      } catch (_) {}
      return new Response(JSON.stringify({ error: String(e) }), {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
  });
