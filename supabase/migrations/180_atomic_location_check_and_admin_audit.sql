-- 180: Der Standort-Check wird atomar, und das Admin-Review wird
-- nachvollziehbar.
--
-- NUTZERWUNSCH (04.11.2026): "die offenen Punkte sinnvoll loesen".
--
-- TEIL 1: DAS TOCTOU-FENSTER IM STANDORT-CHECK
-- ============================================
--
-- BEFUND (Security-Audit 04.11.2026): process-location-check las die
-- alte Position (profile_locations) und den alten Zeitstempel
-- (profiles.location_checked_at) ZWEI getrennt vom Schreiben. Dazwischen
-- lagen zwei Netzaufrufe an check-location (je 50 bis 200 ms). In diesem
-- Fenster konnten zwei Aufrufe parallel laufen - die App wiederholt den
-- Request, wenn die Antwort unterwegs verloren ging.
--
-- Die Folgen waren:
--
--   a) Die Geschwindigkeits-Baseline verfalschte sich. Beide Aufrufe
--      rechneten gegen DIESELBE alte Position und schrieben danach
--      dieselbe neue Basis. Die Zeit seit der letzten Position wurde
--      nicht korrekt fortgeschrieben - der Pruefpunkt rutschte.
--
--   b) Das Verdachtsflag konnte verloren gehen. Der Flag wird an zwei
--      Stellen geschrieben, und die normale Position schrieb ihn mit
--      dem ERGEBNIS der eigenen Pruefung - also konnte ein zweiter
--      Aufruf ein gerade gesetztes Flag wieder auf false setzen.
--
-- LOESUNG: Lesen, Rechnen und Schreiben passieren in EINER
-- Datenbanktransaktion. Die Zeile in profiles wird dabei mit
-- SELECT ... FOR UPDATE gesperrt: ein zweiter Aufruf fuer denselben
-- Nutzer wartet, bis der erste fertig ist. Damit kann keiner dem
-- anderen in die Fussschuesse laufen.
--
-- Die Entfernung rechnet jetzt die Datenbank (public.haversine_km) -
-- dieselbe Formel, die check-location bisher im TypeScript gerechnet
-- hat (Erdradius 6371 km). Der Aufruf an check-location entfaellt in
-- diesem Pfad: er war nur eine weitere Quelle des Zeitfensters.
--
-- Das Verdachtsflag wird jetzt nur noch SETZT, nie geloescht. Das war
-- die dokumentierte Absicht ("ein faelschlich gesetztes Flag ist ein
-- Fehlalarm, ein zurueckgesetztes Flag ist eine Umgehung") - der
-- normale Pfad hat sie aber nicht eingehalten.
--
-- HINWEIS (BEFUND 04.11.2026): Das Flag is_location_suspicious wird
-- zwar geschrieben, aber von KEINER Abfrage ausgewertet - es gibt
-- keinen Filter, der einen auffaelligen Nutzer aus der Discovery
-- nimmt. Die Flag ist damit derzeit ein Hinweis ohne Wirkung. Das ist
-- eine Produktentscheidung und keine technische: entweder wirkt die
-- Flag, oder sie wird entfernt. Bis dahin wird sie wenigstens
-- korrekt und ohne Verlust gefuehrt.
--
-- TEIL 2: DAS ADMIN-REVIEW
-- ========================
--
-- BEFUND (Security-Audit 04.11.2026): Der Review-Pfad von
-- verify-account prueft, ob der Aufrufer Admin ist (das ist richtig und
-- bleibt). Er hat aber:
--
--   * KEIN Rate-Limit. Mit einem geleakten Admin-Token konnte jemand
--     massenhaft Freigaben erteilen oder verweigern.
--   * KEINEN Audit-Eintrag. Wer wann wen freigab, war nicht
--     nachvollziehbar. Fuer eine dating app mit Alterspruefung ist das
--     der denkbar schlechteste Ort fuer eine fehlende Spur.
--
-- LOESUNG: public.admin_review_verification() macht beides in einer
-- Transaktion:
--   * prueft selbst, dass der Aufrufer Admin ist (profiles.is_admin),
--   * begrenzt auf 60 Reviews pro Admin und Stunde,
--   * schreibt das Ergebnis UND den Audit-Eintrag.
--
-- Der Aufrufer ist die Edge Function (service_role). Das Audit ist
-- deshalb nicht manipulationssicher gegen einen kompromittierten
-- service_role - aber ohne service_role kann niemand den Pfad
-- ausloesen, und jeder Review landet in der Spur.
--
-- TEIL 3: DIE APP SAGT, WAS PASSIERT IST
-- =====================================
--
-- Nach dem Ende der Freigabe ist die E-Mail-Adresse des Elternteils
-- geloescht (Migration 179). Die App hat bisher nur "keine Freigabe"
-- gesagt. Jetzt weiss der Server, WANN geloescht wurde, und die App
-- kann es sagen.

BEGIN;

-- =========================================================================
-- 1) Die Entfernung in der Datenbank
-- =========================================================================
--
-- Dieselbe Formel wie in check-location (TypeScript): Haversine mit
-- Erdradius 6371 km. Die Schwellen (15 km fuer "in der Naehe",
-- 300 km/h fuer "unmoeglich schnell") bleiben unveraendert.
CREATE OR REPLACE FUNCTION public.haversine_km(
  p_lat1 double precision,
  p_lon1 double precision,
  p_lat2 double precision,
  p_lon2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT 6371 * 2 * atan2(
    sqrt(
      power(sin(radians(p_lat2 - p_lat1) / 2), 2)
      + cos(radians(p_lat1)) * cos(radians(p_lat2))
      * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
    ),
    sqrt(
      1 - (
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
        * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
      )
    )
  );
$$;

COMMENT ON FUNCTION public.haversine_km(
  double precision, double precision, double precision, double precision) IS
  'Entfernung zweier Koordinaten in Kilometern (Haversine, Erdradius '
  '6371 km). Dieselbe Formel wie in check-location, aber in der '
  'Datenbank - damit der Standort-Check alles in einer Transaktion '
  'rechnen kann (Migration 180).';

REVOKE ALL ON FUNCTION public.haversine_km(
  double precision, double precision, double precision, double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.haversine_km(
  double precision, double precision, double precision, double precision)
  TO service_role;

-- =========================================================================
-- 2) Der atomare Standort-Check
-- =========================================================================
--
-- Der Aufrufer ist die Edge Function process-location-check. Sie
-- uebergibt die neue Position; alles andere passiert hier, in EINER
-- Transaktion.
CREATE OR REPLACE FUNCTION public.apply_location_check(
  p_user_id uuid,
  p_lat      double precision,
  p_lon      double precision
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_checked_at  timestamptz;
  v_prev_lat    double precision;
  v_prev_lon    double precision;
  v_distance    double precision;
  v_elapsed_ms  double precision;
  v_speed_kmh   double precision;
  v_suspicious  boolean;
  v_has_prev    boolean;
  v_susp_before boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_user');
  END IF;

  IF p_lat IS NULL OR p_lon IS NULL
     OR p_lat < -90 OR p_lat > 90
     OR p_lon < -180 OR p_lon > 180 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_coordinates');
  END IF;

  -- -------------------------------------------------------------------
  -- DIE SPERRE: Das ist der ganze Fix.
  --
  -- SELECT ... FOR UPDATE sperrt die Zeile fuer alle anderen
  -- Transactions. Ein zweiter, gleichzeitiger Aufruf fuer denselben
  -- Nutzer wartet hier - und liest danach den ZUSTAND, den der erste
  -- Aufruf geschrieben hat. Damit kann keiner mehr gegen eine
  -- veraltete Basis rechnen.
  --
  -- Die alte Position wird unter derselben Sperre gelesen.
  -- -------------------------------------------------------------------
  SELECT location_checked_at, is_location_suspicious
    INTO v_checked_at, v_susp_before
    FROM public.profiles
   WHERE user_id = p_user_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  SELECT lat, lng INTO v_prev_lat, v_prev_lon
    FROM public.profile_locations
   WHERE user_id = p_user_id;

  v_has_prev := (v_prev_lat IS NOT NULL AND v_prev_lon IS NOT NULL);

  -- -------------------------------------------------------------------
  -- Fall 1: Erstposition. Es gibt keine Vorposition, also kann nichts
  -- geprueft werden. Der Zeitstempel wird gesetzt, die Position
  -- geschrieben. Das Verdachtsflag wird NICHT angefasst.
  -- -------------------------------------------------------------------
  IF NOT v_has_prev THEN
    UPDATE public.profiles
       SET location_checked_at = now()
     WHERE user_id = p_user_id;

    INSERT INTO public.profile_locations (user_id, lat, lng)
    VALUES (p_user_id, p_lat, p_lon)
    ON CONFLICT (user_id) DO UPDATE
      SET lat = EXCLUDED.lat,
          lng = EXCLUDED.lng;

    RETURN jsonb_build_object(
      'ok', true,
      'distance_km', NULL,
      'is_suspicious', v_susp_before,
      'updated', true,
      'reason', 'no_previous_location'
    );
  END IF;

  -- -------------------------------------------------------------------
  -- Fall 2: Die Entfernung zur Vorposition.
  --
  -- Die Vorposition ist die auf das Raster gerundete Zeile aus der
  -- Tabelle, die neue Position sind die Rohkoordinaten des Geraets -
  -- genau wie es vorher in der Edge Function war.
  -- -------------------------------------------------------------------
  v_distance := public.haversine_km(v_prev_lat, v_prev_lon, p_lat, p_lon);

  -- -------------------------------------------------------------------
  -- Fall 3: Unmoeglich schnell (> 300 km/h).
  --
  -- Die Position wird NICHT uebernommen (sonst koennte ein Angreifer
  -- seine Basislinie schrittweise verschieben), das Flag wird gesetzt.
  -- Der Zeitstempel bleibt unveraendert - die Baseline soll ja gerade
  -- dieselbe bleiben.
  -- -------------------------------------------------------------------
  IF v_checked_at IS NOT NULL THEN
    v_elapsed_ms := EXTRACT(EPOCH FROM (now() - v_checked_at)) * 1000;
    IF v_elapsed_ms > 0 THEN
      v_speed_kmh := v_distance / (v_elapsed_ms / 3600000);
      IF v_speed_kmh > 300 THEN
        UPDATE public.profiles
           SET is_location_suspicious = true
         WHERE user_id = p_user_id;

        RETURN jsonb_build_object(
          'ok', true,
          'distance_km', v_distance,
          'is_suspicious', true,
          'updated', false,
          'reason', 'implausible_speed'
        );
      END IF;
    END IF;
  END IF;

  -- -------------------------------------------------------------------
  -- Fall 4: Normaler Fall. Ab 15 km gilt die Position als "nicht in
  -- der Naehe".
  --
  -- Das Verdachtsflag wird nur gesetzt, nie geloescht (is_location_
  -- suspicious OR ...). Sonst koennte ein spaeterer, unauffaelliger
  -- Aufruf ein gerade gesetztes Flag wieder auf false setzen.
  -- -------------------------------------------------------------------
  v_suspicious := (v_distance >= 15);

  UPDATE public.profiles
     SET is_location_suspicious = (is_location_suspicious OR v_suspicious),
         location_checked_at   = now()
   WHERE user_id = p_user_id;

  INSERT INTO public.profile_locations (user_id, lat, lng)
  VALUES (p_user_id, p_lat, p_lon)
  ON CONFLICT (user_id) DO UPDATE
    SET lat = EXCLUDED.lat,
        lng = EXCLUDED.lng;

  RETURN jsonb_build_object(
    'ok', true,
    'distance_km', v_distance,
    'is_suspicious', v_suspicious,
    'updated', true,
    'reason', 'ok'
  );
END;
$$;

COMMENT ON FUNCTION public.apply_location_check(uuid, double precision,
  double precision) IS
  'Prueft und speichert eine neue Position. Lesen, Rechnen und Schreiben '
  'passieren in EINER Transaktion unter einer Zeilensperre - damit kann '
  'kein zweiter Aufruf gegen eine veraltete Basis rechnen und das '
  'Verdachtsflag nicht mehr zurueckgesetzt werden (Migration 180).';

REVOKE ALL ON FUNCTION public.apply_location_check(
  uuid, double precision, double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_location_check(
  uuid, double precision, double precision)
  TO service_role;

-- =========================================================================
-- 3) Das Admin-Audit
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.admin_action_audit (
  id             bigserial PRIMARY KEY,
  actor_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action         text NOT NULL,
  target_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  detail         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admin_action_audit IS
  'Nachvollziehbarkeit der Admin-Arbeit. Ohne diese Spur laesst sich im '
  'Streitfall nicht zeigen, wer wen wann freigegeben oder abgelehnt hat '
  '(Migration 180).';

CREATE INDEX IF NOT EXISTS idx_admin_action_audit_actor
  ON public.admin_action_audit (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_action_audit_target
  ON public.admin_action_audit (target_user_id, created_at DESC);

ALTER TABLE public.admin_action_audit ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policies: Clients lesen und schreiben nie direkt. Alles
-- laeuft ueber die RPC, die den Aufrufer prueft.

-- =========================================================================
-- 4) Das Review mit Rate-Limit und Audit-Eintrag
-- =========================================================================
CREATE OR REPLACE FUNCTION public.admin_review_verification(
  p_admin_id       uuid,
  p_target_user_id uuid,
  p_is_verified    boolean,
  p_verified_age   int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_admin boolean;
  v_rate_ok  boolean;
  v_age      int;
BEGIN
  IF p_admin_id IS NULL OR p_target_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_request');
  END IF;

  -- Der Admin wird IN DER DATENBANK geprueft, nicht nur in der Edge
  -- Function. Das ist der Unterschied: die Edge Function kann ein
  -- Programmierfehler sein, die Datenbank nicht.
  SELECT is_admin INTO v_is_admin
    FROM public.profiles
   WHERE user_id = p_admin_id;

  IF NOT FOUND OR v_is_admin IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_admin');
  END IF;

  -- 60 Reviews pro Admin und Stunde. Ein Admin arbeitet nicht
  -- schneller - und ein geleaktes Token kann nicht massenhaft
  -- Freigeben erteilen.
  v_rate_ok := public.consume_rate_limit(
    'admin-review:' || p_admin_id::text, 60, 3600);
  IF NOT COALESCE(v_rate_ok, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited');
  END IF;

  -- Das Alter: der Wert, den der Admin (und die KI-Schaetzung) festgelegt
  -- hat. Beim Ablehnen wird es wieder geloescht.
  v_age := CASE WHEN p_is_verified THEN p_verified_age ELSE NULL END;

  UPDATE public.profiles
     SET is_verified            = p_is_verified,
         verification_status    = CASE WHEN p_is_verified
                                       THEN 'approved' ELSE 'rejected' END,
         verified_age           = v_age,
         verification_approved_at = CASE WHEN p_is_verified
                                       THEN now() ELSE NULL END
   WHERE user_id = p_target_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'target_not_found');
  END IF;

  -- Der Audit-Eintrag. Er entsteht in derselben Transaktion wie die
  -- Aenderung - ein Review ohne Spur ist nicht moeglich.
  INSERT INTO public.admin_action_audit
    (actor_id, action, target_user_id, detail)
  VALUES
    (p_admin_id, 'verification_review', p_target_user_id,
     jsonb_build_object('is_verified', p_is_verified,
                        'verified_age', v_age));

  RETURN jsonb_build_object('ok', true, 'is_verified', p_is_verified);
END;
$$;

COMMENT ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int) IS
  'Ein Admin entscheidet ueber eine Verifikation. Die Funktion prueft '
  'selbst, dass der Aufrufer Admin ist, begrenzt auf 60 Reviews pro '
  'Admin und Stunde und schreibt den Audit-Eintrag (Migration 180).';

REVOKE ALL ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_verification(
  uuid, uuid, boolean, int)
  TO service_role;

-- =========================================================================
-- 5) Der Status der Freigabe meldet den Loeschzeitpunkt
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_my_guardian_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_row    record;
  v_profile record;
  v_age    int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_profile
    FROM public.profiles
   WHERE user_id = v_uid;

  v_age := public.guardian_eligible_age(v_uid);

  SELECT * INTO v_row
    FROM public.guardian_consents
   WHERE child_user_id = v_uid
     AND status IN ('pending','active','expired')
   ORDER BY requested_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'consentState',       coalesce(v_profile.consent_state, 'none'),
      'supervised',         coalesce(v_profile.supervised, false),
      'status',             'none',
      'age',                v_age,
      'guardianEmail',      null,
      'guardianEmailMasked', null,
      'notifyEnabled',      false,
      'notifyFrequency',    'none',
      'usageLimitEnabled',  false,
      'usageStartMin',      null,
      'usageEndMin',        null,
      'hasPin',             false,
      'accessPolicy',       'ended',
      'accessUntil',        null,
      'transitionPending',  false,
      'confirmedAt',        null,
      'revokedAt',          v_profile.consent_revoked_at
    );
  END IF;

  RETURN jsonb_build_object(
    'consentState',        coalesce(v_profile.consent_state, 'none'),
    'supervised',          coalesce(v_profile.supervised, false),
    'status',              v_row.status,
    'age',                 v_age,
    'guardianEmail',       v_row.guardian_email,
    'guardianEmailMasked', public.guardian_mask_email(v_row.guardian_email),
    'notifyEnabled',       v_row.notify_enabled,
    'notifyFrequency',     v_row.notify_frequency,
    'usageLimitEnabled',   v_row.usage_limit_enabled,
    'usageStartMin',       v_row.usage_start_min,
    'usageEndMin',         v_row.usage_end_min,
    'hasPin',              v_row.pin_hash IS NOT NULL,
    'accessPolicy',        v_row.access_policy,
    'accessUntil',         v_row.access_until,
    'graceMonths',         v_row.grace_months,
    -- Migration 180: Wann wurde die E-Mail-Adresse des Elternteils
    -- geloescht? Die App sagt das dem Nutzer - und kann es nur sagen,
    -- wenn der Server es weiss.
    'emailDeletedAt',      v_row.email_deleted_at,
    'confirmedAt',         v_row.confirmed_at,
    'revokedAt',           v_row.revoked_at,
    -- Der Screen zum 18. Geburtstag steht an, wenn das Konto volljährig
    -- geworden ist, eine aktive Freigabe besteht und noch nichts
    -- entschieden wurde.
    'transitionPending',   (v_age IS NOT NULL AND v_age >= 18
                             AND v_row.status = 'active'
                             AND coalesce(v_profile.guardian_transition_done, false) = false)
  );
END;
$$;;

COMMENT ON FUNCTION public.get_my_guardian_status() IS
  'Der Stand der elterlichen Aufsicht fuer die App: Freigabe, '
  'Benachrichtigungs-Frequenz, Nutzungszeit, PIN vorhanden, ob der '
  'Screen zum 18. Geburtstag ansteht (v0.10.0, Migration 165) und ob '
  'die E-Mail-Adresse des Elternteils geloescht wurde (Migration 180).';

-- =========================================================================
-- 6) Selbsttest
-- =========================================================================
DO $check$
DECLARE
  v_typ text;
  v_count integer;
