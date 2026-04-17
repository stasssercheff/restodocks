require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in environment.');
  process.exit(1);
}

const MODE = (process.env.STRESS_MODE || 'run').trim().toLowerCase();
const CONFIRM = (process.env.STRESS_CONFIRM || '').trim();
const FORCE = CONFIRM === 'YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST';

if (!FORCE) {
  console.error(
    'Refusing to run. Set STRESS_CONFIRM=YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST'
  );
  process.exit(1);
}

const cfg = {
  employees: Number(process.env.STRESS_EMPLOYEES || 100),
  techCards: Number(process.env.STRESS_TECH_CARDS || 1000),
  inventories: Number(process.env.STRESS_INVENTORIES || 10),
  concurrency: Number(process.env.STRESS_CONCURRENCY || 8),
  languageSwitchOps: Number(process.env.STRESS_LANGUAGE_SWITCH_OPS || 300),
  languages: (process.env.STRESS_LANGS || 'ru,en,es,it,tr,vi,de,fr')
    .split(',')
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean),
  cleanupRunId: (process.env.STRESS_CLEANUP_RUN_ID || '').trim(),
};

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const t0 = Date.now();
const metrics = {};
const runId = `stress_${new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14)}`;

function nowMs() {
  return Date.now();
}

function markStart(name) {
  metrics[name] = { start: nowMs() };
}

function markEnd(name, extra = {}) {
  if (!metrics[name]) metrics[name] = {};
  metrics[name].end = nowMs();
  metrics[name].durationMs = metrics[name].end - (metrics[name].start || metrics[name].end);
  Object.assign(metrics[name], extra);
}

async function runWithLimit(items, limit, worker) {
  const queue = [...items];
  const out = [];
  const workers = Array.from({ length: Math.max(1, limit) }).map(async () => {
    while (queue.length) {
      const item = queue.shift();
      if (item === undefined) break;
      out.push(await worker(item));
    }
  });
  await Promise.all(workers);
  return out;
}

async function listColumns(table) {
  const { data, error } = await supabase.from(table).select('*').limit(1);
  if (error) return [];
  if (!data || data.length === 0) return [];
  return Object.keys(data[0]);
}

function projectToColumns(payload, allowedColumns) {
  if (!allowedColumns || allowedColumns.length === 0) return payload;
  const projected = {};
  for (const [k, v] of Object.entries(payload)) {
    if (allowedColumns.includes(k)) projected[k] = v;
  }
  return projected;
}

async function createEstablishment(currentRunId) {
  const pin = String(Math.floor(100000 + Math.random() * 900000));
  const payload = {
    name: `[STRESS ${currentRunId}] Load Test Establishment`,
    pin_code: `${pin}${String(Math.floor(Math.random() * 10))}`.slice(0, 6),
    address: 'Load test synthetic address',
    phone: '+0000000000',
    email: `stress-${currentRunId}@example.invalid`,
  };

  const { data, error } = await supabase
    .from('establishments')
    .insert(payload)
    .select('id,name,pin_code')
    .single();

  if (error) {
    throw new Error(`Failed to create establishment: ${error.message}`);
  }
  return data;
}

async function createAuthAndEmployee(establishmentId, idx, employeeColumns, currentRunId) {
  const email = `stress+${currentRunId}+emp${String(idx).padStart(3, '0')}@example.invalid`;
  const password = `StressPass!${String(idx).padStart(4, '0')}x`;
  const authRes = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { stress_test: true, run_id: currentRunId, index: idx },
  });

  if (authRes.error) {
    return { ok: false, phase: 'auth', idx, error: authRes.error.message, email };
  }

  const authUserId = authRes.data.user?.id;
  if (!authUserId) {
    return { ok: false, phase: 'auth', idx, error: 'Auth user id is missing', email };
  }

  const roles = idx === 0 ? ['owner'] : ['staff'];
  const preferredLanguage = cfg.languages[idx % cfg.languages.length] || 'en';
  let employeePayload = {
    id: authUserId,
    auth_user_id: authUserId,
    full_name: `Stress Employee ${idx}`,
    surname: `Synthetic ${idx}`,
    email,
    password_hash: null,
    department: idx % 2 === 0 ? 'kitchen' : 'service',
    section: idx % 3 === 0 ? 'cold' : 'hot',
    roles,
    establishment_id: establishmentId,
    personal_pin: String(100000 + (idx % 900000)).padStart(6, '0'),
    preferred_language: preferredLanguage,
    is_active: true,
    data_access_enabled: true,
  };

  employeePayload = projectToColumns(employeePayload, employeeColumns);

  const { error: empError } = await supabase.from('employees').insert(employeePayload);
  if (empError) {
    return { ok: false, phase: 'employees', idx, error: empError.message, email };
  }

  return { ok: true, idx, authUserId, email };
}

