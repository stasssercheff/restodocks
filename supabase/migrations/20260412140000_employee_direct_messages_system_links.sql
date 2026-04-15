-- Ссылки на сущности приложения во вложении к сообщению (JSON: [{ "k", "p", "t" }])
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS system_links JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN employee_direct_messages.system_links IS 'Массив вложений-ссылок: k=тип, p=путь go_router, t=подпись';
