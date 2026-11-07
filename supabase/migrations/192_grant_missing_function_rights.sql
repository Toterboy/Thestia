-- 192: zwei Funktionen, die der Client ruft, aber nicht ausfuehren darf
--
-- BEFUND (07.11.2026, Betreiber): "Blockierte-Liste mit Entblockieren."
-- Und im selben Durchgang aufgefallen: "Der Funke entsteht, aber es ist
-- nichts sichtbar."
--
-- DIE URSACHE (live gemessen, nicht vermutet):
--
--   Der Aufruf von public.unblock_user antwortete mit
--       HTTP 403  permission denied for function unblock_user
--
--   Die Funktion existiert und ist SECURITY DEFINER - aber die Rolle
--   "authenticated" hat KEIN Ausfuehrungsrecht darauf. Ihre
--   Schwester block_user hat das Recht, unblock_user nicht.
--
--   Bei der Rechte-Revoke-Migration (123) wurde unblock_user
--   vergessen. Dieselbe Luecke hat accept_soft_ping: das Annehmen
--   eines eingehenden Funkens im Transit-Radar scheiterte mit 403.
--   Der Empfender sah den Ping (die Liste las sich) und beim Tippen
--   auf "Annehmen" passierte nichts - der Nutzer dachte, es liege an
--   ihm.
--
--   Solche Fehler sind still: die App zeigt "fehlgeschlagen", der
--   Nutzer glaubt, es liege an ihm. Und sie sind im Quelltext nicht zu
--   sehen - nur die Datenbank weiss, welche Rechte wirklich gesetzt
--   sind.
--
-- GEFUNDEN HAT DAS tool/check_function_grants.py: es sammelt alle
-- RPC-Aufrufe des Clients (Dart UND Edge Functions) und fragt die
-- PRODUKTIVDATENBANK, welche Rechte die Rollen wirklich haben. Es
-- meldet jede aufgerufene Funktion, die der Server nicht ausfuehren
-- kann.

BEGIN;

-- Beide Funktionen wieder fuer angemeldete Nutzer freigeben.
GRANT EXECUTE ON FUNCTION public.unblock_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_soft_ping(uuid) TO authenticated;

-- Und die Kontrolle: die Rechte muessen jetzt gesetzt sein. Ohne sie
-- waere dieser Fehler wieder still.
DO $$
DECLARE
  v_unblock int;
  v_accept int;
BEGIN
  SELECT count(*) INTO v_unblock
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'unblock_user'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  IF v_unblock = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: unblock_user ist fuer angemeldete Nutzer weiterhin nicht aufrufbar - das Entblockieren funktioniert nicht';
  END IF;

  SELECT count(*) INTO v_accept
    FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'accept_soft_ping'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  IF v_accept = 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: accept_soft_ping ist fuer angemeldete Nutzer weiterhin nicht aufrufbar - ein Funke laesst sich nicht annehmen';
  END IF;
END;
$$;

COMMIT;
