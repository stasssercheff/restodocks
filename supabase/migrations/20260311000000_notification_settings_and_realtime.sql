-- Настройки уведомлений пользователя (опционально — можно хранить и локально).
-- Добавляем колонку notification_settings в employees (JSONB).
ALTER TABLE employees ADD COLUMN IF NOT EXISTS notification_settings JSONB;

COMMENT ON COLUMN employees.notification_settings IS 'Настройки уведомлений: displayType (banner|modal|disabled), messages, orders, inventory, iikoInventory, notifications (bool)';

-- Realtime для документов во входящих
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE order_documents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE inventory_documents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE checklist_submissions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE employee_deletion_notifications;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
