-- =========================================================================
-- Admin: Profile mit gesetztem Standort-Verdachtsflag
-- =========================================================================
--
-- WARUM (06.11.2026): Das Flag is_location_suspicious wird seit
-- Migration 180 korrekt geschrieben, aber von KEINER Abfrage
-- ausgewertet - es gibt keinen Filter, der einen auffaelligen Nutzer
-- aus der Discovery nimmt. Das war als offene Produktentscheidung
-- vermerkt; die Entscheidung des Nutzers ist: das Flag soll im
-- Admin-Bereich sichtbar werden, das Verhalten der App bleibt
-- unveraendert.
--
-- WICHTIG: Diese Funktion aendert NICHTS am Verhalten. Sie liest
-- nur. Niemand wird aus der Discovery genommen, niemand wird
-- gesperrt. Sie zeigt dem Admin, bei wem der Standort-Check
-- aufgefallen ist - mehr nicht.
--
-- DER AUFBAU ist derselbe wie bei den anderen Admin-RPCs: die
-- Funktion prueft selbst, ob der Aufrufer Admin ist
-- (is_current_user_admin). Ohne Admin liefert sie eine leere Liste.
--
-- WAS DRIN STEHT:
--   userId     - wer
--   name       - der Anzeigename
--   checkedAt  - wann die letzte Standort-Pruefung lief
--   isVerified - ob die Alterspruefung schon durch ist
--
-- WAS NICHT DRIN STEHT: die Entfernung. Sie wird bei der Pruefung
-- berechnet (haversine_km), aber nicht gespeichert - der Wert steht
-- nur im Ergebnis des einzelnen Aufrufs. Eine aehnliche Groesse
-- waere geraten.
--
-- DIE SORTIERUNG: nach dem Zeitpunkt der letzten Pruefung, das
-- aelteste zuerst. Wer die Liste am laengsten nicht angesehen hat,
-- steht oben.

CREATE OR REPLACE FUNCTION public.admin_list_location_checks()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'userId', p.user_id,
             'name', p.name,
             'checkedAt', p.location_checked_at,
             'isVerified', p.is_verified
           ) ORDER BY p.location_checked_at DESC NULLS LAST), '[]'::jsonb)
    FROM public.profiles p
   WHERE public.is_current_user_admin()
     AND p.is_location_suspicious;
$$;

COMMENT ON FUNCTION public.admin_list_location_checks() IS
  'Admin-Liste der Profile mit gesetztem Standort-Verdachtsflag. '
  'Nur lesend - das Flag beeinflusst das Verhalten der App nicht.';

-- Nur angemeldete Nutzer duerfen die Funktion aufrufen; die
-- Admin-Pruefung sitzt darin.
REVOKE ALL ON FUNCTION public.admin_list_location_checks() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_location_checks() TO authenticated;
