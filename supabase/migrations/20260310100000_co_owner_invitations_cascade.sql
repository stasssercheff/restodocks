-- co_owner_invitations.invited_by без ON DELETE блокировал удаление сотрудника.
-- Добавляем CASCADE: при удалении сотрудника удаляются его приглашения.
DO $$
DECLARE
  con text;
BEGIN
  SELECT tc.constraint_name INTO con
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_schema = kcu.constraint_schema
    AND tc.constraint_name = kcu.constraint_name
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'co_owner_invitations'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND kcu.column_name = 'invited_by'
  LIMIT 1;
  IF con IS NOT NULL THEN
    EXECUTE format('ALTER TABLE co_owner_invitations DROP CONSTRAINT %I', con);
  END IF;
END $$;
ALTER TABLE co_owner_invitations
  ADD CONSTRAINT co_owner_invitations_invited_by_fkey
  FOREIGN KEY (invited_by) REFERENCES employees(id) ON DELETE CASCADE;