async function insertTechCards(establishmentId, createdBy, count, currentRunId, techCardColumns) {
  const batchSize = 100;
  let inserted = 0;

  for (let i = 0; i < count; i += batchSize) {
    const chunk = [];
    const upper = Math.min(i + batchSize, count);
    for (let x = i; x < upper; x++) {
      const lang = cfg.languages[x % cfg.languages.length] || 'en';
      const localized = {
        [lang]: `[STRESS ${currentRunId}] Dish ${x + 1} (${lang})`,
      };
      const payload = {
        dish_name: `[STRESS ${currentRunId}] Dish ${x + 1}`,
        dish_name_localized: localized,
        category: 'load_test',
        portion_weight: 100 + (x % 50),
        yield: 80 + (x % 20),
        technology: 'Synthetic non-AI content for DB load test.',
        comment: `run_id=${currentRunId}`,
        card_type: 'dish',
        base_portions: 1,
        establishment_id: establishmentId,
        created_by: createdBy,
      };
      chunk.push(projectToColumns(payload, techCardColumns));
    }
    const { error } = await supabase.from('tech_cards').insert(chunk);
    if (error) throw new Error(`Failed tech_cards batch insert: ${error.message}`);
    inserted += chunk.length;
  }
  return inserted;
}

async function insertInventoryDocs(establishmentId, createdBy, count, currentRunId) {
  const rows = Array.from({ length: count }).map((_, i) => ({
    establishment_id: establishmentId,
    created_by_employee_id: createdBy,
    recipient_chef_id: createdBy,
    recipient_email: `inventory+${currentRunId}+${i}@example.invalid`,
    payload: {
      run_id: currentRunId,
      synthetic: true,
      inventory_index: i + 1,
      items: Array.from({ length: 30 }).map((__, j) => ({
        sku: `LOAD-${i + 1}-${j + 1}`,
        qty: (j % 7) + 1,
        unit: 'pcs',
      })),
    },
  }));

  const { error } = await supabase.from('inventory_documents').insert(rows);
  if (error) throw new Error(`Failed inventory_documents insert: ${error.message}`);
  return rows.length;
}

async function languageSwitchChurn(establishmentId, ops, parallel, currentRunId, employeeColumns) {
  if (!employeeColumns.includes('preferred_language')) {
    return { skipped: true, reason: 'preferred_language column missing' };
  }

  const { data: employees, error } = await supabase
    .from('employees')
    .select('id,preferred_language')
    .eq('establishment_id', establishmentId)
    .limit(1000);
  if (error) throw new Error(`Failed to load employees for language churn: ${error.message}`);
  const ids = (employees || []).map((x) => x.id).filter(Boolean);
  if (ids.length === 0) return { skipped: true, reason: 'no employees found' };

  const tasks = Array.from({ length: ops }).map((_, i) => i);
  const result = await runWithLimit(tasks, parallel, async (i) => {
    const employeeId = ids[i % ids.length];
    const nextLang = cfg.languages[(i + 1) % cfg.languages.length] || 'en';
    const started = nowMs();
    const { error: updError } = await supabase
      .from('employees')
      .update({ preferred_language: nextLang })
      .eq('id', employeeId)
      .eq('establishment_id', establishmentId);
    if (updError) return { ok: false, ms: nowMs() - started, error: updError.message };
    return { ok: true, ms: nowMs() - started };
  });

  const ok = result.filter((x) => x.ok);
  const ms = ok.map((x) => x.ms).sort((a, b) => a - b);
  const avg = ms.length ? Math.round(ms.reduce((a, b) => a + b, 0) / ms.length) : 0;
  const p95 = ms.length ? ms[Math.floor(ms.length * 0.95)] : 0;
  const p99 = ms.length ? ms[Math.floor(ms.length * 0.99)] : 0;

  return {
    run_id: currentRunId,
    requested: ops,
    ok: ok.length,
    failed: result.length - ok.length,
    avgMs: avg,
    p95Ms: p95,
    p99Ms: p99,
  };
}

async function readLoad(establishmentId, rounds, parallel) {
  const tasks = Array.from({ length: rounds }).map((_, i) => i);
  const results = await runWithLimit(tasks, parallel, async (i) => {
    const started = nowMs();
    const { count, error } = await supabase
      .from('tech_cards')
      .select('id', { count: 'exact', head: true })
      .eq('establishment_id', establishmentId);
    if (error) return { ok: false, ms: nowMs() - started, error: error.message };
    return { ok: true, ms: nowMs() - started, count: count || 0, i };
  });

  const ok = results.filter((x) => x.ok);
  const ms = ok.map((x) => x.ms).sort((a, b) => a - b);
  const p95 = ms.length ? ms[Math.floor(ms.length * 0.95)] : 0;
  const p99 = ms.length ? ms[Math.floor(ms.length * 0.99)] : 0;
  const avg = ms.length ? Math.round(ms.reduce((a, b) => a + b, 0) / ms.length) : 0;
  const failed = results.length - ok.length;

  return { rounds, ok: ok.length, failed, avgMs: avg, p95Ms: p95, p99Ms: p99 };
}

