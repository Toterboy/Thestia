-- =============================================================================
-- 158_fix_handle_new_user_gender_preferences.sql
-- =============================================================================
-- Registrierung war komplett kaputt - und das ist beim Testen des
-- Meldewegs aufgefallen, nicht beim Lesen des Codes.
--
-- BEFUND (Security-Audit 22.10.2026, 22.10.):
--
-- Beim Anlegen eines Wegwerf-Nutzers ueber die Admin-API kam zurueck:
--   "Database error creating new user"
--
-- Ursache: Migration 138 (location_privacy_contract) hat die Funktion
-- public.handle_new_user() neu definiert und dabei die Spalte
-- `gender_preference` (Singular) in den INSERT geschrieben. Diese Spalte
-- wurde aber bereits in Migration 025 geloescht und durch
-- `gender_preferences` (TEXT[]) ersetzt. Migration 046 hatte genau
-- denselben Fehler schon einmal behoben - Migration 138 hat ihn
-- wieder eingebaut.
--
-- Folge: JEDE Registrierung scheitert seit dem Deploy von Migration 138
-- mit einem SQL-Fehler. Der Client meldet "Registrierung fehlgeschlagen".
-- Bestandskonten sind nicht betroffen - deshalb ist es lange
-- unbemerkt geblieben: das Testkonto war aelter als Migration 138.
--
-- Der Fehler ist ausserhalb des Codes sichtbar, weil ein Datenbank-
-- Fehler beim Anlegen eines Auth-Users als HTTP 500 "Database error
-- creating new user" ankommt - ohne Zeiger auf die Ursache.
--
-- Die Funktion wird hier auf den Stand nach Migration 063 zurueckgebracht
-- und um die inzwischen entfernten Spalten bereinigt:
--   * gender_preferences statt gender_preference (Array)
--   * location_lat/location_lng entfallen (Migration 138 hat sie entfernt)
--   * age_range_max = 65 (Migration 153: die Obergrenze ist jetzt 65,
--     nicht 99 - 99 war der alte Wert vor der Umstellung)
--
-- Der Ban-Check bleibt erhalten: gesperrte E-Mail-Adressen koennen sich
-- weiterhin nicht neu registrieren.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  -- Plattform-Sperre: gesperrte E-Mail-Adressen koennen sich nicht
  -- (neu) registrieren. Nur der Entsperrungsantrag ist moeglich.
  IF public.is_email_banned(NEW.email) THEN
    RAISE EXCEPTION 'email_banned: Diese E-Mail-Adresse ist gesperrt. '
                    'Bitte sende einen Entsperrungsantrag.'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preferences,
    birth_date,
    bio,
    interests,
    personality_type,
    max_distance_km,
    age_range_min,
    age_range_max
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'name', 'Unbekannt'),
    COALESCE(NEW.raw_user_meta_data ->> 'gender', 'unknown'),
    '{}'::text[],
    COALESCE(
      (NEW.raw_user_meta_data ->> 'birth_date')::date,
      '2000-01-01'::date
    ),
    '',
    '[]'::jsonb,
    'INTJ',
    100,
    18,
    65
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Legt das Profil bei der Registrierung an. v0.10.0, Migration 158: '
  'Migration 138 hatte hier die geloeschte Spalte gender_preference '
  'geschrieben - seitdem schlug jede Registrierung fehl.';

-- ===========================================================================
-- Gegenprobe: jede Spalte des INSERT muss existieren.
-- ===========================================================================
-- Der Fehler von Migration 138 war ein Spaltenname, den es nicht mehr
-- gibt. Das haessliche daran: Der Code sah vollstaendig plausibel aus,
-- und die Migration selbst lief fehlerfrei durch - erst zur LAUFZEIT
-- beim ersten Registrierungsversuch brach es.
--
-- Geprueft wird deshalb die Spaltenliste selbst: genau die Spalten, die
-- handle_new_user schreibt, muessen in public.profiles vorhanden sein.
-- Ein INSERT als Test waere nicht moeglich - profiles.user_id hat einen
-- Fremdschluessel auf auth.users, und ein Wegwerf-Autrag ohne
-- auth.users-Zeile scheitert an genau diesem Fremdschluessel.
--
-- Bewusst wird auf den richtigen Namen geprueft: `gender_preference`
-- (Singular) ist die Spalte, die Migration 025 geloescht hat. Sie
-- zaehlt hier als Fehler - sonst waere der Test genau das, was er
-- verhindern soll.
DO $selftest$
DECLARE
  v_fehler text := '';
  v_spalte text;
  v_erwartet text[] := ARRAY[
    'user_id', 'name', 'gender', 'gender_preferences', 'birth_date', 'bio',
    'interests', 'personality_type', 'max_distance_km', 'age_range_min',
    'age_range_max'
  ];
  v_verboten text[] := ARRAY['gender_preference', 'location_lat', 'location_lng'];
BEGIN
  FOREACH v_spalte IN ARRAY v_erwartet LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'profiles'
         AND column_name = v_spalte
    ) THEN
      v_fehler := v_fehler || ' fehlt: ' || v_spalte || ';';
    END IF;
  END LOOP;

  FOREACH v_spalte IN ARRAY v_verboten LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'profiles'
         AND column_name = v_spalte
    ) THEN
      v_fehler := v_fehler || ' existiert noch (darf nicht beschrieben '
        'werden): ' || v_spalte || ';';
    END IF;
  END LOOP;

  IF v_fehler <> '' THEN
    RAISE EXCEPTION
      'Sicherheitscheck fehlgeschlagen: die Spaltenliste von '
      'handle_new_user passt nicht zu public.profiles (%). Eine '
      'Registrierung wuerde scheitern.', v_fehler;
  END IF;
END;
$selftest$;

COMMIT;
