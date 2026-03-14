-- Записи журналов ХАССП не редактируются — только INSERT и DELETE.
-- Удаляем UPDATE policy (если есть) для haccp_*_logs.
-- По умолчанию RLS блокирует UPDATE при отсутствии policy.

DROP POLICY IF EXISTS "auth_haccp_numeric_update" ON haccp_numeric_logs;
DROP POLICY IF EXISTS "auth_haccp_status_update" ON haccp_status_logs;
DROP POLICY IF EXISTS "auth_haccp_quality_update" ON haccp_quality_logs;