async function cleanupByRun(targetRunId) {
  if (!targetRunId) {
    throw new Error('STRESS_CLEANUP_RUN_ID is required for cleanup mode.');
  }

  const pattern = `[STRESS ${targetRunId}]`;
  const { data: estRows, error: estErr } = await supabase
    .from('establishments')
    .select('id,name')
    .like('name', `${pattern}%`);
  if (estErr) throw new Error(`Cleanup lookup failed: ${estErr.message}`);

  let deletedEstablishments = 0;
  for (const row of estRows || []) {
    const { error } = await supabase.from('establishments').delete().eq('id', row.id);
    if (error) throw new Error(`Failed to delete establishment ${row.id}: ${error.message}`);
    deletedEstablishments += 1;
  }

  // Cleanup auth users by email pattern.
  let page = 1;
  let removedUsers = 0;
  const usersToDelete = [];
  while (true) {
    const listRes = await supabase.auth.admin.listUsers({ page, perPage: 200 });
    if (listRes.error) throw new Error(`Failed to list users: ${listRes.error.message}`);
    const users = listRes.data?.users || [];
    if (users.length === 0) break;
    for (const u of users) {
      const mail = (u.email || '').toLowerCase();
      if (mail.includes(`stress+${targetRunId.toLowerCase()}+`)) {
        usersToDelete.push(u.id);
      }
    }
    page += 1;
  }
  for (const userId of usersToDelete) {
    const del = await supabase.auth.admin.deleteUser(userId);
    if (!del.error) removedUsers += 1;
  }

  return { deletedEstablishments, removedUsers };
}

async function main() {
  try {
    if (MODE === 'cleanup') {
      markStart('cleanup');
      const res = await cleanupByRun(cfg.cleanupRunId);
      markEnd('cleanup', res);
      console.log(JSON.stringify({ mode: MODE, cleanupRunId: cfg.cleanupRunId, metrics }, null, 2));
      return;
    }

    console.log(`Starting non-AI stress run: ${runId}`);
    console.log(
      `Plan: employees=${cfg.employees}, techCards=${cfg.techCards}, inventories=${cfg.inventories}, concurrency=${cfg.concurrency}, langSwitchOps=${cfg.languageSwitchOps}, langs=${cfg.languages.join(',')}`
    );

    markStart('create_establishment');
    const establishment = await createEstablishment(runId);
    markEnd('create_establishment', { establishmentId: establishment.id });

    markStart('create_auth_and_employees');
    const employeeColumns = await listColumns('employees');
    const indexes = Array.from({ length: cfg.employees }).map((_, i) => i);
    const employeeResults = await runWithLimit(indexes, cfg.concurrency, async (i) =>
      createAuthAndEmployee(establishment.id, i, employeeColumns, runId)
    );
    const successEmployees = employeeResults.filter((x) => x.ok);
    const failedEmployees = employeeResults.filter((x) => !x.ok);
    markEnd('create_auth_and_employees', {
      requested: cfg.employees,
      created: successEmployees.length,
      failed: failedEmployees.length,
    });

    if (successEmployees.length === 0) {
      throw new Error('No employees created successfully; aborting next steps.');
    }
    if (failedEmployees.length > 0) {
      console.log('Some employees failed:', failedEmployees.slice(0, 5));
    }

    const createdBy = successEmployees[0].authUserId;
    const techCardColumns = await listColumns('tech_cards');

    markStart('insert_tech_cards');
    const insertedTechCards = await insertTechCards(
      establishment.id,
      createdBy,
      cfg.techCards,
      runId,
      techCardColumns
    );
    markEnd('insert_tech_cards', { inserted: insertedTechCards });

    markStart('insert_inventory_documents');
    const insertedInventory = await insertInventoryDocs(
      establishment.id,
      createdBy,
      cfg.inventories,
      runId
    );
    markEnd('insert_inventory_documents', { inserted: insertedInventory });

    markStart('language_switch_churn');
    const churn = await languageSwitchChurn(
      establishment.id,
      cfg.languageSwitchOps,
      cfg.concurrency,
      runId,
      employeeColumns
    );
    markEnd('language_switch_churn', churn);

    markStart('read_load_probe');
    const probe = await readLoad(establishment.id, 60, cfg.concurrency);
    markEnd('read_load_probe', probe);

    const totalMs = nowMs() - t0;
    console.log(
      JSON.stringify(
        {
          mode: 'run',
          runId,
          establishmentId: establishment.id,
          totalMs,
          metrics,
          cleanupCommand: `STRESS_MODE=cleanup STRESS_CLEANUP_RUN_ID=${runId} STRESS_CONFIRM=YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST node scripts/supabase_stress_no_ai.js`,
        },
        null,
        2
      )
    );
  } catch (e) {
    console.error('Stress test failed:', e.message);
    process.exit(1);
  }
}

main();
