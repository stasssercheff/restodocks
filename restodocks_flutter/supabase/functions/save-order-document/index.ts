// Edge Function: сохранение документа заказа с подстановкой цен на сервере.
// Цены берутся из establishment_products (fallback — products.base_price).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface OrderItemInput {
  productId?: string | null;
  productName: string;
  unit: string;
  quantity: number;
}

interface OrderItemOutput {
  productName: string;
  unit: string;
  quantity: number;
  pricePerUnit: number;
  lineTotal: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  try {
    const body = (await req.json()) as {
      establishmentId?: string;
      createdByEmployeeId?: string;
      header?: Record<string, unknown>;
      items?: OrderItemInput[];
      comment?: string;
      sourceLang?: string;
    };

    const { establishmentId, createdByEmployeeId, header, items, comment, sourceLang } = body;

    if (!establishmentId || !createdByEmployeeId || !header || !Array.isArray(items)) {
      return new Response(
        JSON.stringify({ error: "establishmentId, createdByEmployeeId, header, items required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const productIds = items
      .map((i) => i.productId)
      .filter((id): id is string => !!id && typeof id === "string");

    const priceMap: Record<string, { price: number; currency?: string }> = {};

    if (productIds.length > 0) {
      const { data: epRows } = await supabase
        .from("establishment_products")
        .select("product_id, price, currency")
        .eq("establishment_id", establishmentId)
        .in("product_id", productIds);

      if (Array.isArray(epRows)) {
        for (const row of epRows) {
          const pid = row.product_id as string;
          const price = typeof row.price === "number" ? row.price : parseFloat(String(row.price || 0));
          if (!isNaN(price)) {
            priceMap[pid] = { price, currency: row.currency as string | undefined };
          }
        }
      }

      const missingIds = productIds.filter((id) => !(id in priceMap));
      if (missingIds.length > 0) {
        const { data: prodRows } = await supabase
          .from("products")
          .select("id, base_price, currency")
          .in("id", missingIds);

        if (Array.isArray(prodRows)) {
          for (const row of prodRows) {
            const pid = row.id as string;
            const price =
              typeof row.base_price === "number"
                ? row.base_price
                : parseFloat(String(row.base_price || 0));
            if (!isNaN(price) && !(pid in priceMap)) {
              priceMap[pid] = { price, currency: row.currency as string | undefined };
            }
          }
        }
      }
    }

    let grandTotal = 0;
    const itemsPayload: OrderItemOutput[] = [];

    for (const item of items) {
      let pricePerKg = 0;
      if (item.productId) {
        const p = priceMap[item.productId];
        if (p) pricePerKg = p.price;
      }

      let pricePerUnit = pricePerKg;
      if (item.unit === "g" || item.unit === "г") {
        pricePerUnit = pricePerKg / 1000;
      } else if (item.unit !== "kg" && item.unit !== "кг") {
        pricePerUnit = pricePerKg;
      }

      const qty = typeof item.quantity === "number" ? item.quantity : parseFloat(String(item.quantity || 0));
      const lineTotal = qty * pricePerUnit;
      grandTotal += lineTotal;

      itemsPayload.push({
        productName: item.productName || "",
        unit: item.unit || "kg",
        quantity: qty,
        pricePerUnit,
        lineTotal,
      });
    }

    const payload = {
      header,
      items: itemsPayload,
      grandTotal,
      comment: comment ?? null,
      sourceLang: sourceLang ?? null,
    };

    // Получатели: owner, executive_chef, sous_chef (по аналогии с checklist_submissions)
    const { data: empRows } = await supabase
      .from("employees")
      .select("id, email, roles")
      .eq("establishment_id", establishmentId);

    const recipientRoles = ["owner", "executive_chef", "sous_chef"];
    const recipients = (empRows || []).filter((e: { id: string; email?: string; roles?: string[] }) => {
      const roles = Array.isArray(e.roles) ? e.roles : [];
      return roles.some((r: string) => recipientRoles.includes(r));
    });

    // Если нет шефов/владельцев — берём owner_id заведения
    if (recipients.length === 0) {
      const { data: estab } = await supabase
        .from("establishments")
        .select("owner_id")
        .eq("id", establishmentId)
        .single();
      const ownerId = estab?.owner_id;
      if (ownerId) {
        const { data: owner } = await supabase
          .from("employees")
          .select("id, email")
          .eq("id", ownerId)
          .single();
        if (owner) recipients.push(owner);
      }
    }

    // Финальный fallback: используем создателя документа
    if (recipients.length === 0) {
      const { data: creator } = await supabase
        .from("employees")
        .select("id, email")
        .eq("id", createdByEmployeeId)
        .single();
      if (creator) recipients.push(creator);
    }

    // Крайний fallback: создаём запись с id создателя без email
    if (recipients.length === 0) {
      recipients.push({ id: createdByEmployeeId, email: "" });
    }

    // Уникальные получатели (один сотрудник может иметь несколько ролей)
    const seen = new Set<string>();
    const unique = recipients.filter((r: { id: string }) => {
      if (seen.has(r.id)) return false;
      seen.add(r.id);
      return true;
    });

    const rows = unique.map((r: { id: string; email?: string }) => ({
      establishment_id: establishmentId,
      created_by_employee_id: createdByEmployeeId,
      recipient_chef_id: r.id,
      recipient_email: r.email ?? "",
      payload,
    }));

    const { data: inserted, error } = await supabase
      .from("order_documents")
      .insert(rows)
      .select("id")
      .limit(1);

    if (error) {
      console.error("order_documents insert error:", error);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const firstId = Array.isArray(inserted) && inserted.length > 0 ? (inserted[0] as { id: string })?.id : null;
    return new Response(
      JSON.stringify({ ok: true, id: firstId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("save-order-document error:", e);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
