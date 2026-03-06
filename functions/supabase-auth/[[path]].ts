/**
 * Cloudflare Pages Function: прокси всех Supabase API для restodocks.com.
 * Обходит ограничение Supabase по origin — запросы идут через тот же домен.
 */
const SUPABASE_URL = 'https://osglfptwbuqqmqunttha.supabase.co';

export async function onRequest(context: {
  request: Request;
  params: { path?: string[] };
  env: Record<string, unknown>;
}) {
  const { request, params } = context;
  const path = Array.isArray(params.path) ? params.path.join('/') : '';
  if (!path) return new Response('Not found', { status: 404 });

  const url = `${SUPABASE_URL}/${path}`;
  const origin = request.headers.get('Origin') || '*';

  // CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        'Access-Control-Max-Age': '86400',
      },
    });
  }

  const headers = new Headers();
  const forwardHeaders = [
    'authorization', 'apikey', 'x-client-info', 'content-type',
    'accept', 'accept-encoding', 'prefer', 'range',
  ];
  for (const h of forwardHeaders) {
    const v = request.headers.get(h);
    if (v) headers.set(h, v);
  }

  try {
    const body = request.method !== 'GET' && request.method !== 'HEAD'
      ? await request.arrayBuffer()
      : undefined;

    const res = await fetch(url, {
      method: request.method,
      headers,
      body,
    });

    const resHeaders = new Headers(res.headers);
    resHeaders.set('Access-Control-Allow-Origin', origin);
    resHeaders.set('Access-Control-Expose-Headers', '*');

    return new Response(res.body, {
      status: res.status,
      statusText: res.statusText,
      headers: resHeaders,
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': origin,
      },
    });
  }
}
