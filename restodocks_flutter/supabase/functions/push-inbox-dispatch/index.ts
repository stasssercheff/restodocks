// Edge Function: фоновые push (FCM) при INSERT во входящие таблицы.
// Вызывается Database Webhook (Supabase Dashboard) с секретом в заголовке.
// Секреты: FIREBASE_SERVICE_ACCOUNT_JSON, PUSH_WEBHOOK_SECRET, SUPABASE_SERVICE_ROLE_KEY.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initializeApp, getApps, cert } from "npm:firebase-admin@12.7.0/app";
import { getMessaging } from "npm:firebase-admin@12.7.0/messaging";

import { resolveCorsHeaders } from "../_shared/security.ts";

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v?.trim()) throw new Error(`Missing env ${name}`);
  return v.trim();
}

function initFirebase() {
  if (getApps().length > 0) return;
  const raw = requireEnv("FIREBASE_SERVICE_ACCOUNT_JSON");
  const sa = JSON.parse(raw) as Record<string, unknown>;
  initializeApp({ credential: cert(sa as never) });
}

function verifyWebhook(req: Request): boolean {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET")?.trim();
  if (!secret) return false;
  const h1 = req.headers.get("x-webhook-secret")?.trim();
  const h2 = req.headers.get("x-push-webhook-secret")?.trim();
  const auth = req.headers.get("authorization")?.trim();
  if (h1 === secret || h2 === secret) return true;
  if (auth === `Bearer ${secret}`) return true;
  return false;
}

/** Руководители / шефы, кому показываются заказы и чеклисты без явного получателя. */
async function listInboxManagerIds(
  supabase: ReturnType<typeof createClient>,
  establishmentId: string,
): Promise<string[]> {
  const { data, error } = await supabase
    .from("employees")
    .select("id, roles, department")
    .eq("establishment_id", establishmentId)
    .eq("is_active", true);
  if (error) throw error;
  const ids = new Set<string>();
  for (const e of data ?? []) {
    const roles = (e.roles as string[]) ?? [];
    const dept = String(e.department ?? "");
    if (roles.includes("owner")) ids.add(e.id as string);
    if (roles.includes("executive_chef") || roles.includes("sous_chef")) {
      ids.add(e.id as string);
    }
    if (dept === "management") ids.add(e.id as string);
  }
  return [...ids];
}

async function listDeletionNotificationRecipients(
  supabase: ReturnType<typeof createClient>,
  establishmentId: string,
): Promise<string[]> {
  const { data, error } = await supabase
    .from("employees")
    .select("id, roles, department")
    .eq("establishment_id", establishmentId)
    .eq("is_active", true);
  if (error) throw error;
  const ids = new Set<string>();
  for (const e of data ?? []) {
    const roles = (e.roles as string[]) ?? [];
    if (
      roles.includes("owner") ||
      roles.includes("executive_chef") ||
      roles.includes("sous_chef") ||
      roles.includes("bar_manager") ||
      roles.includes("floor_manager")
    ) {
      ids.add(e.id as string);
    }
  }
  return [...ids];
}

async function fetchFcmTokens(
  supabase: ReturnType<typeof createClient>,
  employeeIds: string[],
): Promise<string[]> {
  const uniq = [...new Set(employeeIds.filter((x) => x?.length))];
  if (!uniq.length) return [];
  const { data, error } = await supabase
    .from("employee_push_tokens")
    .select("fcm_token")
    .in("employee_id", uniq);
  if (error) throw error;
  return (data ?? []).map((r) => r.fcm_token as string).filter(Boolean);
}

async function sendMulticast(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  if (!tokens.length) return;
  initFirebase();
  const messaging = getMessaging();
  const chunkSize = 400;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    await messaging.sendEachForMulticast({
      tokens: chunk,
      notification: { title, body },
      data,
      android: { priority: "high" },
      apns: {
        payload: { aps: { sound: "default", badge: 1 } },
      },
    });
  }
}

