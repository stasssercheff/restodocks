-- Ensure owner deletion RPC is callable by authenticated users.
GRANT EXECUTE ON FUNCTION public.delete_establishment_by_owner(uuid, text, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_establishment_by_owner(uuid, text, text) FROM anon;
