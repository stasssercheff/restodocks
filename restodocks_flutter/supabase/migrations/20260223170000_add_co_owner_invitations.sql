-- Таблица для приглашений соучредителей
CREATE TABLE IF NOT EXISTS co_owner_invitations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  invited_email TEXT NOT NULL,
  invited_by UUID NOT NULL REFERENCES employees(id),
  invitation_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired')),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '7 days'),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_establishment_id ON co_owner_invitations(establishment_id);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_invitation_token ON co_owner_invitations(invitation_token);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_invited_email ON co_owner_invitations(invited_email);

-- RLS политики
ALTER TABLE co_owner_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
-- Владельцы могут видеть приглашения своего заведения
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
-- Владельцы могут создавать приглашения
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
-- Владельцы могут обновлять приглашения
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

COMMENT ON TABLE co_owner_invitations IS 'Приглашения для соучредителей заведений';