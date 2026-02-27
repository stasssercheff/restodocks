-- Добавляем recipient_chef_id и recipient_email в order_documents для совместимости
-- (миграция 20260225140000 создаёт таблицу без этих колонок; prod мог быть создан из другого скрипта)
ALTER TABLE order_documents ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE CASCADE;
ALTER TABLE order_documents ADD COLUMN IF NOT EXISTS recipient_email TEXT;

-- Индекс для выборки по получателю (как в checklist_submissions)
CREATE INDEX IF NOT EXISTS idx_order_documents_recipient ON order_documents(recipient_chef_id) WHERE recipient_chef_id IS NOT NULL;

COMMENT ON COLUMN order_documents.recipient_chef_id IS 'Получатель документа (шеф/владелец). Один ряд на получателя.';
COMMENT ON COLUMN order_documents.recipient_email IS 'Email получателя для уведомлений.';