BEGIN
  -- Die Entfernungsfunktion muss rechnen (Aequator-Punkt = 0 km).
  IF public.haversine_km(0, 0, 0, 0) > 0.001 THEN
    RAISE EXCEPTION 'haversine_km rechnet falsch (0 km erwartet).';
  END IF;

  -- Ein Grad am Aequator sind rund 111 km.
  IF public.haversine_km(0, 0, 0, 1) < 100
     OR public.haversine_km(0, 0, 0, 1) > 120 THEN
    RAISE EXCEPTION 'haversine_km rechnet falsch (111 km erwartet).';
  END IF;

  -- Der Standort-Check muss die Zeilensperre benutzen - OHNE sie
  -- waere das TOCTOU-Fenster wieder offen.
  SELECT pg_get_functiondef(
           'public.apply_location_check(uuid,double precision,double precision)'
           ::regprocedure)
    INTO v_typ;
  IF v_typ NOT LIKE '%FOR UPDATE%' THEN
    RAISE EXCEPTION
      'apply_location_check sperrt die Zeile nicht - das TOCTOU-Fenster '
      'waere wieder offen.';
  END IF;
  IF v_typ NOT LIKE '%is_location_suspicious OR%' THEN
    RAISE EXCEPTION
      'apply_location_check kann das Verdachtsflag zuruecksetzen.';
  END IF;

  -- Das Review muss sich selbst pruefen und begrenzen.
  SELECT pg_get_functiondef(
           'public.admin_review_verification(uuid,uuid,boolean,int)'
           ::regprocedure)
    INTO v_typ;
  IF v_typ NOT LIKE '%is_admin%' THEN
    RAISE EXCEPTION
      'admin_review_verification prueft den Admin nicht selbst.';
  END IF;
  IF v_typ NOT LIKE '%consume_rate_limit%' THEN
    RAISE EXCEPTION
      'admin_review_verification hat keine Begrenzung.';
  END IF;
  IF v_typ NOT LIKE '%admin_action_audit%' THEN
    RAISE EXCEPTION
      'admin_review_verification schreibt keinen Audit-Eintrag.';
  END IF;

  -- Die Audit-Tabelle muss existieren.
  SELECT count(*) INTO v_count
    FROM information_schema.tables
   WHERE table_schema = 'public' AND table_name = 'admin_action_audit';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Die Tabelle admin_action_audit fehlt.';
  END IF;

  RAISE NOTICE
    'Standort-Check atomar, Admin-Review mit Audit und Limit, '
    'Entfernungsformel geprueft (Selbsttest ok)';
END;
$check$;

COMMIT;
