-- =============================================================================
-- 159_transit_spark_killswitch.sql
-- =============================================================================
-- Transit Spark serverseitig abschaltbar - ohne Deploy.
--
-- ANLASS (ROADMAP, Statusblock zu 0.10.0):
--
--   "Bedingung für den Release von 0.10.0: Der BLE-Gerätetest ist der
--    einzige Punkt, der den Release blockiert. Ist er bis dahin nicht
--    bestanden, wird Transit Spark serverseitig für Neuregistrierungen
--    gesperrt (Flag in app_config, wirkt über die bestehende RPC)."
--
-- Das Flag existierte nicht. Ohne es hätte die Entscheidung "Gerätetest
-- nicht bestanden" bedeutet, dass Transit Spark im nächsten Release
-- entfernt oder per Not-Patch gesperrt werden muss - beides mit
-- Aufwand und Risiko kurz vor dem Upload.
--
-- UMSETZUNG:
--
-- Alle Transit-Spark-Pfade laufen über public.transit_spark_adult():
-- der Radar (transit_presence_heartbeat), das Matching
-- (match_proximity_spark), der Kontaktversand (send_soft_ping) und die
-- Gegenseiten-Prüfung. Diese eine Funktion wird deshalb um das Flag
-- erweitert - damit wirkt der Schalter auf ALLE Pfade, ohne dass eine
-- der vier RPCs neu geschrieben werden muss.
--
-- Das ist genau der Grund, warum die Funktion hier nicht einfach
-- umbenannt wird: die Aufrufer in den Migrationen 131 und 149 sprechen
-- sie mit ihrem jetzigen Namen an, und eine Umbenennung wuerde dort
-- Brechen ausloesen. Der Name bleibt, die Bedeutung wird im Kommentar
-- und im Funktionsnamen der inneren Alterspruefung sauber getrennt:
--
--   transit_spark_adult(uuid)  = "darf diese Person Transit Spark
--                                 benutzen?" (Alter UND Feature aktiv)
--   transit_spark_is_adult(uuid) = "ist die Person volljährig?" (Alter)
--
-- FAIL-OPEN beim Flag: fehlt der Eintrag in app_config, ist Transit
-- Spark aktiv. Das ist hier richtig und bewusst so gewaehlt: das Flag
-- ist eine Notbremse. Eine Notbremse, die durch einen versehentlich
-- geloeschten Config-Eintrag von selbst ausloest, waere keine Bremse,
-- sondern eine Stoerung. Die Alterssperre selbst ist davon NICHT
-- betroffen - sie ist im Flag-Zweig hart verdrahtet und laesst sich
-- nicht abschalten.
--
-- Der Schalter gilt fuer alle, nicht nur fuer Neuregistrierungen. Das
-- ist die einfachere und ehrlichere Variante: nach einem
-- BLE-Test-Misser ist es besser, wenn NIEMAND Transit Spark nutzt, als
-- wenn nur die Neuen ausgesperrt sind und die Alten weiterfunken.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- 1) Der Schalter
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.transit_spark_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- Fail-open: ein fehlender oder unlesbarer Eintrag heisst "aktiv".
  SELECT coalesce(
    (SELECT lower(btrim(c.value)) NOT IN ('false', '0', 'off', 'no')
       FROM public.app_config c
      WHERE c.key = 'transit_spark_enabled'),
    true
  );
$$;

COMMENT ON FUNCTION public.transit_spark_enabled() IS
  'Schalter fuer Transit Spark (v0.10.0, Migration 159). Der Wert steht '
  'in app_config.transit_spark_enabled. Fail-open: fehlt der Eintrag, ist '
  'Transit Spark aktiv - das Flag ist eine Notbremse und darf nicht '
  'selbstaendig ausloesen.';

REVOKE EXECUTE ON FUNCTION public.transit_spark_enabled() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_spark_enabled() TO authenticated, service_role;

