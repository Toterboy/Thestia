-- Migration 111: Aktive Zufallschat-Session abrufen
--
-- NUTZERWUNSCH "Ich muss im Chat sein, um Nachrichten zu erhalten":
-- Der globale Relay-Eingang (App offen, aber CHAT NICHT offen) muß
-- eingehende Nachrichten dem richtigen Chat-Screen zuordnen können.
-- Die Session-ID des laufenden Zufallschats kennt der Client nur im
-- Chat-Screen - außerhalb braucht er einen Lookup: Diese Funktion
-- liefert die AKTIVE Session des Aufrufers (id + Partner).

CREATE OR REPLACE FUNCTION public.get_my_active_random_chat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT s.id,
         CASE WHEN s.user_a = v_user THEN s.user_b ELSE s.user_a END,
         s.status
    INTO v_id, v_partner, v_status
    FROM public.random_chat_sessions s
   WHERE (s.user_a = v_user OR s.user_b = v_user)
     AND s.status = 'active'
   ORDER BY s.matched_at DESC NULLS LAST
   LIMIT 1;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('sessionId', NULL, 'partnerId', NULL, 'status', 'none');
  END IF;

  RETURN jsonb_build_object(
    'sessionId', v_id,
    'partnerId', v_partner,
    'status', v_status
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_active_random_chat() TO authenticated;
