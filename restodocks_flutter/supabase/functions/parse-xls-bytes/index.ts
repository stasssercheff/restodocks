// Supabase Edge Function: парсинг XLS/XLSX из бинарных байт через SheetJS
// Поддерживает: BIFF8 (.xls, включая Windows-1251/cp1251), XLSX (.xlsx)
// Принимает JSON: { "bytes": "<base64>" }
// deno-lint-ignore-file no-explicit-any
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
    const body = await req.json() as { bytes?: string };
    if (!body.bytes || body.bytes.length === 0) {
      return new Response(JSON.stringify({ error: "Missing 'bytes' field (base64)", rows: [] }), {
        status: 400,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const data = base64ToUint8Array(body.bytes);

    // Импортируем xlsx внутри обработчика — чтобы краш импорта не ронял весь сервер
    // @ts-ignore
    const XLSX = await import("npm:xlsx@0.18.5");

    // Подключаем кодировочные таблицы для Windows-1251 (.xls из 1C/русских программ)
    try {
      // @ts-ignore
      const cptable = await import("npm:xlsx@0.18.5/dist/cpexcel.full.mjs");
      XLSX.set_cptable(cptable);
    } catch (_) {
      // Если не загрузился — продолжаем без него (xlsx всё равно будет работать)
    }

    let workbook: any;
    try {
      workbook = XLSX.read(data, {
        type: "array",
        codepage: 1251,
        cellText: true,
        cellDates: false,
        raw: false,
      });
    } catch (_e1) {
      try {
        workbook = XLSX.read(data, { type: "array", raw: true });
      } catch (_e2) {
        workbook = XLSX.read(data, { type: "array" });
      }
    }

    if (!workbook?.SheetNames?.length) {
      return new Response(JSON.stringify({ error: "No sheets found", rows: [] }), {
        status: 200,
        headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
      });
    }

    const rows: string[][] = [];

    for (const sheetName of workbook.SheetNames) {
      const sheet = workbook.Sheets[sheetName];
      if (!sheet) continue;

      const jsonRows = XLSX.utils.sheet_to_json(sheet, {
        header: 1,
        defval: "",
        blankrows: false,
        raw: false,
      }) as string[][];

      for (const row of jsonRows) {
        if (!Array.isArray(row)) continue;
        const cells = row.map((c: any) => (c ?? "").toString().trim());
        const line = cells.join("\t");
        // Пропускаем строки без букв (числа-итоги, разделители)
        if (!/[a-zA-Zа-яА-ЯёЁ]/.test(line)) continue;
        // Пропускаем слишком длинные строки (описания, примечания)
        if (line.length > 300) continue;
        if (cells.every((c) => !c)) continue;
        rows.push(cells);
        if (rows.length >= 5000) break;
      }

      if (rows.length >= 5000) break;
    }

    return new Response(JSON.stringify({ rows }), {
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), rows: [] }), {
      status: 500,
      headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
    });
  }
});
