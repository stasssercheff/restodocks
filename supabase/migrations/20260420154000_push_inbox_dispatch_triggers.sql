-- DB-side dispatch for inbox/message push events.
-- Avoids manual Supabase Database Webhook setup per table.
--
-- Required vault secrets:
--   push_webhook_secret               (must match Edge env PUSH_WEBHOOK_SECRET)
--   edge_push_inbox_dispatch_url      (optional; fallback URL is used if absent)

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.dispatch_push_inbox_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  SELECT decrypted_secret
  INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_webhook_secret'
  LIMIT 1;

  IF v_secret IS NULL OR btrim(v_secret) = '' THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret
  INTO v_url
  FROM vault.decrypted_secrets
  WHERE name = 'edge_push_inbox_dispatch_url'
  LIMIT 1;

  IF v_url IS NULL OR btrim(v_url) = '' THEN
    v_url := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/push-inbox-dispatch';
  END IF;

  PERFORM net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'table', TG_TABLE_NAME,
      'record', to_jsonb(NEW)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret,
      'Authorization', 'Bearer ' || v_secret
    )
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.dispatch_push_inbox_event() IS
  'POST insert payloads to push-inbox-dispatch Edge Function for FCM/APNs push.';

DROP TRIGGER IF EXISTS trg_push_inbox_employee_direct_messages
  ON public.employee_direct_messages;
CREATE TRIGGER trg_push_inbox_employee_direct_messages
AFTER INSERT ON public.employee_direct_messages
FOR EACH ROW
EXECUTE FUNCTION public.dispatch_push_inbox_event();

DROP TRIGGER IF EXISTS trg_push_inbox_inventory_documents
  ON public.inventory_documents;
CREATE TRIGGER trg_push_inbox_inventory_documents
AFTER INSERT ON public.inventory_documents
FOR EACH ROW
EXECUTE FUNCTION public.dispatch_push_inbox_event();

DROP TRIGGER IF EXISTS trg_push_inbox_order_documents
  ON public.order_documents;
CREATE TRIGGER trg_push_inbox_order_documents
AFTER INSERT ON public.order_documents
FOR EACH ROW
EXECUTE FUNCTION public.dispatch_push_inbox_event();

DROP TRIGGER IF EXISTS trg_push_inbox_checklist_submissions
  ON public.checklist_submissions;
CREATE TRIGGER trg_push_inbox_checklist_submissions
AFTER INSERT ON public.checklist_submissions
FOR EACH ROW
EXECUTE FUNCTION public.dispatch_push_inbox_event();

DROP TRIGGER IF EXISTS trg_push_inbox_employee_deletion_notifications
  ON public.employee_deletion_notifications;
CREATE TRIGGER trg_push_inbox_employee_deletion_notifications
AFTER INSERT ON public.employee_deletion_notifications
FOR EACH ROW
EXECUTE FUNCTION public.dispatch_push_inbox_event();