-- ===========================================================================
-- 2) Die reine Alterspruefung (neuer, klarer Name)
-- ===========================================================================
-- Die bestehende Funktion transit_spark_adult() wird in (3) zur
-- Gesamtfreigabe erweitert. Die reine Altersfrage bekommt hier einen
-- eigenen Namen, damit beides unterscheidbar bleibt.
CREATE OR REPLACE FUNCTION public.transit_spark_is_adult(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- bewusst NICHT public.profile_age(): das coalesct ein fehlendes
  -- birth_date auf '2000-01-01' und wuerde damit ohne Geburtsdatum
  -- faelschlich "erwachsen" liefern.
  SELECT EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.user_id = p_user_id
       AND p.birth_date IS NOT NULL
       AND date_part('year', age(p.birth_date))::int >= 18
  );
$$;

COMMENT ON FUNCTION public.transit_spark_is_adult(uuid) IS
  'Ist die Person volljährig (18+)? Ohne Geburtsdatum: nein (fail-closed). '
  'Das ist die reine Altersfrage - die Frage, ob Transit Spark ueberhaupt '
  'aktiv ist, beantwortet transit_spark_enabled().';

REVOKE EXECUTE ON FUNCTION public.transit_spark_is_adult(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_spark_is_adult(uuid)
  TO authenticated, service_role;

-- ===========================================================================
-- 3) Die Gesamtfreigabe - hier wirkt der Schalter auf alle Pfade
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.transit_spark_adult(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.transit_spark_enabled()
     AND public.transit_spark_is_adult(p_user_id);
$$;

COMMENT ON FUNCTION public.transit_spark_adult(uuid) IS
  'Freigabe fuer Transit Spark: Das Feature muss AKTIV sein (app_config, '
  'Migration 159) und die Person volljährig sein. Diese eine Funktion '
  'entscheidet fuer Radar, Matching und Kontaktversand - deshalb wirkt der '
  'Schalter auf alle drei Pfade.';

REVOKE EXECUTE ON FUNCTION public.transit_spark_adult(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_spark_adult(uuid)
  TO authenticated, service_role;

-- ===========================================================================
-- 4) Der Eintrag selbst
-- ===========================================================================
-- 'true' heisst: Transit Spark ist aktiv. Auf 'false' gesetzt sperrt das
-- Feature fuer alle, ohne Deploy und ohne App-Update.
INSERT INTO public.app_config (key, value)
VALUES ('transit_spark_enabled', 'true')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value;

-- ===========================================================================
-- 5) Selbsttest: der Schalter muss in beide Richtungen greifen
-- ===========================================================================
-- Getestet wird nicht nur der aktuelle Zustand, sondern die Wirkung:
-- nach dem Setzen auf 'false' muss die Freigabe weg, nach dem
-- Zuruecksetzen wieder da sein.
--
-- Der Test aendert den Eintrag nur innerhalb der Transaktion dieser
-- Migration; am Ende steht wieder 'true' (was auch der ausgelieferte
-- Zustand ist - die Migration laeuft in derselben Transaktion, in der
-- der Eintrag gesetzt wurde).
DO $selftest$
DECLARE
  v_vor boolean;
  v_danach boolean;
  v_zurueck boolean;
BEGIN
  v_vor := public.transit_spark_enabled();
  IF v_vor IS DISTINCT FROM true THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: Transit Spark ist nach der Migration '
      'nicht aktiv (%). Der Release-Zustand muss "aktiv" sein.', v_vor;
  END IF;

  -- Schalter auf "aus" stellen und pruefen.
  UPDATE public.app_config
     SET value = 'false'
   WHERE key = 'transit_spark_enabled';
  v_danach := public.transit_spark_enabled();
  IF v_danach IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Schalter wirkt nicht '
      '(erwartet false, bekommen %).', v_danach;
  END IF;

  -- Und wieder zurueck.
  UPDATE public.app_config
     SET value = 'true'
   WHERE key = 'transit_spark_enabled';
  v_zurueck := public.transit_spark_enabled();
  IF v_zurueck IS DISTINCT FROM true THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: der Schalter laesst sich nicht '
      'zuruecksetzen (%).', v_zurueck;
  END IF;

  RAISE NOTICE
    'Selbsttest bestanden: der Transit-Spark-Schalter wirkt in beide '
    'Richtungen.';
END;
$selftest$;

COMMIT;
