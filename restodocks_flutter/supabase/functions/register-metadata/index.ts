// Тонкий entry: OPTIONS без тяжёлых импортов — иначе Supabase отдаёт 503 BOOT_ERROR на preflight.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { corsPreflightHeaders } from "../_shared/cors_light.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsPreflightHeaders(req) });
  }
  const { handleRequest } = await import("./handler.ts");
  return handleRequest(req);
});