Deno.serve(async (req: Request) => {
  const cors = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    if (!verifyWebhook(req)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createClient(supabaseUrl, serviceKey);

    const payload = (await req.json()) as Record<string, unknown>;
    const table = String(payload.table ?? payload["table"] ?? "");
    const rec = (payload.record ?? payload["record"]) as Record<string, unknown> | null;
    if (!table || !rec) {
      return new Response(JSON.stringify({ ok: true, skipped: true, reason: "no record" }), {
        status: 200,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    let employeeIds: string[] = [];
    let title = "Restodocks";
    let body = "";
    const data: Record<string, string> = { category: "inbox", table };

    if (table === "employee_direct_messages") {
      const rid = String(rec.recipient_employee_id ?? "");
      if (!rid) {
        return new Response(JSON.stringify({ ok: true, skipped: true }), {
          status: 200,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      employeeIds = [rid];
      const content = String(rec.content ?? "").trim();
      const hasImage = Boolean(rec.image_url);
      const hasAudio = Boolean(rec.audio_url);
      const rawLinks = rec.system_links;
      const hasLinks = Array.isArray(rawLinks) && (rawLinks as unknown[]).length > 0;
      title = "Сообщение";
      body = hasImage
        ? "Новое сообщение (фото)"
        : hasAudio
        ? "Новое сообщение (голос)"
        : hasLinks
        ? "Новое сообщение (ссылки)"
        : content
        ? content.slice(0, 160)
        : "Новое сообщение";
      const sid = String(rec.sender_employee_id ?? "");
      data.route = `/inbox/chat/${sid}`;
      data.type = "messages";
    } else if (table === "inventory_documents") {
      const rid = String(rec.recipient_chef_id ?? "");
      if (rid) employeeIds = [rid];
      const p = rec.payload as Record<string, unknown> | undefined;
      const ptype = String(p?.type ?? "");
      title = ptype === "iiko_inventory" ? "Инвентаризация iiko" : ptype === "writeoff" ? "Списание" : "Инвентаризация";
      body = "Новый документ во входящих";
      data.route = ptype === "iiko_inventory"
        ? `/inbox/iiko/${rec.id}`
        : ptype === "writeoff"
        ? `/inbox/writeoff/${rec.id}`
        : `/inbox/inventory/${rec.id}`;
      data.type = "inventory";
    } else if (table === "order_documents") {
      const est = String(rec.establishment_id ?? "");
      employeeIds = await listInboxManagerIds(supabase, est);
      const pl = rec.payload as Record<string, unknown> | undefined;
      const header = pl?.header as Record<string, unknown> | undefined;
      const supplier = String(header?.supplierName ?? "Заказ");
      title = "Заказ";
      body = supplier;
      data.route = `/inbox/order/${rec.id}`;
      data.type = "orders";
    } else if (table === "checklist_submissions") {
      const chef = rec.recipient_chef_id as string | null | undefined;
      const est = String(rec.establishment_id ?? "");
      if (chef) {
        employeeIds = [String(chef)];
      } else {
        employeeIds = await listInboxManagerIds(supabase, est);
      }
      const name = String(rec.checklist_name ?? "Чеклист");
      title = "Чеклист";
      body = name;
      data.route = `/inbox/checklist/${rec.id}`;
      data.type = "checklists";
    } else if (table === "employee_deletion_notifications") {
      const est = String(rec.establishment_id ?? "");
      employeeIds = await listDeletionNotificationRecipients(supabase, est);
      const n = String(rec.deleted_employee_name ?? "");
      title = "Персонал";
      body = `Удалён: ${n}`;
      data.route = "/inbox?tab=notifications";
      data.type = "notifications";
    } else {
      return new Response(JSON.stringify({ ok: true, skipped: true, table }), {
        status: 200,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const tokens = await fetchFcmTokens(supabase, employeeIds);
    await sendMulticast(tokens, title, body, data);

    return new Response(JSON.stringify({ ok: true, sent: tokens.length, recipients: employeeIds.length }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[push-inbox-dispatch]", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
