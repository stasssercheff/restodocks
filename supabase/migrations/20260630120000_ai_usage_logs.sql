-- AI usage telemetry for admin analytics (tokens + estimated USD).
-- Filled from Edge Functions shared AI provider layer.

create table if not exists public.ai_usage_logs (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  provider text not null,
  model text null,
  context text null,
  function_name text null,
  establishment_id uuid null,
  user_id uuid null,
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  total_tokens integer not null default 0,
  estimated_cost_usd numeric(14, 6) not null default 0,
  latency_ms integer null,
  status text not null default 'ok',
  error_message text null
);

create index if not exists ai_usage_logs_created_at_idx
  on public.ai_usage_logs (created_at desc);

create index if not exists ai_usage_logs_provider_created_at_idx
  on public.ai_usage_logs (provider, created_at desc);

create index if not exists ai_usage_logs_context_created_at_idx
  on public.ai_usage_logs (context, created_at desc);

create index if not exists ai_usage_logs_function_created_at_idx
  on public.ai_usage_logs (function_name, created_at desc);

alter table public.ai_usage_logs enable row level security;

drop policy if exists ai_usage_logs_service_role_only on public.ai_usage_logs;
create policy ai_usage_logs_service_role_only
on public.ai_usage_logs
for all
to service_role
using (true)
with check (true);
