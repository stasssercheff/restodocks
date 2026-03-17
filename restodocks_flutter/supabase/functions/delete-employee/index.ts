// Edge Function: удаление сотрудника с подтверждением PIN.
// Удаляет запись employees, auth.users (для повторного использования email), создаёт уведомление.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const MANAGER_ROLES = ["owner", "executive_chef", "sous_chef", "bar_manager", "floor_manager"];

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

  const supabase = createClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false } });

  try {
    const body = (await req.json()) as { employee_id?: string; pin_code?: string };
    const employeeId = body.employee_id?.trim();
    const pinCode = (body.pin_code ?? "").trim().toUpperCase();

    if (!employeeId || !pinCode) {
      return new Response(
        JSON.stringify({ error: "employee_id and pin_code are required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // 1. Проверяем текущего пользователя (кто удаляет)
    const { data: { user }, error: userError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 2. Загружаем сотрудника-удаляющего и его заведение
    const { data: callerEmp, error: callerErr } = await supabase
      .from("employees")
      .select("id, full_name, establishment_id, roles")
      .eq("id", user.id)
      .limit(1)
      .single();

    if (callerErr || !callerEmp) {
      return new Response(JSON.stringify({ error: "Caller not found as employee" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const hasManagerRole = (callerEmp.roles as string[] | null)?.some((r: string) => MANAGER_ROLES.includes(r)) ?? false;
    if (!hasManagerRole) {
      return new Response(JSON.stringify({ error: "Only owner or department manager can delete employees" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 3. Проверяем PIN заведения
    const { data: est, error: estErr } = await supabase
      .from("establishments")
      .select("id, pin_code")
      .eq("id", callerEmp.establishment_id)
      .limit(1)
      .single();

    if (estErr || !est) {
      return new Response(JSON.stringify({ error: "Establishment not found" }), {
        status: 404,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const expectedPin = (est.pin_code ?? "").trim().toUpperCase();
    if (pinCode !== expectedPin) {
      return new Response(JSON.stringify({ error: "Invalid PIN code" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 4. Загружаем удаляемого сотрудника (тот же establishment_id)
    const { data: targetEmp, error: targetErr } = await supabase
      .from("employees")
      .select("id, full_name, email, establishment_id, roles")
      .eq("id", employeeId)
      .eq("establishment_id", callerEmp.establishment_id)
      .limit(1)
      .single();

    if (targetErr || !targetEmp) {
      return new Response(JSON.stringify({ error: "Employee not found or not in your establishment" }), {
        status: 404,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 5. Нельзя удалить владельца
    const targetRoles = (targetEmp as { roles?: string[] }).roles ?? [];
    if (targetRoles.includes("owner")) {
      return new Response(JSON.stringify({ error: "Cannot delete owner" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 6. Вставляем уведомление об удалении (до удаления employee)
    await supabase.from("employee_deletion_notifications").insert({
      establishment_id: callerEmp.establishment_id,
      deleted_employee_id: targetEmp.id,
      deleted_employee_name: targetEmp.full_name ?? "—",
      deleted_employee_email: targetEmp.email ?? null,
      deleted_by_employee_id: callerEmp.id,
      deleted_by_name: callerEmp.full_name ?? "—",
    });

    // 7. Удаляем связанные данные и сотрудника (FK: employees.id = auth.users.id)
    await supabase.from("password_reset_tokens").delete().eq("employee_id", targetEmp.id);
    // employee_direct_messages: удаляем где сотрудник отправитель или получатель
    await supabase.from("employee_direct_messages").delete().eq("sender_employee_id", targetEmp.id);
    await supabase.from("employee_direct_messages").delete().eq("recipient_employee_id", targetEmp.id);
    // Групповые чаты: удаляем участника и его сообщения (если таблицы есть)
    try {
      await supabase.from("chat_room_messages").delete().eq("sender_employee_id", targetEmp.id);
      await supabase.from("chat_room_members").delete().eq("employee_id", targetEmp.id);
    } catch {
      // Таблицы могут отсутствовать в старых проектах
    }
    // co_owner_invitations.invited_by — без ON DELETE, удаляем вручную
    await supabase.from("co_owner_invitations").delete().eq("invited_by", targetEmp.id);
    const { error: delEmpErr } = await supabase.from("employees").delete().eq("id", targetEmp.id);

    if (delEmpErr) {
      console.error("[delete-employee] Failed to delete employee:", delEmpErr);
      return new Response(JSON.stringify({ error: "Failed to delete employee" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // 8. Удаляем пользователя из auth.users (чтобы email можно было использовать снова)
    const { error: authDelErr } = await supabase.auth.admin.deleteUser(targetEmp.id);
    if (authDelErr) {
      console.warn("[delete-employee] auth.admin.deleteUser failed (employee already deleted):", authDelErr.message);
      // Не возвращаем ошибку — employee уже удалён, уведомление создано
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[delete-employee] Error:", e);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
