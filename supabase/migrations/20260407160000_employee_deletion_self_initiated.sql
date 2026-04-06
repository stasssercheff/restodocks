-- Самоудаление сотрудника: флаг для текста во входящих (не путать с удалением руководителем).
ALTER TABLE public.employee_deletion_notifications
  ADD COLUMN IF NOT EXISTS is_self_deletion boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.employee_deletion_notifications.is_self_deletion IS
  'true — сотрудник удалил свой профиль (уведомление привязано к руководителю для FK).';
