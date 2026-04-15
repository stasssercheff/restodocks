// После delete_establishment_by_owner: удалить auth.users по одноразовому токену из очереди.
// JWT обязателен и должен совпадать с initiator_user_id (владелец, вызвавший удаление).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

async function isOrphanAuthUser(
  supabase: ReturnType<typeof createClient>,
  uid: string,
): Promise<boolean> {
  const { data: empById } = await supabase
    .from("employees")
    .select("id")
    .eq("id", uid)
    .maybeSingle();
  if (empById != null) return false;

  const { data: empByAuth } = await supabase
    .from("employees")
    .select("id")
    .eq("auth_user_id", uid)
    .maybeSingle();
  if (empByAuth != null) return false;

  const { data: est } = await supabase
    .from("establishments")
    .select("id")
    .eq("owner_id", uid)
    .limit(1)
    .maybeSingle();
  if (est != null) return false;

  return true;
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let body: { purge_token?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const purgeToken = typeof body.purge_token === "string" ? body.purge_token.trim() : "";
  if (!purgeToken) {
    return new Response(JSON.stringify({ error: "purge_token required" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false } });

  try {
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: rows, error: qErr } = await supabase
      .from("establishment_auth_purge_queue")
      .select("auth_user_id, initiator_user_id")
      .eq("disposable_token", purgeToken);

    if (qErr) {
      console.error("[purge-establishment-auth-queue] select:", qErr.message);
      return new Response(JSON.stringify({ error: "Queue lookup failed" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (!rows?.length) {
      return new Response(JSON.stringify({ error: "Unknown or expired purge_token" }), {
        status: 404,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const initiator = rows[0].initiator_user_id as string;
    if (!rows.every((r) => (r.initiator_user_id as string) === initiator)) {
      return new Response(JSON.stringify({ error: "Invalid queue data" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (initiator !== user.id) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const ids = [...new Set(rows.map((r) => r.auth_user_id as string))];
    const deletedUserIds: string[] = [];

    for (const uid of ids) {
      const orphan = await isOrphanAuthUser(supabase, uid);
      if (!orphan) {
        await supabase
          .from("establishment_auth_purge_queue")
          .delete()
          .eq("disposable_token", purgeToken)
          .eq("auth_user_id", uid);
        continue;
      }

      const { error: authDelErr } = await supabase.auth.admin.deleteUser(uid);
      if (authDelErr) {
        console.error("[purge-establishment-auth-queue] deleteUser:", uid, authDelErr.message);
        return new Response(JSON.stringify({ error: "Failed to delete auth user", uid }), {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }

      deletedUserIds.push(uid);
      await supabase
        .from("establishment_auth_purge_queue")
        .delete()
        .eq("disposable_token", purgeToken)
        .eq("auth_user_id", uid);
    }

    return new Response(JSON.stringify({ ok: true, deleted_user_ids: deletedUserIds }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[purge-establishment-auth-queue]", e);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
