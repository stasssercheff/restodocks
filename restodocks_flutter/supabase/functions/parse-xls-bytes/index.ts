// Supabase Edge Function: парсинг XLS/XLSX из бинарных байт через SheetJS
// Поддерживает: BIFF8 (.xls, включая Windows-1251/cp1251), XLSX (.xlsx)
// Принимает JSON: { "bytes": "<base64>" }
// deno-lint-ignore-file
// @ts-ignore
import * as XLSX from "npm:xlsx@0.18.5";
// @ts-ignore
import * as cptable from "npm:xlsx@0.18.5/dist/cpexcel.full.mjs";

XLSX.set_cptable(cptable);

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

  try {
    const body = await req.json() as { bytes?: string };
    if (!body.bytes || body.bytes.length === 0) {
      return new Response(JSON.stringify({ error: "Missing 'bytes' field (base64)", rows: [] }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const data = base64ToUint8Array(body.bytes);

    // Пробуем все возможные кодировки для старых .xls файлов
    let workbook;
    try {
      workbook = XLSX.read(data, {
        type: "array",
        codepage: 1251,
        cellText: true,
        cellDates: false,
        raw: false,
        dense: false,
      });
    } catch (_e1) {
      try {
        workbook = XLSX.read(data, { type: "array", raw: true });
      } catch (_e2) {
        workbook = XLSX.read(data, { type: "array" });
      }
    }

    if (!workbook.SheetNames || workbook.SheetNames.length === 0) {
      return new Response(JSON.stringify({ error: "No sheets found", rows: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const rows: string[] = [];

    for (const sheetName of workbook.SheetNames) {
      const sheet = workbook.Sheets[sheetName];
      if (!sheet) continue;

      // sheet_to_json даёт массив строк — более надёжно чем CSV для ячеек с переносами и спецсимволами
      const jsonRows = XLSX.utils.sheet_to_json<string[]>(sheet, {
        header: 1,
        defval: "",
        blankrows: false,
        raw: false,
      }) as string[][];

      for (const row of jsonRows) {
        if (!Array.isArray(row)) continue;
        const line = row.map((c) => (c ?? "").toString().trim()).join("\t").trim();
        if (line.length === 0 || line === "\t".repeat(row.length - 1)) continue;
        rows.push(line);
      }

      if (rows.length >= 2000) break;
    }

    return new Response(JSON.stringify({ rows: rows.slice(0, 2000) }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), rows: [] }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
