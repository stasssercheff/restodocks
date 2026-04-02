// Supabase Edge Function: извлечение текста из Word (.doc, .docx) через word-extractor
// Поддерживает: Word 97-2003 (.doc), OOXML (.docx)
// Принимает JSON: { "bytes": "<base64>" }
// Возвращает: { "text": string, "rows": string[][] } — текст и разбивка на строки/ячейки для парсера ТТК
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

function base64ToUint8Array(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/** Подсчёт кириллицы в тексте */
function cyrillicCount(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if ((c >= 0x0400 && c <= 0x04ff) || (c >= 0x0500 && c <= 0x052f)) n++;
  }
  return n;
}

/** Исправление mojibake: текст был в Windows-1251, но считан как Latin-1 */
async function tryFixWin1251Mojibake(text: string): Promise<string> {
  try {
    const { Buffer } = await import("node:buffer");
    const iconv = await import("npm:iconv-lite@0.6.3");
    const buf = Buffer.from(text, "latin1");
    const fixed = iconv.decode(buf, "win1251");
    if (cyrillicCount(fixed) > cyrillicCount(text)) return fixed;
  } catch (_) {}
  return text;
}

/** Текст → rows (массив строк с ячейками) для парсера ТТК */
function textToRows(text: string): string[][] {
  const lines = text.split(/\r\n|\r|\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length < 2) return [];

  const tabCount = lines.filter((l) => l.split(/\t/).length >= 2).length;
  const useTab = tabCount >= Math.min(2, lines.length);

  const rows: string[][] = [];
  for (const line of lines) {
    let cells: string[];
    if (useTab) {
      cells = line.split(/\t/).map((c) => c.trim()); // сохраняем пустые ячейки для выравнивания колонок
    } else {
      cells = line.split(/\s{2,}/).map((c) => c.trim()).filter(Boolean);
    }
    if (cells.length === 0 && line.length > 0) cells = [line];
    if (cells.some((c) => c.length > 0)) rows.push(cells);
  }
  return rows;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const cors = resolveCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  }

  const uid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !uid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "parse-doc-bytes", { windowMs: 60_000, maxRequests: 40 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as { bytes?: string };
    if (!body.bytes || body.bytes.length === 0) {
      return new Response(JSON.stringify({ error: "Missing 'bytes' field (base64)", text: "", rows: [] }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const data = base64ToUint8Array(body.bytes);
    const { Buffer } = await import("node:buffer");
    const buf = Buffer.from(data);

    const WordExtractor = (await import("npm:word-extractor@1.0.4")).default;
    const extractor = new WordExtractor();
    const doc = await extractor.extract(buf);
    let bodyText = doc.getBody() ?? "";
    bodyText = await tryFixWin1251Mojibake(bodyText);
    const text = bodyText.trim();

    if (!text) {
      return new Response(JSON.stringify({ text: "", rows: [], error: "empty" }), {
        status: 200,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const rows = textToRows(text);

    return new Response(JSON.stringify({ text, rows }), {
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e);
    return new Response(
      JSON.stringify({ error: errMsg, text: "", rows: [] }),
      { status: 200, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } },
    );
  }
});
