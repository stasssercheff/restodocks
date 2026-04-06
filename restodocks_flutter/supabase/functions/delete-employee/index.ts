// Edge Function: удаление сотрудника с подтверждением PIN.
// Удаляет запись employees, auth.users (для повторного использования email), создаёт уведомление.
// Самоудаление: caller === target, PIN, письмо руководителю подразделения (или владельцу).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const MANAGER_ROLES = ["owner", "executive_chef", "sous_chef", "bar_manager", "floor_manager", "general_manager"];

type EmpRow = {
  id: string;
  full_name: string | null;
  email: string | null;
  establishment_id: string;
  roles: string[] | null;
  department: string | null;
};

function rolesArray(r: unknown): string[] {
  return Array.isArray(r) ? (r as string[]) : [];
}

/** Руководитель подразделения для уведомления и FK deleted_by (не удаляемый сотрудник). */
function pickDepartmentManager(
  staff: EmpRow[],
  department: string,
  excludeId: string,
): EmpRow | null {
  const rolePriority: Record<string, string[]> = {
    kitchen: ["executive_chef", "sous_chef"],
    bar: ["bar_manager"],
    dining_room: ["floor_manager"],
    management: ["general_manager", "owner"],
  };
  const order = rolePriority[department] ?? ["owner"];
  for (const role of order) {
    const m = staff.find((e) => e.id !== excludeId && rolesArray(e.roles).includes(role));
    if (m?.email) return m;
  }
  const owner = staff.find((e) => e.id !== excludeId && rolesArray(e.roles).includes("owner"));
  return owner ?? null;
}

async function sendManagerEmail(
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!resendKey) {
    console.warn("[delete-employee] RESEND_API_KEY not set, skip email");
    return;
  }
  const from = Deno.env.get("RESEND_FROM_EMAIL")?.trim() || "Restodocks <noreply@restodocks.com>";
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error("[delete-employee] Resend failed:", res.status, err);
  }
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

  const supabase = createClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false } });

  try {
    const body = (await req.json()) as { employee_id?: string; pin_code?: string };
    const employeeId = body.employee_id?.trim();
    const pinCode = (body.pin_code ?? "").trim().toUpperCase();

    if (!employeeId || !pinCode) {
      return new Response(
        JSON.stringify({ error: "employee_id and pin_code are required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const { data: { user }, error: userError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
        status: 401,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: callerEmp, error: callerErr } = await supabase
      .from("employees")
      .select("id, full_name, establishment_id, roles, department, email")
      .eq("id", user.id)
      .limit(1)
      .single();

    if (callerErr || !callerEmp) {
      return new Response(JSON.stringify({ error: "Caller not found as employee" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: est, error: estErr } = await supabase
      .from("establishments")
      .select("id, name, pin_code, owner_id")
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

    const { data: targetEmp, error: targetErr } = await supabase
      .from("employees")
      .select("id, full_name, email, establishment_id, roles, department")
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

    const targetRoles = rolesArray(targetEmp.roles);
    if (targetRoles.includes("owner")) {
      return new Response(JSON.stringify({ error: "Cannot delete owner" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const selfDelete = callerEmp.id === targetEmp.id;

    if (!selfDelete) {
      const hasManagerRole = rolesArray(callerEmp.roles).some((r: string) => MANAGER_ROLES.includes(r));
      if (!hasManagerRole) {
        return new Response(JSON.stringify({ error: "Only owner or department manager can delete employees" }), {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
    }

    const { data: staffRaw, error: staffErr } = await supabase
      .from("employees")
      .select("id, full_name, email, establishment_id, roles, department")
      .eq("establishment_id", callerEmp.establishment_id)
      .eq("is_active", true);

    if (staffErr) {
      console.error("[delete-employee] staff load:", staffErr);
    }
    const staff = (staffRaw ?? []) as EmpRow[];

    let deletedById: string = callerEmp.id as string;
    let deletedByName: string = (callerEmp.full_name as string) ?? "—";
    let isSelfDeletion = false;
    let emailTo: string | null = null;

    if (selfDelete) {
      isSelfDeletion = true;
      const dept = String(targetEmp.department ?? "management");
      const mgr = pickDepartmentManager(staff, dept, targetEmp.id);
      if (mgr) {
        deletedById = mgr.id;
        deletedByName = mgr.full_name ?? "—";
        emailTo = mgr.email?.trim() || null;
      } else if (est.owner_id) {
        const { data: ownerEmp } = await supabase
          .from("employees")
          .select("id, full_name, email")
          .eq("id", est.owner_id)
          .limit(1)
          .maybeSingle();
        if (ownerEmp && ownerEmp.id !== targetEmp.id) {
          deletedById = ownerEmp.id as string;
          deletedByName = (ownerEmp.full_name as string) ?? "—";
          emailTo = (ownerEmp.email as string)?.trim() || null;
        }
      }
    }

    const insertRow: Record<string, unknown> = {
      establishment_id: callerEmp.establishment_id,
      deleted_employee_id: targetEmp.id,
      deleted_employee_name: targetEmp.full_name ?? "—",
      deleted_employee_email: targetEmp.email ?? null,
      deleted_by_employee_id: deletedById,
      deleted_by_name: deletedByName,
    };
    if (isSelfDeletion) {
      insertRow.is_self_deletion = true;
    }

    await supabase.from("employee_deletion_notifications").insert(insertRow);

    if (selfDelete && emailTo) {
      const name = targetEmp.full_name ?? "—";
      const estName = (est as { name?: string }).name ?? "";
      const subj = `Restodocks: сотрудник удалил профиль — ${name}`;
      await sendManagerEmail(
        emailTo,
        subj,
        `<p>Сотрудник <strong>${name}</strong> (${targetEmp.email ?? "—"}) удалил свой профиль в приложении Restodocks.</p>
<p>Заведение: ${estName}</p>`,
      );
    }

    await supabase.from("password_reset_tokens").delete().eq("employee_id", targetEmp.id);
    await supabase.from("employee_direct_messages").delete().eq("sender_employee_id", targetEmp.id);
    await supabase.from("employee_direct_messages").delete().eq("recipient_employee_id", targetEmp.id);
    try {
      await supabase.from("chat_room_messages").delete().eq("sender_employee_id", targetEmp.id);
      await supabase.from("chat_room_members").delete().eq("employee_id", targetEmp.id);
    } catch {
      // tables may be missing
    }
    await supabase.from("co_owner_invitations").delete().eq("invited_by", targetEmp.id);
    const { error: delEmpErr } = await supabase.from("employees").delete().eq("id", targetEmp.id);

    if (delEmpErr) {
      console.error("[delete-employee] Failed to delete employee:", delEmpErr);
      return new Response(JSON.stringify({ error: "Failed to delete employee" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { error: authDelErr } = await supabase.auth.admin.deleteUser(targetEmp.id);
    if (authDelErr) {
      console.warn("[delete-employee] auth.admin.deleteUser failed:", authDelErr.message);
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
