-- Ограничение размера одного голосового вложения (согласовано с клиентским лимитом ~3 МБ)
UPDATE storage.buckets
SET file_size_limit = 3145728
WHERE id = 'chat_voice';
