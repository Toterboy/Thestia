-- 189: die Dating-Hour-Paarung laeuft alle 5 Minuten statt alle 30
--
-- BEFUND (07.11.2026, Betreiber): "Bei Dating Hour finden sich die
-- Partner nicht (zwei user drin (meine geräte)) und es passiert nichts.
-- Es steht, dass die sich suchen, aber finden niemanden."
--
-- DIE URSACHE (aus den Daten gelesen):
--
--   Der Cron "run_dating_hour_scheduler" laeuft alle 30 Minuten
--   (*/30 * * * *), das Event dauert aber nur 60 Minuten
--   (20:00-21:00 Ortszeit). Die Paarungsrunde
--   (public.match_dating_hour_round) laeuft nur fuer Termine mit
--   status='active' - und nur im Rahmen des Cron.
--
--   Wer in der ersten halben Stunde beitritt, bekam deshalb KEINE
--   Paarungsrunde mehr: der letzte Cron war schon vorbei, der naechste
--   kam erst beim Ende des Events. Genau das ist passiert: der
--   Betreiber und sein Testpartner sind um 19:42 beigetreten, der
--   Cron lief um 19:30 (vorbei) und um 20:00 (Event-Ende). Ergebnis:
--   zwei Teilnahmen, null Sitzungen, "sie suchen sich" ewig.
--
-- DIE LOESUNG (zwei Teile):
--
--   1. Die App ruft die Paarungsrunde nach dem Beitritt selbst auf
--      (lib/services/dating_hour_service.dart). Damit entsteht die
--      Sitzung SOFORT, unabhaengig vom Cron-Takt.
--
--   2. Der Cron laeuft alle 5 Minuten statt alle 30. Das ist der
--      Rueckfall: wenn die App beim Beitritt nicht erreichbar ist
--      (Telefon aus, kein Netz), soll die Paarung trotzdem
--      zustande kommen - der Cron ist die_instances, die auch dann
--      laeuft. Fuenf Minuten passen in das 60-Minuten-Fenster:
--      nach dem Beitritt bleiben 55 Minuten fuer die Runde, also
--      mindestens zehn Versuche.
--
-- Der alte Job wird zuerst abgemeldet und dann durch den neuen
-- ersetzt - cron.schedule nimmt einen Namen, und der alte Job haette
-- sonst weiter alle 30 Minuten gelaufen.

BEGIN;

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  -- Den alten Job (alle 30 Minuten) finden und abmelden.
  FOR v_jobid IN
    SELECT jobid FROM cron.job
     WHERE jobname = 'run_dating_hour_scheduler'
        OR (command ILIKE '%run_dating_hour_scheduler%'
            AND schedule = '*/30 * * * *')
  LOOP
    PERFORM cron.unschedule(v_jobid);
  END LOOP;

  -- Und den neuen (alle 5 Minuten) anlegen.
  PERFORM cron.schedule(
    'run_dating_hour_scheduler',
    '*/5 * * * *',
    'SELECT public.run_dating_hour_scheduler();'
  );
END;
$$;

-- Die Kontrolle: der Job muss aktiv sein und alle 5 Minuten laufen.
--
-- Mehrere Jobs duerfen den Scheduler rufen - es gab schon einen
-- zusaetzlichen ("0 21 * * *", ein Lauf genau zum Eventende). Der
-- alte 30-Minuten-Takt darf aber nicht mehr vorkommen: genau der
-- liess die Paarung ausfallen.
DO $$
DECLARE
  v_schedule text;
  v_alte int;
BEGIN
  SELECT schedule INTO v_schedule
    FROM cron.job
   WHERE jobname = 'run_dating_hour_scheduler';

  IF v_schedule IS NULL THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: der Job fehlt';
  END IF;

  IF v_schedule <> '*/5 * * * *' THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: der Job laeuft mit "%" statt alle 5 Minuten',
      v_schedule;
  END IF;

  SELECT count(*) INTO v_alte
    FROM cron.job
   WHERE command ILIKE '%run_dating_hour_scheduler%'
     AND schedule = '*/30 * * * *';
  IF v_alte > 0 THEN
    RAISE EXCEPTION 'Kontrolle fehlgeschlagen: % Job(s) laufen noch alle 30 Minuten', v_alte;
  END IF;
END;
$$;

COMMIT;
