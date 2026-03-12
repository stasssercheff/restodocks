// Supabase Edge Function: извлечение текста из Word (.doc, .docx) через word-extractor
// Поддерживает: Word 97-2003 (.doc), OOXML (.docx)
// Принимает JSON: { "bytes": "<base64>" }
// Возвращает: { "text": string, "rows": string[][] } — текст и разбивка на строки/ячейки для парсера ТТК
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
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
    const bodyText = doc.getBody() ?? "";
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
