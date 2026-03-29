import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { corsPreflightHeaders } from "../_shared/cors_light.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsPreflightHeaders(req) });
  }
  try {
    const { handleRequest } = await import("./handler.ts");
    return await handleRequest(req);
  } catch (e) {
    const h = corsPreflightHeaders(req);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...h, "Content-Type": "application/json" },
    });
  }
});
